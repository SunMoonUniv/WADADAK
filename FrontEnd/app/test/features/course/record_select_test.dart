import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/course/course_format.dart';
import 'package:wadadak/features/course/course_list_card.dart';
import 'package:wadadak/features/course/course_public_period_sheet.dart';
import 'package:wadadak/features/course/create/record_select_rows.dart';
import 'package:wadadak/features/course/create/record_select_screen.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';
import '../../run/recording/run_controller_test.dart' as fake;
import 'record_fakes.dart';

/// 한도를 몇 번 물었는지 센다. [gate]가 있으면 열릴 때까지 답하지 않고, [error]가 있으면 받지 못한다.
class _QuotaApi extends FakeCourseApi {
  var asked = 0;
  Completer<void>? gate;
  Object? error;

  @override
  Future<RegistrationQuota> registrationQuota() async {
    asked++;
    await gate?.future;
    if (error != null) throw error!;
    return quota;
  }
}

/// 당겨서 새로고침의 기록 올리기가 [gate]가 열릴 때까지 끝나지 않는다.
class _SlowSync extends RunController {
  _SlowSync(super.store, super.location, super.api, super.owner, {super.automaticTicks, super.nowMs});

  final gate = Completer<void>();
  var refreshed = 0;

  @override
  Future<void> sync({bool manual = false}) async {
    if (manual) {
      refreshed++;
      await gate.future;
    }
    return super.sync(manual: manual);
  }
}

RegistrationQuota _quota({int remaining = 2, List<String> used = const ['run-used']}) => RegistrationQuota(
  custom: const TypeQuota(limit: 1, remaining: 1),
  gps: TypeQuota(limit: 3, remaining: remaining),
  usedRunRecordIds: used,
);

/// 가운데에서 GPS가 끊긴 달린 경로(구간 2개).
const _route = [
  [GeoPoint(37.5280, 126.9330), GeoPoint(37.5290, 126.9350)],
  [GeoPoint(37.5300, 126.9370), GeoPoint(37.5310, 126.9390)],
];

/// 서버 기록 두 페이지(최근 순). 오늘은 2026-10-29(목)이다. 날짜 제목은 한국 시간이다.
final _firstPage = [
  recordSummary('run-free', '2026-10-28T03:00:00Z', meters: 4100, seconds: 1360, route: _route), // 10.28 (수) 등록 가능
  recordSummary('run-course', '2026-10-27T03:00:00Z', meters: 5200, course: true), // 10.27 (화)
  recordSummary('run-gap', '2026-10-26T03:00:00Z', gpsGap: false), // 10.26 (월)
  recordSummary('run-checking', '2026-10-25T03:00:00Z', meters: 3000, gpsGap: null), // 10.25 (일)
  recordSummary('run-used', '2026-10-24T03:00:00Z', meters: 2000), // 10.24 (토)
  recordSummary('run-short', '2026-10-23T03:00:00Z', meters: 800), // 10.23 (금)
  recordSummary('run-ghost', '2026-10-22T03:00:00Z', meters: 6000, ghost: 'LOSE'), // 10.22 (목) 자유 기록 고스트 대결
  recordSummary('run-course-ghost', '2026-10-21T03:00:00Z', meters: 5200, course: true, ghost: 'WIN'), // 10.21 (수)
];
final _secondPage = [recordSummary('run-last-year', '2025-09-20T03:00:00Z', meters: 10000)]; // 2025.09.20 (토)

/// 아직 올리지 않은 기기 기록(10.29 (목)).
recording.LocalRun _pending() => recording.LocalRun(
  id: 'local',
  owner: 'alice',
  startedAt: DateTime.parse('2026-10-29T03:00:00Z'),
  phase: recording.RunPhase.ended,
  inputsLoaded: false,
  summary: {
    'metrics': {'distanceM': 1200.0, 'elapsedMs': 480000, 'paceSecondsPerKm': 400.0},
  },
);

void main() {
  group('rows', () {
    final at = DateTime.utc(2026, 10, 28, 3);
    RecordChoice choice({
      double meters = 5000,
      bool synced = true,
      bool onCourse = false,
      bool? gpsGapPassed = true,
    }) => RecordChoice(
      id: 'run',
      startedAt: at,
      distanceMeters: meters,
      elapsed: const Duration(minutes: 30),
      paceSecondsPerKm: 360,
      synced: synced,
      onCourse: onCourse,
      gpsGapPassed: gpsGapPassed,
    );

    test('status is the first reason that blocks registering (B6-04)', () {
      expect(statusOf(choice(meters: 800, synced: false, onCourse: true), {'run'}), RecordStatus.tooShort);
      expect(statusOf(choice(synced: false), {}), RecordStatus.pendingSync);
      // 코스를 달린 기록은 GPS가 끊겨도 `이미 등록된 코스`다(공통 3)
      expect(statusOf(choice(onCourse: true, gpsGapPassed: false), {'run'}), RecordStatus.onCourse);
      expect(statusOf(choice(gpsGapPassed: null), {'run'}), RecordStatus.checking);
      expect(statusOf(choice(gpsGapPassed: false), {'run'}), RecordStatus.gpsGap);
      expect(statusOf(choice(), {'run'}), RecordStatus.used);
      expect(statusOf(choice(meters: 1000), {}), RecordStatus.registrable);
    });

    test('merges device and server records, preferring the server summary', () {
      final rows = recordChoices(
        local: [
          // 올린 직후 기기 요약에는 GPS 끊김 판정이 아직 없다
          recording.LocalRun(
            id: 'synced',
            owner: 'alice',
            startedAt: at,
            syncState: 'synced',
            summary: {
              'metrics': {'distanceM': 4000.0},
            },
          ),
          recording.LocalRun(
            id: 'pending',
            owner: 'alice',
            startedAt: at,
            result: {
              'metrics': {'distanceM': 2500.0, 'elapsedMs': 900000},
            },
          ),
          recording.LocalRun(id: 'deleted-local', owner: 'alice', startedAt: at),
        ],
        remote: [
          recordSummary('synced', '2026-10-28T03:00:00Z', meters: 4000),
          recordSummary('course-ghost', '2026-10-27T03:00:00Z', course: true, ghost: 'WIN'),
          recordSummary('deleted', '2026-10-26T03:00:00Z'),
        ],
        deletedIds: {'deleted', 'deleted-local'},
      );

      expect([for (final r in rows) r.id], ['synced', 'pending', 'course-ghost']);
      expect(rows[0].gpsGapPassed, isTrue);
      expect(rows[0].typeLabel, '자유 러닝');
      expect(rows[1].synced, isFalse);
      expect(rows[1].distanceMeters, 2500);
      expect(rows[1].typeLabel, '러닝', reason: '올리기 전에는 코스 판정이 없다(I1과 같다)');
      expect(rows[2].onCourse, isTrue);
      expect(rows[2].typeLabel, '고스트 대결');
    });

    test('takes the card route from the server summary, blank for older records (4.1 B6 카드 경로 그림)', () {
      final later = recordSummary('later', '2026-10-26T03:00:00Z', route: _route);
      (later['routeThumbnail'] as Map)['version'] = 'RUN_ROUTE_THUMBNAIL_V2';
      final broken = recordSummary('broken', '2026-10-25T03:00:00Z', route: _route);
      (broken['routeThumbnail'] as Map)['segments'] = [
        [
          {'lat': 37.5},
        ],
      ];
      final rows = recordChoices(
        local: [],
        remote: [
          recordSummary('new', '2026-10-28T03:00:00Z', route: _route),
          recordSummary('old', '2026-10-27T03:00:00Z'),
          later,
          broken,
        ],
        deletedIds: {},
      );

      expect(rows[0].route, _route, reason: '끊긴 구간은 따로 받는다');
      expect(rows[1].route, isEmpty, reason: '경로가 생기기 전 예전 기록은 채우지 않는다');
      expect(rows[2].route, isEmpty, reason: '모르는 형식은 그리지 않는다');
      expect(rows[3].route, isEmpty, reason: '선을 그릴 수 없는 값은 화면을 깨뜨리지 않고 빈 칸이다');
    });

    test('distance sort flips on a second tap and keeps recent first on a tie', () {
      RecordChoice run(String id, double meters, int daysAgo) => RecordChoice(
        id: id,
        startedAt: at.subtract(Duration(days: daysAgo)),
        distanceMeters: meters,
        elapsed: Duration.zero,
        paceSecondsPerKm: null,
        synced: true,
      );
      final runs = [run('short', 2000, 0), run('long-old', 8000, 2), run('long-new', 8000, 1)];
      List<String> sorted(RecordSort sort) => [for (final r in [...runs]..sort(sort.compare)) r.id];

      expect(sorted(RecordSort.recent), ['short', 'long-new', 'long-old']);
      expect(sorted(RecordSort.longest), ['long-new', 'long-old', 'short']);
      expect(sorted(RecordSort.shortest), ['short', 'long-new', 'long-old']);
      expect(RecordSort.recent.distanceTapped, RecordSort.longest);
      expect(RecordSort.longest.distanceTapped, RecordSort.shortest);
      expect(RecordSort.shortest.distanceTapped, RecordSort.longest);
    });
  });

  group('screen', () {
    late MemoryRunStore store;
    late RecordHistoryApi history;
    late _QuotaApi courses;
    late GoRouter router;

    setUp(() {
      store = MemoryRunStore()..local = [_pending()];
      history = RecordHistoryApi([_firstPage, _secondPage]);
      courses = _QuotaApi()..quota = _quota();
    });

    /// B6을 띄운다. D4는 이름만 보이는 화면으로 바꿔 어떤 기록으로 갔는지만 본다.
    Future<void> open(WidgetTester tester, {RunController? runs}) async {
      tester.view
        ..physicalSize = const Size(402, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      runs ??= recordRuns(store, history);
      addTearDown(runs.dispose);
      router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => RecordSelectScreen(now: () => DateTime.utc(2026, 10, 29, 3))),
          GoRoute(path: '/course/new/gps/:id', builder: (_, state) => Text('D4 ${state.pathParameters['id']}')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runControllerProvider.overrideWithValue(runs),
            courseApiClientProvider.overrideWithValue(courses),
          ],
          child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Finder cardOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(WdRunRecordCard));

    Finder inCard(String title, String text) => find.descendant(of: cardOf(title), matching: find.text(text));

    /// 흐린 카드(등록할 수 없는 기록).
    bool dimmed(String title) => find
        .ancestor(of: cardOf(title), matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.55))
        .evaluate()
        .isNotEmpty;

    List<String> titles(WidgetTester tester) => [
      for (final card in tester.widgetList<WdRunRecordCard>(find.byType(WdRunRecordCard))) card.title,
    ];

    Finder chip(String label) => find.widgetWithText(WdFilterChip, label);

    testWidgets('lists every record with its type and why it can or cannot be registered (B6-04)', (tester) async {
      await open(tester);

      expect(find.text('내 기록에서 등록'), findsOneWidget);
      expect(find.widgetWithText(Tab, '전체'), findsOneWidget, reason: '기록 유형은 `전체` 탭 하나다');
      expect(find.text('자유 러닝'), findsNWidgets(6), reason: '칩은 없고 카드 태그만 있다');
      expect(find.text(RecordSelectScreen.guide), findsOneWidget);
      expect(find.text(gpsQuotaUsedUpMessage), findsNothing);
      expect(history.cursors, [null, 'page-1'], reason: '끝까지 받는다');
      expect(history.sizes.last, 50, reason: '이어 받을 때는 50개씩 받는다');
      expect(find.text('등록 가능한 기록 3'), findsOneWidget);
      expect(titles(tester), [
        '10.29 (목)',
        '10.28 (수)',
        '10.27 (화)',
        '10.26 (월)',
        '10.25 (일)',
        '10.24 (토)',
        '10.23 (금)',
        '10.22 (목)',
        '10.21 (수)',
        '2025.09.20 (토)',
      ]);

      expect(inCard('10.28 (수)', '4.10 km · 22:40 · 5′32″/km'), findsOneWidget);
      List<List<GeoPoint>> routeOf(String title) => tester
          .widget<CourseRouteThumbnail>(find.descendant(of: cardOf(title), matching: find.byType(CourseRouteThumbnail)))
          .segments;
      expect(routeOf('10.28 (수)'), _route, reason: '서버 요약의 경로를 그린다');
      expect(routeOf('10.27 (화)'), isEmpty, reason: '경로가 생기기 전 예전 기록은 빈 칸');
      expect(routeOf('10.29 (목)'), isEmpty, reason: '올리지 않은 기록은 서버 경로가 없다');
      for (final (title, type, status) in [
        ('10.29 (목)', '러닝', '동기화 대기'),
        ('10.28 (수)', '자유 러닝', '등록 가능'),
        ('10.27 (화)', '코스 러닝', '이미 등록된 코스'),
        ('10.26 (월)', '자유 러닝', 'GPS 끊김'),
        ('10.25 (일)', '자유 러닝', '확인 중'),
        ('10.24 (토)', '자유 러닝', '이미 등록됨'),
        ('10.23 (금)', '자유 러닝', '1km 미만'),
        ('10.22 (목)', '고스트 대결', '등록 가능'),
        ('10.21 (수)', '고스트 대결', '이미 등록된 코스'),
        ('2025.09.20 (토)', '자유 러닝', '등록 가능'),
      ]) {
        expect(inCard(title, type), findsOneWidget, reason: title);
        expect(inCard(title, status), findsOneWidget, reason: title);
        expect(dimmed(title), status != '등록 가능', reason: title);
      }
    });

    testWidgets('distance sort shows longest first, then shortest on a second tap (B6-02)', (tester) async {
      await open(tester);
      bool selected(String label) => tester.widget<WdFilterChip>(chip(label)).selected;
      const longest = [
        '2025.09.20 (토)', // 10 km
        '10.22 (목)', // 6 km
        '10.27 (화)', // 5.2 km — 같은 거리는 최근 기록이 먼저
        '10.21 (수)', // 5.2 km
        '10.26 (월)',
        '10.28 (수)',
        '10.25 (일)',
        '10.24 (토)',
        '10.29 (목)',
        '10.23 (금)', // 0.8 km
      ];

      expect(selected('최신순 ▾'), isTrue);
      expect(selected('거리순 ▾'), isFalse);

      await tap(tester, chip('거리순 ▾'));
      expect(titles(tester), longest);
      expect(selected('거리순 ▾'), isTrue);
      expect(selected('최신순 ▾'), isFalse);

      await tap(tester, chip('거리순 ▾'));
      expect(titles(tester), [
        '10.23 (금)',
        '10.29 (목)',
        '10.24 (토)',
        '10.25 (일)',
        '10.28 (수)',
        '10.26 (월)',
        '10.27 (화)',
        '10.21 (수)',
        '10.22 (목)',
        '2025.09.20 (토)',
      ]);
      expect(selected('거리순 ▴'), isTrue);
      expect(chip('거리순 ▾'), findsNothing);

      await tap(tester, chip('최신순 ▾'));
      expect(titles(tester).first, '10.29 (목)');
      expect(selected('거리순 ▾'), isFalse, reason: '다시 누르면 긴 기록부터다');

      await tap(tester, chip('거리순 ▾'));
      expect(titles(tester), longest);
    });

    testWidgets('a registrable record opens B11, then D4 (B6-03)', (tester) async {
      await open(tester);
      expect(courses.asked, 1);

      // 흐린 카드는 눌리지 않는다
      await tap(tester, cardOf('10.27 (화)'));
      expect(find.text(CoursePublicPeriodSheet.title), findsNothing);

      // B11을 닫으면 B6에 머문다
      await tap(tester, cardOf('10.28 (수)'));
      expect(courses.asked, 2, reason: '누를 때 한도를 다시 본다');
      expect(find.text(CoursePublicPeriodSheet.title), findsOneWidget);
      await tap(tester, find.byTooltip('닫기'));
      expect(find.text(CoursePublicPeriodSheet.title), findsNothing);
      expect(find.textContaining('D4'), findsNothing);

      await tap(tester, cardOf('10.28 (수)'));
      await tap(tester, find.widgetWithText(WdButton, '확인'));
      expect(find.text('D4 run-free'), findsOneWidget);

      // D4에서 등록하지 않고 돌아오면 한도를 다시 받는다
      courses.quota = _quota(remaining: 0);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(RecordSelectScreen), findsOneWidget);
      expect(find.text(gpsQuotaUsedUpMessage), findsOneWidget);
    });

    testWidgets('shows progress and holds the list while checking the quota (B6-03)', (tester) async {
      await open(tester);
      final gate = courses.gate = Completer<void>();

      await tester.tap(cardOf('10.28 (수)'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // 다른 등록 가능한 카드는 눌리지 않는다
      await tester.tap(cardOf('10.22 (목)'), warnIfMissed: false);
      await tester.pump();
      expect(courses.asked, 2);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tap(tester, find.widgetWithText(WdButton, '확인'));
      expect(find.text('D4 run-free'), findsOneWidget);
    });

    testWidgets('does not block when the quota cannot be read (B6-06)', (tester) async {
      await open(tester);

      courses.error = TypeError(); // 응답 모양이 달라 읽지 못했다
      await tap(tester, cardOf('10.28 (수)'));

      expect(find.text(CoursePublicPeriodSheet.title), findsOneWidget, reason: 'D4 등록 때 서버가 다시 본다');
    });

    testWidgets('stops when today\'s GPS courses are used up (B6-06)', (tester) async {
      courses.quota = _quota(remaining: 0);
      await open(tester);

      expect(find.text(gpsQuotaUsedUpMessage), findsOneWidget);
      await tap(tester, cardOf('10.28 (수)'));

      expect(find.text(gpsQuotaUsedUpMessage), findsNWidgets(2), reason: '배너 + 알림');
      expect(find.text(CoursePublicPeriodSheet.title), findsNothing);
    });

    testWidgets('a record registered meanwhile turns to already registered', (tester) async {
      await open(tester);

      courses.quota = _quota(used: ['run-used', 'run-free']);
      await tap(tester, cardOf('10.28 (수)'));

      expect(find.text(RecordSelectScreen.usedMessage), findsOneWidget);
      expect(find.text(CoursePublicPeriodSheet.title), findsNothing);
      expect(inCard('10.28 (수)', '이미 등록됨'), findsOneWidget);
      expect(dimmed('10.28 (수)'), isTrue);
      expect(find.text('등록 가능한 기록 2'), findsOneWidget);
    });

    testWidgets('keeps device records when server records fail and loads them again (B6-05)', (tester) async {
      history.fail = true;
      await open(tester);

      expect(find.text('서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.'), findsOneWidget);
      expect(titles(tester), ['10.29 (목)']);
      expect(find.text('등록 가능한 기록 0'), findsOneWidget);

      history.fail = false;
      await tap(tester, find.text('다시 불러오기'));

      expect(find.text('서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.'), findsNothing);
      expect(titles(tester), hasLength(10));
      expect(find.text('등록 가능한 기록 3'), findsOneWidget);
    });

    testWidgets('says so when there is no record yet (B6-05)', (tester) async {
      store.local = [];
      history.pages = [[]];
      await open(tester);

      expect(find.text('아직 달린 기록이 없어요.'), findsOneWidget);
      expect(find.text('등록 가능한 기록 0'), findsOneWidget);
    });

    testWidgets('stops refreshing when B6 is closed while records upload', (tester) async {
      final gps = fake.TestLocation();
      final runs = _SlowSync(store, gps, history, () async => 'alice', automaticTicks: false, nowMs: gps.nowMs);
      await open(tester, runs: runs);

      // 당겨서 새로고침. 기록을 올리는 사이 화면을 닫는다
      unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(runs.refreshed, 1);
      router.go('/course/new/gps/run-free');
      await tester.pumpAndSettle();
      expect(find.byType(RecordSelectScreen), findsNothing);

      final requests = history.cursors.length;
      runs.gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(history.cursors, hasLength(requests), reason: '닫은 뒤에는 기록을 다시 받지 않는다');
    });

    testWidgets('floors the distance so a run just under 1 km never reads 1.00 km', (tester) async {
      store.local = [];
      history.pages = [
        [recordSummary('run-almost', '2026-10-28T03:00:00Z', meters: 999.6)],
      ];
      await open(tester);

      expect(inCard('10.28 (수)', '0.99 km · 30:00 · 30′01″/km'), findsOneWidget);
      expect(inCard('10.28 (수)', '1km 미만'), findsOneWidget);
    });

    testWidgets('wraps the tags with large text on a narrow phone', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      store.local = [];
      history.pages = [
        [_firstPage.last], // 고스트 대결 · 이미 등록된 코스
      ];
      await open(tester);
      tester.view.physicalSize = const Size(320, 2400);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '한 줄에 다 들어가지 않는 태그는 다음 줄로 내린다');
      expect(inCard('10.21 (수)', '이미 등록된 코스'), findsOneWidget);
    });
  });
}
