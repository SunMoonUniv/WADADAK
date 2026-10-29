import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui_image;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/data/free_ghost_api.dart';
import 'package:wadadak/features/run/domain/free_ghost.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/features/run/presentation/free_ghost_selection_screen.dart';
import 'package:wadadak/features/run/presentation/course_start_view.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import 'ghost_controller_recovery_test.dart' show GhostLocation;
import 'ghost_recovery_support.dart';
import 'recording/run_controller_test.dart' show FailingStore, until;
import 'recording/course_run_start_test.dart' show CourseApi;

Map<String, dynamic> preparation({
  bool eligible = true,
  String version = 'GHOST_PLAYBACK_FREE_V1',
}) {
  final base = ghostApproval(ghostIntent());
  final replay = {
    ...(base['playback'] as Map).cast<String, dynamic>(),
    'version': version,
    'course': {
      ...ghostCourse(sourceId).toJson(),
      'courseId': null,
      'version': 1,
    },
    'eligible': eligible,
    if (!eligible) 'unavailableReasons': ['TOTAL_GAP_EXCEEDED'],
  };
  return {
    'playback': replay,
    'originalDistanceM': 1200.0,
    'originalElapsedMs': 260000,
    'endReason': 'INTERRUPTED',
    'referenceHash': 'a' * 64,
  };
}

Map<String, dynamic> approval(GhostStartIntent i) => {
  ...ghostApproval(i),
  'version': 'GHOST_START_FREE_V1',
  'playback': {
    ...(ghostApproval(i)['playback'] as Map).cast<String, dynamic>(),
    'version': i.playbackVersion,
  },
};

class Choices implements FreeGhostSource {
  bool eligible = true;
  Map<String, dynamic>? response;
  int reads = 0;
  Completer<Map<String, dynamic>>? gate;
  @override
  Future<({List<FreeGhostCandidate> content, String? nextCursor})> candidates(
    String owner, {
    String period = 'ALL',
    String? cursor,
  }) async => (
    content: [
      for (final (id, distance) in [('small', 999.9), (sourceId, 1200.0)])
        FreeGhostCandidate.fromJson({
          'id': id,
          'startedAt': ghostEpoch.toIso8601String(),
          'distanceM': distance,
          'elapsedMs': 260000,
          'endReason': 'INTERRUPTED',
          'distanceEligible': distance >= 1000,
        }),
    ],
    nextCursor: null,
  );
  @override
  Future<Map<String, dynamic>> prepare(String owner, String id) async {
    reads++;
    return gate == null
        ? response ?? preparation(eligible: eligible)
        : gate!.future;
  }
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
  late CourseApi courses;
  late RecoveryApi starts;
  late GhostLocation location;
  late Choices choices;
  late GoRouter router;
  late GlobalKey capture;
  var member = 'alice';
  setUp(() {
    member = 'alice';
    courses = CourseApi();
    starts = RecoveryApi()..onStart = (i) async => approval(i);
    location = GhostLocation()..clock = 100000;
    choices = Choices();
    capture = GlobalKey();
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
          path: Routes.runFreeGhostSelect,
          builder: (_, _) => const FreeGhostSelectionScreen(),
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
    for (final s in location.streams) {
      await s.close();
    }
  });
  Future<void> mount(WidgetTester tester, {double width = 402}) async {
    tester.view.physicalSize = Size(width, 1104);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => runs.bindOwner());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(runs),
          freeRunControllerProvider.overrideWithValue(ui),
          freeGhostSourceProvider.overrideWithValue(choices),
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
    await tester.tap(find.text('내 자유 기록 선택'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byType(WdRankRow).at(1));
    await tester.pumpAndSettle();
  }

  Future<void> png(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(
        format: ui_image.ImageByteFormat.png,
      );
      final f = File('build/free-ghost-check/$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'free picker disables sub-kilometre records and allows an interrupted source at 320px',
    (tester) async {
      await mount(tester, width: 320);
      expect(
        tester.widget<WdRankRow>(find.byType(WdRankRow).first).onTap,
        isNull,
      );
      await tester.tap(find.byType(WdRankRow).first);
      await tester.pumpAndSettle();
      expect(choices.reads, 0);
      await choose(tester);
      expect(find.text('대결 비교 시간'), findsOneWidget);
      expect(find.text('원래 기록 04:20'), findsOneWidget);
      await png(tester, '320-selected');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('이 기록과 대결하기'));
      await tester.pumpAndSettle();
      expect(runs.selectedCourse, isNull);
      expect(runs.selectedFreeGhost!.endReason, 'INTERRUPTED');
      expect(courses.prepared, isEmpty);
      expect(starts.posts, isEmpty);
    },
  );
  testWidgets(
    'free source starts and persists without any registered course preparation or start',
    (tester) async {
      await mount(tester);
      await choose(tester);
      await png(tester, '402-selected');
      await tester.tap(find.text('이 기록과 대결하기'));
      await tester.pumpAndSettle();
      final start = find.widgetWithText(WdButton, '고스트 대결 시작');
      await tester.ensureVisible(start);
      await tester.runAsync(() async {
        await tester.tap(start);
        await until(() => !runs.preparing && runs.courseStart != null);
      });
      await tester.pumpAndSettle();
      expect(find.byType(CourseStartView), findsOneWidget);
      expect(runs.courseStart!.course, isNull);
      await tester.runAsync(() async {
        await runs.prepareStart();
      });
      await tester.pumpAndSettle();
      expect(runs.error, isNull);
      expect(runs.recorder.active, true);
      expect(courses.prepared, isEmpty);
      expect(courses.started, isEmpty);
      expect(starts.posts.single.course.courseId, isNull);
      expect(starts.posts.single.referenceHash, 'a' * 64);
      final saved = await tester.runAsync(
        () async => (await runs.store.list('alice')).single,
      );
      expect(saved!.ghost!.intent.isFree, true);
      final restored = GhostRunContext.fromJson(saved.ghost!.toJson());
      expect(restored.intent.referenceHash, 'a' * 64);
      expect(restored.replay.playback.at(100000).coursePositionM, isNotNull);
      expect(find.textContaining('거리 '), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'quality failure and late response after account change cannot select a source',
    (tester) async {
      choices.eligible = false;
      await mount(tester);
      await choose(tester);
      expect(find.textContaining('위치를 알 수 없는 시간이 5%를 초과'), findsOneWidget);
      expect(
        tester
            .widget<WdButton>(find.widgetWithText(WdButton, '이 기록과 대결하기'))
            .onPressed,
        isNull,
      );
      choices.gate = Completer();
      await tester.tap(find.byType(WdRankRow).at(1));
      await tester.pump();
      await tester.runAsync(() async {
        member = 'bob';
        await runs.bindOwner();
      });
      choices.gate!.complete(preparation());
      await tester.pumpAndSettle();
      expect(runs.selectedFreeGhost, isNull);
    },
  );
  testWidgets(
    'selection expires at 15 seconds, ignores late data and can retry',
    (tester) async {
      final first = Completer<Map<String, dynamic>>();
      choices.gate = first;
      await mount(tester);
      final row = find.byType(WdRankRow).at(1);
      await tester.tap(row);
      await tester.pump();
      expect(find.text('확인 중'), findsOneWidget);
      expect(tester.widget<WdRankRow>(row).onTap, isNull);
      expect(choices.reads, 1);
      await tester.pump(const Duration(milliseconds: 14999));
      expect(find.text('확인 중'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('확인 중'), findsNothing);
      expect(
        find.text(freeGhostPreparationTimeoutError.message),
        findsOneWidget,
      );
      expect(tester.widget<WdRankRow>(row).onTap, isNotNull);
      expect(find.text('대결 비교 시간'), findsNothing);

      final second = Completer<Map<String, dynamic>>();
      choices.gate = second;
      await tester.tap(row);
      await tester.pump();
      expect(choices.reads, 2);
      first.complete(preparation());
      await tester.pumpAndSettle();
      expect(find.text('확인 중'), findsOneWidget);
      expect(find.text('대결 비교 시간'), findsNothing);
      second.complete(preparation(version: 'GHOST_PLAYBACK_FREE_V2'));
      await tester.pumpAndSettle();
      expect(find.text('확인 중'), findsNothing);
      expect(find.text('대결 비교 시간'), findsOneWidget);
      expect(find.text(freeGhostPreparationTimeoutError.message), findsNothing);
      expect(starts.posts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selection completed before deadline stays selected afterwards', (
    tester,
  ) async {
    choices.gate = Completer();
    await mount(tester);
    await tester.tap(find.byType(WdRankRow).at(1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 14));
    choices.gate!.complete(preparation());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('대결 비교 시간'), findsOneWidget);
    expect(find.text(freeGhostPreparationTimeoutError.message), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a pending selection cancels its screen deadline', (
    tester,
  ) async {
    choices.gate = Completer();
    await mount(tester);
    await tester.tap(find.byType(WdRankRow).at(1));
    await tester.pump();
    router.go(Routes.run);
    await tester.pumpAndSettle();
    choices.gate!.completeError(StateError('late source failure'));
    await tester.pump(const Duration(seconds: 15));
    expect(find.byType(FreeGhostSelectionScreen), findsNothing);
    expect(runs.selectedFreeGhost, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('specific distance failure fits 320px and keeps duel disabled', (
    tester,
  ) async {
    choices.response = {
      ...preparation(eligible: false),
      'playback': {
        ...preparation(eligible: false)['playback'] as Map,
        'unavailableReasons': ['REFERENCE_NOT_REPRODUCIBLE'],
      },
      'diagnostics': {
        'reason': 'DISTANCE_SHORT',
        'recognizedPercent': 78.690075,
        'recognizedDistanceM': 1390.8532,
        'referenceDistanceM': 1767.5078,
      },
    };
    await mount(tester, width: 320);
    await choose(tester);
    expect(find.textContaining('78.69%'), findsOneWidget);
    expect(find.textContaining('95%'), findsOneWidget);
    expect(
      tester
          .widget<WdButton>(find.widgetWithText(WdButton, '이 기록과 대결하기'))
          .onPressed,
      isNull,
    );
    await png(tester, '320-unavailable');
    expect(tester.takeException(), isNull);
    expect(runs.selectedFreeGhost, isNull);
    expect(starts.posts, isEmpty);
  });
  test('free approval rejects a changed route break', () {
    final p = PreparedFreeGhost('alice', preparation());
    final c = p.reference;
    final intent = GhostStartIntent(
      owner: 'alice',
      id: ghostId,
      startedAt: ghostEpoch,
      course: CourseSnapshot(
        sessionId: ghostId,
        route: c.route,
        totalDistanceMeters: c.totalDistanceMeters,
        version: 1,
      ),
      sourceId: sourceId,
      sourceSeconds: 230,
      clock: const RunClockSample(100000, 'boot-a'),
      referenceHash: p.referenceHash,
    );
    final receipt = approval(intent);
    expect(GhostRunContext(intent, receipt).intent.isFree, true);
    (receipt['course'] as Map)['breaks'] = [1];
    expect(() => GhostRunContext(intent, receipt), throwsFormatException);
  });
  testWidgets('private verdict and pending retry fit a narrow result screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1104);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var retries = 0;
    Future<void> show({Map<String, dynamic>? ghost}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
          child: MaterialApp(
            theme: WdTheme.light(),
            home: FreeRunResultView(
              run: RunSnapshot(
                state: RunState.finished,
                sessionId: ghostId,
                startedAt: ghostEpoch,
                elapsed: const Duration(seconds: 250),
                active: Duration.zero,
                distanceMeters: 0,
                inputs: const [],
                ghost: ghost,
                ghostPending: ghost == null,
                storageStatus: '거리 기록 없음',
              ),
              onConfirm: () {},
              onRetryGhost: () => retries++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    expect(find.text('서버 판정 대기'), findsOneWidget);
    await tester.tap(find.text('판정 다시 확인'));
    expect(retries, 1);
    await show(
      ghost: {
        'outcome': 'LOSE',
        'courseElapsedSeconds': 250,
        'sourceElapsedSeconds': 230,
      },
    );
    expect(find.text('패배'), findsOneWidget);
    expect(find.text('상대 03:50'), findsOneWidget);
    expect(find.text('판정 다시 확인'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
