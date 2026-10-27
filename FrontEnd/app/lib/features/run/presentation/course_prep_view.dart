import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/course_api_client.dart';
import '../../../core/api/ranking_api_client.dart';
import '../../../routes.dart';
import '../../course/course_format.dart';
import '../../course/course_list_card.dart';
import '../../course/detail/course_ranking_state.dart';
import '../../review/review_state.dart';
import '../domain/course_run.dart';
import '../domain/run_models.dart';

/// 고른 코스의 상세(경로·거리·난이도·현재 러너). 실패하면 카드에 이름만 보인다
final runCourseDetailProvider = FutureProvider.autoDispose
    .family<CourseDetail, String>(
      (ref, courseId) =>
          ref.watch(courseApiClientProvider).courseDetail(courseId),
      retry: (_, _) => null,
    );

/// C6 달리기 준비 — 코스 러닝(Figma 1453:4196): 코스 카드 · 이 코스의 내 최고 기록 · 이탈 안내 한 줄.
/// 고스트 대결 준비(C1)도 같은 부품(WdSelectedCourseCard · WdRecordCard)을 쓴다.
class CourseRunPrep extends ConsumerWidget {
  const CourseRunPrep({super.key, required this.course, this.ghost = false});
  final bool ghost;

  /// 고른 코스. `코스 러닝` 탭에서 아직 안 골랐으면 null이고 C8로 고르게 한다(RUN-03)
  final CourseSelection? course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = this.course;
    if (course == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ghost ? '지난 기록과 다시 달려보세요.' : '익숙한 코스, 새로운 기록.',
            style: WdText.ko22Bold,
          ),
          const SizedBox(height: WdSpace.s4),
          Text(
            '달릴 코스를 골라 주세요.',
            style: WdText.ko12.copyWith(color: WdColors.muted),
          ),
          const SizedBox(height: WdSpace.s8),
          GestureDetector(
            onTap: () => context.push(Routes.runCourseSelect),
            child: WdSelectedCourseCard(
              title: '코스를 골라 주세요',
              meta: '최근 달린 코스 · 내 주변 · 검색',
              status: '',
              changeLabel: '선택',
              onChange: () => context.push(Routes.runCourseSelect),
            ),
          ),
        ],
      );
    }
    final id = course.courseId;
    final detail = ref.watch(runCourseDetailProvider(id)).value;
    final rating = ref.watch(reviewSummaryProvider(id)).value?.averageRating;
    final ranking = ghost
        ? null
        : ref
              .watch(
                courseRankingProvider((
                  courseId: id,
                  period: RankingPeriod.all,
                )),
              )
              .value;
    final me = ranking?.me;
    final best = me?.courseElapsedSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ghost ? '지난 기록과 다시 달려보세요.' : '익숙한 코스, 새로운 기록.',
          style: WdText.ko22Bold,
        ),
        const SizedBox(height: WdSpace.s4),
        Text(
          '${course.name}${objectParticle(course.name)} 따라 끝까지 달려보세요.',
          style: WdText.ko12.copyWith(color: WdColors.muted),
        ),
        const SizedBox(height: WdSpace.s8),
        WdSelectedCourseCard(
          title: course.name,
          meta: detail == null
              ? ''
              : [
                  formatKm(detail.distanceMeters),
                  '난이도 ${detail.difficulty.label}',
                  if (detail.tags.isNotEmpty) detail.tags.first.label,
                ].join(' · '),
          status: [
            if (rating != null) '★ ${rating.toStringAsFixed(1)}',
            formatActiveRunners(detail?.activeRunners ?? 0),
          ].join(' · '),
          thumbnail: detail == null ? null : CourseRouteThumbnail(detail.route),
          onChange: () => context.push(Routes.runCourseSelect),
        ),
        const SizedBox(height: WdSpace.s8),
        if (!ghost)
          WdRecordCard(
            overline: '코스 최고 기록',
            title: '이 코스의 내 최고 기록',
            time: best == null ? '—' : formatRunTime(Duration(seconds: best)),
            caption: best == null
                ? '아직 완주 기록이 없어요'
                : '평균 페이스 ${formatRunPace(me!.paceSecondsPerKm?.toDouble())}',
            footer: switch (me?.status) {
              MyRankStatus.ranked =>
                '코스 순위 ${me!.rank}위 / ${formatCount(ranking!.participantCount)}명',
              MyRankStatus.private =>
                '비공개 중 · 참여 ${formatCount(ranking!.participantCount)}명',
              _ => '완주하면 코스 랭킹에 올라요',
            },
            onTap: () => context.push(
              Routes.courseRankings(id),
              extra: (courseName: course.name, period: RankingPeriod.all),
            ),
          ),
        const SizedBox(height: WdSpace.s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WdSpace.s10,
          children: [
            const WdIcon(WdIcons.ghostInfo, size: 18),
            Expanded(
              // Figma 문구("30 m 이상 벗어난 채 달리면 완주로 인정되지 않아요")는 정책과 달라 고쳤다:
              // 벗어난 구간만 인정 거리에서 빠지고, 돌아와 95%를 채우면 완주다(7.3)
              child: Text(
                '코스를 벗어나 달린 구간은 완주 거리로 인정되지 않아요.',
                style: WdText.ko12.copyWith(color: WdColors.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 목적격 조사 을/를. 받침 있는 한글로 끝나면 '을', 그 밖(받침 없음·영문·숫자)은 '를'
String objectParticle(String word) {
  final code = word.isEmpty ? 0 : word.runes.last;
  final hangul = code >= 0xAC00 && code <= 0xD7A3;
  return hangul && (code - 0xAC00) % 28 != 0 ? '을' : '를';
}
