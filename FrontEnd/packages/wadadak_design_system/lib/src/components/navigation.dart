import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';

/// Tab item × n — 밑줄 탭, 너비 균등 분할 (h46).
///
/// Material [TabBar]를 Figma 스타일로 감싼 것이라 [TabBarView]와 그대로 연동된다.
class WdTabBar extends StatelessWidget implements PreferredSizeWidget {
  const WdTabBar({super.key, required this.tabs, this.controller, this.onTap});

  final List<String> tabs;

  /// null이면 [DefaultTabController]를 쓴다.
  final TabController? controller;
  final ValueChanged<int>? onTap;

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) => TabBar(
        controller: controller,
        onTap: onTap,
        tabs: [for (final t in tabs) Tab(text: t, height: 46)],
        labelColor: WdColors.ink,
        unselectedLabelColor: WdColors.muted,
        labelStyle: WdText.raw(13, FontWeight.w700),
        unselectedLabelStyle: WdText.raw(13, FontWeight.w400),
        labelPadding: EdgeInsets.zero,
        indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: WdColors.ink, width: 2)),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      );
}

class WdBottomNavItem {
  const WdBottomNavItem({required this.icon, required this.label});

  final WdIcons icon;
  final String label;
}

/// A DS / Bottom navigation — 선택된 탭은 라임 알약 + 굵은 라벨.
///
/// `Scaffold(bottomNavigationBar: WdBottomNav(...))`. 하단 안전 영역을 포함한다.
class WdBottomNav extends StatelessWidget {
  const WdBottomNav({super.key, required this.currentIndex, required this.onTap, this.items = defaultItems});

  static const defaultItems = [
    WdBottomNavItem(icon: WdIcons.home, label: '홈'),
    WdBottomNavItem(icon: WdIcons.run, label: '달리기'),
    WdBottomNavItem(icon: WdIcons.trophy, label: '랭킹'),
    WdBottomNavItem(icon: WdIcons.user, label: 'MY'),
  ];

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<WdBottomNavItem> items;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: WdColors.surfaceDefault,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 18), // Figma 84 = 12 + 54 + 18
          child: Padding(
            padding: const EdgeInsets.fromLTRB(WdSpace.s20, WdSpace.s12, WdSpace.s20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (var i = 0; i < items.length; i++) _tab(i)],
            ),
          ),
        ),
      );

  Widget _tab(int i) {
    final selected = i == currentIndex;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(i),
        child: SizedBox(
          width: 76,
          height: 54,
          child: Column(
            spacing: WdSpace.s4,
            children: [
              Container(
                width: 44,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? WdColors.actionPrimary : null,
                  borderRadius: BorderRadius.circular(WdRadius.full),
                ),
                child: WdIcon(items[i].icon, size: 21, color: selected ? WdColors.textPrimary : WdColors.textSecondary),
              ),
              Text(
                items[i].label,
                style: selected
                    ? WdText.caption11Bold.copyWith(color: WdColors.textPrimary)
                    : WdText.ko11Medium.copyWith(color: WdColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum WdSegmentStyle {
  /// Run / Mode segment — soft 트랙, 선택 시 ink.
  dark,

  /// Builder segment — 회색 트랙, 선택 시 흰 바탕 + 테두리.
  light,
}

/// 세그먼트 컨트롤. 바깥 여백(화면 패딩)은 포함하지 않는다.
class WdSegmentedControl extends StatelessWidget {
  const WdSegmentedControl({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.style = WdSegmentStyle.dark,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final WdSegmentStyle style;

  @override
  Widget build(BuildContext context) {
    final dark = style == WdSegmentStyle.dark;
    return Container(
      padding: EdgeInsets.all(dark ? WdSpace.s4 : 3),
      decoration: BoxDecoration(
        color: dark ? WdColors.soft : WdColors.neutralSurface,
        borderRadius: BorderRadius.circular(dark ? WdRadius.r12 : 10),
      ),
      child: Row(
        spacing: dark ? WdSpace.s4 : 0,
        children: [for (var i = 0; i < items.length; i++) Expanded(child: _segment(i, dark))],
      ),
    );
  }

  Widget _segment(int i, bool dark) {
    final selected = i == selectedIndex;
    final TextStyle text;
    final BoxDecoration decoration;
    if (dark) {
      text = WdText.ko12Medium.copyWith(color: selected ? WdColors.white : WdColors.muted);
      decoration = BoxDecoration(
        color: selected ? WdColors.ink : null,
        borderRadius: BorderRadius.circular(WdRadius.r8),
      );
    } else {
      text = WdText.raw(12, selected ? FontWeight.w700 : FontWeight.w400, 12 * 1.4)
          .copyWith(color: selected ? WdColors.neutralText : WdColors.neutralTextSecondary);
      decoration = BoxDecoration(
        color: selected ? WdColors.white : null,
        borderRadius: BorderRadius.circular(WdRadius.r8),
        // 선택 전후 높이가 같도록 테두리 자리는 항상 둔다.
        border: Border.all(color: selected ? WdColors.neutralBorder : const Color(0x00000000)),
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: Container(
          height: dark ? 34 : 12 * 1.4 + 18, // light: py9 + 12px/140%
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: decoration,
          child: Text(items[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
        ),
      ),
    );
  }
}
