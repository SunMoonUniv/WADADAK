import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/review_api_client.dart';

/// 실패하면 다시 받지 않고 화면이 "다시 시도"를 보인다.
Duration? _noRetry(int _, Object _) => null;

/// 코스 평점 요약(G2 상단). 키는 코스 ID.
final reviewSummaryProvider = FutureProvider.autoDispose.family<ReviewSummary, String>(
  (ref, courseId) => ref.watch(reviewApiClientProvider).summary(courseId),
  retry: _noRetry,
);

/// 이 코스에 대한 내 리뷰 상태(G2 내 리뷰 · 작성 버튼 · B10). 키는 코스 ID.
final myReviewProvider = FutureProvider.autoDispose.family<MyReview, String>(
  (ref, courseId) => ref.watch(reviewApiClientProvider).mine(courseId),
  retry: _noRetry,
);

/// G2 "다른 러너 리뷰" 목록 조건. 내 리뷰는 위에 따로 보이므로 늘 뺀다.
typedef ReviewQuery = ({String courseId, ReviewSort sort, bool photoOnly});

/// 지금까지 받은 리뷰 카드와 다음 페이지 커서.
class ReviewFeed {
  const ReviewFeed(this.cards, this.nextCursor);

  final List<ReviewCard> cards;
  final String? nextCursor;
}

/// G2 리뷰 목록. 첫 페이지를 받고 [ReviewFeedNotifier.loadMore]로 이어 받는다.
/// 정렬 · 사진 조건이 바뀌면 키가 달라져 첫 페이지부터 다시 받는다.
final reviewFeedProvider = AsyncNotifierProvider.autoDispose.family<ReviewFeedNotifier, ReviewFeed, ReviewQuery>(
  ReviewFeedNotifier.new,
  retry: _noRetry,
);

class ReviewFeedNotifier extends AsyncNotifier<ReviewFeed> {
  ReviewFeedNotifier(this.query);

  final ReviewQuery query;
  bool _loading = false;

  @override
  Future<ReviewFeed> build() async {
    final page = await _fetch(null);
    return ReviewFeed(page.cards, page.nextCursor);
  }

  Future<ReviewPage> _fetch(String? cursor) => ref
      .read(reviewApiClientProvider)
      .list(query.courseId, sort: query.sort, photoOnly: query.photoOnly, excludeMine: true, cursor: cursor);

  /// 다음 페이지를 붙인다. 실패하면 받아 둔 리뷰는 그대로 두고 오류를 던진다.
  Future<void> loadMore() async {
    final feed = state.value;
    if (feed == null || feed.nextCursor == null || _loading) return;
    _loading = true;
    try {
      final page = await _fetch(feed.nextCursor);
      // 받는 사이에 새로고침했으면 버린다.
      if (ref.mounted && identical(state.value, feed)) {
        state = AsyncData(ReviewFeed([...feed.cards, ...page.cards], page.nextCursor));
      }
    } finally {
      _loading = false;
    }
  }
}

/// 리뷰를 쓰거나 고치거나 지운 뒤 그 코스의 요약 · 내 리뷰 · 목록을 다시 받게 한다.
void refreshCourseReviews(WidgetRef ref, String courseId) {
  ref
    ..invalidate(reviewSummaryProvider(courseId))
    ..invalidate(myReviewProvider(courseId))
    ..invalidate(reviewFeedProvider);
}
