import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/ranking_api_client.dart';
import '../../core/api/region_api_client.dart';
import '../../core/auth/auth_controller.dart';

/// 실패하면 다시 받지 않고 화면이 "다시 시도"를 보인다.
Duration? _noRetry(int _, Object _) => null;

/// 첫 화면 값([summary])과 그 뒤로 이어 받은 순위([rest]).
class RankingFeed<S> {
  const RankingFeed(this.summary, this.rest, this.nextCursor);

  final S summary;
  final List<DistanceRankingEntry> rest;
  final String? nextCursor;
}

/// 첫 화면 값을 받으면 다음 한 페이지까지 받아 둔다. 그 뒤는 [loadMore]로 이어 받는다.
abstract class _RankingFeedNotifier<S> extends AsyncNotifier<RankingFeed<S>> {
  bool _loading = false;

  Future<RankingPage> _fetch(String cursor);

  Future<RankingFeed<S>> _start(S summary, String? cursor) async {
    if (cursor == null) return RankingFeed(summary, const [], null);
    final page = await _fetch(cursor);
    return RankingFeed(summary, page.entries, page.nextCursor);
  }

  /// 다음 페이지를 붙인다. 실패하면 받아 둔 순위는 그대로 두고 오류를 던진다.
  Future<void> loadMore() async {
    final feed = state.value;
    if (feed == null || feed.nextCursor == null || _loading) return;
    _loading = true;
    try {
      final page = await _fetch(feed.nextCursor!);
      // 받는 사이에 새로고침했으면 버린다.
      if (ref.mounted && identical(state.value, feed)) {
        state = AsyncData(RankingFeed(feed.summary, [...feed.rest, ...page.entries], page.nextCursor));
      }
    } finally {
      _loading = false;
    }
  }
}

/// E1 전체 랭킹(기간별).
final distanceFeedProvider = AsyncNotifierProvider.autoDispose
    .family<DistanceFeed, RankingFeed<DistanceRankingSummary>, RankingPeriod>(DistanceFeed.new, retry: _noRetry);

class DistanceFeed extends _RankingFeedNotifier<DistanceRankingSummary> {
  DistanceFeed(this.period);

  final RankingPeriod period;

  @override
  Future<RankingFeed<DistanceRankingSummary>> build() async {
    final summary = await ref.watch(rankingApiClientProvider).distance(period);
    return _start(summary, summary.nextCursor);
  }

  @override
  Future<RankingPage> _fetch(String cursor) => ref.read(rankingApiClientProvider).distanceEntries(period, cursor);
}

/// 지역 주간 랭킹 첫 화면(I2). 키가 null이면 내 활동 지역.
final regionWeeklyProvider = FutureProvider.autoDispose.family<RegionWeeklyRanking, String?>(
  (ref, regionCode) => ref.watch(rankingApiClientProvider).regionWeekly(regionCode),
  retry: _noRetry,
);

/// 지역 주간 전체 순위(I5). 첫 화면 값은 [regionWeeklyProvider]와 같이 쓴다.
final regionFeedProvider = AsyncNotifierProvider.autoDispose
    .family<RegionFeed, RankingFeed<RegionWeeklyRanking>, String?>(RegionFeed.new, retry: _noRetry);

class RegionFeed extends _RankingFeedNotifier<RegionWeeklyRanking> {
  RegionFeed(this.regionCode);

  final String? regionCode;

  @override
  Future<RankingFeed<RegionWeeklyRanking>> build() async {
    final summary = await ref.watch(regionWeeklyProvider(regionCode).future);
    return _start(summary, summary.nextCursor);
  }

  @override
  Future<RankingPage> _fetch(String cursor) =>
      ref.read(rankingApiClientProvider).regionWeeklyEntries(regionCode, cursor);
}

/// 지역 주간 랭킹(I2 · I5)에서 보는 시·군·구. null이면 내 활동 지역. 로그인 상태가 바뀌면 내 지역으로 돌아간다.
final selectedRegionProvider = NotifierProvider<SelectedRegion, Region?>(SelectedRegion.new);

class SelectedRegion extends Notifier<Region?> {
  @override
  Region? build() {
    ref.watch(authControllerProvider);
    return null;
  }

  void select(Region? region) => state = region;
}

/// I6 최근 선택. 최근 것부터 5개를 로그인한 동안 기억한다.
final recentRegionsProvider = NotifierProvider<RecentRegions, List<Region>>(RecentRegions.new);

class RecentRegions extends Notifier<List<Region>> {
  @override
  List<Region> build() {
    ref.watch(authControllerProvider);
    return const [];
  }

  void add(Region region) => state = [region, ...state.where((r) => r != region)].take(5).toList();
}
