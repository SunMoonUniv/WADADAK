import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

/// B1 · B8 탭 안의 빈 상태 카드(Figma B1-1 · B8-1). 고스트 아이콘 · 제목 · 설명이다.
class CourseEmptyCard extends StatelessWidget {
  const CourseEmptyCard({super.key, required this.title, required this.message});

  final String title;

  /// 여러 줄이면 `\n`.
  final String message;

  @override
  Widget build(BuildContext context) => WdSurface(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16, vertical: WdSpace.s24),
        child: Column(
          spacing: WdSpace.s8,
          children: [
            const WdIcon(WdIcons.ghostInfo, size: 24),
            Text(title, textAlign: TextAlign.center, style: WdText.ko15Bold.copyWith(color: WdColors.ink)),
            Text(message, textAlign: TextAlign.center, style: WdText.ko12.copyWith(color: WdColors.muted)),
          ],
        ),
      );
}
