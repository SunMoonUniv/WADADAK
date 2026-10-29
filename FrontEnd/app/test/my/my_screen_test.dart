import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/features/my/my_screen.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/domain/run_voice.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import '../run/recording/run_controller_test.dart' as fake;

/// 서버 기록 한 줄(RecordSummary).
Map<String, dynamic> _summary(String id, double meters) => {
  'id': id,
  'startedAt': '2026-10-14T03:00:00Z',
  'endReason': 'USER',
  'metrics': {'distanceM': meters, 'elapsedMs': 1634000, 'movingMs': 1634000, 'paceSecondsPerKm': 313.6},
  'course': null,
};

/// 서버 기록 두 페이지: 5.21km · 3.4km, 다음 페이지 1.0km. [fail]이면 둘째 페이지에서 실패한다.
class _HistoryApi extends fake.TestApi {
  bool fail = false;

  @override
  Future<Map<String, dynamic>> history(String owner, {String? cursor, int? size}) async {
    if (cursor == null) {
      return {
        'content': [_summary('a', 5210), _summary('b', 3400)],
        'nextCursor': 'next',
      };
    }
    if (fail) throw const ApiException(ApiException.network, '오프라인');
    return {
      'content': [_summary('c', 1000)],
      'nextCursor': null,
    };
  }
}

/// 기기 저장소. 기기에만 있는 기록은 없다.
class _LocalStore extends fake.FailingStore {
  @override
  Future<Set<String>> deletedIds(String owner) async => {};

  @override
  Future<List<String>> pendingDeletions(String owner) async => [];

  @override
  Future<List<PendingGhostStart>> pendingGhostStarts(String owner) async => [];

  @override
  Future<List<CourseStartIntent>> pendingCourseStarts(String owner) async => [];

  @override
  Future<List<String>> pendingGhostClosures(String owner) async => [];

  @override
  Future<RunVoiceSettings> voiceSettings(String owner) async => const RunVoiceSettings();

  @override
  Future<List<recording.LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  }) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMemberApi members;
  late _HistoryApi history;
  late MemoryTokenStorage tokens;

  /// E3을 띄운다. I1은 이름만 보이는 화면으로 바꿔 어디로 갔는지만 본다.
  Future<void> openMy(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gps = fake.TestLocation();
    final c = RunController(_LocalStore(), gps, history, () async => 'alice', automaticTicks: false, nowMs: gps.nowMs);
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: Routes.my,
      routes: [
        GoRoute(path: Routes.my, builder: (_, _) => const MyScreen()),
        GoRoute(path: Routes.myRecords, builder: (_, _) => const Text('I1')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(c),
          memberApiClientProvider.overrideWithValue(members),
          tokenStorageProvider.overrideWithValue(tokens),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    members = FakeMemberApi();
    history = _HistoryApi();
    tokens = MemoryTokenStorage(testTokens);
  });

  /// [label] 통계 칸 안의 [value].
  Finder stat(String label, String value) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(WdSurface)),
    matching: find.text(value),
  );

  testWidgets('E3 shows my profile with region, affiliation and running experience', (tester) async {
    await openMy(tester);

    expect(members.meCalls, 1);
    expect(find.text('wonehgus'), findsOneWidget);
    expect(find.text('성북구 · 선문대학교 · 러닝 6개월+'), findsOneWidget);
  });

  testWidgets('empty profile parts are skipped', (tester) async {
    members.profile = {...members.profile, 'affiliation': null, 'region': null, 'runningExperience': 'BEGINNER'};
    await openMy(tester);

    expect(find.text('러닝 입문'), findsOneWidget);
  });

  testWidgets('total distance and run count add up every record', (tester) async {
    await openMy(tester);

    // 5.21 + 3.4 + 1.0 = 9.61km, 3회. 등록 코스는 API가 없어 자리만 둔다
    expect(stat('총 거리', '9.61 km'), findsOneWidget);
    expect(stat('러닝', '3회'), findsOneWidget);
    expect(stat('등록 코스', '—'), findsOneWidget);
    expect(find.text('3회'), findsNWidgets(2)); // 통계 + 내 러닝 기록 줄
  });

  testWidgets('totals stay blank when records stop loading halfway', (tester) async {
    history.fail = true;
    await openMy(tester);

    expect(stat('총 거리', '—'), findsOneWidget);
    expect(stat('러닝', '—'), findsOneWidget);
  });

  testWidgets('my run records opens I1, unbuilt screens say they are coming', (tester) async {
    await openMy(tester);

    await tester.tap(find.text('저장한 코스'));
    await tester.pump();
    expect(find.text('저장한 코스 화면은 준비 중이에요.'), findsOneWidget);

    await tester.tap(find.text('편집'));
    await tester.pump();
    expect(find.text('프로필 편집 화면은 준비 중이에요.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('설정'));
    await tester.pump();
    expect(find.text('설정 화면은 준비 중이에요.'), findsOneWidget);

    await tester.tap(find.text('내 러닝 기록'));
    await tester.pumpAndSettle();
    expect(find.text('I1'), findsOneWidget);
  });

  testWidgets('a failed profile can be loaded again', (tester) async {
    members.meError = const ApiException(ApiException.network, '오프라인');
    await openMy(tester);
    expect(find.text('내 정보를 불러오지 못했어요.'), findsOneWidget);

    members.meError = null;
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('wonehgus'), findsOneWidget);
    expect(members.meCalls, 2);
  });

  testWidgets('logout stays at the bottom until F4 exists', (tester) async {
    await openMy(tester);

    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(members.logouts, 1);
    expect(tokens.tokens, isNull);
  });
}
