import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/review_api_client.dart';
import '../../core/error_message.dart';
import '../../routes.dart';
import '../course/course_format.dart';
import 'review_form_screen.dart';
import 'review_state.dart';
import 'review_widgets.dart';

/// 리뷰를 쓸 자격이 없을 때 "리뷰 작성하기"를 누르면 보이는 안내(정책 공통 5).
const reviewEligibilityGuide = '이 코스를 한 번에 20% 이상(최소 1km) 달리면 리뷰를 쓸 수 있어요.';

/// G2 · 코스 리뷰 전체. B8 "모두 보기"에서 연다.
///
/// 위에서부터 평점 요약 · 내 리뷰(있을 때) · 다른 러너 리뷰 목록이다. 목록은 내 리뷰를 빼고 받는다.
/// "리뷰 작성하기"는 늘 보인다: 내 리뷰가 있으면 수정(B10), 자격이 있으면 작성(B2), 없으면 안내.
class ReviewListScreen extends ConsumerStatefulWidget {
  const ReviewListScreen({super.key, required this.courseId, required this.courseName});

  final String courseId;

  /// 앱 바 오른쪽과 B2 · B10 상단에 보이는 코스 이름. 리뷰 API에는 없어 B8이 넘겨준다.
  final String courseName;

  @override
  ConsumerState<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends ConsumerState<ReviewListScreen> {
  var _sort = ReviewSort.latest;
  var _photoOnly = false;
  var _deleting = false;

  ReviewQuery get _query => (courseId: widget.courseId, sort: _sort, photoOnly: _photoOnly);

  Future<void> _refresh() async {
    refreshCourseReviews(ref, widget.courseId);
    await ref.read(reviewFeedProvider(_query).future);
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(reviewFeedProvider(_query).notifier).loadMore();
    } on Object catch (e) {
      if (mounted) showError(context, e, onRetry: _loadMore);
    }
  }

  /// 내 리뷰가 있으면 B10, 자격이 있으면 B2, 없으면 안내.
  void _write(MyReview? my) {
    if (my == null) {
      // 아직 못 받았거나 실패했다. 다시 받는다.
      ref.invalidate(myReviewProvider(widget.courseId));
      return;
    }
    if (my.review != null) {
      _edit(my);
    } else if (my.eligibleRecord case final record?) {
      context.push(
        Routes.reviewForm,
        extra: ReviewFormArgs.write(courseId: widget.courseId, courseName: widget.courseName, record: record),
      );
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(reviewEligibilityGuide)));
    }
  }

  void _edit(MyReview my) => context.push(
    Routes.reviewForm,
    extra: ReviewFormArgs.edit(
      courseId: widget.courseId,
      courseName: widget.courseName,
      review: my.review!,
      record: my.sourceRecord,
      sourceRecordDeleted: my.sourceRecordDeleted,
    ),
  );

  Future<void> _delete(ReviewCard review) async {
    if (_deleting || !await confirmReviewDelete(context) || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(reviewApiClientProvider).delete(review.reviewId);
      if (!mounted) return;
      refreshCourseReviews(ref, widget.courseId);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('리뷰를 삭제했어요.')));
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(reviewSummaryProvider(widget.courseId));
    final mine = ref.watch(myReviewProvider(widget.courseId));
    final feed = ref.watch(reviewFeedProvider(_query));
    final my = mine.value?.review;
    final heading = WdText.ko16Bold.copyWith(color: WdColors.ink);

    // 처음 받을 때 실패하면 화면 전체를 다시 시도로 바꾼다. 받아 둔 값이 있으면 그대로 보인다.
    final firstError = switch ((summary, mine)) {
      (AsyncValue(hasValue: false, :final error?), _) || (_, AsyncValue(hasValue: false, :final error?)) => error,
      _ => null,
    };

    return Scaffold(
      appBar: WdAppBar(
        title: summary.value == null ? '리뷰' : '리뷰 ${formatCount(summary.value!.reviewCount)}',
        onBack: () => context.pop(),
        action: WdAppBarAction.text(widget.courseName, onTap: null),
      ),
      body: firstError != null
          ? _Failure(error: firstError, onRetry: () => refreshCourseReviews(ref, widget.courseId))
          : !summary.hasValue || !mine.hasValue
          ? const Center(child: CircularProgressIndicator(color: WdColors.ink))
          : RefreshIndicator(
              color: WdColors.ink,
              onRefresh: _refresh,
              child: NotificationListener<ScrollNotification>(
                // 끝에서 400px 안으로 내려오면 다음 페이지를 받는다
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 400 &&
                      notification is ScrollUpdateNotification &&
                      notification.metrics.axisDirection == AxisDirection.down) {
                    _loadMore();
                  }
                  return false;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
                  children: [
                    ReviewSummaryCard(summary.value!),
                    if (my != null) ...[
                      const SizedBox(height: WdSpace.s16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: WdSpace.s8,
                        children: [
                          Row(
                            spacing: WdSpace.s6,
                            children: [
                              Text('내 리뷰', style: heading),
                              Text(
                                '${reviewDate(my.createdAt)} 작성',
                                style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
                              ),
                            ],
                          ),
                          ReviewCardView(my),
                          Row(
                            spacing: WdSpace.s8,
                            children: [
                              Expanded(child: _OutlineButton('수정하기', onTap: () => _edit(mine.value!))),
                              Expanded(
                                child: _OutlineButton(
                                  '삭제하기',
                                  color: WdColors.negative,
                                  onTap: _deleting ? null : () => _delete(my),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: WdSpace.s16),
                    Text('다른 러너 리뷰 ${formatCount(summary.value!.reviewCount - (my == null ? 0 : 1))}', style: heading),
                    const SizedBox(height: WdSpace.s16),
                    // 정렬은 칩, 사진 조건은 오른쪽 체크박스(정렬과 함께 쓸 수 있다)
                    Row(
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              spacing: WdSpace.s6,
                              children: [
                                for (final sort in ReviewSort.values)
                                  WdFilterChip(
                                    sort.label,
                                    height: 36,
                                    selected: sort == _sort,
                                    onTap: () => setState(() => _sort = sort),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: WdSpace.s8),
                        _PhotoOnlyCheck(
                          checked: _photoOnly,
                          onChanged: (checked) => setState(() => _photoOnly = checked),
                        ),
                      ],
                    ),
                    ...switch (feed) {
                      AsyncValue(:final value?) when value.cards.isEmpty => [
                        const SizedBox(height: WdSpace.s24),
                        Center(
                          child: Text(
                            _photoOnly ? '사진이 있는 리뷰가 아직 없어요.' : '아직 다른 러너의 리뷰가 없어요.',
                            style: WdText.label12.copyWith(color: WdColors.muted),
                          ),
                        ),
                      ],
                      AsyncValue(:final value?) => [
                        for (final card in value.cards) ...[const SizedBox(height: WdSpace.s16), ReviewCardView(card)],
                      ],
                      AsyncValue(:final error?) => [
                        const SizedBox(height: WdSpace.s16),
                        _Failure(error: error, onRetry: () => ref.invalidate(reviewFeedProvider(_query))),
                      ],
                      _ => const [
                        SizedBox(height: WdSpace.s24),
                        Center(child: CircularProgressIndicator(color: WdColors.ink)),
                      ],
                    },
                  ],
                ),
              ),
            ),
      bottomNavigationBar: DecoratedBox(
        // Figma G2: 위 1px 선 · pt10 · pb18 · px16
        decoration: const BoxDecoration(
          color: WdColors.paper,
          border: Border(top: BorderSide(color: WdColors.map)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s10, WdSpace.s16, 18),
          child: WdButton('리뷰 작성하기', onPressed: () => _write(mine.value)),
        ),
      ),
    );
  }
}

/// G2 "수정하기 · 삭제하기": 흰 바탕 · 선 테두리 · 12 Medium.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton(this.label, {required this.onTap, this.color = WdColors.ink});

  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: WdSurface(
      color: WdColors.paper,
      border: const BorderSide(color: WdColors.line),
      padding: const EdgeInsets.symmetric(vertical: WdSpace.s10),
      onTap: onTap,
      child: Center(
        child: Text(label, style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: color)),
      ),
    ),
  );
}

/// "사진 리뷰만" 체크박스. 동의 화면(WdConsentRow)과 같은 체크 모양이다: 켜면 초록, 끄면 회색.
class _PhotoOnlyCheck extends StatelessWidget {
  const _PhotoOnlyCheck({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: checked,
    label: '사진 리뷰만',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!checked),
      // 칩과 같은 높이(36)로 눌리는 영역을 잡는다
      child: SizedBox(
        height: 36,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: WdSpace.s4,
          children: [
            WdIcon(WdIcons.check, size: 18, color: checked ? null : WdColors.checkOff),
            Text('사진 리뷰만', style: WdText.label12Medium.copyWith(color: checked ? WdColors.ink : WdColors.muted)),
          ],
        ),
      ),
    ),
  );
}

/// 리뷰를 불러오지 못했을 때.
class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      WdStateMessage(title: '리뷰를 불러오지 못했어요', message: errorMessage(error)),
      WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: onRetry),
    ],
  );
}
