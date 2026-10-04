import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'surface.dart';

/// Input — 흰 바탕 · 테두리 · radius 10 · 13px (h44).
class WdTextField extends StatelessWidget {
  const WdTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  static OutlineInputBorder _border(Color color) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color));

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        enabled: enabled,
        style: WdText.body13.copyWith(color: WdColors.neutralText),
        cursorColor: WdColors.ink,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: WdText.body13.copyWith(color: WdColors.neutralTextWeak),
          isDense: true,
          filled: true,
          fillColor: WdColors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          enabledBorder: _border(WdColors.neutralBorder),
          disabledBorder: _border(WdColors.neutralBorder),
          // 포커스 모양은 Figma에 없어 ink 테두리로 표시만 한다.
          focusedBorder: _border(WdColors.ink),
        ),
      );
}

/// Search / Bar — soft 바탕 검색 입력.
///
/// 검색 화면으로 이동만 하는 자리라면 [onTap]을 주면 입력 없이 탭만 받는다.
class WdSearchBar extends StatelessWidget {
  const WdSearchBar({
    super.key,
    this.controller,
    this.hintText = '지역 · 코스 이름 검색',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = WdText.raw(12, FontWeight.w400, 18);
    return WdSurface(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12, vertical: 11),
      child: Row(
        spacing: WdSpace.s8,
        children: [
          Text('⌕', style: WdText.raw(14, FontWeight.w400, 14 * 1.4).copyWith(color: WdColors.muted)),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              onTap: onTap,
              readOnly: onTap != null,
              textInputAction: TextInputAction.search,
              style: text.copyWith(color: WdColors.ink),
              cursorColor: WdColors.ink,
              decoration: InputDecoration.collapsed(hintText: hintText, hintStyle: text.copyWith(color: WdColors.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search / Header — 검색 결과 화면 상단: 뒤로 + 검색어 + 지우기.
class WdSearchHeader extends StatelessWidget {
  const WdSearchHeader({
    super.key,
    required this.controller,
    required this.onBack,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onBack;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final text = WdText.raw(12, FontWeight.w400, 18);
    return Padding(
      padding: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s10, WdSpace.s16, WdSpace.s12),
      child: Row(
        spacing: WdSpace.s10,
        children: [
          Semantics(
            button: true,
            label: '뒤로 가기',
            child: GestureDetector(
              onTap: onBack,
              child: Text('←', style: WdText.raw(19, FontWeight.w500, 19 * 1.4).copyWith(color: WdColors.ink)),
            ),
          ),
          Expanded(
            child: WdSurface(
              padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12, vertical: WdSpace.s10),
              child: Row(
                spacing: WdSpace.s8,
                children: [
                  Text('⌕', style: text.copyWith(color: WdColors.muted)),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textInputAction: TextInputAction.search,
                      style: text.copyWith(color: WdColors.ink),
                      cursorColor: WdColors.ink,
                      decoration: InputDecoration.collapsed(
                          hintText: hintText, hintStyle: text.copyWith(color: WdColors.muted)),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '검색어 지우기',
                    child: GestureDetector(
                      onTap: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                      child: Text('✕', style: text.copyWith(color: WdColors.muted)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// List row의 토글 — 44×26, 켜짐 #14141A · 꺼짐 #D9D9DE.
class WdSwitch extends StatelessWidget {
  const WdSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        enabled: onChanged != null,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? WdColors.neutralDark : WdColors.switchOff,
              borderRadius: BorderRadius.circular(13),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: const SizedBox.square(
                dimension: 20,
                child: DecoratedBox(decoration: BoxDecoration(color: WdColors.white, shape: BoxShape.circle)),
              ),
            ),
          ),
        ),
      );
}

/// Consent row — 약관 동의 한 줄 (h52). 체크 전에는 연회색 체크.
class WdConsentRow extends StatelessWidget {
  const WdConsentRow({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
    this.onView,
    this.viewLabel = '보기 ›',
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  /// null이 아니면 오른쪽에 "보기 ›".
  final VoidCallback? onView;
  final String viewLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        checked: checked,
        child: WdSurface(
          radius: WdRadius.r12,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16),
          onTap: () => onChanged(!checked),
          child: Row(
            spacing: WdSpace.s12,
            children: [
              WdIcon(WdIcons.check, color: checked ? null : WdColors.checkOff),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WdText.raw(14, FontWeight.w500, 20).copyWith(color: WdColors.ink)),
              ),
              if (onView != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onView,
                  child: SizedBox(
                    height: 52,
                    child: Center(
                      child: Text(viewLabel, style: WdText.raw(12, FontWeight.w500).copyWith(color: WdColors.muted)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Review / Rating form 한 줄 — 라벨 + 별 5개 (min-h44).
class WdRatingRow extends StatelessWidget {
  const WdRatingRow({super.key, required this.label, required this.value, this.onChanged});

  final String label;

  /// 0–5
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final star = WdText.raw(22, FontWeight.w400, 18).copyWith(color: WdColors.muted);
    return Row(
      children: [
        Expanded(child: Text(label, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.ink))),
        for (var i = 0; i < 5; i++)
          Semantics(
            button: true,
            selected: i < value,
            label: '${i + 1}점',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onChanged == null ? null : () => onChanged!(i + 1),
              // Figma 글자 "★ ★ ★ ★ ☆" 그대로 — 별 사이 공백 포함.
              child: SizedBox(
                height: 44,
                child: Center(child: Text('${i < value ? '★' : '☆'}${i < 4 ? ' ' : ''}', style: star)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Review / Photo upload — 추가 버튼 + 사진 74px.
class WdPhotoUpload extends StatelessWidget {
  const WdPhotoUpload({super.key, required this.photos, required this.onAdd, this.onTapPhoto});

  final List<ImageProvider> photos;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onTapPhoto;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: WdSpace.s8,
          children: [
            Semantics(
              button: true,
              label: '사진 추가',
              child: WdSurface(
                color: WdColors.paper,
                border: const BorderSide(color: WdColors.line),
                width: 74,
                height: 74,
                onTap: onAdd,
                child: Center(child: Text('＋', style: WdText.raw(20, FontWeight.w400, 28).copyWith(color: WdColors.muted))),
              ),
            ),
            for (var i = 0; i < photos.length; i++)
              WdSurface(
                radius: 10,
                width: 74,
                height: 74,
                onTap: onTapPhoto == null ? null : () => onTapPhoto!(i),
                child: Image(image: photos[i], fit: BoxFit.cover),
              ),
          ],
        ),
      );
}

/// Stepper — − 값 ＋ (예: 1 km 지점 간격).
class WdStepper extends StatelessWidget {
  const WdStepper({super.key, required this.value, this.onDecrement, this.onIncrement});

  /// 표시 문자열 (예: "1.0 km").
  final String value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: WdColors.soft, borderRadius: BorderRadius.circular(WdRadius.r16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _step('−', '줄이기', onDecrement),
            DecoratedBox(
              decoration: BoxDecoration(color: WdColors.paper, borderRadius: BorderRadius.circular(WdRadius.r16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WdSpace.s6),
                child: Text(value, style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
              ),
            ),
            _step('＋', '늘리기', onIncrement),
          ],
        ),
      );

  Widget _step(String glyph, String label, VoidCallback? onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WdSpace.s10, vertical: WdSpace.s6),
            child: Text(glyph, style: WdText.raw(14, FontWeight.w500).copyWith(color: WdColors.ink)),
          ),
        ),
      );
}
