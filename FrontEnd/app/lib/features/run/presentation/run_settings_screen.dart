import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

class RunSettingsScreen extends StatelessWidget {
  const RunSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.paper,
    appBar: WdAppBar(
      title: '러닝 설정',
      onBack: () => Navigator.pop(context),
    ),
    body: ListView(
      padding: const EdgeInsets.all(WdSpace.s24),
      children: [
        Text('케이던스', style: WdText.ko20Bold),
        const SizedBox(height: WdSpace.s8),
        Text(
          '휴대폰을 들고 달리면 걸음 센서로 분당 걸음 수를 측정해요. 센서가 없는 기기에서는 —로 표시해요. 평균은 센서가 측정된 시간의 걸음 수 기준이며 일시정지 중 이동은 제외해요.',
          style: WdText.ko13.copyWith(color: WdColors.muted),
        ),
        const SizedBox(height: WdSpace.s16),
        WdButton(
          '권한 설정 열기',
          variant: WdButtonVariant.secondary,
          onPressed: () => openAppSettings(),
        ),
      ],
    ),
  );
}
