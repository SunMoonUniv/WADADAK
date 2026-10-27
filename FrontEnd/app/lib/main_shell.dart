import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'core/auth/auth_controller.dart';
import 'features/home/home_tab_exits.dart';
import 'features/run/application/free_run_controller.dart';
import 'features/run/domain/run_models.dart';
import 'routes.dart';

/// 하단 탭 4개(홈 · 달리기 · 랭킹 · MY). 탭마다 자기 화면 기록을 유지한다.
/// 홈은 다른 탭에 갔다 오면 탐색 상태를 처음으로 되돌린다(FIL-08, [HomeTabExits]).
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(freeRunControllerProvider);
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        // C5만 탭을 표시하고 H4/C4/D1-2는 피그마의 전체 화면을 쓴다.
        final fullScreen =
            shell.currentIndex == 1 &&
            (run.preparing ||
                run.courseStart != null ||
                run.snapshot.state != RunState.ready);
        return Scaffold(
          body: HomeTabExits(atHome: shell.currentIndex == 0, child: shell),
          bottomNavigationBar: fullScreen
              ? null
              : WdBottomNav(
                  currentIndex: shell.currentIndex,
                  // 홈은 다른 탭에서 돌아와도 처음 자리(A2)다. 홈 탭 안에 연 검색(G1)은 닫힌다(FIL-08).
                  onTap: (index) => shell.goBranch(
                    index,
                    initialLocation: index == shell.currentIndex || index == 0,
                  ),
                ),
        );
      },
    );
  }
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
              child: Text(
                '준비 중인 화면이에요',
                style: WdText.body13.copyWith(color: WdColors.muted),
              ),
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}

/// MY 탭. E3 마이페이지를 만들 때까지 내 러닝 기록(I1)으로 가는 버튼과 로그아웃만 둔다.
class MyPlaceholderTab extends ConsumerWidget {
  const MyPlaceholderTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlaceholderTab(
    title: 'MY',
    action: Column(
      spacing: WdSpace.s12,
      children: [
        WdButton('내 러닝 기록', onPressed: () => context.push(Routes.myRecords)),
        WdButton(
          '로그아웃',
          variant: WdButtonVariant.secondary,
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ],
    ),
  );
}
