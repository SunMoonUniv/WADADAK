import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/api/upload_form.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/my/run_history_screen.dart';
import 'package:wadadak/features/review/review_form_screen.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/run_voice.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../run/recording/run_controller_test.dart' as fake;

/// 서버 기록 한 줄(RecordSummary). [course]가 있으면 코스 러닝, [ghost]가 있으면 고스트 대결이다.
Map<String, dynamic> _summary(String id, String startedAt, {Map<String, dynamic>? course, String? ghost}) => {
  'id': id,
  'startedAt': startedAt,
  'endReason': 'USER',
  'metrics': {'distanceM': 5210.0, 'elapsedMs': 1634000, 'activeMs': 1634000, 'movingMs': 1634000, 'paceSecondsPerKm': 313.6, 'gapCount': 0},
  'course': course,
  'ghost': ghost == null ? null : {'outcome': ghost, 'reason': 'COMPLETED_TIME_COMPARISON', 'completed': true},
};

const _course = {
  'courseId': 'course-1',
  'courseName': '한강 야경 5K',
  'completed': true,
  'progressPercent': 100.0,
  'reviewEligible': true,
};

/// 서버 기록 두 페이지(최근 순). 첫 페이지: 코스 완주 · 코스 62% · 자유 러닝(10/12~14), 둘째: 9월 자유 러닝.
class _HistoryApi extends fake.TestApi {
  final cursors = <String?>[];
  final sizes = <int?>[];
  bool withSeptember = true;

  /// 첫 페이지 끝에 코스 위 고스트 대결(승리, 10/11)과 자유 고스트 대결(패배, 10/10)을 붙인다.
  bool withGhosts = false;

  @override
  Future<Map<String, dynamic>> history(String owner, {String? cursor, int? size}) async {
    cursors.add(cursor);
    sizes.add(size);
    return cursor == null
        ? {
            'content': [
              _summary('run-course', '2026-10-14T03:00:00Z', course: _course),
              _summary('run-half', '2026-10-13T03:00:00Z', course: {..._course, 'courseId': 'course-2', 'courseName': '성북천 벚꽃길 3K', 'completed': false, 'progressPercent': 62.4}),
              _summary('run-free', '2026-10-12T03:00:00Z'),
              if (withGhosts) ...[
                _summary('run-ghost-course', '2026-10-11T03:00:00Z', course: _course, ghost: 'WIN'),
                _summary('run-ghost-free', '2026-10-10T03:00:00Z', ghost: 'LOSE'),
              ],
            ],
            'nextCursor': withSeptember ? 'next' : null,
          }
        : {
            'content': [_summary('run-september', '2026-09-20T03:00:00Z')],
            'nextCursor': null,
          };
  }
}

/// 기기 저장소. 테스트에서 실제 DB를 열지 않도록 목록 · 삭제 · 음성 설정을 메모리로 바꾼다.
/// [withLocal]이면 아직 올리지 않은 기기 기록 하나가 있다.
class _LocalStore extends fake.FailingStore {
  bool withLocal = false;
  RunVoiceSettings settings = const RunVoiceSettings();

  @override
  Future<Set<String>> deletedIds(String owner) async => {};

  @override
  Future<List<String>> pendingDeletions(String owner) async => [];

  // This in-memory history fixture has no pending ghost starts or closures.
  @override
  Future<List<PendingGhostStart>> pendingGhostStarts(String owner) async => [];

  @override
  Future<List<String>> pendingGhostClosures(String owner) async => [];

  @override
  Future<RunVoiceSettings> voiceSettings(String owner) async => settings;

  @override
  Future<List<recording.LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  }) async => !withLocal || unfinishedOnly || pendingOnly
      ? []
      : [
          recording.LocalRun(
            id: 'local',
            owner: owner,
            startedAt: DateTime.parse('2026-10-15T03:00:00Z'),
            phase: recording.RunPhase.ended,
            syncState: 'pending',
            inputsLoaded: !summaryOnly,
            // 거리 0인 기록은 목록에서 빠져서(정책) 거리를 준다
            summary: {
              'metrics': {'distanceM': 1200.0, 'elapsedMs': 480000, 'paceSecondsPerKm': 400.0},
            },
          ),
        ];
}

/// 리뷰 진입(`openReviewWriter`)이 묻는 내 리뷰 상태. 자격 있는 기록이 있어 B2로 간다.
class _ReviewApi implements ReviewApiClient {
  final asked = <String>[];

  @override
  Future<MyReview> mine(String courseId) async {
    asked.add(courseId);
    return MyReview.fromJson({
      'review': null,
      'sourceRecord': null,
      'sourceRecordDeleted': false,
      'eligibleRecord': {
        'runRecordId': 'run-course',
        'courseDistanceMeters': 5200,
        'courseElapsedSeconds': 1634,
        'progressPercent': 100,
        'completed': true,
        'endedAt': '2026-10-14T03:30:00Z',
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');

  @override
  Future<UploadForm> photoUploadForm() => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LocalStore store;
  late _ReviewApi reviews;
  late _HistoryApi history;

  /// I1을 띄운다. 코스 상세(B1) · 기록 상세는 이름만 보이는 화면으로 바꿔 어디로 갔는지만 본다.
  Future<void> openHistory(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 2200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gps = fake.TestLocation();
    final c = RunController(store, gps, history, () async => 'alice', automaticTicks: false, nowMs: gps.nowMs);
    final ui = FreeRunController.recording(c);
    addTearDown(() {
      ui.dispose();
      c.dispose();
    });
    final router = GoRouter(
      routes: [
        // 오늘은 2026-10-15(목)이다
        GoRoute(path: '/', builder: (_, _) => MyRunHistoryScreen(now: () => DateTime(2026, 10, 15, 12))),
        GoRoute(path: '/course/:id', builder: (_, state) => Text('B1 ${state.pathParameters['id']}')),
        GoRoute(path: '/my/record/:id', builder: (_, state) => Text('기록 ${state.pathParameters['id']}')),
        GoRoute(path: Routes.reviewForm, builder: (_, state) => ReviewFormScreen(args: state.extra! as ReviewFormArgs)),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(c),
          freeRunControllerProvider.overrideWithValue(ui),
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          reviewApiClientProvider.overrideWithValue(reviews),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cardOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(RunRecordCard));

  /// 의미 라벨로 찾는다(막대 · 화살표는 글자가 없다).
  Finder labeled(String label) =>
      find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

  setUp(() {
    store = _LocalStore();
    reviews = _ReviewApi();
    history = _HistoryApi();
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('I1 loads every record 50 at a time and sums the whole period', (tester) async {
    await openHistory(tester);

    expect(history.cursors, [null, 'next']);
    // 첫 페이지는 run 컨트롤러가 로그인 확인 때 서버 기본 개수로 먼저 받는다. 이어 받는 페이지부터 50개씩이다
    expect(history.sizes, [null, 50]);
    expect(find.text('전체 4'), findsOneWidget);
    // 전체 기간: 5.21km × 4, 27:14 × 4, 움직인 시간 합 ÷ 거리 합. 칼로리는 계산식이 아직 없다
    expect(find.text('전체 기간'), findsOneWidget);
    expect(find.text('20.84'), findsOneWidget);
    expect(find.text('01:48:56'), findsOneWidget);
    expect(find.text('5′14″'), findsOneWidget);
    expect(find.text('칼로리(kcal)'), findsOneWidget);
  });

  testWidgets('calendar stamps run days and the list shows only that month', (tester) async {
    await openHistory(tester);

    expect(find.text('2026.10'), findsOneWidget);
    for (final day in [12, 13, 14]) {
      expect(labeled('10월 $day일 달림'), findsOneWidget);
    }
    expect(labeled('10월 15일 달림'), findsNothing);
    expect(find.text('10월 분석'), findsOneWidget);
    expect(find.text('15.63km  /  01:21:42  /  5′14″  /  —kcal'), findsOneWidget);
    expect(find.byType(RunRecordCard), findsNWidgets(3)); // 9월 기록은 빠진다
    expect(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('완주')), findsOneWidget);
    expect(find.descendant(of: cardOf('성북천 벚꽃길 3K'), matching: find.text('62% 주행')), findsOneWidget);
    expect(find.descendant(of: cardOf('자유 러닝'), matching: find.text('기록')), findsOneWidget);
    expect(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('27:14 · 5.21km · 5′14″/km')), findsOneWidget);
    expect(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('수')), findsOneWidget); // 10/14 수요일
    // 코스 러닝에만 버튼이 있다
    expect(find.text('리뷰 쓰기'), findsNWidgets(2));
    expect(find.descendant(of: cardOf('자유 러닝'), matching: find.text('리뷰 쓰기')), findsNothing);
  });

  testWidgets('moving the month changes the calendar, analysis and list but not the total', (tester) async {
    await openHistory(tester);

    await tap(tester, labeled('이전 달'));
    expect(find.text('2026.09'), findsOneWidget);
    expect(labeled('9월 20일 달림'), findsOneWidget);
    expect(find.text('9월 분석'), findsOneWidget);
    expect(find.text('5.21km  /  27:14  /  5′14″  /  —kcal'), findsOneWidget);
    expect(find.byType(RunRecordCard), findsOneWidget);
    expect(find.text('20.84'), findsOneWidget); // 전체 기간은 그대로

    // 첫 기록이 9월이라 더 앞으로는 못 간다
    await tap(tester, labeled('이전 달'));
    expect(find.text('2026.09'), findsOneWidget);

    await tap(tester, find.text('오늘'));
    expect(find.text('2026.10'), findsOneWidget);
    // 이번 달보다 뒤로는 못 간다
    await tap(tester, labeled('다음 달'));
    expect(find.text('2026.10'), findsOneWidget);
  });

  testWidgets('a month with no runs says so', (tester) async {
    history.withSeptember = false;
    await openHistory(tester);
    store.withLocal = false;

    await tap(tester, find.text('고스트 대결'));
    expect(find.text('아직 고스트 대결 기록이 없어요.'), findsOneWidget);
    expect(find.byType(RunRecordCard), findsNothing);
  });

  testWidgets('the month sheet picks a month but not one after this month', (tester) async {
    await openHistory(tester);

    await tap(tester, labeled('연 · 월 고르기'));
    expect(find.text('연 · 월 선택'), findsOneWidget);

    // 월 휠을 한 칸 아래로(11월): 이번 달보다 뒤라 적용할 수 없다
    await tester.drag(find.byType(ListWheelScrollView).last, const Offset(0, -48));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('연 · 월 선택'), findsOneWidget);

    // 두 칸 위로(9월) 고르고 적용
    await tester.drag(find.byType(ListWheelScrollView).last, const Offset(0, 96));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('연 · 월 선택'), findsNothing);
    expect(find.text('2026.09'), findsOneWidget);
  });

  testWidgets('type tabs filter the total, calendar and list', (tester) async {
    await openHistory(tester);

    await tap(tester, find.text('코스 러닝'));
    expect(find.text('코스 러닝 2'), findsOneWidget);
    expect(find.text('10.42'), findsOneWidget);
    expect(labeled('10월 12일 달림'), findsNothing); // 자유 러닝 날은 도장이 없다
    expect(find.byType(RunRecordCard), findsNWidgets(2));
    expect(cardOf('자유 러닝'), findsNothing);

    await tap(tester, find.text('고스트 대결'));
    expect(find.text('고스트 대결 0'), findsOneWidget);
    expect(find.text('아직 고스트 대결 기록이 없어요.'), findsOneWidget);
  });

  testWidgets('ghost duels show only in the ghost tab with the server verdict', (tester) async {
    history.withGhosts = true;
    await openHistory(tester);

    // 전체에는 다 보이고, 대결 기록은 승 · 패 태그를 단다
    expect(find.byType(RunRecordCard), findsNWidgets(5));
    expect(find.descendant(of: cardOf('고스트 대결'), matching: find.text('패배')), findsOneWidget);
    final courseDuel = find.ancestor(of: find.text('승리'), matching: find.byType(RunRecordCard));
    expect(find.descendant(of: courseDuel, matching: find.text('한강 야경 5K')), findsOneWidget);
    // 코스 위 대결이라 코스 버튼은 그대로 있다
    expect(find.descendant(of: courseDuel, matching: find.text('리뷰 쓰기')), findsOneWidget);

    // 자유 · 코스 탭에는 대결 기록이 없다. 자유 러닝은 카드 제목과 겹쳐서 탭 막대 안에서 찾는다
    await tap(tester, find.descendant(of: find.byType(WdTabBar), matching: find.text('자유 러닝')));
    expect(find.text('자유 러닝 2'), findsOneWidget); // 10/12 + 9월
    expect(find.text('패배'), findsNothing);
    await tap(tester, find.text('코스 러닝'));
    expect(find.text('코스 러닝 2'), findsOneWidget);
    expect(find.text('승리'), findsNothing);

    await tap(tester, find.text('고스트 대결'));
    expect(find.text('고스트 대결 2'), findsOneWidget);
    expect(find.byType(RunRecordCard), findsNWidgets(2));
    expect(find.text('승리'), findsOneWidget);
    expect(find.text('패배'), findsOneWidget);
    for (final day in [10, 11]) {
      expect(labeled('10월 $day일 달림'), findsOneWidget);
    }
    expect(labeled('10월 12일 달림'), findsNothing);
  });

  testWidgets('a run still on the device waits for sync', (tester) async {
    store.withLocal = true;
    await openHistory(tester);

    expect(find.descendant(of: cardOf('러닝'), matching: find.text('동기화 대기')), findsOneWidget);
  });

  testWidgets('write review opens B2 with the eligible record of that course', (tester) async {
    await openHistory(tester);

    await tap(tester, find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('리뷰 쓰기')));

    expect(reviews.asked, ['course-1']);
    final form = tester.widget<ReviewFormScreen>(find.byType(ReviewFormScreen));
    expect(form.args.courseId, 'course-1');
    expect(form.args.courseName, '한강 야경 5K');
    expect(form.args.record!.runRecordId, 'run-course');
  });

  testWidgets('course detail opens B1 of that course', (tester) async {
    await openHistory(tester);

    await tap(tester, find.descendant(of: cardOf('성북천 벚꽃길 3K'), matching: find.text('코스 상세')));

    expect(find.text('B1 course-2'), findsOneWidget);
  });

  testWidgets('a card opens the record', (tester) async {
    await openHistory(tester);

    await tap(tester, cardOf('자유 러닝').first);

    expect(find.text('기록 run-free'), findsOneWidget);
  });
}
