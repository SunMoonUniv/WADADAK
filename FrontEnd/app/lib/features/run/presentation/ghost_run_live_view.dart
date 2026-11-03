import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/course_run.dart';
import '../domain/ghost_live_comparison.dart';
import '../domain/run_models.dart';
import 'free_run_live_view.dart';
import 'run_metric.dart';

/// Figma C4 1453:4671, C4-1 1453:4799, C4-2 1453:4744.
class GhostRunLiveView extends StatefulWidget {
  const GhostRunLiveView({
    super.key,
    required this.run,
    required this.opponent,
    required this.comparison,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.course,
    this.courseNotice,
  });
  final RunSnapshot run;
  final String opponent;
  final GhostLiveComparison comparison;
  final CourseLive? course;
  final String? courseNotice;
  final VoidCallback? onPause, onResume, onStop;

  @override
  State<GhostRunLiveView> createState() => _GhostRunLiveViewState();
}

class _GhostRunLiveViewState extends State<GhostRunLiveView> {
  final _pages = PageController(initialPage: 1);
  int _page = 1;
  final _metrics = [
    RunMetric.active,
    RunMetric.distance,
    RunMetric.averagePace,
    RunMetric.heartRate,
  ];

  @override
  void didUpdateWidget(GhostRunLiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.sessionId != widget.run.sessionId) {
      _metrics.setAll(0, [
        RunMetric.active,
        RunMetric.distance,
        RunMetric.averagePace,
        RunMetric.heartRate,
      ]);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _editable(int slot, Widget child) => Semantics(
    key: ValueKey('run-metric-$slot'),
    button: true,
    label: '${_metrics[slot].label}, ${_metrics[slot].value(widget.run)}',
    hint: '터치하면 ${_metrics[slot].next.label} 표시',
    child: InkWell(
      onTap: () => setState(() => _metrics[slot] = _metrics[slot].next),
      child: child,
    ),
  );

  String _value(RunMetric metric) => switch (metric) {
    RunMetric.averagePace => formatRunPace(widget.run.paceSecondsPerKm),
    RunMetric.currentPace => formatRunPace(widget.run.currentPaceDisplay),
    _ => metric.value(widget.run),
  };

  Widget _time({bool editable = false}) {
    final metric = editable ? _metrics[0] : RunMetric.active;
    final time = WdElapsedTime(
      time: _value(metric),
      label: metric == RunMetric.active ? '달린 시간' : metric.label,
      caption: '총 소요 ${formatRunTime(widget.run.elapsed)}',
    );
    return editable ? _editable(0, time) : time;
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run, course = widget.course;
    final paused = run.state == RunState.paused;
    return Scaffold(
      backgroundColor: WdColors.runBackground,
      body: SafeArea(
        child: Column(
          children: [
            WdRunHeader(
              title: course?.name ?? '고스트 러닝',
              subtitle: '고스트 대결 · ${widget.opponent}',
              badge: paused
                  ? '일시정지'
                  : course?.offRoute == true
                  ? '경로 이탈'
                  : '기록 중',
            ),
            // Routine GPS status belongs on the map. Interruptions remain visible.
            for (final notice in [
              run.notice,
              widget.courseNotice,
              run.voiceNotice,
            ])
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WdSpace.s24,
                    vertical: WdSpace.s4,
                  ),
                  child: Text(
                    notice,
                    style: WdText.ko12.copyWith(color: WdColors.lime),
                  ),
                ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() => _page = page),
                children: [_map(), _basic(), _details()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WdSpace.s24,
                WdSpace.s4,
                WdSpace.s24,
                WdSpace.s12,
              ),
              child: Column(
                spacing: WdSpace.s12,
                children: [
                  WdPageIndicator(count: 3, index: _page),
                  if (paused)
                    WdRunPausedButtons(
                      onStop: widget.onStop,
                      onResume: widget.onResume,
                    )
                  else
                    WdRunPauseButton(onPressed: widget.onPause),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scroll(List<Widget> children, {double spacing = WdSpace.s20}) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WdSpace.s24,
          WdSpace.s16,
          WdSpace.s24,
          WdSpace.s24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: spacing,
          children: children,
        ),
      );

  Widget _basic() => _scroll([
    _time(editable: true),
    SizedBox(
      height: 75,
      child: Row(
        spacing: WdSpace.s15,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var slot = 1; slot <= 3; slot++)
            Expanded(
              child: _editable(
                slot,
                SizedBox(
                  height: 75,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: WdMetric(
                        label: _metrics[slot].label,
                        value: _value(_metrics[slot]),
                        dark: true,
                        labelStyle: WdText.run13W500H17,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    WdGhostLeadCard(
      title: widget.comparison.title,
      value: widget.comparison.value,
      caption: widget.comparison.caption,
      message: widget.comparison.message,
    ),
    _laps(),
    if (widget.course case final course?)
      WdCourseProgress(
        progress: course.progress,
        ghostProgress: widget.comparison.ghostProgress,
        leading: course.nextTarget,
        trailing: '총 ${(course.lengthM / 1000).toStringAsFixed(1)} km',
      ),
  ]);

  Widget _laps() {
    final all = widget.run.laps;
    final recent = all.length > 3 ? all.sublist(all.length - 3) : all;
    // Recorded laps use travelled distance/moving time. Replay uses course
    // position/elapsed time, so it cannot truthfully supply a per-lap pace delta.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 140),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = (constraints.maxWidth / 354).clamp(0.75, 1.0);
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: constraints.maxWidth / scale,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WdLapRecords(
                    laps: [
                      for (final lap in recent)
                        WdLap(
                          label: lap.complete
                              ? '${lap.number} km'
                              : '현재 ${(lap.distanceM / 1000).toStringAsFixed(2)} km',
                          pace: formatRunPace(lap.paceSecondsPerKm),
                          delta: '—',
                          current: !lap.complete,
                        ),
                    ],
                  ),
                  if (recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: WdSpace.s12),
                      child: Text(
                        '첫 구간을 측정하고 있어요.',
                        style: WdText.ko13.copyWith(color: WdColors.runTextSub),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _map() => SingleChildScrollView(
    child: Column(
      spacing: WdSpace.s20,
      children: [
        SizedBox(
          height: 434,
          child: Stack(
            children: [
              Positioned.fill(
                child: RunRouteView(
                  run: widget.run,
                  dark: true,
                  showDistanceMarkers: true,
                  course: widget.course,
                  ghostPosition: widget.comparison.position,
                  square: true,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: WdSurface(
                  color: WdColors.lime,
                  padding: const EdgeInsets.symmetric(
                    horizontal: WdSpace.s16,
                    vertical: WdSpace.s12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: WdSpace.s4,
                    children: [
                      Text(
                        widget.course?.nextTarget ?? '고스트 경로를 따라 달리는 중',
                        style: WdText.ko16Bold,
                      ),
                      Text(
                        '${widget.comparison.title} · ${widget.comparison.value}',
                        style: WdText.ko13.copyWith(color: WdColors.green),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 8,
                child: WdSurface(
                  color: WdColors.runBackground.withValues(alpha: 0.7),
                  radius: WdRadius.full,
                  padding: const EdgeInsets.symmetric(
                    horizontal: WdSpace.s10,
                    vertical: WdSpace.s6,
                  ),
                  child: _legend(dark: true),
                ),
              ),
              ...courseDeviationBand(widget.course), // 위 고스트 카드를 덮는다
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24),
          child: Column(
            spacing: WdSpace.s20,
            children: [
              SizedBox(
                height: 75,
                child: Row(
                  spacing: WdSpace.s8,
                  children: [
                    for (final metric in [
                      RunMetric.active,
                      RunMetric.distance,
                      RunMetric.averagePace,
                      RunMetric.cadence,
                    ])
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: WdMetric(
                              label: metric == RunMetric.active
                                  ? '달린 시간'
                                  : metric.label,
                              value: _value(metric),
                              dark: true,
                              labelStyle: WdText.run13W500H17,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.course case final course?)
                _remaining(
                  leading:
                      '남은 거리 ${CourseLive.formatMeters(course.remainingM)}',
                  trailing: '코스 진행 ${(course.progress * 100).round()}%',
                  progress: course.progress,
                  dark: true,
                ),
              Text(
                'GPS · ${widget.run.gpsStatus}',
                style: WdText.ko12.copyWith(color: WdColors.runTextSub),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _legend({bool dark = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: WdSpace.s4,
    children: [
      for (final (label, color) in [
        ('나', WdColors.lime),
        ('고스트', const Color(0xFF9851D1)),
      ]) ...[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(
          label,
          style: WdText.ko12.copyWith(
            color: dark ? WdColors.white : WdColors.green,
          ),
        ),
      ],
    ],
  );

  Widget _gapTrack(CourseLive course) => Column(
    spacing: WdSpace.s8,
    children: [
      SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth - 14;
            final runnerX = width * course.progress.clamp(0, 1);
            final ghost = widget.comparison.ghostProgress;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 4,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WdColors.nearBlack.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(WdRadius.full),
                    ),
                  ),
                ),
                if (ghost != null) ...[
                  Positioned(
                    left:
                        (runnerX < width * ghost.clamp(0, 1)
                            ? runnerX
                            : width * ghost.clamp(0, 1)) +
                        7,
                    top: 4,
                    width: (runnerX - width * ghost.clamp(0, 1)).abs(),
                    height: 6,
                    child: const ColoredBox(color: WdColors.nearBlack),
                  ),
                  Positioned(
                    left: width * ghost.clamp(0, 1),
                    top: 0,
                    child: SvgPicture.asset(
                      'assets/run/ghost_gap_opponent.svg',
                    ),
                  ),
                ],
                Positioned(
                  left: runnerX,
                  top: 0,
                  child: SvgPicture.asset('assets/run/ghost_gap_runner.svg'),
                ),
              ],
            );
          },
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WdSpace.s8,
        children: [
          Expanded(
            child: Text(
              '● 나   ○ 고스트',
              style: WdText.ko13.copyWith(color: WdColors.green),
            ),
          ),
          Text(widget.comparison.value, style: WdText.ko13Bold),
        ],
      ),
    ],
  );

  Widget _remaining({
    required String leading,
    required String trailing,
    required double progress,
    bool dark = false,
  }) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: constraints.maxWidth < 322 ? 322 : constraints.maxWidth,
        child: WdRemainingDistance(
          leading: leading,
          trailing: trailing,
          progress: progress,
          dark: dark,
        ),
      ),
    ),
  );

  Widget _details() => _scroll([
    _time(),
    for (final row in [
      [
        ('거리', runDistance(widget.run)),
        ('평균 페이스', formatRunPace(widget.run.paceSecondsPerKm)),
      ],
      [('심박수', '—'), ('최고 페이스', '—')],
      [
        ('케이던스', _value(RunMetric.cadence)),
        (
          '누적 고도',
          widget.run.liveElevationGainM == null
              ? '—'
              : '+${widget.run.liveElevationGainM!.round()} m',
        ),
      ],
    ])
      Row(
        spacing: WdSpace.s12,
        children: [
          for (final (label, value) in row)
            Expanded(
              child: WdRunMetricTile(label: label, value: value),
            ),
        ],
      ),
    WdSurface(
      color: WdColors.lime,
      padding: const EdgeInsets.all(WdSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s10,
        children: [
          Text(
            '${widget.comparison.title} · ${widget.comparison.value}',
            style: WdText.ko14Bold,
          ),
          Text(
            '${widget.comparison.caption} · ${widget.opponent}',
            style: WdText.ko13.copyWith(color: WdColors.green),
          ),
          if (widget.course case final course?) ...[
            _gapTrack(course),
            _remaining(
              leading: '남은 거리 ${CourseLive.formatMeters(course.remainingM)}',
              trailing: course.nextTarget,
              progress: course.progress,
            ),
          ],
        ],
      ),
    ),
  ], spacing: WdSpace.s12);
}
