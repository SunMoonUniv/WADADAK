import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/ranking_api_client.dart';
import '../../routes.dart';
import 'ranking_state.dart';
import 'ranking_widgets.dart';

/// E1 · 랭킹. 전체 랭킹(이번 주 · 이번 달 · 누적)과 지역 주간 랭킹(I2) 탭.
///
/// 순위는 매일 자정에 계산한 값이라 들어올 때 · 기간이나 지역을 바꿀 때 · 당겨서 새로고침할 때만 받는다.
/// 다른 러너를 누르면 I3로 간다(I3가 생기면 연결).
class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: WdAppBar(title: '랭킹'),
          body: Column(
            children: [
              WdTabBar(tabs: ['전체 랭킹', '지역 주간 랭킹']),
              Divider(height: 1, thickness: 1, color: WdColors.divider),
              Expanded(child: TabBarView(children: [_DistanceTab(), _RegionTab()])),
            ],
          ),
        ),
      );
}

/// (기간, 칩, 안내 문구의 기준)
const _periods = [
  (RankingPeriod.week, '이번 주', '이번 주'),
  (RankingPeriod.month, '이번 달', '이번 달'),
  (RankingPeriod.all, '누적', '총'),
];

class _DistanceTab extends ConsumerStatefulWidget {
  const _DistanceTab();

  @override
  ConsumerState<_DistanceTab> createState() => _DistanceTabState();
}

class _DistanceTabState extends ConsumerState<_DistanceTab> with AutomaticKeepAliveClientMixin {
  var _period = RankingPeriod.all;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = distanceFeedProvider(_period);
    final feed = ref.watch(provider);
    final (_, chip, basis) = _periods.firstWhere((p) => p.$1 == _period);
    return RankingScrollView(
      onRefresh: () => ref.refresh(provider.future),
      onEnd: () => ref.read(provider.notifier).loadMore(),
      children: [
        Row(
          spacing: WdSpace.s6,
          children: [
            for (final (period, label, _) in _periods)
              WdFilterChip(label,
                  height: 36, selected: period == _period, onTap: () => setState(() => _period = period)),
            const Spacer(),
            if (feed.value case final value?)
              Text('러너 ${grouped(value.summary.participantCount)}명',
                  style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
          ],
        ),
        ...switch (feed) {
          AsyncValue(:final value?) when value.summary.participantCount == 0 => const [RankingEmpty()],
          AsyncValue(:final value?) => [
              _Podium(value.summary.top),
              _myCard(value.summary.me, chip),
              if (value.rest.isNotEmpty) ...[
                const WdSectionHeading('전체 순위'),
                WdRankList(ranks: [for (final entry in value.rest) _rank(entry)]),
              ],
              WdInfoBanner('앱 전체 러너 · $basis 달린 거리 기준 · 매일 자정 갱신', plain: true),
            ],
          AsyncValue(:final error?) => [RankingError(error, onRetry: () => ref.invalidate(provider))],
          _ => const [RankingLoading()],
        },
      ],
    );
  }

  WdRank _rank(DistanceRankingEntry entry) {
    final whole = _period == RankingPeriod.all;
    return WdRank(
      rank: '${entry.rank}',
      name: entry.nickname,
      meta: whole ? '주 평균 ${km(entry.weeklyAverageMeters, whole: true)}' : '러닝 ${entry.runCount}회',
      value: km(entry.distanceMeters),
      avatar: avatarOf(entry),
    );
  }

  Widget _myCard(MyDistanceRanking me, String chip) => WdMyRankCard(
        WdRank(
          rank: myRankLabel(me),
          name: myName(me),
          avatar: myAvatar(me),
          meta: me.status == MyRankStatus.noRecord
              ? (_period == RankingPeriod.all ? '아직 기록이 없어요' : '$chip 기록이 없어요')
              : [
                  if (_period != RankingPeriod.week && me.thisWeekDistanceMeters != null)
                    '이번 주 +${km(me.thisWeekDistanceMeters!)}',
                  if (me.topPercent != null) '상위 ${me.topPercent}%',
                ].join(' · '),
          value: me.distanceMeters == null ? '-' : km(me.distanceMeters!),
        ),
        onTap: () => context.go(Routes.my),
      );
}

/// 시상대. 왼쪽부터 2 · 1 · 3번째 줄이고, 블록 높이와 색은 순위로 정한다(공동 순위면 같은 블록).
class _Podium extends StatelessWidget {
  const _Podium(this.top);

  final List<DistanceRankingEntry> top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: WdSpace.s6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: WdSpace.s10,
          children: [
            for (final i in [1, 0, 2]) Expanded(child: i < top.length ? _place(top[i]) : const SizedBox()),
          ],
        ),
      );

  Widget _place(DistanceRankingEntry entry) {
    final (height, color) = switch (entry.rank) {
      1 => (112.0, WdColors.podiumGold),
      2 => (86.0, WdColors.podiumSilver),
      _ => (66.0, WdColors.podiumBronze),
    };
    return Column(
      spacing: WdSpace.s6,
      children: [
        WdAvatar(size: 38, image: avatarOf(entry)),
        Text(entry.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.ink)),
        Text(km(entry.distanceMeters),
            style: WdText.raw(16, FontWeight.w700, 23).copyWith(color: WdColors.ink)),
        Container(
          height: height,
          width: double.infinity,
          padding: const EdgeInsets.only(top: WdSpace.s8),
          alignment: Alignment.topCenter,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(WdRadius.r16)),
          child: Text('${entry.rank}', style: WdText.raw(20, FontWeight.w700).copyWith(color: WdColors.ink)),
        ),
      ],
    );
  }
}

/// I2 · 지역 주간 랭킹. 상위 5명까지 보이고 나머지는 I5에서 본다.
class _RegionTab extends ConsumerStatefulWidget {
  const _RegionTab();

  @override
  ConsumerState<_RegionTab> createState() => _RegionTabState();
}

class _RegionTabState extends ConsumerState<_RegionTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = regionWeeklyProvider(ref.watch(selectedRegionProvider)?.code);
    return RankingScrollView(
      onRefresh: () => ref.refresh(provider.future),
      children: [
        const RegionChips(),
        ...switch (ref.watch(provider)) {
          AsyncValue(value: final ranking?) => [
              if (ranking.me.status != MyRankStatus.otherRegion) RegionMyRankCard(ranking),
              Text('${ranking.region.name} 순위 · 이번 주',
                  style: WdText.raw(12, FontWeight.w700, 18).copyWith(color: WdColors.muted)),
              if (ranking.top.isEmpty)
                const RankingEmpty()
              else
                WdRankList(ranks: [for (final entry in ranking.top) regionRank(entry)]),
              if (ranking.nextCursor != null)
                WdButton(
                  '${min(ranking.participantCount - ranking.top.length, 20)}명 더 보기',
                  variant: WdButtonVariant.secondary,
                  onPressed: () => context.push(Routes.rankingRegion),
                ),
            ],
          AsyncValue(:final error?) => [RankingError(error, onRetry: () => ref.invalidate(provider))],
          _ => const [RankingLoading()],
        },
      ],
    );
  }
}
