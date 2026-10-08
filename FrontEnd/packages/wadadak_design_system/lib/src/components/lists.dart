import 'package:flutter/material.dart';

import '../tokens.dart';
import 'inputs.dart';
import 'surface.dart';

/// List row — 설정·정보 목록 한 줄 (와이어프레임 이관).
///
/// Type=Value: [value]만 / Chevron: [value] + [onTap] / ToggleOn·Off: [toggle] + [onToggle].
class WdListRow extends StatelessWidget {
  const WdListRow({super.key, required this.label, this.value, this.onTap, this.toggle, this.onToggle});

  final String label;
  final String? value;

  /// null이 아니면 오른쪽에 "›"가 붙는다.
  final VoidCallback? onTap;

  /// null이 아니면 오른쪽에 스위치가 붙는다.
  final bool? toggle;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      // Figma: Value 40 · Chevron 44 · Toggle 48
      height: toggle != null ? 48 : (onTap != null ? 44 : 40),
      color: Colors.transparent,
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WdText.body13.copyWith(color: WdColors.neutralText)),
          ),
          if (value != null) Text(value!, style: WdText.label12.copyWith(color: WdColors.neutralTextSecondary)),
          if (toggle != null) WdSwitch(value: toggle!, onChanged: onToggle),
          if (onTap != null && toggle == null)
            Text('›', style: WdText.raw(16, FontWeight.w400, 16 * 1.4).copyWith(color: WdColors.neutralTextWeak)),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

class WdMenuItem {
  const WdMenuItem({required this.label, this.value, required this.onTap});

  final String label;
  final String? value;
  final VoidCallback? onTap;
}

/// List card / Menu — soft 카드 안 메뉴 목록 (예: 내 러닝 기록 42회 ›).
class WdMenuCard extends StatelessWidget {
  const WdMenuCard({super.key, required this.items});

  final List<WdMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final small = WdText.raw(12, FontWeight.w400, 20).copyWith(color: WdColors.muted);
    return WdSurface(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, indent: WdSpace.s14, endIndent: WdSpace.s14, color: WdColors.map),
            InkWell(
              onTap: items[i].onTap,
              child: SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14),
                  child: Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: Text(items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.ink)),
                      ),
                      if (items[i].value != null) Text(items[i].value!, style: small),
                      Text('›', style: small),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Section heading / With meta — 섹션 제목 + 오른쪽 안내 링크.
class WdSectionHeading extends StatelessWidget {
  const WdSectionHeading(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;

  /// 예: "러너를 탭하면 프로필 ›"
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(actionLabel!, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.green)),
            ),
        ],
      );
}

/// Step row — 굵은 제목 + 설명 (코스 만들기 단계 안내 등).
class WdStepRow extends StatelessWidget {
  const WdStepRow({super.key, required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Text(title, style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
          Text(description, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
        ],
      );
}
