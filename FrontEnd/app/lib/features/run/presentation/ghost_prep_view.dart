import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../routes.dart';
import '../application/course_run_entry.dart';
import '../domain/course_run.dart';
import '../domain/own_ghost.dart';
import '../domain/free_ghost.dart';
import '../domain/run_models.dart';
import 'course_prep_view.dart';
import 'free_ghost_record_choice.dart';

class GhostRunPrep extends StatelessWidget {
  const GhostRunPrep({
    super.key,
    required this.course,
    required this.ghost,
    required this.kind,
    this.locked = false,
    this.freeGhost,
  });
  final CourseSelection? course;
  final PreparedCourseGhost? ghost;
  final GhostRecordKind kind;
  final bool locked;
  final PreparedFreeGhost? freeGhost;

  @override
  Widget build(BuildContext context) {
    if (kind == GhostRecordKind.personal) {
      final free = freeGhost;
      final choose = locked
          ? null
          : () => context.push(Routes.runFreeGhostSelect);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('어제의 나를 넘어설 시간.', style: WdText.ko22Bold),
          const SizedBox(height: 4),
          Text(
            '내 자유러닝 기록을 골라 같은 경로에서 대결해요.',
            style: WdText.ko12.copyWith(color: WdColors.muted),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: choose,
            child: WdSelectedCourseCard(
              title: free == null
                  ? '내 자유 기록 선택'
                  : freeGhostRecordTitle(free.startedAt),
              meta: free == null
                  ? '저장된 자유러닝 기록에서 선택'
                  : '${(free.originalDistanceM / 1000).toStringAsFixed(2)} km · ${freeGhostRecordDate(free.startedAt)}',
              status: free == null ? '1km 이상 · 경로 확인 후 사용' : '자유러닝 · 경로 재생 가능',
              changeLabel: '기록 선택',
              onChange: choose,
              thumbnail: free == null
                  ? const Center(child: WdIcon(WdIcons.run))
                  : FreeGhostRouteThumbnail(
                      segments: free.reference.routeSegments,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          WdRecordCard(
            overline: '선택한 내 자유러닝 기록',
            title: free == null ? '대결할 기록을 골라 주세요' : '지난 기록의 나',
            time: free == null
                ? '—'
                : formatRunTime(Duration(seconds: free.replay.seconds)),
            caption: free == null ? '기록을 고르면 비교 시간을 확인해요' : '대결 비교 시간 · 정지 포함',
            footer: free == null
                ? '내 자유 기록 선택 ›'
                : '${freeGhostRecordDate(free.startedAt)} · 이 기록과 다시 달려요.',
            onTap: choose,
          ),
          const SizedBox(height: 8),
          const WdInfoBanner('선택한 기록의 경로를 따라 고스트와 대결해요.', plain: true),
        ],
      );
    }
    final selected = ghost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: locked,
          child: CourseRunPrep(course: course, ghost: true),
        ),
        const SizedBox(height: 8),
        WdRecordCard(
          overline: selected?.publicPeriod == null
              ? '대결 상대 · 내 기록'
              : '대결 상대 · 공개 코스 기록',
          title: selected == null
              ? '내 완주 기록 선택'
              : selected.publicPeriod == null
              ? '선택한 내 완주 기록'
              : '선택한 공개 기록',
          time: selected == null
              ? '—'
              : formatRunTime(Duration(seconds: selected.seconds)),
          caption: selected == null ? '내 최고·최근·과거 완주 기록' : '정지 포함 코스 총 소요시간',
          footer: course == null
              ? '코스를 먼저 골라 주세요'
              : selected == null
              ? '기록 선택'
              : selected.publicPeriod == null
              ? '다른 내 기록 선택'
              : '내 완주 기록으로 변경',
          onTap: course == null || locked
              ? null
              : () => context.push(Routes.runOwnGhostSelect),
        ),
        const SizedBox(height: 8),
        const WdInfoBanner('고스트와의 거리 차이를 실시간으로 확인하세요.', plain: true),
      ],
    );
  }
}
