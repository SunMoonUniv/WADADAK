import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'surface.dart';

// 지도 위에 올리는 요소들. 지도 자체는 지도 SDK가 그린다.

/// Map button / Locate — 현위치 버튼 (40).
class WdMapLocateButton extends StatelessWidget {
  const WdMapLocateButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '현재 위치',
        child: WdSurface(
          color: WdColors.paper,
          radius: WdRadius.full,
          width: 40,
          height: 40,
          onTap: onPressed,
          child: const Center(child: WdIcon(WdIcons.locate)),
        ),
      );
}

/// Map button / Zoom — 확대·축소 (40 × 81, 그림자).
class WdMapZoomControl extends StatelessWidget {
  const WdMapZoomControl({super.key, required this.onZoomIn, required this.onZoomOut});

  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WdColors.white,
          borderRadius: BorderRadius.circular(WdRadius.r12),
          boxShadow: WdShadows.floating,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button('＋', '확대', onZoomIn),
            const ColoredBox(color: WdColors.divider, child: SizedBox(width: 24, height: 1)),
            _button('－', '축소', onZoomOut),
          ],
        ),
      );

  Widget _button(String glyph, String label, VoidCallback? onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Center(child: Text(glyph, style: WdText.raw(18, FontWeight.w500).copyWith(color: WdColors.ink))),
          ),
        ),
      );
}

/// Km marker — 경로를 따라 1 km마다 놓는 표지.
class WdKmMarker extends StatelessWidget {
  const WdKmMarker(this.label, {super.key});

  /// 예: "1 km"
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: WdColors.lime,
          border: Border.all(color: WdColors.ink, width: 1.5),
          borderRadius: BorderRadius.circular(WdRadius.full),
        ),
        child: Text(label, style: WdText.raw(11, FontWeight.w700, 14).copyWith(color: WdColors.ink)),
      );
}

/// Route point — 경로 그리기 입력점 (14). 코스 등록 후에는 표시하지 않는다.
class WdRoutePoint extends StatelessWidget {
  const WdRoutePoint({super.key});

  @override
  Widget build(BuildContext context) => const WdIcon(WdIcons.routePoint);
}

/// Map / Region count bubble — 지도 축소 시 지역별 코스 수 (64).
class WdRegionCountBubble extends StatelessWidget {
  const WdRegionCountBubble({super.key, required this.count, required this.region, this.onTap});

  /// 예: "1,240"
  final String count;

  /// 예: "서울"
  final String region;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WdSurface(
        color: WdColors.ink,
        radius: WdRadius.full,
        width: 64,
        height: 64,
        padding: const EdgeInsets.all(WdSpace.s8),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 2,
          children: [
            Text(count, maxLines: 1, style: WdText.raw(16, FontWeight.w700, 18).copyWith(color: WdColors.lime)),
            Text(region, maxLines: 1, style: WdText.raw(11, FontWeight.w400, 15).copyWith(color: WdColors.white)),
          ],
        ),
      );
}

/// Map / Sheet peek — 지도 아래 접힌 코스 목록 시트의 머리.
class WdSheetPeek extends StatelessWidget {
  const WdSheetPeek({super.key, required this.title, this.meta, this.onTap});

  /// 예: "↑ 위로 올려 코스 목록 보기"
  final String title;

  /// 예: "전국 3,412"
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WdSurface(
        color: WdColors.paper,
        radius: 18,
        border: const BorderSide(color: WdColors.line),
        padding: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s10, WdSpace.s16, WdSpace.s12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: WdSpace.s8,
          children: [
            // Figma 그대로 왼쪽 정렬 핸들.
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: WdColors.map, borderRadius: BorderRadius.circular(2)),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
                ),
                if (meta != null)
                  Text(meta!, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
              ],
            ),
          ],
        ),
      );
}
