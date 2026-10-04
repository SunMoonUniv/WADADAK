import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'surface.dart';

enum _Kind { circle, icon, text, button }

/// [WdAppBar] 오른쪽 동작 — Figma 앱 바 변형의 네 가지 동작 모양.
class WdAppBarAction {
  /// 40px 원형 soft 버튼 — Action(settings) · Action(share) · Large.
  const WdAppBarAction.circle(WdIcons this.icon, {required this.onTap, required String this.semanticLabel})
      : label = null,
        primary = false,
        _kind = _Kind.circle;

  /// 배경 없는 아이콘 — Back + Title + Share.
  const WdAppBarAction.icon(WdIcons this.icon, {required this.onTap, required String this.semanticLabel})
      : label = null,
        primary = false,
        _kind = _Kind.icon;

  /// 회색 글자 — Back + Title + Text (예: 초기화).
  const WdAppBarAction.text(String this.label, {required this.onTap})
      : icon = null,
        semanticLabel = null,
        primary = false,
        _kind = _Kind.text;

  /// 알약 버튼 — Back + Title + Button. 화면의 주 동작(저장)은 [primary].
  const WdAppBarAction.button(String this.label, {required this.onTap, this.primary = false})
      : icon = null,
        semanticLabel = null,
        _kind = _Kind.button;

  final WdIcons? icon;
  final String? label;
  final String? semanticLabel;
  final bool primary;
  final VoidCallback? onTap;
  final _Kind _kind;

  Widget _build() => switch (_kind) {
        _Kind.circle => Semantics(
            button: true,
            label: semanticLabel,
            child: WdSurface(
              radius: WdRadius.full,
              width: 40,
              height: 40,
              onTap: onTap,
              child: Center(child: WdIcon(icon!)),
            ),
          ),
        _Kind.icon => _FullHeightTap(
            onTap: onTap,
            semanticLabel: semanticLabel,
            child: WdIcon(icon!),
          ),
        _Kind.text => _FullHeightTap(
            onTap: onTap,
            child: Text(label!, style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.muted)),
          ),
        _Kind.button => Semantics(
            button: true,
            child: WdSurface(
              color: primary ? WdColors.lime : WdColors.soft,
              radius: WdRadius.full,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onTap: onTap,
              child: Center(
                widthFactor: 1,
                child: Text(label!, style: WdText.raw(13, FontWeight.w700, 18).copyWith(color: WdColors.ink)),
              ),
            ),
          ),
      };
}

/// 공통 앱 바 (App bar / *).
///
/// | Figma 변형 | 사용 |
/// |---|---|
/// | Title | `WdAppBar(title: ..)` |
/// | Back + Title | `onBack: ..` |
/// | Back + Title + Text | `onBack`, `action: WdAppBarAction.text('초기화', ..)` |
/// | Back + Title + Share | `onBack`, `action: WdAppBarAction.icon(WdIcons.share, ..)` |
/// | Back + Title + Button | `onBack`, `action: WdAppBarAction.button('저장', primary: true, ..)` |
/// | Back + Title + Action(settings·share) | `onBack`, `action: WdAppBarAction.circle(..)` — 제목 가운데 |
/// | Title + Action(settings) | `action: WdAppBarAction.circle(WdIcons.settings, ..)` |
/// | Title + Action(settings) · Large | 위 + `large: true` |
class WdAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WdAppBar({super.key, required this.title, this.onBack, this.action, this.large = false});

  final String title;

  /// null이 아니면 뒤로 가기 아이콘을 보인다.
  final VoidCallback? onBack;
  final WdAppBarAction? action;

  /// MY 같은 최상위 탭용 큰 앱 바 (높이 76).
  final bool large;

  bool get _circle => action?._kind == _Kind.circle;

  // Figma 변형별 높이 그대로.
  @override
  Size get preferredSize => Size.fromHeight(large ? 76 : (_circle ? (onBack != null ? 66 : 64) : 70.5));

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WdText.ko20Bold.copyWith(color: WdColors.ink),
    );
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: preferredSize.height,
        child: Padding(
          // 뒤로 가기는 왼쪽 여백까지 터치 영역으로 쓴다.
          padding: EdgeInsets.only(left: onBack == null ? WdSpace.s24 : 0, right: WdSpace.s24),
          child: Row(
            spacing: WdSpace.s12,
            children: [
              if (onBack != null)
                _FullHeightTap(
                  onTap: onBack,
                  semanticLabel: '뒤로 가기',
                  child: const Padding(
                    padding: EdgeInsets.only(left: WdSpace.s24),
                    child: WdIcon(WdIcons.back),
                  ),
                ),
              // Back + 원형 동작 변형만 제목이 양 끝 사이 가운데에 온다.
              Expanded(child: onBack != null && _circle ? Center(child: titleText) : titleText),
              if (action != null) action!._build(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 앱 바 높이 전체를 터치 영역으로 쓰는 작은 동작.
class _FullHeightTap extends StatelessWidget {
  const _FullHeightTap({required this.onTap, this.semanticLabel, required this.child});

  final VoidCallback? onTap;
  final String? semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(height: double.infinity, child: Center(child: child)),
        ),
      );
}
