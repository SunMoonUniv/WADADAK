import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/review_api_client.dart';
import '../course/course_format.dart';
import '../run/domain/run_models.dart';

/// 별 5개 글자(Figma "★ ★ ★ ★ ☆"). [filled]개만 채운다.
String stars(int filled) => List.generate(5, (i) => i < filled ? '★' : '☆').join(' ');

/// 날짜(Asia/Seoul) `2026.09.08`. 한국은 서머타임이 없어 UTC+9로 계산한다.
String reviewDate(DateTime time) {
  final seoul = time.toUtc().add(const Duration(hours: 9));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${seoul.year}.${two(seoul.month)}.${two(seoul.day)}';
}

/// 진행도 배지: 100%면 `완주 100%`(초록), 아니면 `62% 주행`(회색) — Figma G2.
(String, WdTone) progressBadge(int percent, {bool completed = false}) =>
    completed || percent >= 100 ? ('완주 $percent%', WdTone.success) : ('$percent% 주행', WdTone.neutral);

/// B2 · B10 상단 기록 한 줄: `5.2km · 2026.09.08 완주 100% · 27:14`.
String courseRunLine(CourseRun run) {
  final (progress, _) = progressBadge(run.progressPercent, completed: run.completed);
  return '${formatKm(run.courseDistanceMeters)} · ${reviewDate(run.endedAt)} $progress · '
      '${formatRunTime(Duration(seconds: run.courseElapsedSeconds))}';
}

/// 리뷰 카드(B8-04 · G2). 완주 횟수가 0이면 날짜만 보인다(정책 D-09). 내 리뷰는 `나 (닉네임)`.
class ReviewCardView extends StatelessWidget {
  const ReviewCardView(this.card, {super.key});

  final ReviewCard card;

  @override
  Widget build(BuildContext context) {
    final (badge, tone) = progressBadge(card.bestProgressPercent);
    final nickname = card.nickname ?? '러너';
    return WdReviewCard(
      author: card.mine ? '나 ($nickname)' : nickname,
      badge: badge,
      badgeTone: tone,
      meta: card.completedCount > 0
          ? '${reviewDate(card.createdAt)} · ${card.completedCount}회 주행'
          : reviewDate(card.createdAt),
      rating: card.rating,
      body: card.content,
      avatar: card.profileImageUrl == null ? null : NetworkImage(card.profileImageUrl!),
      photos: [for (final photo in card.photos) NetworkImage(photo.url)],
      onTapPhoto: (index) => showReviewPhotos(context, card.photos, index),
      tags: [for (final tag in card.tags) tag.label],
    );
  }
}

/// G2 상단 평점 요약: 평균 · 별점별 분포 막대 · 항목별 평균. 리뷰가 없으면 `-`.
class ReviewSummaryCard extends StatelessWidget {
  const ReviewSummaryCard(this.summary, {super.key});

  final ReviewSummary summary;

  static String _average(double? value) => value?.toStringAsFixed(1) ?? '-';

  @override
  Widget build(BuildContext context) {
    final muted = WdText.label12.copyWith(color: WdColors.muted);
    final total = summary.reviewCount;
    return WdSurface(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 9,
        children: [
          Row(
            spacing: WdSpace.s14,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    _average(summary.averageRating),
                    style: WdText.raw(30, FontWeight.w700, 33).copyWith(color: WdColors.ink),
                  ),
                  // 4.6은 별 4개(Figma)
                  Text(
                    stars(summary.averageRating?.floor() ?? 0),
                    style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  spacing: WdSpace.s4,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Row(
                        spacing: WdSpace.s8,
                        children: [
                          Text('${5 - i}', style: muted),
                          Expanded(child: _RatingBar(total == 0 ? 0 : summary.ratingCounts[i] / total)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 좁은 화면에서는 다음 줄로 내려간다
          Wrap(
            spacing: WdSpace.s8,
            runSpacing: WdSpace.s8,
            children: [
              for (final (label, value) in [
                ('안전성', summary.safety),
                ('도로', summary.road),
                ('조명', summary.lighting),
                ('편의', summary.amenity),
              ])
                WdSurface(
                  padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Text(label, style: muted),
                      Text(
                        _average(value),
                        style: WdText.label12.copyWith(fontWeight: FontWeight.w700, color: WdColors.ink),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 별점 분포 막대 한 줄(높이 6). [fraction]은 0~1.
class _RatingBar extends StatelessWidget {
  const _RatingBar(this.fraction);

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: SizedBox(
      height: 6,
      child: ColoredBox(
        color: WdColors.soft,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: WdColors.neutralDark,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 삭제 확인창. 지우면 되돌릴 수 없어 한 번 묻는다.
Future<bool> confirmReviewDelete(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('리뷰를 삭제할까요?'),
        content: const Text('사진도 함께 지워지고 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    ) ??
    false;

/// 리뷰 사진 크게 보기. 넘겨서 다음 사진, 두 손가락으로 확대한다.
Future<void> showReviewPhotos(BuildContext context, List<ReviewPhoto> photos, int initialIndex) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReviewPhotoViewer(photos: photos, initialIndex: initialIndex),
      ),
    );

class ReviewPhotoViewer extends StatefulWidget {
  const ReviewPhotoViewer({super.key, required this.photos, required this.initialIndex});

  final List<ReviewPhoto> photos;
  final int initialIndex;

  @override
  State<ReviewPhotoViewer> createState() => _ReviewPhotoViewerState();
}

class _ReviewPhotoViewerState extends State<ReviewPhotoViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.runBackground,
    body: SafeArea(
      child: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (_, index) => InteractiveViewer(
              maxScale: 4,
              child: Center(child: Image.network(widget.photos[index].url, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            left: WdSpace.s8,
            top: WdSpace.s8,
            child: IconButton(
              tooltip: '닫기',
              onPressed: () => Navigator.of(context).pop(),
              icon: const WdIcon(WdIcons.back, color: WdColors.white),
            ),
          ),
          if (widget.photos.length > 1)
            Positioned(
              top: WdSpace.s20,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_index + 1} / ${widget.photos.length}',
                  style: WdText.label12Medium.copyWith(color: WdColors.white),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
