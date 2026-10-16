import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

/// B11 코스 공개 기간 안내 시트. 코스 정보 입력으로 가기 전에 매번 띄운다 — B3 다음, B6 기록 선택 뒤(Figma 프로토타입, 4.1 B11).
///
/// `확인`을 누르면 true다. X · 바깥 · 뒤로 닫으면 false이고 부른 화면에 머문다.
Future<bool> showCoursePublicPeriodSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      builder: (_) => const CoursePublicPeriodSheet(),
    ) ??
    false;

class CoursePublicPeriodSheet extends StatelessWidget {
  const CoursePublicPeriodSheet({super.key});

  static const title = '코스 공개 기간';

  /// Figma B11 순서. 공개 · 연장 · 비공개 후 삭제 · 만료 표시(정책 공통 4 · A2-05).
  static const rules = [
    '등록한 날부터 30일 동안 공개돼요',
    '그 안에 누군가 완주하면 30일 연장돼요',
    '기간이 끝나면 비공개로 바뀌고 24시간 뒤 삭제돼요',
    '7일 이하로 남으면 ‘만료 D-3’처럼 남은 날이 표시돼요',
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WdSpace.s16, 0, WdSpace.s16, WdSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WdSpace.s16,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: WdText.ko20Bold.copyWith(color: WdColors.ink))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: WdColors.muted),
                    tooltip: '닫기',
                  ),
                ],
              ),
              Text('코스는 정해진 기간 동안만 지도에 공개돼요', style: WdText.label12.copyWith(color: WdColors.muted)),
              WdSurface(
                padding: const EdgeInsets.all(WdSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: WdSpace.s14,
                  children: [
                    for (final rule in rules)
                      Row(
                        spacing: WdSpace.s10,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: WdColors.green, shape: BoxShape.circle),
                          ),
                          Expanded(child: Text(rule, style: WdText.ko13.copyWith(color: WdColors.ink))),
                        ],
                      ),
                  ],
                ),
              ),
              WdButton('확인', onPressed: () => Navigator.of(context).pop(true)),
            ],
          ),
        ),
      );
}
