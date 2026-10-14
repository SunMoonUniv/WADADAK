import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';
import 'run_lap_list.dart';
import '../../../core/map/map_view.dart';

String runDistance(RunSnapshot run) => run.hasLocation
    ? '${(run.distanceMeters / 1000).toStringAsFixed(2)} km'
    : '—';

/// Figma H4-1 / C4 / C4-2. 지도 · 기본 지표 · 전체 지표를 좌우로 넘긴다.
class FreeRunLiveView extends StatefulWidget {
  const FreeRunLiveView({
    super.key,
    required this.run,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });
  final RunSnapshot run;
  final VoidCallback? onPause, onResume, onStop;

  @override
  State<FreeRunLiveView> createState() => _FreeRunLiveViewState();
}

class _FreeRunLiveViewState extends State<FreeRunLiveView> {
  final _pages = PageController(initialPage: 1);
  int _page = 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _time() => WdElapsedTime(
    label: '이동 시간',
    time: formatRunTime(widget.run.movingTime),
    caption: '총 소요 ${formatRunTime(widget.run.elapsed)}',
  );

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final paused = run.state == RunState.paused;
    return Scaffold(
      backgroundColor: WdColors.runBackground,
      body: SafeArea(
        child: Column(
          children: [
            WdRunHeader(
              title: '자유 러닝',
              subtitle: '자유 러닝',
              badge: paused ? '일시정지' : '기록 중',
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
                      child: RunRouteView(run: run, dark: true),
                    ),
                    Row(
                      spacing: WdSpace.s8,
                      children: [
                        for (final (label, value) in [
                          ('이동 시간', formatRunTime(run.movingTime)),
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
                    Text(
                      '자유 러닝 · ${run.gpsStatus}',
                      style: WdText.ko13.copyWith(color: WdColors.runTextSub),
                    ),
                  ]),
                  _scroll([
                    _time(),
                    SizedBox(
                      height: 75,
                      child: Row(
                        spacing: WdSpace.s15,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (label, value) in [
                            ('거리', runDistance(run)),
                            ('평균 페이스', formatRunPace(run.paceSecondsPerKm)),
                            ('현재 페이스', formatRunPace(run.currentPaceDisplay)),
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
                    if (paused)
                      Text(
                        '일시정지 ${formatRunTime(run.elapsed - run.active)}',
                        style: WdText.ko13.copyWith(color: WdColors.runTextSub),
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
                        ('이동 시간', formatRunTime(run.movingTime)),
                      ],
                      [('심박수', '—'), ('최고 페이스', '—')],
                      [
                        (
                          '케이던스',
                          run.currentCadence == null
                              ? '—'
                              : '${run.currentCadence!.round()} spm',
                        ),
                        ('누적 고도', '—'),
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
  const RunRouteView({super.key, required this.run, this.dark = false});
  final RunSnapshot run;
  final bool dark;
  @override
  Widget build(BuildContext context) {
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
          for (var index = 0; index < run.segments.length; index++)
            MapLine(
              id: 'run-$index',
              style: MapLineStyle.track,
              points: run.segments[index]
                  .map((p) => GeoPoint(p.latitude, p.longitude))
                  .toList(),
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
