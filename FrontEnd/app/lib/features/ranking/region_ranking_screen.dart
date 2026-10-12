import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/ranking_api_client.dart';
import 'ranking_state.dart';
import 'ranking_widgets.dart';

/// I5 · 지역 주간 전체 순위. I2의 "더 보기"로 연다. 여기서 지역을 바꾸면 I2도 그 지역을 본다.
class RegionRankingScreen extends ConsumerWidget {
  const RegionRankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(selectedRegionProvider)?.code;
    final provider = regionFeedProvider(code);
    final feed = ref.watch(provider);
    final weekStart = feed.value?.summary.weekStart;
    void reload() {
      ref.invalidate(regionWeeklyProvider(code));
      ref.invalidate(provider);
    }

    return Scaffold(
      appBar: WdAppBar(
        title: '지역 주간 전체 순위',
        onBack: () => context.pop(),
        action: weekStart == null ? null : WdAppBarAction.text(weekLabel(weekStart), onTap: null),
      ),
      body: RankingScrollView(
        onRefresh: () {
          reload();
          return ref.read(provider.future);
        },
        onEnd: () => ref.read(provider.notifier).loadMore(),
        children: [
          const RegionChips(),
          ...switch (feed) {
            AsyncValue(:final value?) => _content(value),
            AsyncValue(:final error?) => [RankingError(error, onRetry: reload)],
            _ => const [RankingLoading()],
          },
        ],
      ),
    );
  }

  List<Widget> _content(RankingFeed<RegionWeeklyRanking> feed) {
    final ranking = feed.summary;
    final entries = [...ranking.top, ...feed.rest];
    final runners = '${grouped(ranking.participantCount)}명';
    return [
      WdStatSummary([
        ('참여 러너', runners),
        ('1위', ranking.top.isEmpty ? '-' : km(ranking.top.first.distanceMeters)),
        (
          '내 순위',
          switch (ranking.me.status) {
            MyRankStatus.ranked => '${ranking.me.rank}위',
            MyRankStatus.private => '비공개',
            _ => '-',
          }
        ),
      ]),
      if (ranking.me.status != MyRankStatus.otherRegion) RegionMyRankCard(ranking),
      WdSectionHeading('전체 순위 $runners'),
      if (entries.isEmpty)
        const RankingEmpty()
      else
        WdRankList(ranks: [for (final entry in entries) regionRank(entry, ranking.region.name)]),
      const WdInfoBanner('매일 자정에 갱신되고, 매주 월요일 00:00에 초기화돼요.', plain: true),
    ];
  }
}
