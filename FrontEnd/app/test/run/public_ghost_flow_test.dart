import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/course_run_entry.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/public_ghost_api.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/presentation/ghost_prep_view.dart';
import 'package:wadadak/features/run/presentation/public_ghost_entry_screen.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'ghost_controller_recovery_test.dart' show GhostLocation;
import '../fakes.dart' show FakeCourseApi, FakeCourseReviewApi;
import 'ghost_recovery_support.dart';
import 'recording/course_run_start_test.dart' show CourseApi;
import 'recording/run_controller_test.dart' show FailingStore, until;

Map<String, dynamic> publicPreparation({String period = 'WEEK'}) => {
  'publicPeriod': period,
  'candidate': {
    'runRecordId': sourceId,
    'memberId': 'other',
    'rank': 1,
    'courseElapsedSeconds': 230,
  },
  'playback': ghostApproval(ghostIntent())['playback'],
};

class PublicSource implements PublicGhostSource {
  final calls = <String>[];
  Completer<Map<String, dynamic>>? gate;
  bool denied = false;
  @override
  Future<Map<String, dynamic>> prepare(
    String owner,
    String source,
    String course,
    String period,
  ) async {
    calls.add('$owner/$source/$course/$period');
    if (denied) throw StateError('private');
    return gate == null ? publicPreparation(period: period) : gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late RunController runs;
  late CourseApi courses;
  late RecoveryApi starts;
  late GhostLocation location;
  late PublicSource source;
  late GoRouter router;
  String member = 'alice';

  setUp(() {
    member = 'alice';
    courses = CourseApi();
    starts = RecoveryApi()
      ..onStart = (i) async => {
        ...ghostApproval(i),
        'publicPeriod': i.publicPeriod,
      };
    location = GhostLocation()..clock = 100000;
    source = PublicSource();
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
    router = GoRouter(
      initialLocation: '/entry',
      routes: [
        GoRoute(
          path: '/entry',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) => Scaffold(
              body: WdButton(
                '공개 상대 선택',
                onPressed: () => runPublicGhost(
                  context,
                  ref,
                  const CourseSelection(courseId, '등록된 코스'),
                  GhostCandidate.fromJson({
                    'runRecordId': sourceId,
                    'memberId': 'other',
                    'rank': 1,
                    'courseElapsedSeconds': 230,
                  }),
                  RankingPeriod.week,
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: Routes.runPublicGhost,
          builder: (_, state) =>
              PublicGhostEntryScreen(args: state.extra! as PublicGhostArgs),
        ),
        GoRoute(
          path: Routes.run,
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: GhostRunPrep(
                course: runs.selectedCourse,
                ghost: runs.selectedGhost,
              ),
            ),
          ),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final s in location.streams) {
      await s.close();
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 402,
    bool selected = true,
    VoidCallback? beforeTap,
  }) async {
    tester.view.physicalSize = Size(width, 1104);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => runs.bindOwner());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(runs),
          publicGhostSourceProvider.overrideWithValue(source),
          courseApiClientProvider.overrideWithValue(FakeCourseApi()),
          reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi()),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    beforeTap?.call();
    await tester.tap(find.text('공개 상대 선택'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      if (selected && source.gate == null && !source.denied) {
        await until(() => runs.selectedGhost != null);
      }
    });
    if (source.gate == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets(
    'public ranking entry directly selects the opponent in existing preparation at 320px',
    (tester) async {
      await mount(tester, width: 320);
      expect(router.routeInformationProvider.value.uri.path, Routes.run);
      expect(source.calls.single, endsWith('/WEEK'));
      expect(find.text('선택한 공개 기록'), findsOneWidget);
      expect(find.text('대결 상대 · 공개 코스 기록'), findsOneWidget);
      expect(find.text('내 완주 기록으로 변경'), findsOneWidget);
      expect(find.text('재생 미리보기'), findsNothing);
      expect(courses.prepared, hasLength(1));
      expect(starts.posts, isEmpty);
      expect(courses.started, isEmpty);
      expect(runs.run, isNull);
      expect(runs.recorder.active, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal public start reuses preparation and durably saves the selected period',
    (tester) async {
      await mount(tester);
      expect(runs.selectedGhost!.publicPeriod, 'WEEK');
      await tester.runAsync(() async {
        await runs.prepareStart();
        await runs.prepareStart();
      });
      expect(runs.error, isNull);
      expect(runs.recorder.active, true);
      expect(courses.prepared, hasLength(1));
      expect(starts.posts.single.request['publicPeriod'], 'WEEK');
      expect(courses.started, isEmpty);
      final saved = await tester.runAsync(
        () async => (await runs.store.list('alice')).single,
      );
      final context = GhostRunContext.fromJson(saved!.ghost!.toJson());
      expect(context.intent.publicPeriod, 'WEEK');
      expect(context.replay.playback.at(100000).coursePositionM, isNotNull);
    },
  );

  testWidgets(
    'account change discards a delayed public response before course preparation',
    (tester) async {
      source.gate = Completer();
      await mount(tester);
      await tester.runAsync(() async {
        member = 'bob';
        await runs.bindOwner();
      });
      source.gate!.complete(publicPreparation());
      await tester.pumpAndSettle();
      expect(find.textContaining('계정 또는 진행 중인 러닝이 바뀌었어요'), findsOneWidget);
      expect(runs.selectedGhost, isNull);
      expect(courses.prepared, isEmpty);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets(
    'unavailable public record cannot replace the opponent or start a course',
    (tester) async {
      source.denied = true;
      await mount(tester);
      expect(find.textContaining('공개 기록을 사용할 수 없어요'), findsOneWidget);
      expect(source.calls, hasLength(1));
      expect(runs.selectedGhost, isNull);
      expect(courses.prepared, isEmpty);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets(
    'pending start returns to the existing run without fetching another opponent',
    (tester) async {
      await mount(
        tester,
        selected: false,
        beforeTap: () => runs.hasPendingGhostStart = true,
      );
      expect(router.routeInformationProvider.value.uri.path, Routes.run);
      expect(source.calls, isEmpty);
      expect(courses.prepared, isEmpty);
      expect(runs.hasPendingGhostStart, true);
      expect(starts.posts, isEmpty);
    },
  );

  testWidgets('mismatched public period response cannot enter preparation', (
    tester,
  ) async {
    source.gate = Completer();
    await mount(tester);
    source.gate!.complete(publicPreparation(period: 'ALL'));
    await tester.pumpAndSettle();
    expect(find.textContaining('공개 기록을 사용할 수 없어요'), findsOneWidget);
    expect(runs.selectedGhost, isNull);
    expect(courses.prepared, isEmpty);
    expect(starts.posts, isEmpty);
  });

  testWidgets('changed course geometry cannot select an old public opponent', (
    tester,
  ) async {
    courses.startLat = 37;
    await mount(tester, selected: false);
    expect(find.textContaining('공개 기록을 사용할 수 없어요'), findsOneWidget);
    expect(runs.selectedGhost, isNull);
    expect(starts.posts, isEmpty);
    expect(runs.run, isNull);
  });

  test('public period is durable and mismatched approval is rejected', () {
    final original = ghostIntent();
    final request = GhostStartIntent(
      owner: original.owner,
      id: original.id,
      startedAt: original.startedAt,
      course: original.course,
      sourceId: original.sourceId,
      sourceSeconds: original.sourceSeconds,
      clock: original.clock,
      publicPeriod: 'ALL',
    );
    expect(GhostStartIntent.fromJson(request.toJson()).publicPeriod, 'ALL');
    expect(
      () => GhostRunContext(request, {
        ...ghostApproval(request),
        'publicPeriod': 'WEEK',
      }),
      throwsFormatException,
    );
    expect(
      GhostRunContext(request, {
        ...ghostApproval(request),
        'publicPeriod': 'ALL',
      }).intent.publicPeriod,
      'ALL',
    );
  });
}
