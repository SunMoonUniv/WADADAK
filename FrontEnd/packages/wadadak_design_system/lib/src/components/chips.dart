import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'surface.dart';

enum WdTone { neutral, success, warning, info }

/// Tag — 상태·메타 배지.
///
/// - `filled: true` (기본): 와이어프레임 Tag — 톤 배경 · 10px.
/// - `filled: false`: A DS 카드 안 글자 태그 — 배경 없음 · 12px (예: "완주 100%", "만료 D-7").
class WdTag extends StatelessWidget {
  const WdTag(this.label, {super.key, this.tone = WdTone.neutral, this.filled = true});

  final String label;
  final WdTone tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      WdTone.neutral => (WdColors.neutralSurface, WdColors.neutralTextSecondary),
      WdTone.success => (WdColors.successBg, WdColors.success),
      WdTone.warning => (WdColors.warningBg, WdColors.warning),
      WdTone.info => (WdColors.infoBg, WdColors.info),
    };
    final plain = switch (tone) {
      WdTone.neutral => WdColors.muted,
      WdTone.success => WdColors.green,
      WdTone.warning => WdColors.warningText,
      WdTone.info => WdColors.info,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: filled ? BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)) : null,
      child: Text(
        label,
        maxLines: 1,
        style: (filled ? WdText.micro10 : WdText.label12).copyWith(color: filled ? fg : plain),
      ),
    );
  }
}

/// 목록 정렬·필터 칩 (홈 Course filters) — h30, 선택 시 ink 배경.
///
/// 선택지 칩(프로필 설정 F2 러닝 경력)은 `height: 36`.
class WdFilterChip extends StatelessWidget {
  const WdFilterChip(String this.label, {super.key, this.selected = false, this.height = 30, required this.onTap})
      : icon = null,
        semanticLabel = null;

  /// 아이콘만 있는 칩 (예: 상세 필터 슬라이더, w32).
  const WdFilterChip.icon(WdIcons this.icon, {super.key, required String this.semanticLabel, required this.onTap})
      : label = null,
        selected = false,
        height = 30;

  final String? label;
  final WdIcons? icon;
  final String? semanticLabel;
  final bool selected;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        child: WdSurface(
          color: selected ? WdColors.ink : WdColors.soft,
          radius: WdRadius.full,
          width: icon != null ? 32 : null,
          height: height,
          padding: icon != null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: WdSpace.s8),
          onTap: onTap,
          child: Center(
            widthFactor: 1,
            child: icon != null
                ? WdIcon(icon!, size: 16)
                : Text(label!, style: WdText.ko12Medium.copyWith(color: selected ? WdColors.white : WdColors.ink)),
          ),
        ),
      );
}
