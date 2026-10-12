import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/course_api_client.dart';
import '../../../core/map/map_view.dart';
import '../course_format.dart';

/// B4 코스 정보 입력 & 등록(Figma 프레임 이름은 B5).
///
/// 지금은 서버가 만든 최종 경로와 1km 거리 표지만 보여 준다(B4-01). 입력점은 보이지 않는다.
/// 이름·난이도·태그 입력과 등록(B4-02~07)은 다음 PR에서 붙인다.
class CourseInfoScreen extends StatelessWidget {
  const CourseInfoScreen({super.key, required this.route});

  final GeneratedRoute route;

  @override
  Widget build(BuildContext context) => Scaffold(
        // 경로를 고치려면 B3로 돌아간다. B3에는 입력점이 그대로 있다.
        appBar: WdAppBar(title: '코스 정보 입력', onBack: () => context.pop()),
        body: Column(
          children: [
            Expanded(
              child: MapView(
                initialCenter: route.route.first,
                lines: [MapLine(id: 'route', points: route.route)],
                markers: [
                  for (final marker in route.distanceMarkers)
                    MapMarker(
                      id: 'km-${marker.km}',
                      position: marker.point,
                      child: WdKmMarker('${marker.km} km'),
                      imageKey: 'km:${marker.km}',
                    ),
                ],
                onCreated: (map) => map.fitPoints(route.route),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(WdSpace.s24),
                child: Column(
                  spacing: WdSpace.s16,
                  children: [
                    WdSummaryTiles([('총 거리', formatKm(route.distanceMeters))]),
                    Text('이름 · 난이도 · 태그 입력과 등록은 준비 중이에요',
                        style: WdText.body13.copyWith(color: WdColors.muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
