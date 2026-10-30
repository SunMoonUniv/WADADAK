import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/course_run.dart';
import '../domain/run_models.dart';
import 'course_register_card.dart';
import 'free_run_live_view.dart';
import 'ghost_result_screen.dart';
import 'run_pace_bars.dart';
import 'run_segment_analysis_screen.dart';

/// Figma D1 / D1-1 / D1-2. Measured values and the server verdict remain authoritative.
class FreeRunResultView extends StatelessWidget {
  const FreeRunResultView({
    super.key,
    required this.run,
    required this.onConfirm,
    this.onDelete,
    this.history = false,
    this.pendingCourse,
    this.onRetryGhost,
  });
  final RunSnapshot run;
  final VoidCallback onConfirm;
  final VoidCallback? onDelete;
  final bool history;
  final String? pendingCourse;
  final VoidCallback? onRetryGhost;

  @override
  Widget build(BuildContext context) {
    final start = run.startedAt?.toLocal();
    final startedLabel = start == null
        ? '—'
        : '${start.year}.${_two(start.month)}.${_two(start.day)} · ${_two(start.hour)}:${_two(start.minute)} 시작';
    final courseRun = run.course != null || pendingCourse != null;
    final ghost = run.ghost != null || run.ghostPending;
    final speed = run.hasLocation && run.movingTime.inMilliseconds > 0
        ? '${(run.distanceMeters * 3600 / run.movingTime.inMilliseconds).toStringAsFixed(1)} km/h'
        : '—';
    final cadence = run.averageCadence == null
        ? '—'
        : '${run.averageCadence!.round()} spm';
    final elevation = run.resultStats?.elevationGainM;
    final gain = elevation == null
        ? '—'
        : '${elevation > 0 ? '+' : ''}${elevation.round()} m';
    final best = run.resultStats?.bestLapNumber == null
        ? '—'
        : '${run.resultStats!.bestLapNumber}구간';
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(
        title: '러닝 결과',
        onBack: onConfirm,
        actions: [
          if (history)
            IconButton(
              tooltip: '기록 삭제',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              visualDensity: VisualDensity.standard,
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 22,
                color: WdColors.ink,
              ),
            ),
        ],
        action: WdAppBarAction.icon(
          WdIcons.share,
          semanticLabel: '러닝 결과 공유',
          onTap: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('결과 공유 기능은 준비 중이에요.'))),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 208),
              color: WdColors.lime,
              padding: const EdgeInsets.all(24),
              child: Column(
                spacing: 12,
                children: [
                  WdSurface(
                    color: WdColors.ink,
                    radius: WdRadius.full,
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '러닝 완료 · ${run.storageStatus}',
                      style: WdText.ko12Medium.copyWith(color: WdColors.lime),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      runDistance(run),
                      style: WdText.run56W800H74.copyWith(color: WdColors.ink),
                    ),
                  ),
                  Text(
                    run.course?.completed == false
                        ? '끝까지 달린 것만으로 충분해요.'
                        : '오늘도 한 걸음 더 달렸어요.',
                    style: WdText.ko22Bold.copyWith(color: WdColors.ink),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 20,
                children: [
                  WdStepRow(
                    title: courseRun
                        ? run.course?.courseName ?? pendingCourse ?? '코스 러닝'
                        : '자유 러닝',
                    description: switch ((run.course, pendingCourse)) {
                      (final course?, _) =>
                        '$startedLabel · ${course.completed ? '코스 완주' : '코스 미완주'}',
                      (null, final String _) => '$startedLabel · 판정 대기',
                      _ => startedLabel,
                    },
                  ),
                  if (courseRun)
                    _CourseBadge(course: run.course)
                  else
                    CourseRegisterCard(run: run),
                  WdSurface(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 24,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 8,
                            children: [
                              Text(
                                '총 소요 시간 (기록)',
                                style: WdText.ko12.copyWith(
                                  color: WdColors.muted,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  formatRunTime(run.elapsed),
                                  style: WdText.run34W700H39,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '달린 시간 ${formatRunTime(run.active)} · 일시정지 ${formatRunTime(run.elapsed - run.active)}',
                                  maxLines: 1,
                                  style: WdText.ko11.copyWith(
                                    color: WdColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: (courseRun || ghost)
                              ? _ghostSummary(context)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 8,
                                  children: [
                                    Text(
                                      '평균 페이스',
                                      style: WdText.ko12.copyWith(
                                        color: WdColors.muted,
                                      ),
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        formatRunPace(run.paceSecondsPerKm),
                                        style: WdText.run34W700H39,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                  WdStatSummary(
                    courseRun || ghost
                        ? [
                            ('평균 페이스', formatRunPace(run.paceSecondsPerKm)),
                            ('평균 속도', speed),
                            ('케이던스', cadence),
                          ]
                        : [
                            ('평균 속도', speed),
                            ('케이던스', cadence),
                            ('소모 칼로리', '—'),
                          ],
                  ),
                  WdStatSummary(
                    courseRun || ghost
                        ? [('상승 고도', gain), ('소모 칼로리', '—'), ('최고 구간', best)]
                        : [
                            ('상승 고도', gain),
                            ('최고 구간', best),
                            (
                              '최고 페이스',
                              formatRunPace(
                                run.resultStats?.bestPaceSecondsPerKm,
                              ),
                            ),
                          ],
                  ),
                  SizedBox(
                    height: 180,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RunRouteView(run: run),
                    ),
                  ),
                  RunPaceBars(run: run),
                  if (run.gapCount > 0)
                    WdInfoBanner(
                      'GPS 측정 공백 ${run.gapCount}곳의 확인하지 못한 거리는 포함하지 않았어요.',
                      tone: WdBannerTone.warning,
                    ),
                  if (run.endReason != null && run.endReason != 'USER')
                    const WdInfoBanner(
                      '측정이 중단되어 마지막 저장 지점까지 기록했어요.',
                      tone: WdBannerTone.warning,
                    ),
                  if (run.storageStatus == '기기 저장' ||
                      run.storageStatus.startsWith('기기 저장 ·'))
                    const WdInfoBanner(
                      '이 기기에 기록을 저장했어요. 서버 등록을 기다리고 있어요.',
                      tone: WdBannerTone.warning,
                    ),
                  if (run.storageStatus == '측정 거리 없음')
                    const WdInfoBanner(
                      '측정된 거리가 없어 개인 기록을 저장하지 않았어요.',
                      tone: WdBannerTone.warning,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WdBottomBar.dual(
        secondary: WdButton(
          '구간 상세 분석',
          variant: WdButtonVariant.secondary,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RunSegmentAnalysisScreen(run: run),
            ),
          ),
        ),
        primary: WdButton('확인', onPressed: onConfirm),
      ),
    );
  }

  Widget _ghostSummary(BuildContext context) {
    final result = run.ghost;
    final delta = result == null
        ? 0
        : (result['sourceElapsedSeconds'] as num).toInt() -
              (result['courseElapsedSeconds'] as num).toInt();
    final label = switch (result?['outcome']) {
      'WIN' => '${delta.abs()}초 앞섬',
      'LOSE' => '${delta.abs()}초 뒤처짐',
      'DRAW' => '동시에 도착',
      'INVALID' => '대결 무효',
      _ => run.ghostPending ? '서버 판정 대기' : '대결 없음',
    };
    return InkWell(
      onTap: result == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => GhostResultScreen(run: run),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text('고스트 대결', style: WdText.ko12.copyWith(color: WdColors.muted)),
          Text(
            label,
            style: WdText.ko22Bold.copyWith(
              color: result?['outcome'] == 'WIN'
                  ? WdColors.green
                  : WdColors.muted,
            ),
          ),
          if (result != null)
            Text(
              '대결 결과 보기 ›',
              style: WdText.ko12.copyWith(color: WdColors.green),
            )
          else if (run.ghostPending && onRetryGhost != null)
            TextButton(
              onPressed: onRetryGhost,
              child: const Text('판정 다시 확인', style: WdText.ko12),
            ),
        ],
      ),
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _CourseBadge extends StatelessWidget {
  const _CourseBadge({required this.course});
  final RunCourseResult? course;

  @override
  Widget build(BuildContext context) {
    final c = course;
    final (bg, fg, icon, title, detail) = switch (c) {
      null => (
        WdColors.infoBg,
        WdColors.info,
        WdIcons.ghostInfo,
        '코스 완주 판정 대기',
        '기록을 올린 뒤 서버가 완주를 판정해요.',
      ),
      RunCourseResult(completed: true) => (
        WdColors.limeSoft,
        WdColors.green,
        WdIcons.ghostSuccess,
        '코스 완주 인정',
        [
          ?c.courseName,
          if (c.courseDistanceMeters > 0)
            '${(c.courseDistanceMeters / 1000).toStringAsFixed(1)} km 완주',
        ].join(' · '),
      ),
      _ => (
        WdColors.warningBg,
        WdColors.warning,
        WdIcons.ghostWarning,
        '코스 완주 미인정',
        '${c.shortfall}\n코스 ${(c.recognizedDistanceMeters / 1000).toStringAsFixed(1)} km(${c.progressPercent.floor()}%)까지 인정됐고 개인 기록으로 저장됐어요.',
      ),
    };
    return WdSurface(
      color: bg,
      radius: WdRadius.r12,
      padding: const EdgeInsets.symmetric(
        horizontal: WdSpace.s14,
        vertical: WdSpace.s12,
      ),
      child: Row(
        spacing: WdSpace.s10,
        children: [
          WdIcon(icon, size: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s2,
              children: [
                Text(title, style: WdText.run13W700H16.copyWith(color: fg)),
                Text(
                  detail,
                  style: WdText.ko12.copyWith(color: WdColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
