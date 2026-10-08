import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'surface.dart';

enum WdButtonVariant { primary, secondary }

/// A DS / Button — h54 · radius 16 · 16 Bold. 부모 너비를 꽉 채운다.
///
/// [onPressed]가 null이면 비활성 모양(서비스 이용 동의 — 선택 전 화면 기준).
class WdButton extends StatelessWidget {
  const WdButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.variant = WdButtonVariant.primary,
    this.showArrow = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final WdButtonVariant variant;

  /// Figma `showIcon` — 라벨 오른쪽 화살표.
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? WdColors.textPrimary : WdColors.disabledText;
    return Semantics(
      button: true,
      enabled: enabled,
      child: WdSurface(
        color: !enabled
            ? WdColors.disabledBg
            : variant == WdButtonVariant.primary
                ? WdColors.actionPrimary
                : WdColors.surfaceSubtle,
        width: double.infinity,
        height: 54,
        onTap: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: WdSpace.s8,
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.ko16Bold.copyWith(color: fg)),
            ),
            if (showArrow) WdIcon(WdIcons.arrowRight, color: fg),
          ],
        ),
      ),
    );
  }
}

/// 화면 하단 고정 버튼 영역 — Bottom bar / Pinned CTA · Dual CTA.
///
/// `Scaffold(bottomNavigationBar: WdBottomBar.pinned(...))`처럼 쓴다. 하단 안전 영역을 포함한다.
class WdBottomBar extends StatelessWidget {
  /// Pinned CTA: 버튼 하나 (pt16 · pb24 · px24).
  const WdBottomBar.pinned({super.key, required this.primary}) : secondary = null;

  /// Dual CTA: 보조(왼쪽) + 주(오른쪽), 같은 너비 (pt10 · pb18 · px16 · gap 8).
  const WdBottomBar.dual({super.key, required Widget this.secondary, required this.primary});

  final Widget? secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    final dual = secondary != null;
    return ColoredBox(
      color: WdColors.paper,
      child: SafeArea(
        top: false,
        minimum: dual ? const EdgeInsets.fromLTRB(16, 10, 16, 18) : const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: dual
            ? Row(spacing: WdSpace.s8, children: [Expanded(child: secondary!), Expanded(child: primary)])
            : primary,
      ),
    );
  }
}

enum WdSocialProvider { kakao, apple, google }

/// Social login button — 각 사 공식 가이드 기준 (h54 · radius 12).
class WdSocialLoginButton extends StatelessWidget {
  const WdSocialLoginButton(this.provider, {super.key, required this.onPressed});

  final WdSocialProvider provider;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (bg, border, icon, gap, label) = switch (provider) {
      WdSocialProvider.kakao => (
          const Color(0xFFFEE500),
          null,
          const WdIcon(WdIcons.kakao),
          WdSpace.s8,
          Text('카카오 로그인', style: WdText.raw(18, FontWeight.w500).copyWith(color: const Color(0xD9000000))),
        ),
      WdSocialProvider.apple => (
          WdColors.white,
          const BorderSide(color: Color(0xFF000000)),
          const WdIcon(WdIcons.apple),
          WdSpace.s8,
          Text('Apple로 로그인', style: WdText.raw(23, FontWeight.w500).copyWith(color: const Color(0xFF000000))),
        ),
      WdSocialProvider.google => (
          WdColors.white,
          const BorderSide(color: Color(0xFF747775)),
          const WdIcon(WdIcons.google),
          WdSpace.s12,
          Text.rich(
            const TextSpan(children: [
              // Figma: "Google"만 Roboto Medium (Android 시스템 폰트).
              TextSpan(text: 'Google', style: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500)),
              TextSpan(text: ' 계정으로 로그인'),
            ]),
            style: WdText.raw(19, FontWeight.w500).copyWith(color: const Color(0xFF1F1F1F)),
          ),
        ),
    };
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: WdSurface(
        color: bg,
        radius: WdRadius.r12,
        border: border,
        width: double.infinity,
        height: 54,
        onTap: onPressed,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: gap, children: [icon, label]),
      ),
    );
  }
}
