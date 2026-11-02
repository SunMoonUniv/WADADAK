import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/api/member_api_client.dart';
import '../../core/api/ranking_api_client.dart';
import '../../core/error_message.dart';
import '../../core/map/geo_point.dart';
import '../../routes.dart';
import '../course/course_format.dart';
import '../course/course_list_card.dart';
import '../course/detail/course_ranking_tab.dart';
import '../course/detail/course_reviews_tab.dart';
import '../my/my_screen.dart';
import '../run/application/course_run_entry.dart';
import '../run/domain/course_run.dart';
import 'ranking_widgets.dart';
import 'runner_profile_state.dart';

/// 코스 화면(B9 · G3)에서 I3을 열 때 넘기는 값. 코스 이름과 썸네일 경로는 들어온 화면의 값을 쓴다.
typedef RunnerProfileCourse = ({String courseId, String courseName, List<GeoPoint> route, RankingPeriod period});

/// 다른 러너의 I3을 연다. 코스 화면에서 열면 [course]로 `이 코스에서의 기록`을 보인다.
void openRunnerProfile(BuildContext context, String memberId, {RunnerProfileCourse? course}) =>
    context.push(Routes.runnerProfile(memberId), extra: course);

/// I3 · 다른 러너 프로필. 앱 바(닉네임), 프로필(사진 · 닉네임 · `지역 · 러닝 경력`), 총 거리 · 러닝 · 등록 코스,
/// 이 코스에서의 기록, 등록한 코스 순서다(Figma I3, 정책 문서 4.1 `I3 범위`).
///
/// - 프로필 · 총 거리 · 등록 코스 · 기록 · 코스 목록은 member · ranking · course API를 따로 받는다. 하나가 실패해도 그 칸만 `—`다.
/// - 내 정보 비공개 러너는 총 거리 · 러닝이 `—`다. 등록 코스는 공개 정보라 그대로 보인다.
/// - 이 코스에서의 기록은 코스 화면에서 들어왔을 때만 받고, 그 러너의 기록이 없으면(비공개 · 기간 기록 없음 · 삭제) 섹션을 숨긴다.
/// - 탈퇴했거나 없는 러너는 열지 않는다. 당겨서 새로고침하면 모두 다시 받고, 코스 목록은 끝 가까이에서 다음 쪽을 받는다.
class RunnerProfileScreen extends ConsumerWidget {
  const RunnerProfileScreen({super.key, required this.memberId, this.course});

  final String memberId;
  final RunnerProfileCourse? course;

  static const unavailableTitle = '볼 수 없는 러너예요';
  static const unavailableMessage = '탈퇴했거나 없는 러너예요.';
  static const failedTitle = '프로필을 불러오지 못했어요';
  static const coursesFailedMessage = '등록한 코스를 불러오지 못했어요.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileProvider = runnerProfileProvider(memberId);
    final profile = ref.watch(profileProvider);
    final runner = profile.value;
    if (runner == null) {
      return Scaffold(
        appBar: WdAppBar(title: '', onBack: () => context.pop()),
        body: Center(
          child: switch (profile.error) {
            null => const CircularProgressIndicator(color: WdColors.ink),
            ApiException(code: MemberApiClient.runnerNotFoundCode) =>
              const WdStateMessage(title: unavailableTitle, message: unavailableMessage, icon: WdIcons.ghostInfo),
            final error => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WdStateMessage(title: failedTitle, message: errorMessage(error), icon: WdIcons.ghostWarning),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24),
                    child: WdButton('다시 시도',
                        variant: WdButtonVariant.secondary, onPressed: () => ref.invalidate(profileProvider)),
                  ),
                ],
              ),
          },
        ),
      );
    }
    final course = this.course;
    final recordProvider =
        course == null ? null : runnerRecordProvider((courseId: course.courseId, memberId: memberId, period: course.period));
    final record = recordProvider == null ? null : ref.watch(recordProvider).value;
    final coursesProvider = runnerCoursesProvider(memberId);
    final courses = ref.watch(coursesProvider);

    Future<void> refresh() {
      ref
        ..invalidate(runnerDistanceProvider(memberId))
        ..invalidate(runnerCourseCountProvider(memberId))
        ..invalidate(coursesProvider);
      if (recordProvider != null) ref.invalidate(recordProvider);
      return ref.refresh(profileProvider.future);
    }

    return Scaffold(
      appBar: WdAppBar(title: runner.nickname, onBack: () => context.pop()),
      body: RankingScrollView(
        onRefresh: refresh,
        onEnd: () => ref.read(coursesProvider.notifier).loadMore(),
        children: [
          _Header(runner),
          _Stats(memberId),
          if (course != null && record != null) ...[
            const WdSectionHeading('이 코스에서의 기록'),
            _RecordCard(
              course: course,
              record: record,
              nickname: runner.nickname,
              onGhost: () => runPublicGhost(
                context,
                ref,
                CourseSelection(course.courseId, course.courseName),
                GhostCandidate(
                  runRecordId: record.runRecordId,
                  memberId: memberId,
                  rank: record.rank,
                  courseElapsedSeconds: record.courseElapsedSeconds,
                ),
                course.period,
              ),
            ),
          ],
          ...switch (courses) {
            // 등록한 코스가 없으면 섹션을 두지 않는다(위 칸이 `0개`다)
            AsyncValue(:final value?) when value.courses.isEmpty => const [],
            AsyncValue(:final value?) => [
                const WdSectionHeading('등록한 코스'),
                _CourseList(value.courses),
                if (courses.hasError)
                  CourseRefreshFailed(coursesFailedMessage, onRetry: () => ref.invalidate(coursesProvider)),
              ],
            AsyncValue(hasError: true) => [
                const WdSectionHeading('등록한 코스'),
                CourseRefreshFailed(coursesFailedMessage, onRetry: () => ref.invalidate(coursesProvider)),
              ],
            _ => const [],
          },
        ],
      ),
    );
  }
}

/// 사진 · 닉네임 · `지역 · 러닝 경력`(MY와 같은 `러닝 1년+`).
class _Header extends StatelessWidget {
  const _Header(this.runner);

  final RunnerProfile runner;

  @override
  Widget build(BuildContext context) {
    final meta = [
      ?runner.region?.name,
      if (runner.runningExperience case final experience?) '러닝 ${experience.label}',
    ].join(' · ');
    return Row(
      spacing: WdSpace.s14,
      children: [
        WdAvatar(size: 64, image: runner.profileImageUrl == null ? null : NetworkImage(runner.profileImageUrl!)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WdSpace.s4,
            children: [
              Text(
                runner.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WdText.raw(20, FontWeight.w700, 25).copyWith(color: WdColors.ink),
              ),
              if (meta.isNotEmpty) Text(meta, style: WdText.body13.copyWith(color: WdColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 총 거리 · 러닝 · 등록 코스. 받기 전 · 실패 · 내 정보 비공개면 `—`다.
class _Stats extends ConsumerWidget {
  const _Stats(this.memberId);

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distance = ref.watch(runnerDistanceProvider(memberId)).value;
    final courseCount = ref.watch(runnerCourseCountProvider(memberId)).value;
    const none = CourseRankingStats.noValue;
    return WdStatSummary([
      ('총 거리', switch (distance?.totalDistanceMeters) { final meters? => statKm(meters), null => none }),
      ('러닝', switch (distance?.runCount) { final count? => '${formatCount(count)}회', null => none }),
      ('등록 코스', courseCount == null ? none : '${formatCount(courseCount)}개'),
    ]);
  }
}

/// 이 코스에서의 기록: 코스 이름 · 순위, 총 소요시간 · 페이스, 내 최고 기록과의 차이, `이 기록과 대결하기`.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.course, required this.record, required this.nickname, required this.onGhost});

  final RunnerProfileCourse course;
  final RunnerCourseRecord record;
  final String nickname;
  final VoidCallback onGhost;

  @override
  Widget build(BuildContext context) => WdSurface(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 9,
          children: [
            Row(
              spacing: WdSpace.s12,
              children: [
                WdRouteThumbnail(width: 52, height: 52, child: CourseRouteThumbnail(course.route)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(
                        '${course.courseName} · ${record.rank}위',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.raw(12, FontWeight.w700, 18).copyWith(color: WdColors.ink),
                      ),
                      Text(
                        '${formatCourseTime(record.courseElapsedSeconds)} · ${formatCoursePace(record.paceSecondsPerKm)}',
                        style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (record.myCourseElapsedSeconds case final mine?)
              _RecordGap(nickname: nickname, runner: record.courseElapsedSeconds, mine: mine),
            WdButton('이 기록과 대결하기', onPressed: onGhost),
          ],
        ),
      );
}

/// 내 최고 기록과의 차이. 내가 느리면 빨강 `n 느려요`, 빠르면 초록 `n 빨라요`, 같으면 `기록과 같아요`.
/// 내 기록이 없으면 그리지 않는다(2026-11-02 사용자 결정).
class _RecordGap extends StatelessWidget {
  const _RecordGap({required this.nickname, required this.runner, required this.mine});

  final String nickname;
  final int runner;
  final int mine;

  @override
  Widget build(BuildContext context) {
    final slower = mine - runner;
    final (lead, gap, color, background) = switch (slower) {
      > 0 => ('$nickname보다 ', '${formatRecordGap(slower)} 느려요', WdColors.negative,
          WdColors.negative.withValues(alpha: 0.1)),
      < 0 => ('$nickname보다 ', '${formatRecordGap(-slower)} 빨라요', WdColors.success, WdColors.successBg),
      _ => ('$nickname의 기록과 ', '같아요', WdColors.ink, WdColors.map),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12, vertical: WdSpace.s10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(WdRadius.r12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          Text.rich(
            TextSpan(text: lead, children: [
              TextSpan(text: gap, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            ]),
            style: WdText.raw(14, FontWeight.w500, 21).copyWith(color: WdColors.ink),
          ),
          Text.rich(
            TextSpan(text: '내 최고 기록은 ', children: [
              TextSpan(
                text: formatCourseTime(mine),
                style: const TextStyle(fontWeight: FontWeight.w500, color: WdColors.ink),
              ),
              const TextSpan(text: '예요'),
            ]),
            style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 기록 차이. 예: `3분 02초`, 1분이 안 되면 `42초`, 1시간이 넘으면 `1시간 02분 03초`.
String formatRecordGap(int seconds) {
  String two(int value) => value.toString().padLeft(2, '0');
  final (hours, minutes, rest) = (seconds ~/ 3600, seconds % 3600 ~/ 60, seconds % 60);
  if (hours > 0) return '$hours시간 ${two(minutes)}분 ${two(rest)}초';
  if (minutes > 0) return '$minutes분 ${two(rest)}초';
  return '$rest초';
}

/// 등록한 코스(최근 등록순). 줄을 누르면 코스 상세(B1)로 간다.
class _CourseList extends StatelessWidget {
  const _CourseList(this.courses);

  final List<RunnerCourse> courses;

  @override
  Widget build(BuildContext context) => WdSurface(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
        child: Column(
          children: [
            for (var i = 0; i < courses.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: WdColors.map),
              _CourseRow(courses[i]),
            ],
          ],
        ),
      );
}

/// Figma I3 코스 줄: 썸네일 40 · 이름 · `8.1km · ★ 4.4 · 주행 61회` · `›`. 리뷰가 없으면 평점은 빠진다.
class _CourseRow extends StatelessWidget {
  const _CourseRow(this.course);

  final RunnerCourse course;

  @override
  Widget build(BuildContext context) {
    final meta = [
      formatKm(course.distanceMeters),
      if (course.averageRating case final rating?) '★ ${rating.toStringAsFixed(1)}',
      '주행 ${formatCount(course.completionCount)}회',
    ].join(' · ');
    return InkWell(
      onTap: () => context.push(Routes.courseDetail(course.courseId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          spacing: 11,
          children: [
            WdRouteThumbnail(width: 40, height: 40, child: CourseRouteThumbnail(course.route)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.ink),
                  ),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: WdText.label12.copyWith(color: WdColors.muted)),
                ],
              ),
            ),
            Text('›', style: WdText.raw(16, FontWeight.w400, 16 * 1.4).copyWith(color: WdColors.muted)),
          ],
        ),
      ),
    );
  }
}
