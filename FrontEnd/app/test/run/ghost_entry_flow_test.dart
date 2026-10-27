import 'dart:async';
import 'dart:io';
import 'dart:ui' as image_ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/course_run_entry.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/own_ghost_api.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/presentation/course_select_screen.dart';
import 'package:wadadak/features/run/presentation/course_start_view.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/features/run/presentation/own_ghost_selection_screen.dart';
import 'package:wadadak/features/run/presentation/own_ghost_selection_view.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import 'ghost_controller_recovery_test.dart' show GhostLocation;
import 'ghost_recovery_support.dart';
import 'recording/course_run_start_test.dart' show CourseApi;
import 'recording/run_controller_test.dart' show FailingStore, until;

class EntryCourseApi extends CourseApi {
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> prepareCourse(
    String owner,
    String id,
    String courseId,
  ) async {
    await gate?.future;
    return super.prepareCourse(owner, id, courseId);
  }
}

class EntryGhostSource implements OwnGhostSource {
  final candidate = OwnGhostCandidate.fromJson({
    'id': sourceId,
    'courseId': courseId,
    'courseVersion': 0,
    'startedAt': ghostEpoch.toIso8601String(),
    'registeredAt': ghostEpoch.toIso8601String(),
    'courseElapsedSeconds': 230,
    'courseDistanceMeters': 1112,
  });
  bool empty = false, unavailable = false;
  Completer<OwnGhostReplay>? delayed;
  int queries = 0;
  @override
  Future<OwnGhostPage> candidates(
    String owner,
    GhostCourseContext course, {
    required OwnGhostSort sort,
    required OwnGhostPeriod period,
    String? cursor,
  }) async {
    queries++;
    return OwnGhostPage(
      empty ? [] : [candidate],
      null,
      empty ? OwnGhostSummary.empty : OwnGhostSummary(1, 230, candidate),
    );
  }

  OwnGhostReplay replay() => OwnGhostReplay.fromJson({
    ...(ghostApproval(ghostIntent())['playback'] as Map)
        .cast<String, dynamic>(),
    if (unavailable) 'eligible': false,
    if (unavailable) 'unavailableReasons': ['TOTAL_GAP_EXCEEDED'],
  });
  @override
  Future<OwnGhostReplay> playback(String owner, String recordId) async =>
      delayed == null ? replay() : await delayed!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    final fonts = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await fonts.load();
  });
  late RunController runs;
  late FreeRunController ui;
  late EntryCourseApi courses;
  late RecoveryApi starts;
  late EntryGhostSource source;
  late GhostLocation location;
  late GoRouter router;
  late GlobalKey capture;
  var member = 'alice';

  setUp(() {
    member = 'alice';
    courses = EntryCourseApi();
    capture = GlobalKey();
    starts = RecoveryApi();
    source = EntryGhostSource();
    location = GhostLocation()..clock = 100000;
    runs = RunController(
      FailingStore(),
      location,
      courses,
      () async => member,
      wait: (_) async {},
      utcNow: () => location.utc,
      nowMs: location.nowMs,
      recoveryClock: () async => RunClockSample(location.clock, 'boot-a'),
      ghostApi: starts,
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
    ui = FreeRunController.recording(runs);
    router = GoRouter(
      initialLocation: Routes.run,
      routes: [
        GoRoute(path: Routes.run, builder: (_, _) => const FreeRunScreen()),
        GoRoute(
          path: Routes.runCourseSelect,
          builder: (_, _) => const CourseSelectScreen(),
        ),
        GoRoute(
          path: Routes.runOwnGhostSelect,
          builder: (_, _) => const OwnGhostSelectionScreen(),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    ui.dispose();
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    bool course = true,
    double width = 402,
  }) async {
    tester.view.physicalSize = Size(width, 1104);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await runs.bindOwner();
    });
    if (course) runs.selectCourse(const CourseSelection(courseId, '합성 코스'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWith((ref) {
            ref.listen(selectedCourseProvider, (_, next) {
              if (next != null) runs.selectCourse(next);
            });
            return runs;
          }),
          freeRunControllerProvider.overrideWithValue(ui),
          ownGhostSourceProvider.overrideWithValue(source),
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          courseApiClientProvider.overrideWithValue(FakeCourseApi()),
          rankingApiClientProvider.overrideWithValue(FakeCourseRankingApi()),
          reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi()),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            theme: WdTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('고스트 대결'));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.ensureVisible(find.text('내 완주 기록 선택'));
    await tester.tap(find.text('내 완주 기록 선택'));
    await tester.pumpAndSettle();
    expect(find.byType(OwnGhostSelectionView), findsOneWidget);
  }

  Future<void> png(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final bitmap = await boundary.toImage(pixelRatio: 1);
      final bytes = await bitmap.toByteData(
        format: image_ui.ImageByteFormat.png,
      );
      final file = File('build/ghost-entry-check/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      bitmap.dispose();
    });
  }

  Future<void> choose(WidgetTester tester) async {
    await openPicker(tester);
    await tester.tap(find.byType(WdMyRankCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 고스트와 대결하기'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ghost preparation requires both a course and an eligible own record',
    (tester) async {
      await mount(tester, course: false, width: 320);
      expect(find.text('코스를 골라 주세요'), findsOneWidget);
      expect(
        tester
            .widget<WdButton>(find.widgetWithText(WdButton, '고스트 대결 시작'))
            .onPressed,
        isNull,
      );
      expect(source.queries, 0);
      expect(starts.posts, isEmpty);
      expect(tester.takeException(), isNull);
      await png(tester, '320-preparation');
    },
  );

  testWidgets(
    'C8 course selection returns to ghost preparation without starting a run',
    (tester) async {
      await mount(tester, course: false);
      runs.remoteRecords = [
        {
          'id': 'r1',
          'course': {'courseId': courseId, 'courseName': '합성 코스'},
        },
      ];
      await tester.tap(find.text('코스를 골라 주세요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('합성 코스'));
      await tester.pump();
      await tester.tap(find.text('이 코스로 설정'));
      await tester.pumpAndSettle();
      expect(runs.selectedCourse!.courseId, courseId);
      expect(find.text('고스트 대결 시작'), findsOneWidget);
      expect(runs.selectedGhost, isNull);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets(
    'C9 selection reuses one preparation identity through hold countdown and ghost approval',
    (tester) async {
      await mount(tester);
      await choose(tester);
      await png(tester, '402-selected');
      expect(runs.selectedGhost!.candidate.id, sourceId);
      expect(courses.prepared, hasLength(1));
      expect(starts.posts, isEmpty);
      expect(location.streams, isEmpty);
      expect(runs.run, isNull);
      final id = courses.prepared.single.$2;
      final button = find.widgetWithText(WdButton, '고스트 대결 시작');
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        await until(() => !runs.preparing && runs.courseStart != null);
      });
      await tester.pumpAndSettle();
      expect(find.byType(CourseStartView), findsOneWidget);
      expect(starts.posts, isEmpty);
      expect(runs.courseStart!.runId, id);
      final hold = find.byType(RunHoldToStart);
      await tester.runAsync(() async {
        final gesture = await tester.startGesture(tester.getCenter(hold));
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await gesture.up();
        await until(() => !runs.preparing && runs.recorder.active);
      });
      await tester.pumpAndSettle();
      expect(runs.error, isNull);
      expect(starts.posts.single.id, id);
      expect(courses.prepared, hasLength(1));
      expect(courses.started, isEmpty);
      expect(
        runs.run!.inputs.where((p) => p.kind == RunKind.start),
        hasLength(1),
      );
      expect(find.text('내 기록 03:50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no completion or unusable replay keeps the duel action disabled',
    (tester) async {
      source.empty = true;
      await mount(tester);
      await openPicker(tester);
      expect(find.text('이 코스의 완주 기록이 없어요. 먼저 코스를 완주해 보세요.'), findsOneWidget);
      expect(
        tester
            .widget<WdButton>(find.widgetWithText(WdButton, '이 고스트와 대결하기'))
            .onPressed,
        isNull,
      );
      router.pop();
      await tester.pumpAndSettle();
      source.empty = false;
      source.unavailable = true;
      await openPicker(tester);
      await tester.tap(find.byType(WdMyRankCard));
      await tester.pumpAndSettle();
      expect(find.text('GPS 공백이 많은 기록이에요. 다른 기록을 선택해 주세요.'), findsOneWidget);
      expect(runs.selectedGhost, isNull);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets('changing course suppresses a delayed replay response', (
    tester,
  ) async {
    source.delayed = Completer<OwnGhostReplay>();
    await mount(tester);
    await openPicker(tester);
    await tester.tap(find.byType(WdMyRankCard));
    await tester.pump();
    runs.selectCourse(const CourseSelection('different-course', '다른 코스'));
    await tester.pump();
    source.delayed!.complete(source.replay());
    await tester.pumpAndSettle();
    expect(find.byType(OwnGhostSelectionView), findsNothing);
    expect(runs.selectedGhost, isNull);
    expect(starts.posts, isEmpty);
  });

  testWidgets(
    'account change suppresses a delayed replay and clears the old selection',
    (tester) async {
      source.delayed = Completer<OwnGhostReplay>();
      await mount(tester);
      await openPicker(tester);
      await tester.tap(find.byType(WdMyRankCard));
      await tester.pump();
      member = 'bob';
      await tester.runAsync(() => runs.bindOwner());
      source.delayed!.complete(source.replay());
      await tester.pumpAndSettle();
      expect(runs.selectedGhost, isNull);
      expect(runs.selectedCourse, isNull);
      expect(find.byType(OwnGhostSelectionView), findsNothing);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets(
    'switching to ordinary course mode clears the opponent but preserves the course',
    (tester) async {
      await mount(tester);
      await choose(tester);
      await tester.tap(find.text('코스 러닝'));
      await tester.pumpAndSettle();
      expect(runs.selectedGhost, isNull);
      expect(runs.selectedCourse!.courseId, courseId);
      expect(find.text('고스트 대결 시작'), findsNothing);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets(
    'an existing duel returns to its running screen without changing the opponent',
    (tester) async {
      await mount(tester);
      await choose(tester);
      await tester.runAsync(() async {
        await runs.prepareStart();
        await runs.prepareStart();
      });
      final id = runs.run!.id;
      router.push(Routes.runOwnGhostSelect);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, Routes.run);
      expect(find.byType(OwnGhostSelectionView), findsNothing);
      expect(runs.run!.id, id);
      expect(starts.posts, hasLength(1));
    },
  );

  testWidgets(
    'a late course preparation cannot restore a course changed while loading',
    (tester) async {
      courses.gate = Completer<void>();
      await mount(tester);
      await tester.tap(find.text('내 완주 기록 선택'));
      await tester.pump();
      runs.selectCourse(const CourseSelection('other-course', '다른 코스'));
      courses.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(OwnGhostSelectionView), findsNothing);
      expect(runs.selectedCourse!.courseId, 'other-course');
      expect(source.queries, 0);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets(
    'course preparation failure retries without silently substituting an opponent',
    (tester) async {
      courses.prepareError = const ApiException(
        'COURSE-002',
        '사용할 수 없는 코스예요.',
        status: 409,
      );
      await mount(tester);
      await tester.tap(find.text('내 완주 기록 선택'));
      await tester.pumpAndSettle();
      expect(find.text('사용할 수 없는 코스예요.'), findsOneWidget);
      expect(source.queries, 0);
      expect(starts.posts, isEmpty);
      courses.prepareError = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnGhostSelectionView), findsOneWidget);
    },
  );
}
