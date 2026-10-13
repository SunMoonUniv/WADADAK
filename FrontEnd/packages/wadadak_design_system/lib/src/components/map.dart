import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'surface.dart';

// 지도 위에 올리는 요소들. 지도 자체는 지도 SDK가 그린다.

/// Map button / Locate — 현위치 버튼 (40).
class WdMapLocateButton extends StatelessWidget {
  const WdMapLocateButton({super.key, required this.onPressed});

  /// 지름. 지도 여백을 맞출 때 쓴다.
  static const size = 40.0;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '현재 위치',
        child: WdSurface(
          color: WdColors.paper,
          radius: WdRadius.full,
          width: size,
          height: size,
          onTap: onPressed,
          child: const Center(child: WdIcon(WdIcons.locate)),
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

// ── 경로 그리기(B3) 지도 위 요소 ──
// Figma에는 컴포넌트가 없고 B3 화면에 직접 그려져 있어 그 값을 옮겼다.

/// 지도 위 안내 문구 — B3 "지도를 탭해 경로 그리기 · 점을 순서대로 연결".
class WdMapHint extends StatelessWidget {
  const WdMapHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s10, vertical: WdSpace.s6),
        decoration: BoxDecoration(color: WdColors.ink, borderRadius: BorderRadius.circular(WdRadius.full)),
        child: Text(text, style: WdText.raw(12, FontWeight.w500).copyWith(color: WdColors.white)),
      );
}

/// 지도 위 코스 이름표 — A5 "성북천 벚꽃길 3K · ★4.8". 평점이 없으면 이름만 보인다.
///
/// 지도 표지로 올릴 때는 아래 가운데를 코스 출발점에 둔다.
class WdMapCourseLabel extends StatelessWidget {
  const WdMapCourseLabel(this.name, {super.key, this.rating});

  final String name;

  /// 예: "4.8"
  final String? rating;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8, vertical: WdSpace.s4),
        decoration: BoxDecoration(color: WdColors.ink, borderRadius: BorderRadius.circular(WdRadius.full)),
        child: Text(rating == null ? name : '$name · ★$rating', style: WdText.ko12Medium.copyWith(color: WdColors.white)),
      );
}

/// 지도 위 흰 알약 버튼.
class WdMapPillButton extends StatelessWidget {
  /// B3 `↺  되돌리기` · `✕  전체 지우기` — 여백 10·8, 떠 있는 그림자. Figma는 되돌리기만 [bold]다.
  const WdMapPillButton(this.label, {super.key, required this.onPressed, this.bold = false}) : _small = false;

  /// 홈 `＋ 코스 만들기` — 여백 8·4, 그림자 없음.
  const WdMapPillButton.small(this.label, {super.key, required this.onPressed})
      : bold = false,
        _small = true;

  final String label;

  /// null이면 비활성(글자를 흐리게).
  final VoidCallback? onPressed;
  final bool bold;
  final bool _small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final style = _small ? WdText.ko12Medium : WdText.raw(12, bold ? FontWeight.w700 : FontWeight.w500);
    return Semantics(
      button: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WdRadius.full),
          boxShadow: _small ? null : WdShadows.floating,
        ),
        child: Material(
          color: WdColors.white,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: _small
                  ? const EdgeInsets.symmetric(horizontal: WdSpace.s8, vertical: WdSpace.s4)
                  : const EdgeInsets.symmetric(horizontal: WdSpace.s10, vertical: WdSpace.s8),
              child: Text(label, style: style.copyWith(color: enabled ? WdColors.ink : WdColors.disabledText)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 경로 그리기 출발·도착 표지 — 이름표 + 점.
///
/// 지도 표지로 올릴 때는 점 가운데가 좌표에 오도록 [startAnchor] · [endAnchor]를 쓴다.
/// 네이버 지도는 위젯을 그림으로 한 번 그려 올리므로 SVG 없이 그린다.
class WdRouteEndpoint extends StatelessWidget {
  /// 출발: 위에 초록 `출발`, 아래에 큰 점(잉크 · 흰 테두리 · 라임 가운데).
  const WdRouteEndpoint.start({super.key}) : _start = true;

  /// 도착: 경로 작성점과 같은 점, 아래에 잉크 `도착`.
  const WdRouteEndpoint.end({super.key}) : _start = false;

  final bool _start;

  static const _label = 20.0;
  static const _gap = WdSpace.s6;
  static const _startDot = 26.0;
  static const _endDot = 14.0;

  /// 출발 표지에서 점 가운데의 위치(표지 크기에 대한 비율).
  static const startAnchor = Offset(0.5, (_label + _gap + _startDot / 2) / (_label + _gap + _startDot));

  /// 도착 표지에서 점 가운데의 위치(표지 크기에 대한 비율).
  static const endAnchor = Offset(0.5, (_endDot / 2) / (_endDot + _gap + _label));

  @override
  Widget build(BuildContext context) {
    final label = Container(
      height: _label,
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _start ? WdColors.green : WdColors.ink,
        borderRadius: BorderRadius.circular(WdRadius.full),
      ),
      child: Text(_start ? '출발' : '도착',
          style: WdText.raw(12, FontWeight.w700).copyWith(color: _start ? WdColors.white : WdColors.lime)),
    );
    final dot = _start
        ? Container(
            width: _startDot,
            height: _startDot,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WdColors.ink,
              shape: BoxShape.circle,
              border: Border.all(color: WdColors.white, width: 4),
            ),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: WdColors.lime, shape: BoxShape.circle),
            ),
          )
        // WdRoutePoint(SVG)와 같은 모양: 흰 원 + 잉크 테두리 3.
        : Container(
            width: _endDot,
            height: _endDot,
            decoration: BoxDecoration(
              color: WdColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: WdColors.ink, width: 3),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: _gap,
      children: _start ? [label, dot] : [dot, label],
    );
  }
}

/// 경로 그리기 범례 — 출발 · 도착 · 찍은 점. 색은 출발·도착 이름표와 같다.
class WdRouteLegend extends StatelessWidget {
  const WdRouteLegend({super.key});

  /// 높이. 지도 여백을 맞출 때 쓴다.
  static const height = 26.0;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s10),
        decoration: BoxDecoration(
          color: WdColors.white,
          borderRadius: BorderRadius.circular(WdRadius.full),
          boxShadow: WdShadows.floating,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: WdSpace.s10,
          children: [
            _item(const BoxDecoration(color: WdColors.green, shape: BoxShape.circle), '출발'),
            _item(const BoxDecoration(color: WdColors.ink, shape: BoxShape.circle), '도착'),
            _item(
              BoxDecoration(
                color: WdColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: WdColors.ink, width: 1.5),
              ),
              '찍은 점',
            ),
          ],
        ),
      );

  Widget _item(BoxDecoration dot, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s4,
        children: [
          Container(width: 8, height: 8, decoration: dot),
          Text(label, style: WdText.raw(12, FontWeight.w500).copyWith(color: WdColors.muted)),
        ],
      );
}
