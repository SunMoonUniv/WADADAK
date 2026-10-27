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
import 'package:wadadak/features/run/domain/run_voice.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../run/recording/run_controller_test.dart' as fake;

/// 서버 기록 한 줄(RecordSummary). [course]가 있으면 코스 러닝이다.
Map<String, dynamic> _summary(String id, String startedAt, {Map<String, dynamic>? course}) => {
  'id': id,
  'startedAt': startedAt,
  'endReason': 'USER',
  'metrics': {'distanceM': 5210.0, 'elapsedMs': 1634000, 'activeMs': 1634000, 'movingMs': 1634000, 'paceSecondsPerKm': 313.6, 'gapCount': 0},
  'course': course,
};

const _course = {
  'courseId': 'course-1',
  'courseName': '한강 야경 5K',
  'completed': true,
  'progressPercent': 100.0,
  'reviewEligible': true,
};

/// 서버 기록 세 페이지(최근 순).
/// 첫 페이지: 코스 완주 · 코스 62% · 자유 러닝(이번 주 월~수), 둘째: 9월 자유 러닝, 셋째: 8월 자유 러닝.
class _HistoryApi extends fake.TestApi {
  final cursors = <String?>[];

  @override
  Future<Map<String, dynamic>> history(String owner, {String? cursor}) async {
    cursors.add(cursor);
    return cursor == null
        ? {
            'content': [
              _summary('run-course', '2026-10-14T03:00:00Z', course: _course),
              _summary('run-half', '2026-10-13T03:00:00Z', course: {..._course, 'courseId': 'course-2', 'courseName': '성북천 벚꽃길 3K', 'completed': false, 'progressPercent': 62.4}),
              _summary('run-free', '2026-10-12T03:00:00Z'),
            ],
            'nextCursor': 'next',
          }
        : cursor == 'next'
        ? {
            'content': [_summary('run-september', '2026-09-20T03:00:00Z')],
            'nextCursor': 'more',
          }
        : {
            'content': [_summary('run-august', '2026-08-10T03:00:00Z')],
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
      ..physicalSize = const Size(402, 1400)
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

  testWidgets('I1 shows course and free run cards with their results', (tester) async {
    await openHistory(tester);

    expect(find.text('한강 야경 5K'), findsOneWidget);
    expect(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('5.21km · 27:14 · 5′14″/km')), findsOneWidget);
    expect(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('10.14 (수)')), findsOneWidget);
    expect(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('완주')), findsOneWidget);
    expect(find.descendant(of: cardOf('성북천 벚꽃길 3K'), matching: find.text('62% 주행')), findsOneWidget);
    expect(find.descendant(of: cardOf('자유 러닝'), matching: find.text('기록')), findsNWidgets(2));
    // 코스 러닝에만 버튼이 있다
    expect(find.text('리뷰 쓰기'), findsNWidgets(2));
    expect(find.descendant(of: cardOf('자유 러닝'), matching: find.text('리뷰 쓰기')), findsNothing);
  });

  testWidgets('I1 loads only what this month and this week need', (tester) async {
    await openHistory(tester);

    // 10월 1일보다 앞선 기록(9월)이 나오면 멈춘다. 8월 페이지는 받지 않는다
    expect(history.cursors, [null, 'next']);
    expect(find.text('2026년 10월'), findsOneWidget);
    // 10월 기록 3개: 5.21km × 3, 움직인 시간 합 ÷ 거리 합
    expect(find.text('이번 달 거리'), findsOneWidget);
    expect(find.text('15.6 km'), findsOneWidget);
    expect(find.text('3회'), findsOneWidget);
    expect(find.text('5′14″'), findsOneWidget);
    // 이번 주(10/12 월 ~ 10/18 일)
    expect(labeled('월 5.2km'), findsOneWidget);
    expect(labeled('수 5.2km'), findsOneWidget);
    expect(labeled('목 0.0km'), findsOneWidget);
  });

  testWidgets('month arrows change only the summary and load that month', (tester) async {
    await openHistory(tester);

    await tester.tap(labeled('이전 달'));
    await tester.pumpAndSettle();

    // 9월 1일보다 앞선 기록이 나올 때까지 더 받는다
    expect(history.cursors, [null, 'next', 'more']);
    expect(find.text('2026년 9월'), findsOneWidget);
    expect(find.text('9월 거리'), findsOneWidget);
    expect(find.text('5.2 km'), findsOneWidget);
    expect(find.text('1회'), findsOneWidget);
    // 차트는 이번 주, 목록은 전체 그대로다
    expect(labeled('월 5.2km'), findsOneWidget);
    expect(find.text('한강 야경 5K'), findsOneWidget);
    // 다 받았고 첫 기록이 8월이라 8월보다 앞으로는 못 간다
    await tester.tap(labeled('이전 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 8월'), findsOneWidget);
    await tester.tap(labeled('이전 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 8월'), findsOneWidget);

    await tester.tap(labeled('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 9월'), findsOneWidget);
  });

  testWidgets('type tabs filter the summary, chart and list', (tester) async {
    await openHistory(tester);

    await tester.tap(find.text('코스 러닝'));
    await tester.pumpAndSettle();
    expect(find.text('10.4 km'), findsOneWidget);
    expect(find.byType(RunRecordCard), findsNWidgets(2));
    expect(cardOf('자유 러닝'), findsNothing);
    expect(labeled('월 0.0km'), findsOneWidget);

    await tester.tap(find.text('고스트 대결'));
    await tester.pumpAndSettle();
    expect(find.text('아직 고스트 대결 기록이 없어요.'), findsOneWidget);
    expect(find.text('이전 기록 더 보기'), findsNothing); // 더 받아도 고스트 기록은 없다
  });

  testWidgets('older records load page by page', (tester) async {
    await openHistory(tester);
    expect(find.byType(RunRecordCard), findsNWidgets(4));

    await tester.ensureVisible(find.text('이전 기록 더 보기'));
    await tester.tap(find.text('이전 기록 더 보기'));
    await tester.pumpAndSettle();

    expect(history.cursors, [null, 'next', 'more']);
    expect(find.byType(RunRecordCard), findsNWidgets(5));
    expect(find.text('이전 기록 더 보기'), findsNothing); // 다 받았다
  });

  testWidgets('a run still on the device waits for sync', (tester) async {
    store.withLocal = true;
    await openHistory(tester);

    expect(find.descendant(of: cardOf('러닝'), matching: find.text('동기화 대기')), findsOneWidget);
  });

  testWidgets('write review opens B2 with the eligible record of that course', (tester) async {
    await openHistory(tester);

    await tester.tap(find.descendant(of: cardOf('한강 야경 5K'), matching: find.text('리뷰 쓰기')));
    await tester.pumpAndSettle();

    expect(reviews.asked, ['course-1']);
    final form = tester.widget<ReviewFormScreen>(find.byType(ReviewFormScreen));
    expect(form.args.courseId, 'course-1');
    expect(form.args.courseName, '한강 야경 5K');
    expect(form.args.record!.runRecordId, 'run-course');
  });

  testWidgets('course detail opens B1 of that course', (tester) async {
    await openHistory(tester);

    await tester.tap(find.descendant(of: cardOf('성북천 벚꽃길 3K'), matching: find.text('코스 상세')));
    await tester.pumpAndSettle();

    expect(find.text('B1 course-2'), findsOneWidget);
  });

  testWidgets('a card opens the record', (tester) async {
    await openHistory(tester);

    await tester.tap(cardOf('자유 러닝').first);
    await tester.pumpAndSettle();

    expect(find.text('기록 run-free'), findsOneWidget);
  });
}
