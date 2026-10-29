import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/features/course/detail/course_ranking_tab.dart';
import 'package:wadadak/features/course/detail/course_rankings_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseRankingApi rankings;

  /// 25명 중 나 24위. 1위부터 10초씩 늦다. 공개 고스트는 1위.
  final runners = [
    for (var rank = 1; rank <= 25; rank++)
      courseRankingEntry(rank, rank == 24 ? '러닝왕김' : '러너$rank', 1450 + rank * 10, pace: 280 + rank, mine: rank == 24),
  ];
  final all = courseRankingSummary(
    participants: 25,
    average: 1580,
    me: const {
      'status': 'RANKED',
      'rank': 24,
      'nickname': '러닝왕김',
      'courseElapsedSeconds': 1690,
      'paceSecondsPerKm': 304,
      'completedAt': '2026-09-08T01:00:00Z',
      'topPercent': 96,
    },
    top: runners.take(5).toList(),
    ghost: 1,
  );

  Future<void> openRankings(WidgetTester tester, {RankingPeriod period = RankingPeriod.all}) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [rankingApiClientProvider.overrideWithValue(rankings)],
      child: MaterialApp(
        theme: WdTheme.light(),
        home: CourseRankingsScreen(courseId: 'c1', courseName: '한강 야경 5K', period: period),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<String> chips(WidgetTester tester) => [
        for (final chip in tester.widgetList<WdFilterChip>(find.byType(WdFilterChip)))
          '${chip.label}${chip.selected ? '*' : ''}',
      ];
  List<WdRank> ranks(WidgetTester tester) => tester.widget<WdRankList>(find.byType(WdRankList)).ranks;
  List<(String, bool)> bottomButtons(WidgetTester tester) => [
        for (final button in tester.widgetList<WdButton>(
            find.descendant(of: find.byType(WdBottomBar), matching: find.byType(WdButton))))
          (button.label, button.onPressed != null),
      ];
  Future<void> pull(WidgetTester tester) async {
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
  }

  setUp(() {
    rankings = FakeCourseRankingApi({RankingPeriod.all: all})..rows[RankingPeriod.all] = runners;
  });

  testWidgets('shows the stats, my rank and the runners with their finish dates (Figma G3)', (tester) async {
    await openRankings(tester);

    final appBar = tester.widget<WdAppBar>(find.byType(WdAppBar));
    expect((appBar.title, appBar.action?.label), ('전체 순위', '한강 야경 5K'));
    expect(chips(tester), ['전체 기간*', '이번 달', '이번 주']);
    expect(tester.widget<WdStatSummary>(find.byType(WdStatSummary)).items,
        [('참여 러너', '25명'), ('1위 기록', '24:20'), ('평균 기록', '26:20')]);
    final me = tester.widget<WdMyRankCard>(find.byType(WdMyRankCard));
    expect([me.data.rank, me.data.name, me.data.meta, me.data.value],
        ['24', '나 (러닝왕김)', '5′04″/km · 09.08 · 상위 96%', '28:10']);
    expect(me.onTap, isNull, reason: '내 순위는 누를 수 없다');
    expect(find.text('전체 순위 25명'), findsOneWidget);
    expect(find.textContaining('프로필'), findsNothing, reason: 'I3가 생길 때까지 러너를 누를 수 없다');
    expect(tester.widget<WdRankList>(find.byType(WdRankList)).onTap, isNull);
    expect(ranks(tester), hasLength(20), reason: '처음에는 한 페이지만');
    final first = ranks(tester).first;
    expect('${first.rank} ${first.name} ${first.meta} ${first.value}', '1 러너1 4′41″/km · 09.07 24:20');
    expect(rankings.entryRequests, [(RankingPeriod.all, null)]);
    expect(bottomButtons(tester), [('이 코스로 달리기', true), ('고스트 대결 ▶', true)]);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(rankings.entryRequests, [(RankingPeriod.all, null), (RankingPeriod.all, '20')], reason: '끝 가까이에서 이어 받는다');
    expect(ranks(tester), hasLength(25));
    expect(ranks(tester)[23].name, '나 (러닝왕김)');
  });

  testWidgets('opens with the period from B9 and asks again from the first runner on a change or a pull',
      (tester) async {
    rankings
      ..summaries[RankingPeriod.week] = courseRankingSummary(participants: 2, average: 1500, top: runners.take(2).toList())
      ..rows[RankingPeriod.week] = runners.take(2).toList();
    await openRankings(tester, period: RankingPeriod.week);

    expect(chips(tester), ['전체 기간', '이번 달', '이번 주*']);
    expect(ranks(tester), hasLength(2));
    expect(tester.widget<WdMyRankCard>(find.byType(WdMyRankCard)).data.meta, '이번 주 완주 기록이 없어요');
    expect(bottomButtons(tester), [('고스트 없음', false), ('이 코스로 달리기', true)], reason: '이번 주에는 공개 고스트가 없다');

    await tester.tap(find.text('이번 달'));
    await tester.pumpAndSettle();
    expect(find.text('전체 순위 0명'), findsOneWidget);
    expect(find.text('이번 달에 완주한 러너가 아직 없어요'), findsOneWidget);
    expect(find.byType(WdRankList), findsNothing);

    await tester.tap(find.text('전체 기간'));
    await tester.pumpAndSettle();
    await pull(tester);
    expect(rankings.summaryRequests, [RankingPeriod.week, RankingPeriod.month, RankingPeriod.all, RankingPeriod.all]);
    expect(rankings.entryRequests.map((request) => request.$2), everyElement(isNull), reason: '모두 1위부터');
  });

  testWidgets('offers to retry with dashes when it cannot be loaded', (tester) async {
    rankings.entriesError = const ApiException('NETWORK', '');
    await openRankings(tester);

    expect(tester.widget<WdStatSummary>(find.byType(WdStatSummary)).items,
        [('참여 러너', '—'), ('1위 기록', '—'), ('평균 기록', '—')]);
    expect(find.text(CourseRankingTab.failedMessage), findsOneWidget);
    expect(bottomButtons(tester).last, ('고스트 대결 ▶', false));

    rankings.entriesError = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(ranks(tester), hasLength(20));
    expect(bottomButtons(tester).last, ('고스트 대결 ▶', true));
  });

  testWidgets('keeps the runners and offers to retry when a pull fails', (tester) async {
    await openRankings(tester);
    rankings.error = const ApiException('NETWORK', '');
    await pull(tester);

    expect(ranks(tester), hasLength(20), reason: '받아 둔 순위 그대로');
    expect(find.text(CourseRankingTab.staleMessage), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: '다시 시도 줄로 알린다');

    rankings.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text(CourseRankingTab.staleMessage), findsNothing);
  });

  testWidgets('no longer shows the obsolete ghost placeholder', (tester) async {
    await openRankings(tester);

    await tester.tap(find.text('고스트 대결 ▶'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
