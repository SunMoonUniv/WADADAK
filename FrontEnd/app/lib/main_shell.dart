import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'core/auth/auth_controller.dart';

/// 하단 탭 4개(홈 · 달리기 · 랭킹 · MY). 탭마다 자기 화면 기록을 유지한다.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: WdBottomNav(
          currentIndex: shell.currentIndex,
          // 지금 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다.
          onTap: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
        ),
      );
}

/// 각 탭 담당자가 실제 화면으로 바꾼다.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: WdAppBar(title: title),
        body: Padding(
          padding: const EdgeInsets.all(WdSpace.s24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Text('준비 중인 화면이에요', style: WdText.body13.copyWith(color: WdColors.muted)),
                ),
              ),
              ?action,
            ],
          ),
        ),
      );
}

/// MY 탭 담당(F13)이 실제 화면을 만들 때까지 로그아웃만 둔다.
class MyPlaceholderTab extends ConsumerWidget {
  const MyPlaceholderTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlaceholderTab(
        title: 'MY',
        action: WdButton(
          '로그아웃',
          variant: WdButtonVariant.secondary,
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      );
}
