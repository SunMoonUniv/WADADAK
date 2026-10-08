import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'chips.dart';
import 'surface.dart';

/// Course / Summary tile — 라벨 + 굵은 값.
class WdSummaryTile extends StatelessWidget {
  const WdSummaryTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => WdSurface(
        padding: const EdgeInsets.all(WdSpace.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.label12.copyWith(color: WdColors.muted)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.button15.copyWith(color: WdColors.ink)),
          ],
        ),
      );
}

/// Course / Info grid · Build summary — [WdSummaryTile]을 같은 너비로 나란히.
class WdSummaryTiles extends StatelessWidget {
  const WdSummaryTiles(this.items, {super.key});

  /// (라벨, 값)
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Row(
        spacing: WdSpace.s8,
        children: [for (final (l, v) in items) Expanded(child: WdSummaryTile(label: l, value: v))],
      );
}

/// A DS / Metric — 라벨 + 숫자. [dark]는 어두운 배경용.
class WdMetric extends StatelessWidget {
  const WdMetric({super.key, required this.label, required this.value, this.dark = false});

  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s6,
        children: [
          Text(label,
              style: WdText.ko11Medium
                  .copyWith(color: dark ? WdColors.textInverseSecondary : WdColors.textSecondary)),
          Text(value, style: WdText.numeric24.copyWith(color: dark ? WdColors.textInverse : WdColors.textPrimary)),
        ],
      );
}

/// Card / Stat summary — soft 카드 n개 (참여 러너 · 1위 기록 · 평균 기록).
class WdStatSummary extends StatelessWidget {
  const WdStatSummary(this.items, {super.key});

  /// (라벨, 값)
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Row(
        spacing: WdSpace.s8,
        children: [
          for (final (label, value) in items)
            Expanded(
              child: WdSurface(
                height: 86,
                padding: const EdgeInsets.all(WdSpace.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: WdSpace.s6,
                  children: [
                    Text(label, style: WdText.raw(12, FontWeight.w500, 16).copyWith(color: WdColors.muted)),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.raw(22, FontWeight.w700, 28).copyWith(color: WdColors.ink)),
                  ],
                ),
              ),
            ),
        ],
      );
}

/// A 확장 / Avatar — soft 원 + 사람 아이콘. [image]가 있으면 사진.
class WdAvatar extends StatelessWidget {
  const WdAvatar({super.key, this.size = 40, this.image});

  final double size;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: image != null
              ? Image(image: image!, fit: BoxFit.cover)
              : ColoredBox(color: WdColors.soft, child: Center(child: WdIcon(WdIcons.user, size: size / 2))),
        ),
      );
}

/// Map / Thumbnail · A 확장 / Route thumbnail — 지도색 바탕 + 코스 경로 이미지.
///
/// 경로 그림은 데이터라 [child]로 받는다 (지도 스냅샷, 경로 SVG 등).
class WdRouteThumbnail extends StatelessWidget {
  const WdRouteThumbnail({super.key, this.width = 64, this.height = 58, this.child});

  final double width;
  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) => WdSurface(
        color: WdColors.map,
        radius: WdRadius.r12,
        width: width,
        height: height,
        child: child ?? const SizedBox.expand(),
      );
}

/// 썸네일 · 제목 · 보조 줄 · 오른쪽 요소 / 아래 줄 — Course card·Run record card 공통 뼈대.
class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.thumbnail,
    required this.title,
    required this.titleStyle,
    required this.lines,
    this.trailing,
    this.footer,
    this.footerGap = WdSpace.s8,
    this.onTap,
  });

  final Widget thumbnail;
  final String title;
  final TextStyle titleStyle;
  final List<String> lines;
  final Widget? trailing;
  final Widget? footer;
  final double footerGap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WdSurface(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: footerGap,
          children: [
            Row(
              spacing: WdSpace.s12,
              children: [
                thumbnail,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 3,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle.copyWith(color: WdColors.ink)),
                      for (final line in lines)
                        Text(line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (footer != null) footer!,
          ],
        ),
      );
}

Widget _chevron(double size) =>
    Text('›', style: WdText.raw(size, FontWeight.w400, size * 1.4).copyWith(color: WdColors.muted));

Widget _link(String label, VoidCallback? onTap) => GestureDetector(
      onTap: onTap,
      child: Text(label, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.green)),
    );

/// Course card — Type=Saved · Search · List.
///
/// - Saved: `lines: [메타, '만든 사람 ..']`, `actionLabel: '이 코스로 달리기 ›'`, 썸네일 54.
/// - Search: `showChevron: true`, 썸네일 58.
/// - List: `lines: [메타, '★ 4.6 (128)']`, `showChevron: true`, 썸네일 64×58.
class WdCourseCard extends StatelessWidget {
  const WdCourseCard({
    super.key,
    required this.title,
    required this.lines,
    this.thumbnail,
    this.thumbnailSize = const Size(58, 58),
    this.tags = const [],
    this.showChevron = false,
    this.actionLabel,
    this.onAction,
    this.onTap,
  });

  final String title;
  final List<String> lines;

  /// 경로 이미지. [WdRouteThumbnail.child]로 들어간다.
  final Widget? thumbnail;
  final Size thumbnailSize;

  /// 보통 `WdTag(.., filled: false)`.
  final List<Widget> tags;
  final bool showChevron;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _MediaCard(
        thumbnail: WdRouteThumbnail(width: thumbnailSize.width, height: thumbnailSize.height, child: thumbnail),
        title: title,
        titleStyle: WdText.cardTitle14,
        lines: lines,
        trailing: showChevron ? _chevron(17) : null,
        footerGap: actionLabel != null ? 9 : WdSpace.s8,
        footer: tags.isEmpty && actionLabel == null
            ? null
            : Row(
                spacing: WdSpace.s6,
                children: [
                  ...tags,
                  if (actionLabel != null) ...[const Spacer(), _link(actionLabel!, onAction)],
                ],
              ),
        onTap: onTap,
      );
}

/// Run record card — 러닝 기록 목록 · `.selectable` 코스 등록용 기록 선택.
class WdRunRecordCard extends StatelessWidget {
  /// Run record card: 제목 16 Bold, 결과 태그, 아래 줄에 날짜 + 상세 보기.
  const WdRunRecordCard({
    super.key,
    required this.title,
    required this.summary,
    required String this.date,
    this.resultTag,
    this.thumbnail,
    this.detailLabel = '상세 보기 ›',
    this.onTap,
  })  : tags = const [],
        _selectable = false;

  /// Run record card / Selectable: 제목(날짜) 14 Bold, "›", 아래 줄에 태그.
  const WdRunRecordCard.selectable({
    super.key,
    required this.title,
    required this.summary,
    this.tags = const [],
    this.thumbnail,
    this.onTap,
  })  : date = null,
        resultTag = null,
        detailLabel = '',
        _selectable = true;

  final String title;

  /// 예: "5.21km · 27:14 · 5′14″/km"
  final String summary;
  final String? date;

  /// 예: `WdTag('대결 승', tone: WdTone.success, filled: false)`
  final Widget? resultTag;
  final List<Widget> tags;
  final Widget? thumbnail;
  final String detailLabel;
  final VoidCallback? onTap;
  final bool _selectable;

  @override
  Widget build(BuildContext context) => _selectable
      ? _MediaCard(
          thumbnail: WdRouteThumbnail(child: thumbnail),
          title: title,
          titleStyle: WdText.cardTitle14,
          lines: [summary],
          trailing: _chevron(18),
          footer: tags.isEmpty ? null : Row(spacing: WdSpace.s6, children: tags),
          onTap: onTap,
        )
      : _MediaCard(
          thumbnail: WdRouteThumbnail(width: 52, height: 52, child: thumbnail),
          title: title,
          titleStyle: WdText.ko16Bold,
          lines: [summary],
          trailing: resultTag,
          footer: Row(
            children: [
              Text(date!, style: WdText.label12.copyWith(color: WdColors.muted)),
              const Spacer(),
              Text(detailLabel, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.green)),
            ],
          ),
          onTap: onTap,
        );
}

/// Review card — With photos · Text only ([photos]가 비면 Text only).
class WdReviewCard extends StatelessWidget {
  const WdReviewCard({
    super.key,
    required this.author,
    required this.meta,
    required this.rating,
    required this.body,
    this.badge,
    this.avatar,
    this.photos = const [],
    this.tags = const [],
  });

  final String author;

  /// 예: "2026.09.06 · 4회 주행"
  final String meta;

  /// 0–5
  final int rating;
  final String body;

  /// 이름 옆 글자 태그 (예: 완주 100%).
  final String? badge;
  final ImageProvider? avatar;
  final List<ImageProvider> photos;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final small = WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted);
    return WdSurface(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s8,
        children: [
          Row(
            spacing: WdSpace.s10,
            children: [
              WdAvatar(size: 34, image: avatar),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Row(
                      spacing: WdSpace.s6,
                      children: [
                        Flexible(
                          child: Text(author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
                        ),
                        if (badge != null) WdTag(badge!, tone: WdTone.success, filled: false),
                      ],
                    ),
                    Text(meta, style: WdText.label12.copyWith(color: WdColors.muted)),
                  ],
                ),
              ),
              Semantics(
                label: '별점 $rating점',
                excludeSemantics: true,
                child: Text(List.generate(5, (i) => i < rating ? '★' : '☆').join(' '), style: small),
              ),
            ],
          ),
          Text(body, style: small),
          if (photos.isNotEmpty)
            Row(
              spacing: WdSpace.s6,
              children: [
                for (final p in photos)
                  WdSurface(
                    color: WdColors.photoPlaceholder,
                    radius: 10,
                    width: 76,
                    height: 76,
                    child: Image(image: p, fit: BoxFit.cover),
                  ),
              ],
            ),
          if (tags.isNotEmpty) Row(spacing: WdSpace.s6, children: [for (final t in tags) WdTag(t, filled: false)]),
        ],
      ),
    );
  }
}
