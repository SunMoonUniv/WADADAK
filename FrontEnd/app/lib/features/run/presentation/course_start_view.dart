import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/map/map_view.dart';
import '../domain/course_run.dart';
import 'free_run_screen.dart';

/// C11 출발점 이동 · C12 출발점 도착(Figma 2323:6372 · 2328:6217, RCR-01). 지도에 코스 경로·출발점·현재 위치와
/// 현재 위치~출발점 점선을 보이고, 출발점 반경 안에서만 코스 러닝 시작을 켠다. 출발점까지 이동은 기록하지 않는다.
class CourseStartView extends StatefulWidget {
  const CourseStartView({
    super.key,
    required this.start,
    required this.onStart,
    required this.onCancel,
    this.error,
  });

  final CourseStart start;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final String? error;

  @override
  State<CourseStartView> createState() => _CourseStartViewState();
}

class _CourseStartViewState extends State<CourseStartView> {
  MapController? _map;

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final near = start.nearStart;
    final position = start.position;
    final meters = start.distanceToStartM;
    final (distance, unit) =
        meters < 1000 ? ('${meters.round()}', 'm') : ((meters / 1000).toStringAsFixed(1), 'km');
    return Scaffold(
      backgroundColor: WdColors.runBackground,
      body: SafeArea(
        child: Column(
          children: [
            WdRunHeader(title: start.course.name, subtitle: '코스 러닝', badge: near ? '시작 가능' : '준비'),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MapView(
                      initialCenter: position,
                      initialZoom: 16,
                      dark: true,
                      myLocationSource: MyLocationSource.app,
                      myLocation: position,
                      padding: const EdgeInsets.only(bottom: 56),
                      lines: [
                        MapLine(id: 'course', points: start.snapshot.route),
                        MapLine(id: 'to-start', points: [position, start.start], style: MapLineStyle.guide),
                      ],
                      markers: [
                        MapMarker(
                          id: 'course-start',
                          position: start.start,
                          child: const WdCourseStartDot(),
                          imageKey: 'course-start',
                        ),
                        MapMarker(
                          id: 'course-start-label',
                          position: start.start,
                          anchor: const Offset(0.5, 1.7), // 출발점 표지 위
                          child: const _Label('출발점', color: WdColors.lime, textColor: WdColors.ink),
                          imageKey: 'label:start',
                        ),
                        MapMarker(
                          id: 'my-location-label',
                          position: position,
                          anchor: const Offset(0.5, -0.8), // 현재 위치 점 아래
                          child: const _Label('현재 위치', color: WdColors.runSurface, textColor: WdColors.white),
                          imageKey: 'label:me',
                        ),
                      ],
                      onCreated: (map) async {
                        _map = map;
                        await map.fitPoints([...start.snapshot.route, position]);
                        map.showMyLocation(follow: false);
                      },
                    ),
                  ),
                  const Positioned(left: WdSpace.s24, bottom: WdSpace.s16, child: _Legend()),
                  Positioned(
                    right: WdSpace.s24,
                    bottom: WdSpace.s12,
                    child: WdMapLocateButton(onPressed: () => _map?.fitPoints([position, start.start])),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s24, WdSpace.s24, WdSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s12,
                children: [
                  Text(
                    near ? '출발점에 도착했어요' : '출발점으로 이동해 주세요',
                    style: WdText.ko22Bold.copyWith(color: WdColors.white),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: WdSpace.s8,
                    children: [
                      Text(distance, style: WdText.run56W800H74.copyWith(color: near ? WdColors.lime : WdColors.white)),
                      Text(unit, style: WdText.ko13.copyWith(color: WdColors.runTextSub)),
                    ],
                  ),
                  Text(
                    near
                        ? '출발점 ${CourseStart.radiusM.round()} m 안에 도착했어요.\n준비됐다면 코스 러닝을 시작해 주세요.'
                        : '출발점 ${CourseStart.radiusM.round()} m 안에 들어오면\n코스 러닝을 시작할 수 있어요.',
                    style: WdText.ko13.copyWith(color: WdColors.runTextSub),
                  ),
                  if (widget.error != null) WdInfoBanner(widget.error!, tone: WdBannerTone.warning),
                  const SizedBox(height: WdSpace.s4),
                  // 1초 누르기 → 3초 카운트다운(RUN-04)
                  RunHoldToStart(label: '코스 러닝 시작', onStart: near ? widget.onStart : null),
                  WdButton('취소', onPressed: widget.onCancel, variant: WdButtonVariant.secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 지도 위 이름표(출발점 · 현재 위치)
class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color, required this.textColor});
  final String text;
  final Color color, textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s10, vertical: WdSpace.s6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(WdRadius.r8)),
    child: Text(text, style: WdText.ko12Medium.copyWith(color: textColor)),
  );
}

/// Map legend: ● 출발점 ● 현재 위치
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color dot, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: WdSpace.s6,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        Text(label, style: WdText.ko12.copyWith(color: WdColors.white)),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12, vertical: WdSpace.s6),
      decoration: BoxDecoration(color: WdColors.ink, borderRadius: BorderRadius.circular(WdRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s14,
        children: [item(WdColors.lime, '출발점'), item(WdColors.info, '현재 위치')],
      ),
    );
  }
}
