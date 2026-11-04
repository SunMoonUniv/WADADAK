import 'dart:async';
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

  Future<void> open(
    WidgetTester tester, {
    FakeCourseApi? courses,
    FakeMyLocation? location,
    Size size = const Size(402, 995),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
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
          myLocationProvider.overrideWithValue(location ?? FakeMyLocation()),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: WdTheme.light(),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
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

  testWidgets('the selected route preview is at the top, scrolled into view', (
    tester,
  ) async {
    await open(
      tester,
      courses: FakeCourseApi()
        ..searchable = [for (var i = 1; i <= 4; i++) testCourse('한강 코스 $i')],
    );
    // 고른 카드가 내린 목록 아래에 있게 화면을 줄인다
    tester.view.physicalSize = const Size(402, 640);
    await tester.enterText(find.byType(TextField), '한강');
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('한강 코스 4'));
    await tester.pumpAndSettle();

    expect(find.text('선택한 코스의 경로').hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('선택한 코스의 경로')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
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

  testWidgets(
    'saved courses show only public saved courses and can be picked',
    (tester) async {
      final api = FakeCourseApi()
        ..bookmarkRows = [
          testBookmark(
            '한강 다리 왕복 8K',
            rating: 4.4,
            activeRunners: 2,
            expiresAt: '2030-01-01T14:59:59Z',
          ),
          testBookmark('정릉 오르막 4K', expiresAt: '2030-01-01T14:59:59Z'),
          testBookmark('안암 골목길 2K', pendingDelete: true),
        ];
      await open(tester, courses: api);

      await tester.tap(find.widgetWithText(WdFilterChip, '저장한 코스'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<WdFilterChip>(find.widgetWithText(WdFilterChip, '저장한 코스'))
            .selected,
        isTrue,
      );
      expect(find.text('한강 다리 왕복 8K'), findsOneWidget);
      expect(find.text('5.2km · 난이도 중 · ★ 4.4'), findsOneWidget);
      expect(find.text('지금 2명 달리는 중'), findsOneWidget);
      expect(find.text('정릉 오르막 4K'), findsOneWidget);
      // 칩 · 머리글 · 각 카드 오른쪽 위 배지
      expect(find.text('저장한 코스'), findsNWidgets(4));
      expect(find.widgetWithText(WdTag, '저장한 코스'), findsNWidgets(2));
      expect(find.text('달리는 러너 없음'), findsOneWidget);
      expect(find.text('안암 골목길 2K'), findsNothing, reason: '삭제 예정 코스는 달릴 수 없다');
      expect(api.detailRequests, isEmpty, reason: '저장 목록의 카드 값을 그대로 쓴다');

      await tester.tap(find.text('한강 다리 왕복 8K'));
      await tester.pump();
      await tester.tap(find.text('이 코스로 설정'));
      await tester.pumpAndSettle();
      expect(container.read(selectedCourseProvider)?.courseId, '한강 다리 왕복 8K');
    },
  );

  testWidgets('my courses show only my public courses', (tester) async {
    final api = FakeCourseApi()
      ..mine = [
        testMyCourse('성북천 벚꽃길 3K', courseId: 'c1'),
        testMyCourse(
          '개운산 숲길 4K',
          courseId: 'c3',
          hiddenReason: CourseHiddenReason.userDeleted,
        ),
      ];
    await open(tester, courses: api);

    await tester.tap(find.text('내가 만든'));
    await tester.pumpAndSettle();

    expect(find.text('내가 만든 코스'), findsOneWidget);
    expect(find.text('성북천 벚꽃길 3K'), findsOneWidget);
    expect(find.text('개운산 숲길 4K'), findsNothing);
  });

  testWidgets('cards of other tabs tell which course is saved', (tester) async {
    final api = FakeCourseApi()..savedIds = {'c2'};
    await open(tester, courses: api);
    runs.remoteRecords = [
      record('r1', courseId: 'c1', courseName: '한강 야경 5K'),
      record('r2', courseId: 'c2', courseName: '성북천 벚꽃길 3K'),
    ];
    runs.notifyListeners();
    await tester.pumpAndSettle();

    // 저장한 카드도 다른 카드와 동일하게 러너 상태를 표시한다.
    expect(find.text('저장한 코스'), findsNWidgets(2));
    expect(find.text('달리는 러너 없음'), findsNWidgets(2));
    expect(find.widgetWithText(WdTag, '저장한 코스'), findsOneWidget);
  });

  Future<void> screenshot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final bitmap =
          await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/course-select-ui/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      bitmap.dispose();
    });
  }

  const loadingMessage = '코스를 불러오고 있어요. 잠시 기다려주세요.';
  const nearbyEmpty = '가까운 코스가 없거나 위치를 확인할 수 없어요.';

  for (final label in ['내 주변', '저장한 코스', '내가 만든']) {
    testWidgets('$label waits for the course response before showing empty', (
      tester,
    ) async {
      final api = _DelayedCourseApi();
      await open(
        tester,
        courses: api,
        location: FakeMyLocation(
          allowed: true,
          location: const GeoPoint(37, 127),
        ),
      );
      await tester.tap(find.widgetWithText(WdFilterChip, label));
      await tester.pumpAndSettle();
      expect(find.text(loadingMessage), findsOneWidget);
      expect(find.text(nearbyEmpty), findsNothing);
      expect(find.text('저장한 코스가 없어요. 코스 상세에서 북마크로 저장해 보세요.'), findsNothing);
      expect(find.text('공개 중인 내 코스가 없어요.'), findsNothing);
      if (label == '내 주변') await screenshot(tester, 'loading-402');

      api.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(loadingMessage), findsNothing);
      expect(
        find.text(switch (label) {
          '내 주변' => nearbyEmpty,
          '저장한 코스' => '저장한 코스가 없어요. 코스 상세에서 북마크로 저장해 보세요.',
          _ => '공개 중인 내 코스가 없어요.',
        }),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final allowed in [true, false]) {
    testWidgets('nearby waits for location before showing courses ($allowed)', (
      tester,
    ) async {
      final fix = Completer<void>();
      final location = FakeMyLocation(
        allowed: allowed,
        location: const GeoPoint(37, 127),
      )..fix = fix;
      await open(
        tester,
        location: location,
        courses: FakeCourseApi()..listed = [testCourse('코스 테스트')],
      );
      await tester.tap(find.text('내 주변'));
      await tester.pumpAndSettle();
      expect(find.text(loadingMessage), findsOneWidget);
      expect(find.text(nearbyEmpty), findsNothing);

      fix.complete();
      await tester.pumpAndSettle();
      expect(find.text(loadingMessage), findsNothing);
      expect(find.text(allowed ? '코스 테스트' : nearbyEmpty), findsOneWidget);
    });
  }

  testWidgets('search and recent history show loading while pending', (
    tester,
  ) async {
    final gate = Completer<void>();
    await open(tester, courses: FakeCourseApi()..searchGate = gate);
    runs.loadingHistory = true;
    runs.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text(loadingMessage), findsOneWidget);
    expect(find.text('아직 달린 코스가 없어요. 내 주변이나 검색으로 골라 보세요.'), findsNothing);
    runs.loadingHistory = false;
    runs.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text(loadingMessage), findsNothing);

    await tester.enterText(find.byType(TextField), '한강');
    await tester.pumpAndSettle();
    expect(find.text(loadingMessage), findsOneWidget);
    expect(find.text('찾는 코스가 없어요.'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(loadingMessage), findsNothing);
    expect(find.text('찾는 코스가 없어요.'), findsOneWidget);
  });

  for (final width in [402.0, 320.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('saved badge stays above runner status at $width / $scale', (
        tester,
      ) async {
        final api = FakeCourseApi()
          ..listed = [testCourse('코스 테스트', activeRunners: 3)]
          ..savedIds = {'id-코스 테스트'};
        await open(
          tester,
          courses: api,
          location: FakeMyLocation(
            allowed: true,
            location: const GeoPoint(37, 127),
          ),
          size: Size(width, 995),
          textScale: scale,
        );
        await tester.tap(find.text('내 주변'));
        await tester.pumpAndSettle();
        final badge = find.widgetWithText(WdTag, '저장한 코스');
        final title = find.text('코스 테스트');
        final runners = find.text('지금 3명 달리는 중');
        expect(badge, findsOneWidget);
        expect(runners, findsOneWidget);
        expect(
          tester.getTopLeft(badge).dx,
          greaterThan(tester.getTopLeft(title).dx),
        );
        expect(tester.getSize(title).width, greaterThan(40));
        if (scale == 1) {
          expect(tester.getTopLeft(badge).dy, tester.getTopLeft(title).dy);
        } else {
          expect(
            tester.getBottomRight(badge).dy,
            lessThan(tester.getTopLeft(title).dy),
          );
        }
        expect(
          tester.getBottomRight(badge).dy,
          lessThan(tester.getTopLeft(runners).dy),
        );
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'saved-${width.toInt()}-${scale.toInt()}x');
      });
    }
  }

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

/// Keep list responses pending to verify the screen's loading state.
class _DelayedCourseApi extends FakeCourseApi {
  final gate = Completer<void>();

  @override
  Future<CourseListPage> listCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
    CourseListSort sort = CourseListSort.initial,
    CoursePeriod? period,
    GeoPoint? origin,
    String? cursor,
  }) async {
    await gate.future;
    return super.listCourses(
      southWest: southWest,
      northEast: northEast,
      filter: filter,
      pick: pick,
      sort: sort,
      period: period,
      origin: origin,
      cursor: cursor,
    );
  }

  @override
  Future<BookmarkPage> bookmarks({
    BookmarkSort sort = BookmarkSort.recent,
    GeoPoint? origin,
    String? cursor,
  }) async {
    await gate.future;
    return super.bookmarks(sort: sort, origin: origin, cursor: cursor);
  }

  @override
  Future<MyCoursePage> myCourses({String? cursor, int? size}) async {
    await gate.future;
    return super.myCourses(cursor: cursor, size: size);
  }
}
