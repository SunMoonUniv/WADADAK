import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/course_run.dart';
import '../domain/run_models.dart';
import '../domain/run_distance_marker.dart';
import 'run_lap_list.dart';
import 'run_metric.dart';
import '../../../core/map/map_view.dart';

String runDistance(RunSnapshot run) => run.hasLocation
    ? '${(run.distanceMeters / 1000).toStringAsFixed(2)} km'
    : '—';

/// Figma H4-1 / C4 / C4-2. 지도 · 기본 지표 · 전체 지표를 좌우로 넘긴다.
/// 코스 러닝이면 [course]로 코스 경로·km 표지·진행도·남은 거리를 더한다(Figma C4 코스·C4-1).
class FreeRunLiveView extends StatefulWidget {
  const FreeRunLiveView({
    super.key,
    required this.run,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.course,
    this.courseNotice,
  });
  final RunSnapshot run;
  final VoidCallback? onPause, onResume, onStop;
  final CourseLive? course;

  /// 코스 구간이 끝나 자유 러닝으로 바뀐 뒤 안내(경로 끝 도착·코스만 종료)
  final String? courseNotice;

  @override
  State<FreeRunLiveView> createState() => _FreeRunLiveViewState();
}

class _FreeRunLiveViewState extends State<FreeRunLiveView> {
  final _pages = PageController(initialPage: 1);
  int _page = 1;
  final List<RunMetric> _metrics = [
    RunMetric.active,
    RunMetric.distance,
    RunMetric.averagePace,
    RunMetric.currentPace,
  ];

  @override
  void didUpdateWidget(covariant FreeRunLiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.sessionId != widget.run.sessionId) {
      _metrics.setAll(0, [
        RunMetric.active,
        RunMetric.distance,
        RunMetric.averagePace,
        RunMetric.currentPace,
      ]);
    }
  }

  void _cycle(int slot) => setState(() => _metrics[slot] = _metrics[slot].next);

  Widget _metricButton(int slot, Widget child) => Semantics(
    key: ValueKey('run-metric-$slot'),
    button: true,
    label: '${_metrics[slot].label}, ${_metrics[slot].value(widget.run)}',
    hint: '터치하면 ${_metrics[slot].next.label} 표시',
    onTap: () => _cycle(slot),
    child: ExcludeSemantics(
      child: InkWell(onTap: () => _cycle(slot), child: child),
    ),
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _time({bool editable = false}) {
    final metric = editable ? _metrics.first : RunMetric.active;
    final content = WdElapsedTime(
      label: metric.label,
      time: metric.value(widget.run),
    );
    return Column(
      children: [
        editable ? _metricButton(0, content) : content,
        Text(
          '총 소요 시간 ${formatRunTime(widget.run.elapsed)} (정지 시간 포함)',
          style: WdText.raw(
            13,
            FontWeight.w400,
            17,
          ).copyWith(color: WdColors.runTextSub),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final course = widget.course;
    final paused = run.state == RunState.paused;
    return Scaffold(
      backgroundColor: WdColors.runBackground,
      body: SafeArea(
        child: Column(
          children: [
            WdRunHeader(
              title: course?.name ?? '자유 러닝',
              subtitle: course == null ? '자유 러닝' : '코스 러닝',
              badge: paused
                  ? '일시정지'
                  : course?.offRoute == true
                  ? '경로 이탈'
                  : '기록 중',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WdSpace.s24,
                vertical: WdSpace.s4,
              ),
              child: Text(
                run.notice ?? 'GPS · ${run.gpsStatus}',
                style: WdText.ko12.copyWith(color: WdColors.runTextSub),
              ),
            ),
            if (widget.courseNotice != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WdSpace.s24,
                  vertical: WdSpace.s4,
                ),
                child: Text(
                  widget.courseNotice!,
                  style: WdText.ko12Medium.copyWith(color: WdColors.lime),
                ),
              ),
            if (run.voiceNotice != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WdSpace.s24,
                  vertical: WdSpace.s4,
                ),
                child: Text(
                  run.voiceNotice!,
                  style: WdText.ko12.copyWith(color: WdColors.runTextSub),
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _scroll([
                    SizedBox(
                      height: 434,
                      child: RunRouteView(
                        run: run,
                        dark: true,
                        showDistanceMarkers: true,
                        course: course,
                      ),
                    ),
                    Row(
                      spacing: WdSpace.s8,
                      children: [
                        for (final (label, value) in [
                          ('시간', formatRunTime(run.active)),
                          ('거리', runDistance(run)),
                          ('평균 페이스', formatRunPace(run.paceSecondsPerKm)),
                          (
                            '케이던스',
                            run.currentCadence == null
                                ? '—'
                                : '${run.currentCadence!.round()} spm',
                          ),
                        ])
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topLeft,
                              child: WdMetric(
                                label: label,
                                value: value,
                                dark: true,
                                labelStyle: WdText.run13W500H17,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (course != null)
                      WdRemainingDistance(
                        leading: '남은 거리 ${CourseLive.formatMeters(course.remainingM)}',
                        trailing: '코스 진행 ${(course.progress * 100).round()}%',
                        progress: course.progress,
                        dark: true,
                      ),
                    Text(
                      '${course == null ? '자유 러닝' : course.deviation != null ? '코스에서 ${CourseLive.formatMeters(course.deviation!.d)} 벗어났어요' : course.nextTarget} · ${run.gpsStatus}',
                      style: WdText.ko13.copyWith(color: WdColors.runTextSub),
                    ),
                  ]),
                  _scroll([
                    _time(editable: true),
                    SizedBox(
                      height: 75,
                      child: Row(
                        spacing: WdSpace.s15,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var slot = 1; slot <= 3; slot++)
                            Expanded(
                              child: _metricButton(
                                slot,
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.topLeft,
                                    child: WdMetric(
                                      label: _metrics[slot].label,
                                      value: _metrics[slot].value(run),
                                      dark: true,
                                      labelStyle: WdText.run13W500H17,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '지표를 터치하면 다른 정보를 볼 수 있어요.',
                      style: WdText.ko12.copyWith(color: WdColors.runTextSub),
                    ),
                    WdGhostLeadCard(
                      title: paused ? '잠시 쉬어가는 중이에요' : '나만의 리듬으로 달리는 중',
                      value: '—',
                      caption: '소모 칼로리',
                      message: paused
                          ? '이동하면 자동으로 다시 달려요.'
                          : '편안하게 나만의 속도로 이어가세요.',
                    ),
                    RunLapList(run: run, dark: true, recentOnly: true),
                    if (course != null)
                      WdCourseProgress(
                        progress: course.progress,
                        leading: course.nextTarget,
                        trailing: '총 ${(course.lengthM / 1000).toStringAsFixed(1)} km',
                      ),
                  ]),
                  _scroll([
                    _time(),
                    for (final row in [
                      [
                        ('거리', runDistance(run)),
                        ('평균 페이스', formatRunPace(run.paceSecondsPerKm)),
                      ],
                      [
                        ('현재 페이스', formatRunPace(run.currentPaceDisplay)),
                        ('시간', formatRunTime(run.active)),
                      ],
                      [('심박수', '—'), ('최고 페이스', '—')],
                      [
                        (
                          '케이던스',
                          run.currentCadence == null
                              ? '—'
                              : '${run.currentCadence!.round()} spm',
                        ),
                        (
                          '누적 고도',
                          run.liveElevationGainM == null
                              ? '—'
                              : '${run.liveElevationGainM!.round()} m',
                        ),
                      ],
                    ])
                      Row(
                        spacing: WdSpace.s16,
                        children: [
                          for (final (label, value) in row)
                            Expanded(
                              child: WdRunMetricTile(
                                label: label,
                                value: value,
                              ),
                            ),
                        ],
                      ),
                    Text(
                      '케이던스 · ${run.cadenceStatus}',
                      style: WdText.ko12.copyWith(color: WdColors.runTextSub),
                    ),
                    WdSurface(
                      color: WdColors.runSurface,
                      height: 74,
                      padding: const EdgeInsets.all(WdSpace.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: WdSpace.s4,
                        children: [
                          Text(
                            '나만의 리듬으로 달려보세요',
                            style: WdText.ko14Bold.copyWith(
                              color: WdColors.white,
                            ),
                          ),
                          Text(
                            '연결하지 않은 센서는 —로 표시해요.',
                            style: WdText.run13W400H17.copyWith(
                              color: WdColors.runTextSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ],
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

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      WdSpace.s24,
      WdSpace.s16,
      WdSpace.s24,
      WdSpace.s24,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s20,
      children: children,
    ),
  );
}

/// 위치를 수집하기 전에는 시안의 예시 경로를 실제 기록처럼 보여주지 않는다.
class RunRouteView extends StatelessWidget {
  const RunRouteView({
    super.key,
    required this.run,
    this.dark = false,
    this.showDistanceMarkers = false,
    this.course,
  });
  final RunSnapshot run;
  final bool dark, showDistanceMarkers;

  /// 코스 러닝이면 코스 경로(주행선 아래)·코스 출발점·코스 km 표지를 그린다. km 표지는 주행 거리 대신 코스 기준이다
  final CourseLive? course;
  @override
  Widget build(BuildContext context) {
    final course = this.course;
    if (!run.hasLocation) return RunRouteEmpty(dark: dark);
    final location =
        run.inputs.reversed
            .where(
              (p) =>
                  p.kind == RunInputKind.gps &&
                  p.point != null &&
                  p.accuracyM != null &&
                  p.accuracyM! <= 30,
            )
            .firstOrNull
            ?.point ??
        run.segments.lastWhere((s) => s.isNotEmpty).last;
    final points = run.segments
        .expand((s) => s)
        .map((p) => GeoPoint(p.latitude, p.longitude))
        .toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(WdRadius.r12),
      child: MapView(
        initialCenter: GeoPoint(location.latitude, location.longitude),
        initialZoom: 16,
        dark: dark,
        myLocationSource: MyLocationSource.app,
        myLocation: GeoPoint(location.latitude, location.longitude),
        lines: [
          if (course != null)
            MapLine(id: 'course', points: course.route, style: MapLineStyle.runCourse),
          // C4-3: 벗어났으면 내 위치에서 가장 가까운 경로 지점까지 점선
          if (course?.deviation case final deviation?)
            MapLine(
              id: 'to-route',
              points: [GeoPoint(location.latitude, location.longitude), deviation.point],
              style: MapLineStyle.guide,
            ),
          for (var index = 0; index < run.segments.length; index++)
            MapLine(
              id: 'run-$index',
              style: MapLineStyle.track,
              points: run.segments[index]
                  .map((p) => GeoPoint(p.latitude, p.longitude))
                  .toList(),
            ),
        ],
        // Endpoints use the accepted route only, including server-only history.
        // No markers or lines are interpolated across GPS/pause gaps.
        markers: [
          if (course != null) ...[
            for (final (km, point) in course.tracker.route.kilometres())
              MapMarker(
                id: 'course-km-$km',
                position: point,
                imageKey: 'km:$km',
                child: WdKmMarker('$km km'),
              ),
            MapMarker(
              id: 'course-start',
              position: course.route.first,
              child: const WdCourseStartDot(),
              imageKey: 'course-start',
            ),
          ] else if (showDistanceMarkers)
            for (final marker in runDistanceMarkers(run))
              MapMarker(
                id: 'run-km-${marker.km}',
                position: GeoPoint(
                  marker.point.latitude,
                  marker.point.longitude,
                ),
                imageKey: 'km:${marker.km}',
                child: WdKmMarker('${marker.km} km'),
              ),
          if (points.isNotEmpty && course == null)
            MapMarker(
              id: 'run-start',
              position: points.first,
              anchor: const Offset(1, 1),
              imageKey: 'run-start',
              child: _endpoint('출발'),
            ),
          if (points.isNotEmpty && run.state == RunState.finished)
            MapMarker(
              id: 'run-finish',
              position: points.last,
              anchor: const Offset(0, 1),
              imageKey: 'run-finish',
              child: _endpoint('종료'),
            ),
        ],
        onCreated: (controller) async {
          if (dark) {
            controller.showMyLocation();
          } else if (points.length > 1) {
            await controller.fitPoints(points);
          }
        },
      ),
    );
  }

  Widget _endpoint(String label) => WdSurface(
    color: WdColors.ink,
    radius: WdRadius.full,
    padding: const EdgeInsets.symmetric(
      horizontal: WdSpace.s8,
      vertical: WdSpace.s4,
    ),
    child: Text(label, style: WdText.ko11.copyWith(color: WdColors.lime)),
  );
}

class RunRouteEmpty extends StatelessWidget {
  const RunRouteEmpty({super.key, this.dark = false});
  final bool dark;

  @override
  Widget build(BuildContext context) => WdSurface(
    color: dark ? WdColors.runSurface : WdColors.soft,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(WdSpace.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: WdSpace.s12,
          children: [
            WdIcon(
              WdIcons.locate,
              size: 24,
              color: dark ? WdColors.lime : WdColors.muted,
            ),
            Text(
              '아직 위치 기록이 없어요',
              style: WdText.ko14Bold.copyWith(
                color: dark ? WdColors.white : WdColors.ink,
              ),
            ),
            Text(
              'GPS 연결 후 달린 경로를 표시해요.',
              textAlign: TextAlign.center,
              style: WdText.ko12.copyWith(
                color: dark ? WdColors.runTextSub : WdColors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
