import 'package:flutter/material.dart';

import '../tokens.dart';
import 'surface.dart';

class WdRank {
  const WdRank({required this.rank, required this.name, required this.meta, required this.value, this.avatar});

  final String rank;
  final String name;

  /// 예: "4′39″/km · 09.07"
  final String meta;

  /// 예: "24:12"
  final String value;
  final ImageProvider? avatar;
}

Widget _avatar(ImageProvider? image, Color color) => ClipOval(
      child: SizedBox.square(
        dimension: 30,
        child: image != null ? Image(image: image, fit: BoxFit.cover) : ColoredBox(color: color),
      ),
    );

/// Rank row — 랭킹 한 줄 (h74).
class WdRankRow extends StatelessWidget {
  const WdRankRow(this.data, {super.key, this.onTap});

  final WdRank data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 74,
      child: Row(
        spacing: 11,
        children: [
          SizedBox(
            width: 26,
            child: Text(data.rank, style: WdText.raw(14, FontWeight.w700, 22).copyWith(color: WdColors.ink)),
          ),
          _avatar(data.avatar, WdColors.neutralSurface),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WdText.raw(14, FontWeight.w500, 22).copyWith(color: WdColors.ink)),
                Text(data.meta, style: WdText.raw(12, FontWeight.w400, 16).copyWith(color: WdColors.muted)),
              ],
            ),
          ),
          Text(data.value, style: WdText.raw(16, FontWeight.w700, 22).copyWith(color: WdColors.ink)),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Rank / List (top 5 · compact) — soft 카드 안 랭킹 목록. compact는 meta에 날짜를 빼면 된다.
class WdRankList extends StatelessWidget {
  const WdRankList({super.key, required this.ranks, this.onTap});

  final List<WdRank> ranks;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) => WdSurface(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < ranks.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: WdColors.map),
              WdRankRow(ranks[i], onTap: onTap == null ? null : () => onTap!(i)),
            ],
          ],
        ),
      );
}

/// Rank / My rank card — 내 순위 강조 (--record-self-*).
class WdMyRankCard extends StatelessWidget {
  const WdMyRankCard(this.data, {super.key, this.onTap});

  final WdRank data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WdSurface(
        color: WdColors.recordSelfSurface,
        radius: WdRadius.r12,
        border: const BorderSide(color: WdColors.recordSelfBorder),
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12),
        height: 84,
        onTap: onTap,
        child: Row(
          spacing: 11,
          children: [
            Text(data.rank,
                style: WdText.raw(14, FontWeight.w700, 21).copyWith(color: WdColors.recordSelfTextPrimary)),
            _avatar(data.avatar, WdColors.recordSelfAvatar),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WdText.raw(14, FontWeight.w700, 21).copyWith(color: WdColors.recordSelfTextPrimary)),
                  Text(data.meta,
                      style: WdText.raw(12, FontWeight.w400, 16).copyWith(color: WdColors.recordSelfTextSecondary)),
                ],
              ),
            ),
            Text(data.value, style: WdText.raw(16, FontWeight.w700, 21).copyWith(color: WdColors.recordSelfValue)),
          ],
        ),
      );
}
