import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/ranking_api_client.dart';
import '../../core/error_message.dart';
import '../../routes.dart';
import 'ranking_state.dart';

/// 천 단위 쉼표. 예: 12,480 · 1,284.0
String grouped(num value, [int fractionDigits = 0]) =>
    value.toStringAsFixed(fractionDigits).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// 거리는 소수 한 자리(1,284.0 km), 주 평균은 정수(38 km).
String km(int meters, {bool whole = false}) => '${grouped(meters / 1000, whole ? 0 : 1)} km';

/// 이번 주 월요일로 "10월 2주차". 월요일이 그 달의 몇 번째 월요일인지로 센다.
String weekLabel(DateTime monday) => '${monday.month}월 ${(monday.day + 6) ~/ 7}주차';

ImageProvider? avatarOf(DistanceRankingEntry entry) =>
    entry.profileImageUrl == null ? null : NetworkImage(entry.profileImageUrl!);

/// 내 행 이름. 순위 줄처럼 `나 (닉네임)`이고 닉네임을 못 받으면 `나`(Figma E1 · I5).
String myName(MyDistanceRanking me) => me.nickname == null ? '나' : '나 (${me.nickname})';

ImageProvider? myAvatar(MyDistanceRanking me) =>
    me.profileImageUrl == null ? null : NetworkImage(me.profileImageUrl!);

/// 내 순위 자리: 내 정보 비공개면 `비공개 중`, 기록이 없거나 다른 지역이면 `-`.
String myRankLabel(MyDistanceRanking me) => switch (me.status) {
      MyRankStatus.ranked => '${me.rank}',
      MyRankStatus.private => '비공개 중',
      _ => '-',
    };

/// 지역 주간 순위 한 줄. [region]을 주면 메타에 지역 이름을 붙인다(I5).
WdRank regionRank(DistanceRankingEntry entry, [String? region]) => WdRank(
      rank: '${entry.rank}',
      name: entry.nickname,
      meta: region == null ? '러닝 ${entry.runCount}회' : '러닝 ${entry.runCount}회 · $region',
      value: km(entry.distanceMeters),
      avatar: avatarOf(entry),
    );

/// 지역 주간 내 순위(I2 · I5). 누르면 MY로 간다. 다른 지역을 볼 때는 그리지 않는다.
class RegionMyRankCard extends StatelessWidget {
  const RegionMyRankCard(this.ranking, {super.key});

  final RegionWeeklyRanking ranking;

  @override
  Widget build(BuildContext context) {
    final me = ranking.me;
    final region = ranking.region.name;
    return WdMyRankCard(
      WdRank(
        rank: myRankLabel(me),
        name: myName(me),
        avatar: myAvatar(me),
        meta: switch (me) {
          MyDistanceRanking(status: MyRankStatus.noRecord) => '$region · 이번 주 기록이 없어요',
          MyDistanceRanking(:final rank?, :final lastWeekRank?) =>
            '$region · 지난주 $lastWeekRank위${_change(lastWeekRank - rank)}',
          _ => region,
        },
        value: me.distanceMeters == null ? '-' : km(me.distanceMeters!),
      ),
      onTap: () => context.go(Routes.my),
    );
  }

  static String _change(int up) => up > 0 ? ' ▲$up' : (up < 0 ? ' ▼${-up}' : '');
}

/// 내 지역 칩, 다른 지역을 보고 있으면 그 지역 칩, 그리고 지역 검색(I6).
class RegionChips extends ConsumerWidget {
  const RegionChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedRegionProvider);
    final mine = ref.watch(regionWeeklyProvider(null)).value?.region;
    return Wrap(
      spacing: WdSpace.s6,
      runSpacing: WdSpace.s6,
      children: [
        if (mine != null)
          WdFilterChip(
            mine.name,
            height: 36,
            selected: selected == null,
            onTap: () => ref.read(selectedRegionProvider.notifier).select(null),
          ),
        if (selected != null) WdFilterChip(selected.name, height: 36, selected: true, onTap: null),
        WdFilterChip('⌕ 지역 검색', height: 36, onTap: () => context.push(Routes.rankingRegionSelect)),
      ],
    );
  }
}

/// 랭킹 본문(가로 24 · 위 20 · 아래 24, 사이 16). 당겨서 새로고침하고, 끝 가까이에서 멈추면 [onEnd]로 다음 순위를 받는다.
class RankingScrollView extends StatelessWidget {
  const RankingScrollView({super.key, required this.onRefresh, this.onEnd, required this.children});

  final Future<void> Function() onRefresh;
  final Future<void> Function()? onEnd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    void report(Object error) {
      if (context.mounted) showError(context, error);
    }

    return RefreshIndicator(
      color: WdColors.ink,
      onRefresh: () => onRefresh().catchError(report),
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (end) {
          if (onEnd != null && end.metrics.extentAfter < 600) onEnd!().catchError(report);
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          // ponytail: 받은 순위를 한 번에 그린다. 수천 줄을 넘게 내려보는 일이 생기면 줄 단위 지연 목록으로 바꾼다.
          children: [Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: WdSpace.s16, children: children)],
        ),
      ),
    );
  }
}

class RankingLoading extends StatelessWidget {
  const RankingLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator(color: WdColors.ink)),
      );
}

/// 처음 받기에 실패했다. 받아 둔 값이 있으면 이 대신 그 값을 보인다.
class RankingError extends StatelessWidget {
  const RankingError(this.error, {super.key, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        spacing: WdSpace.s8,
        children: [
          WdStateMessage(title: '랭킹을 불러오지 못했어요', message: errorMessage(error)),
          WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: onRetry),
        ],
      );
}

class RankingEmpty extends StatelessWidget {
  const RankingEmpty({super.key});

  @override
  Widget build(BuildContext context) => const WdStateMessage(
        title: '아직 달린 러너가 없어요',
        message: '달린 거리는 매일 자정에 순위에 반영돼요.',
        icon: WdIcons.trophy,
      );
}
