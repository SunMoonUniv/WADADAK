import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ranking_api_client.dart';

/// 실패하면 다시 받지 않고 화면이 다시 시도를 보인다.
Duration? _noRetry(int _, Object _) => null;

typedef CourseRankingKey = ({String courseId, RankingPeriod period});

/// B9 랭킹 요약과 고스트 대결 버튼. B1 · B8은 전체 기간을 쓴다(정책 공통 6).
final courseRankingProvider = FutureProvider.autoDispose.family<CourseRankingSummary, CourseRankingKey>(
  (ref, key) => ref.watch(rankingApiClientProvider).courseSummary(key.courseId, key.period),
  retry: _noRetry,
);

/// G3 첫 화면 값과 지금까지 받은 순위.
class CourseRankingFeed {
  const CourseRankingFeed(this.summary, this.entries, this.nextCursor);

  final CourseRankingSummary summary;
  final List<CourseRankingEntry> entries;
  final String? nextCursor;
}

/// G3 전체 순위. 요약과 1위부터의 첫 페이지를 함께 받고 [CourseRankingFeedNotifier.loadMore]로 이어 받는다.
/// 들어올 때 · 기간을 바꿀 때 · 당겨서 새로고침할 때 처음부터 다시 받는다(G3-01 · G3-04).
final courseRankingFeedProvider =
    AsyncNotifierProvider.autoDispose.family<CourseRankingFeedNotifier, CourseRankingFeed, CourseRankingKey>(
  CourseRankingFeedNotifier.new,
  retry: _noRetry,
);

class CourseRankingFeedNotifier extends AsyncNotifier<CourseRankingFeed> {
  CourseRankingFeedNotifier(this.key);

  final CourseRankingKey key;
  bool _loading = false;

  @override
  Future<CourseRankingFeed> build() async {
    final api = ref.watch(rankingApiClientProvider);
    final summary = api.courseSummary(key.courseId, key.period);
    final page = api.courseEntries(key.courseId, key.period);
    // 둘을 함께 받고, 실패하면 먼저 난 오류(ApiException)를 그대로 던진다.
    await Future.wait([summary, page]);
    final first = await page;
    return CourseRankingFeed(await summary, first.entries, first.nextCursor);
  }

  /// 다음 페이지를 붙인다. 실패하면 받아 둔 순위는 그대로 두고 오류를 던진다.
  Future<void> loadMore() async {
    final feed = state.value;
    if (feed == null || feed.nextCursor == null || _loading) return;
    _loading = true;
    try {
      final page =
          await ref.read(rankingApiClientProvider).courseEntries(key.courseId, key.period, cursor: feed.nextCursor);
      // 받는 사이에 새로고침했으면 버린다.
      if (ref.mounted && identical(state.value, feed)) {
        state = AsyncData(CourseRankingFeed(feed.summary, [...feed.entries, ...page.entries], page.nextCursor));
      }
    } finally {
      _loading = false;
    }
  }
}
