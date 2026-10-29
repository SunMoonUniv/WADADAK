import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'features/home/home_tab_exits.dart';
import 'features/run/application/free_run_controller.dart';
import 'features/run/domain/run_models.dart';

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
