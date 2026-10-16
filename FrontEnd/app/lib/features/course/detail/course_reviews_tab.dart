import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/review_api_client.dart';
import '../../review/review_widgets.dart';
import '../course_format.dart';
import 'course_empty_card.dart';

/// B8 리뷰 탭 미리보기 조건. 내 리뷰도 함께 받는다(G2와 달리 따로 보이지 않는다).
typedef CourseReviewQuery = ({String courseId, ReviewSort sort, bool photoOnly});

/// B8 리뷰 미리보기. 첫 페이지에서 [CourseReviewsTab.previewCount]개만 쓴다. 실패하면 화면이 다시 시도를 보인다.
final courseReviewPreviewProvider = FutureProvider.autoDispose.family<List<ReviewCard>, CourseReviewQuery>(
  (ref, query) async {
    final page = await ref
        .watch(reviewApiClientProvider)
        .list(query.courseId, sort: query.sort, photoOnly: query.photoOnly);
    return page.cards.take(CourseReviewsTab.previewCount).toList();
  },
  retry: (_, _) => null,
);

/// B8 코스 상세 — 리뷰 탭. 평점 요약 · 분포, 항목별 평균, 정렬 · 사진 칩, 리뷰 미리보기, 모두 보기(G2)다.
///
/// 리뷰가 없으면 Figma B8-1 안내만 보인다. 요약 · 미리보기는 B1이 받아 넘긴다(탭을 오가도 다시 받지 않는다).
class CourseReviewsTab extends StatelessWidget {
  const CourseReviewsTab({
    super.key,
    required this.summary,
    required this.preview,
    required this.sort,
    required this.photoOnly,
    required this.onSort,
    required this.onPhotoOnly,
    required this.onRetrySummary,
    required this.onRetryPreview,
    required this.onSeeAll,
  });

  /// Figma B8처럼 카드 2개를 보이고 나머지는 G2에서 본다(4.1 B8).
  static const previewCount = 2;

  static const emptyTitle = '아직 리뷰가 없어요';
  static const emptyMessage = '이 코스를 1km 이상, 코스의 20% 이상 달린 뒤\n작성할 수 있어요.';
  static const failedMessage = '리뷰를 불러오지 못했어요.';

  /// 받아 둔 요약 · 리뷰를 다시 받다 실패했을 때(B8-02 · B8-03). 받아 둔 것은 그대로 보인다.
  static const staleSummaryMessage = '평점을 새로 받지 못했어요.';
  static const stalePreviewMessage = '리뷰를 새로 받지 못했어요.';

  final AsyncValue<ReviewSummary> summary;
  final AsyncValue<List<ReviewCard>> preview;
  final ReviewSort sort;
  final bool photoOnly;
  final ValueChanged<ReviewSort> onSort;
  final ValueChanged<bool> onPhotoOnly;
  final VoidCallback onRetrySummary;
  final VoidCallback onRetryPreview;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    // 받아 둔 요약이 있으면 다시 받다 실패해도 그대로 보인다(B8-02).
    final value = summary.value;
    if (value == null) {
      return summary.hasError ? _Failure(onRetry: onRetrySummary) : const _Loading();
    }
    final summaryStale = summary.hasError
        ? CourseRefreshFailed(staleSummaryMessage, onRetry: onRetrySummary)
        : null;
    if (value.reviewCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s16,
        children: [
          const CourseEmptyCard(title: emptyTitle, message: emptyMessage),
          ?summaryStale,
        ],
      );
    }
    final previewStale = preview.hasError
        ? CourseRefreshFailed(stalePreviewMessage, onRetry: onRetryPreview)
        : null;
    final muted = WdText.label12.copyWith(color: WdColors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s16,
      children: [
        _RatingSummary(value),
        ?summaryStale,
        const WdSectionHeading('항목별 평균'),
        WdSummaryTiles([
          for (final (label, average) in [
            ('안전성', value.safety),
            ('도로 상태', value.road),
            ('야간 조명', value.lighting),
            ('편의시설', value.amenity),
          ])
            (label, average?.toStringAsFixed(1) ?? '—'),
        ]),
        // 정렬은 칩 하나만, 사진은 오른쪽 체크박스로 따로 켜고 끈다(B8-03, G2와 같다). 고른 조건은 다시 받다 실패해도 그대로다.
        Row(
          children: [
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: WdSpace.s6,
                  children: [
                    for (final option in ReviewSort.values)
                      WdFilterChip(option.label, height: 36, selected: option == sort, onTap: () => onSort(option)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: WdSpace.s8),
            ReviewPhotoOnlyCheck(checked: photoOnly, onChanged: onPhotoOnly),
          ],
        ),
        ...switch (preview) {
          AsyncValue(:final value?) when value.isEmpty => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WdSpace.s8),
              child: Text(
                photoOnly ? '사진이 있는 리뷰가 아직 없어요.' : emptyTitle,
                textAlign: TextAlign.center,
                style: muted,
              ),
            ),
            ?previewStale,
          ],
          AsyncValue(:final value?) => [for (final card in value) ReviewCardView(card), ?previewStale],
          AsyncValue(hasError: true) => [_Failure(onRetry: onRetryPreview)],
          _ => const [_Loading()],
        },
        WdButton(
          '리뷰 ${formatCount(value.reviewCount)}개 모두 보기',
          variant: WdButtonVariant.secondary,
          onPressed: onSeeAll,
        ),
      ],
    );
  }
}

/// 평균 · 별 · 리뷰 수와 별점별 분포 막대(Figma B8).
class _RatingSummary extends StatelessWidget {
  const _RatingSummary(this.summary);

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final muted = WdText.label12.copyWith(color: WdColors.muted);
    final average = summary.averageRating;
    final total = summary.reviewCount;
    return Row(
      spacing: WdSpace.s16,
      children: [
        Column(
          spacing: 3,
          children: [
            Text(
              average?.toStringAsFixed(1) ?? '—',
              style: WdText.raw(36, FontWeight.w700, 40).copyWith(color: WdColors.ink),
            ),
            // 4.6은 별 4개(G2와 같다)
            Text(stars(average?.floor() ?? 0), style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
            Text('리뷰 ${formatCount(total)}', style: muted),
          ],
        ),
        Expanded(
          child: Column(
            spacing: 5,
            children: [
              // ratingCounts는 5점부터
              for (var i = 0; i < 5; i++)
                Row(
                  spacing: WdSpace.s8,
                  children: [
                    Text('${5 - i}', style: muted),
                    Expanded(
                      child: WdProgressBar(value: summary.ratingCounts[i] / total, trackColor: WdColors.soft),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 받아 둔 값을 다시 받다 실패했을 때 그 아래에 보이는 한 줄. 받아 둔 값은 그대로 두고 다시 시도를 준다(B8-02).
/// B1 러너 평가도 쓴다.
class CourseRefreshFailed extends StatelessWidget {
  const CourseRefreshFailed(this.message, {super.key, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
        spacing: WdSpace.s8,
        children: [
          Expanded(child: Text(message, style: WdText.label12.copyWith(color: WdColors.muted))),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              // 글자만 누르기 어렵지 않게 위아래로 눌리는 자리를 넓힌다
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: WdSpace.s8),
                child: Text('다시 시도', style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.green)),
              ),
            ),
          ),
        ],
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 96,
        child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s8,
        children: [
          Text(
            CourseReviewsTab.failedMessage,
            textAlign: TextAlign.center,
            style: WdText.ko13.copyWith(color: WdColors.muted),
          ),
          WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: onRetry),
        ],
      );
}
