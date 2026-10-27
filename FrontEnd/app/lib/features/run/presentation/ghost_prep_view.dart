import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../routes.dart';
import '../domain/course_run.dart';
import '../domain/own_ghost.dart';
import '../domain/free_ghost.dart';
import '../domain/run_models.dart';
import 'course_prep_view.dart';

class GhostRunPrep extends StatelessWidget {
  const GhostRunPrep({
    super.key,
    required this.course,
    required this.ghost,
    this.locked = false,
    this.freeGhost,
    this.onClearFree,
  });
  final CourseSelection? course;
  final PreparedOwnGhost? ghost;
  final bool locked;
  final PreparedFreeGhost? freeGhost;
  final VoidCallback? onClearFree;

  @override
  Widget build(BuildContext context) {
    final selected = ghost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WdRecordCard(
          overline: '코스 등록 없이 대결',
          title: freeGhost == null ? '내 자유 기록 선택' : '선택한 내 자유 기록',
          time: freeGhost == null
              ? '—'
              : formatRunTime(Duration(seconds: freeGhost!.replay.seconds)),
          caption: freeGhost == null
              ? '1km 이상 · 중단 기록도 재생 가능하면 선택'
              : '대결 비교 시간 · 정지 포함',
          footer: freeGhost == null ? '과거 자유 기록 고르기' : '다른 자유 기록 선택',
          onTap: locked ? null : () => context.push(Routes.runFreeGhostSelect),
        ),
        if (freeGhost != null) ...[
          const SizedBox(height: WdSpace.s8),
          WdInfoBanner(
            '원래 기록 ${formatRunTime(Duration(milliseconds: freeGhost!.originalElapsedMs))}. 같은 경로의 완주 조건까지 비교해요.',
            plain: true,
          ),
        ],
        const SizedBox(height: WdSpace.s16),
        if (freeGhost == null) ...[
          IgnorePointer(
            ignoring: locked,
            child: CourseRunPrep(course: course, ghost: true),
          ),
          const SizedBox(height: WdSpace.s12),
          WdRecordCard(
            overline: '대결 상대 · 내 기록',
            title: selected == null ? '내 완주 기록 선택' : '선택한 내 완주 기록',
            time: selected == null
                ? '—'
                : formatRunTime(Duration(seconds: selected.candidate.seconds)),
            caption: selected == null ? '내 최고·최근·과거 완주 기록' : '정지 포함 코스 총 소요시간',
            footer: course == null
                ? '코스를 먼저 골라 주세요'
                : selected == null
                ? '기록 선택'
                : '다른 내 기록 선택',
            onTap: course == null || locked
                ? null
                : () => context.push(Routes.runOwnGhostSelect),
          ),
        ] else
          WdButton(
            '코스 완주 기록으로 선택하기',
            variant: WdButtonVariant.secondary,
            onPressed: locked ? null : onClearFree,
          ),
        const SizedBox(height: WdSpace.s8),
        const WdInfoBanner(
          '자유 기록을 고르거나 코스와 완주 기록을 골라 시작해요. 최종 완주와 승패는 러닝 종료 후 서버에서 판정해요.',
          plain: true,
        ),
      ],
    );
  }
}
