import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/presentation/route_preview_map.dart';
import 'package:wadadak/features/run/presentation/course_prep_view.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/run/application/course_run_entry.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/presentation/course_select_screen.dart';

import '../fakes.dart';
import 'recording/run_controller_test.dart'
    show FailingStore, TestApi, TestLocation;

/// C8 코스 선택(Figma 1453:4434)
void main() {
  late RunController runs;
  late ProviderContainer container;
  late GoRouter router;
  late GlobalKey capture;
  setUpAll(() async {
    final fonts = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final w in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$w.otf',
        ),
      );
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Map<String, dynamic> record(
    String id, {
    String? courseId,
    String? courseName,
  }) => {
    'id': id,
    'course': courseId == null
        ? null
        : {'courseId': courseId, 'courseName': courseName, 'completed': true},
  };

  Future<void> open(WidgetTester tester, {FakeCourseApi? courses}) async {
    tester.view.physicalSize = const Size(402, 995);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    capture = GlobalKey();
    sqfliteFfiInit();
    runs = RunController(
      FailingStore(),
      TestLocation(),
      TestApi(),
      () async => 'alice',
      wait: (_) async {},
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
    // shutdown은 기기 DB를 닫느라 위젯 테스트의 가짜 시간 안에서 끝나지 않는다. 여기서는 DB를 열지 않아 닫지 않는다
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('C6')),
        GoRoute(path: '/c8', builder: (_, _) => const CourseSelectScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          runControllerProvider.overrideWithValue(runs),
          courseApiClientProvider.overrideWithValue(courses ?? FakeCourseApi()),
          rankingApiClientProvider.overrideWithValue(FakeCourseRankingApi()),
          reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi()),
          myLocationProvider.overrideWithValue(FakeMyLocation()),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: WdTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(tester.element(find.text('C6')));
    router.push('/c8');
    await tester.pumpAndSettle();
  }

  test(
    'recent courses come from my record list, latest first, once per course',
    () {
      expect(
        recentCourses([
          record('r3', courseId: 'c2', courseName: '성북천 벚꽃길 3K'),
          record('r2'),
          record('r1', courseId: 'c1', courseName: '한강 야경 5K'),
          record('r0', courseId: 'c2', courseName: '성북천 벚꽃길 3K'),
        ]).map((c) => c.name),
        ['성북천 벚꽃길 3K', '한강 야경 5K'],
      );
    },
  );

  testWidgets(
    'picking a recent course sets it for the course run and goes back',
    (tester) async {
      await open(tester);
      runs.remoteRecords = [
        record('r1', courseId: 'c1', courseName: '한강 야경 5K'),
      ];
      runs.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('한강 야경 5K'), findsOneWidget);
      expect(find.text('아직 달린 기록 없음'), findsOneWidget);
      await tester.tap(find.text('한강 야경 5K'));
      await tester.pump();
      await tester.tap(find.text('이 코스로 설정'));
      await tester.pumpAndSettle();

      expect(find.text('C6'), findsOneWidget);
      expect(container.read(selectedCourseProvider)?.courseId, 'c1');
    },
  );

  testWidgets('search shows matching courses and more can be revealed', (
    tester,
  ) async {
    await open(
      tester,
      courses: FakeCourseApi()
        ..searchable = [
          for (var i = 1; i <= 4; i++)
            testCourse('한강 코스 $i', averageRating: 4.5, activeRunners: i),
        ],
    );
    await tester.enterText(find.byType(TextField), '한강');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과'), findsOneWidget);
    expect(find.text('한강 코스 3'), findsOneWidget);
    expect(find.text('한강 코스 4'), findsNothing);
    await tester.dragUntilVisible(
      find.text('코스 1개 더 보기'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('코스 1개 더 보기'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('한강 코스 4'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('한강 코스 4'), findsOneWidget);
  });

  testWidgets(
    'selected course shows full detail route and retry only refetches that course',
    (tester) async {
      final api = FakeCourseApi();
      await open(tester, courses: api);
      runs.remoteRecords = [
        record('r1', courseId: 'c1', courseName: '한강 야경 5K'),
      ];
      runs.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(RunRoutePreviewMap), findsNothing);
      await tester.tap(find.text('한강 야경 5K'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('경로 다시 불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('코스 경로를 불러오지 못했어요.'), findsOneWidget);
      // A failed preview is local to the map; course selection remains available.
      final before = api.detailRequests.length;
      await tester.tap(find.text('경로 다시 불러오기'));
      await tester.pumpAndSettle();
      expect(api.detailRequests.length, before + 1);
      expect(container.read(runCourseDetailProvider('c1')).hasError, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview switches to the selected full route before course confirmation',
    (tester) async {
      const first = [
        GeoPoint(37, 127),
        GeoPoint(37.1, 127.1),
        GeoPoint(37.2, 127.2),
      ];
      const second = [GeoPoint(35, 129), GeoPoint(35.3, 129.3)];
      CourseDetail detail(String id, List<GeoPoint> route) => CourseDetail(
        courseId: id,
        name: id,
        courseType: CourseType.custom,
        difficulty: Difficulty.medium,
        tags: const [],
        distanceMeters: 5000,
        route: route,
        distanceMarkers: const [],
        expiresAt: DateTime.utc(2030),
      );
      final api = FakeCourseApi()
        ..details = {'c1': detail('c1', first), 'c2': detail('c2', second)};
      await open(tester, courses: api);
      runs.remoteRecords = [
        record('r1', courseId: 'c1', courseName: '첫 코스'),
        record('r2', courseId: 'c2', courseName: '두 번째 코스'),
      ];
      runs.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('첫 코스'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(RunRoutePreviewMap));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RunRoutePreviewMap>(find.byType(RunRoutePreviewMap))
            .segments
            .single,
        first,
      );
      await tester.ensureVisible(find.text('두 번째 코스'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('두 번째 코스'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(RunRoutePreviewMap));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RunRoutePreviewMap>(find.byType(RunRoutePreviewMap))
            .segments
            .single,
        second,
      );
      await tester.runAsync(() async {
        final bitmap =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/ghost-entry-check/402-course-map.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
        bitmap.dispose();
      });
      expect(container.read(selectedCourseProvider), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('running without a course clears the chosen course', (
    tester,
  ) async {
    await open(tester);
    runs.selectCourse(const CourseSelection('c1', '한강 야경 5K'));
    await tester.tap(find.text('코스 없이 달리기'));
    await tester.pumpAndSettle();

    expect(find.text('C6'), findsOneWidget);
    expect(runs.selectedCourse, isNull);
  });
}
