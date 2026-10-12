import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../application/free_run_controller.dart';
import '../domain/run_models.dart';

class FreeRunScreen extends ConsumerWidget {
  const FreeRunScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(freeRunControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final run = controller.snapshot;
        if (controller.countdown != null) {
          return Scaffold(
            appBar: const WdAppBar(title: '시작 준비'),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${controller.countdown}', style: WdText.numeric88),
                  const SizedBox(height: WdSpace.s24),
                  WdButton(
                    '시작 취소',
                    onPressed: controller.cancelStart,
                    variant: WdButtonVariant.secondary,
                  ),
                ],
              ),
            ),
          );
        }
        if (run.state == RunState.ready) {
          return Scaffold(
            appBar: const WdAppBar(title: '달리기 준비'),
            body: Padding(
              padding: const EdgeInsets.all(WdSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('자유 러닝', style: WdText.ko17Bold),
                  const SizedBox(height: WdSpace.s12),
                  const Text('시간 기록을 시작해 보세요.'),
                  const SizedBox(height: WdSpace.s12),
                  const Text('현재 기록은 앱을 종료하면 사라져요. 거리 기록은 준비 중이에요.'),
                  const Spacer(),
                  _HoldToStart(onStart: controller.prepareStart),
                ],
              ),
            ),
          );
        }
        if (run.state == RunState.finished) {
          return Scaffold(
            appBar: const WdAppBar(title: '러닝 결과'),
            body: Padding(
              padding: const EdgeInsets.all(WdSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('러닝을 마쳤어요', style: WdText.ko17Bold),
                  const SizedBox(height: WdSpace.s24),
                  WdSummaryTiles([
                    ('총 소요시간', formatRunTime(run.elapsed)),
                    ('달린시간', formatRunTime(run.active)),
                  ]),
                  const SizedBox(height: WdSpace.s12),
                  WdSummaryTiles([
                    (
                      '거리',
                      run.hasLocation
                          ? '${(run.distanceMeters / 1000).toStringAsFixed(2)} km'
                          : '—',
                    ),
                    ('평균 페이스', formatRunPace(run.paceSecondsPerKm)),
                  ]),
                  const SizedBox(height: WdSpace.s24),
                  const Text('현재 기록은 앱을 종료하면 사라져요.'),
                  const Spacer(),
                  WdButton('새 러닝 준비', onPressed: controller.newRun),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: WdColors.dark,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(WdSpace.s24),
              child: Column(
                children: [
                  WdRunHeader(
                    title: '자유 러닝',
                    subtitle: '시간 기록',
                    badge: run.state == RunState.paused ? '일시정지' : '기록 중',
                  ),
                  const SizedBox(height: WdSpace.s24),
                  WdElapsedTime(
                    time: formatRunTime(run.active),
                    caption: '총 소요 ${formatRunTime(run.elapsed)}',
                  ),
                  const Spacer(),
                  if (run.state == RunState.running)
                    WdRunPauseButton(onPressed: controller.pause)
                  else
                    WdRunPausedButtons(
                      onResume: controller.resume,
                      onStop: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('러닝을 종료할까요?'),
                            content: const Text('이번 러닝의 결과를 확인할 수 있어요.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('취소'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('종료'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) controller.finish();
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HoldToStart extends StatefulWidget {
  const _HoldToStart({required this.onStart});
  final VoidCallback onStart;
  @override
  State<_HoldToStart> createState() => _HoldToStartState();
}

class _HoldToStartState extends State<_HoldToStart> {
  Timer? _hold;
  int? _pointer;
  void _release(PointerEvent event) {
    if (!mounted || _pointer != event.pointer) return;
    _hold?.cancel();
    setState(() => _pointer = null);
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '1초 눌러 러닝 시작',
    onLongPress: widget.onStart,
    excludeSemantics: true,
    child: Listener(
      onPointerDown: (event) {
        if (_pointer != null) return;
        setState(() => _pointer = event.pointer);
        _hold = Timer(const Duration(seconds: 1), widget.onStart);
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: WdButton(
        _pointer == null ? '1초 눌러 시작' : '누르고 있어 주세요',
        onPressed: () {},
      ),
    ),
  );
}
