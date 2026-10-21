import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/map/map_view.dart';
import '../domain/course_run.dart';
import 'free_run_screen.dart';

/// 코스 러닝 측정 전(RCR-01). 러닝 화면 지도(Figma C4-1·C4-3 모양)에 코스 경로·출발점·현재 위치와
/// 현재 위치~출발점 점선을 보이고, 출발점 반경 안에서만 시작 버튼을 켠다. 출발점까지 이동은 기록하지 않는다.
class CourseStartView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final near = start.nearStart;
    final position = start.position;
    return Scaffold(
      backgroundColor: WdColors.runBackground,
      body: SafeArea(
        child: Column(
          children: [
            WdRunHeader(title: start.course.name, subtitle: '코스 러닝', badge: '준비'),
            Expanded(
              child: MapView(
                initialCenter: position,
                initialZoom: 16,
                dark: true,
                myLocationSource: MyLocationSource.app,
                myLocation: position,
                lines: [
                  MapLine(id: 'course', points: start.snapshot.route, style: MapLineStyle.runCourse),
                  MapLine(id: 'to-start', points: [position, start.start], style: MapLineStyle.guide),
                ],
                markers: [
                  MapMarker(
                    id: 'course-start',
                    position: start.start,
                    child: const WdCourseStartDot(),
                    imageKey: 'course-start',
                  ),
                ],
                onCreated: (map) async {
                  await map.fitPoints([...start.snapshot.route, position]);
                  map.showMyLocation(follow: false);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s16, WdSpace.s24, WdSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s12,
                children: [
                  Text(
                    near ? '출발점이에요' : '출발점까지 ${CourseLive.formatMeters(start.distanceToStartM)}',
                    style: WdText.ko22Bold.copyWith(color: WdColors.white),
                  ),
                  Text(
                    near
                        ? '1초 길게 눌러 시작하세요. 출발점까지 온 거리는 기록하지 않아요.'
                        : '출발점 ${CourseStart.radiusM.round()} m 안에 들어오면 시작할 수 있어요.',
                    style: WdText.ko13.copyWith(color: WdColors.runTextSub),
                  ),
                  if (error != null) WdInfoBanner(error!, tone: WdBannerTone.warning),
                  RunHoldToStart(label: '코스 러닝 시작', onStart: near ? onStart : null),
                  WdButton('취소', onPressed: onCancel, variant: WdButtonVariant.secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
