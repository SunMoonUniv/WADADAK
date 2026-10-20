import 'dart:async';

import 'package:go_router/go_router.dart';

import '../../../routes.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../application/free_run_controller.dart';
import '../domain/run_models.dart';
import 'free_run_live_view.dart';
import 'free_run_result_view.dart';

/// C5 → H4 → C4 / 일시정지 → D1-2. 측정 상태는 화면 밖에서 유지한다.
class FreeRunScreen extends ConsumerWidget {
  const FreeRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(freeRunControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final run = controller.snapshot;
        final dark =
            controller.preparing ||
            run.state == RunState.running ||
            run.state == RunState.paused;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: controller.preparing
              ? _Countdown(
                  value: controller.countdown,
                  gpsStatus: controller.gpsStatus,
                  onCancel: controller.canCancelStart
                      ? controller.cancelStart
                      : null,
                )
              : switch (run.state) {
                  RunState.ready => _Preparation(
                    onStart: controller.prepareStart,
                    error: controller.error,
                    onSettings: controller.hasSettingsAction
                        ? controller.openSettings
                        : null,
                    recent: controller.recent,
                  ),
                  RunState.finished => FreeRunResultView(
                    run: run,
                    onConfirm: controller.newRun,
                  ),
                  _ => FreeRunLiveView(
                    run: run,
                    onPause: controller.storageFault ? null : controller.pause,
                    onResume: controller.storageFault
                        ? null
                        : controller.resume,
                    onStop: controller.storageFault
                        ? null
                        : () => _confirmStop(context, controller),
                  ),
                },
        );
      },
    );
  }

  Future<void> _confirmStop(
    BuildContext context,
    FreeRunController controller,
  ) async {
    controller.setEndConfirmation(true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: WdColors.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WdRadius.r20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WdSpace.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('러닝을 종료할까요?', style: WdText.ko20Bold),
                const SizedBox(height: WdSpace.s12),
                Text(
                  '이번 러닝의 결과를 확인할 수 있어요.',
                  style: WdText.ko13.copyWith(color: WdColors.muted),
                ),
                const SizedBox(height: WdSpace.s24),
                Row(
                  spacing: WdSpace.s8,
                  children: [
                    Expanded(
                      child: WdButton(
                        '취소',
                        variant: WdButtonVariant.secondary,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                    Expanded(
                      child: WdButton(
                        '종료',
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed == true && context.mounted) await controller.finish();
    } finally {
      controller.setEndConfirmation(false);
    }
  }
}

void _notReady(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$feature 기능은 준비 중이에요.')));
}

/// Figma 1453:4123 — 준비 화면. 실제 기록 조회 연결 전에는 빈 최근 기록을 표시한다.
class _Preparation extends StatelessWidget {
  const _Preparation({
    required this.onStart,
    this.error,
    this.onSettings,
    this.recent,
  });
  final VoidCallback onStart;
  final String? error;
  final VoidCallback? onSettings;
  final RunSnapshot? recent;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.paper,
    appBar: WdAppBar(
      title: '달리기',
      action: WdAppBarAction.circle(
        WdIcons.settings,
        semanticLabel: '러닝 설정',
        onTap: () => context.push(Routes.runSettings),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WdSpace.s24,
            WdSpace.s0,
            WdSpace.s24,
            WdSpace.s12,
          ),
          child: WdSegmentedControl(
            items: const ['자유 러닝', '코스 러닝', '고스트 대결'],
            selectedIndex: 0,
            onChanged: (index) {
              if (index != 0) {
                _notReady(context, index == 1 ? '코스 러닝' : '고스트 대결');
              }
            },
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WdSpace.s24,
                      WdSpace.s16,
                      WdSpace.s24,
                      WdSpace.s24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (error != null) ...[
                          WdInfoBanner(error!, tone: WdBannerTone.warning),
                          if (onSettings != null)
                            WdButton('권한 설정 열기', onPressed: onSettings),
                          const SizedBox(height: WdSpace.s12),
                        ],
                        Text('오늘은, 발길이 닿는 대로.', style: WdText.ko22Bold),
                        const SizedBox(height: WdSpace.s4),
                        Text(
                          '코스 제한 없이 나만의 속도로 달려보세요.',
                          style: WdText.ko12.copyWith(color: WdColors.muted),
                        ),
                        const SizedBox(height: WdSpace.s8),
                        const WdInfoBanner(
                          '자유 러닝은 코스 기록 · 랭킹 · 고스트 대결에 반영되지 않아요.',
                          tone: WdBannerTone.warning,
                          plain: true,
                        ),
                        const SizedBox(height: WdSpace.s8),
                        WdSurface(
                          height: 96,
                          padding: const EdgeInsets.all(WdSpace.s12),
                          child: Row(
                            spacing: WdSpace.s12,
                            children: [
                              // 피그마 원본 26×24 아이콘. 탭의 21×21 러닝 아이콘과 별개다.
                              SvgPicture.asset(
                                'assets/run/free_run.svg',
                                width: 26,
                                height: 24,
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: WdSpace.s3,
                                  children: [
                                    Text(
                                      '정해진 길 없이, 자유롭게',
                                      style: WdText.ko16Bold,
                                    ),
                                    Text(
                                      '시간과 거리, 페이스를 함께 기록해요',
                                      style: WdText.ko12.copyWith(
                                        color: WdColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: WdSpace.s8),
                        WdSurface(
                          color: WdColors.dark,
                          radius: WdRadius.r20,
                          height: 178,
                          padding: const EdgeInsets.all(WdSpace.s20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                spacing: WdSpace.s10,
                                children: [
                                  WdSurface(
                                    color: WdColors.darkCard,
                                    radius: WdRadius.r12,
                                    width: 42,
                                    height: 42,
                                    child: const Center(
                                      child: WdIcon(WdIcons.brandGhost),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: WdSpace.s3,
                                      children: [
                                        Text(
                                          '지난 러닝',
                                          style: WdText.run11W700H16.copyWith(
                                            color: WdColors.grayLight,
                                          ),
                                        ),
                                        Text(
                                          '최근 자유 러닝',
                                          style: WdText.ko15Bold.copyWith(
                                            color: WdColors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: WdSpace.s14),
                              Text(
                                recent == null
                                    ? '아직 기록이 없어요'
                                    : '${(recent!.distanceMeters / 1000).toStringAsFixed(2)} km',
                                style: WdText.ko22Bold.copyWith(
                                  color: WdColors.white,
                                ),
                              ),
                              const Spacer(),
                              const ColoredBox(
                                color: WdColors.darkLine,
                                child: SizedBox(height: WdSpace.s1),
                              ),
                              const SizedBox(height: WdSpace.s14),
                              Text(
                                recent == null
                                    ? '첫 자유 러닝을 시작해 보세요.'
                                    : '총 소요 ${formatRunTime(recent!.elapsed)} · 기기 저장 완료',
                                style: WdText.ko12.copyWith(
                                  color: WdColors.grayLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: WdSpace.s8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: WdSpace.s10,
                          children: [
                            const WdIcon(WdIcons.ghostInfo, size: 18),
                            Expanded(
                              child: Text(
                                '러닝 기록은 이 기기에 자동으로 저장돼요.',
                                style: WdText.ko12.copyWith(
                                  color: WdColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: WdSpace.s30),
                        const Spacer(),
                        Center(
                          child: Text(
                            'GPS와 걸음 센서로 측정해요',
                            style: WdText.ko12.copyWith(color: WdColors.muted),
                          ),
                        ),
                        const SizedBox(height: WdSpace.s8),
                        _HoldToStart(onStart: onStart),
                        const SizedBox(height: WdSpace.s8),
                        Center(
                          child: Text(
                            '1초 길게 눌러 시작',
                            style: WdText.ko12.copyWith(color: WdColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Figma 1453:4617 — 3초 카운트다운. OS 상태바는 SafeArea로 처리한다.
class _Countdown extends StatelessWidget {
  const _Countdown({
    required this.value,
    required this.onCancel,
    required this.gpsStatus,
  });
  final int? value;
  final VoidCallback? onCancel;
  final String gpsStatus;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.runBackground,
    body: SafeArea(
      child: Column(
        children: [
          const WdRunHeader(title: '자유 러닝', subtitle: '자유 러닝', badge: '준비'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: WdSpace.s16,
                      horizontal: WdSpace.s24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: WdSpace.s28,
                      children: [
                        WdSurface(
                          color: WdColors.runSurface,
                          radius: WdRadius.full,
                          padding: const EdgeInsets.symmetric(
                            horizontal: WdSpace.s8,
                            vertical: WdSpace.s6,
                          ),
                          child: Text(
                            '자유 러닝',
                            style: WdText.ko12Medium.copyWith(
                              color: WdColors.lime,
                            ),
                          ),
                        ),
                        Text(
                          value == null ? 'GPS 신호를 확인하고 있어요' : '곧 출발해요',
                          style: WdText.ko22Bold.copyWith(
                            color: WdColors.white,
                          ),
                        ),
                        if (value == null)
                          const SizedBox(
                            height: 100,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: WdColors.lime,
                              ),
                            ),
                          )
                        else
                          Text(
                            '$value',
                            style: WdText.run180W800H207.copyWith(
                              color: WdColors.lime,
                            ),
                          ),
                        Text(
                          '나의 기록을 넘어서는 한 걸음.',
                          style: WdText.run14W400H20.copyWith(
                            color: WdColors.runTextSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WdSpace.s24,
              WdSpace.s12,
              WdSpace.s24,
              WdSpace.s24,
            ),
            child: Column(
              spacing: WdSpace.s12,
              children: [
                WdSensorStatus([('GPS 신호', gpsStatus), ('케이던스 센서', '시작 후 측정')]),
                WdButton(
                  '시작 취소',
                  onPressed: onCancel,
                  variant: WdButtonVariant.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
        _pointer == null ? '자유 러닝 시작' : '누르고 있어 주세요',
        onPressed: () {},
      ),
    ),
  );
}
