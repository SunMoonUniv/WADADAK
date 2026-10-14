import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../application/run_controller.dart';
import '../domain/run_voice.dart';

class RunSettingsScreen extends ConsumerStatefulWidget {
  const RunSettingsScreen({super.key});
  @override
  ConsumerState<RunSettingsScreen> createState() => _RunSettingsScreenState();
}

class _RunSettingsScreenState extends ConsumerState<RunSettingsScreen> {
  bool _saving = false;
  String? _error;
  Future<void> _save(RunVoiceSettings value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(runControllerProvider).saveVoiceSettings(value);
    } on Object {
      if (mounted) setState(() => _error = '설정을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(runControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.voiceSettings;
        return Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(
            title: '러닝 설정',
            onBack: () => Navigator.pop(context),
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('음성 안내', style: WdText.ko20Bold),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('음성 안내 사용'),
                subtitle: const Text('일시정지 중에는 안내하지 않아요.'),
                value: settings.enabled,
                onChanged: _saving
                    ? null
                    : (value) => _save(settings.copyWith(enabled: value)),
              ),
              const SizedBox(height: 16),
              WdSegmentedControl(
                items: const ['거리 기준', '시간 기준'],
                selectedIndex: settings.unit.index,
                onChanged: (index) {
                  if (!_saving) {
                    _save(settings.copyWith(unit: VoiceUnit.values[index]));
                  }
                },
              ),
              const SizedBox(height: 16),
              Text('안내 간격', style: WdText.ko14Bold),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final interval
                      in settings.unit == VoiceUnit.distance
                          ? [1, 2, 5]
                          : [5, 10, 15])
                    ChoiceChip(
                      label: Text(
                        '$interval${settings.unit == VoiceUnit.distance ? ' km' : '분'}',
                      ),
                      selected:
                          interval ==
                          (settings.unit == VoiceUnit.distance
                              ? settings.distanceKm
                              : settings.timeMinutes),
                      onSelected: _saving
                          ? null
                          : (_) => _save(
                              settings.unit == VoiceUnit.distance
                                  ? settings.copyWith(distanceKm: interval)
                                  : settings.copyWith(timeMinutes: interval),
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '시간 안내는 일시정지를 제외한 달린 시간 기준이에요. 거리와 시간 중 하나만 안내해요.',
                style: WdText.ko12.copyWith(color: WdColors.muted),
              ),
              const SizedBox(height: 16),
              WdButton(
                '음성 들어보기',
                variant: WdButtonVariant.secondary,
                onPressed: controller.run?.phase.name == 'paused'
                    ? null
                    : controller.testVoice,
              ),
              if (controller.voiceNotice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: WdInfoBanner(
                    controller.voiceNotice!,
                    tone: WdBannerTone.warning,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: WdInfoBanner(_error!, tone: WdBannerTone.warning),
                ),
              const SizedBox(height: 32),
              Text('케이던스', style: WdText.ko20Bold),
              const SizedBox(height: 8),
              Text(
                '휴대폰을 들고 달리면 걸음 센서로 분당 걸음 수를 측정해요. 센서가 없는 기기에서는 —로 표시해요. 평균은 센서가 측정된 시간의 걸음 수 기준이며 일시정지 중 이동은 제외해요.',
                style: WdText.ko13.copyWith(color: WdColors.muted),
              ),
              const SizedBox(height: 16),
              WdButton(
                '권한 설정 열기',
                variant: WdButtonVariant.secondary,
                onPressed: () => openAppSettings(),
              ),
            ],
          ),
        );
      },
    );
  }
}
