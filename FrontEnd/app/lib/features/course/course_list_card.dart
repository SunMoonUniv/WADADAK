import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/course_api_client.dart';
import '../../core/map/geo_point.dart';
import 'course_format.dart';

/// 코스 목록 카드(A2-05 · A6-03). Figma A6 카드 모양이다(썸네일 64×58 · 오른쪽 `›`).
///
/// 평점 · 리뷰 수 · 현재 러너는 코스 통계(F11)를 만든 뒤 붙인다.
class CourseListCard extends StatelessWidget {
  const CourseListCard({super.key, required this.course, required this.now, this.myLocation, this.onTap});

  final CourseListItem course;

  /// 만료까지 남은 날을 세는 기준 시각.
  final DateTime now;

  /// 현재 위치. 있으면 출발점까지 직선 거리를 둘째 줄에 보인다(Figma A2 `0.8 km 거리`).
  final GeoPoint? myLocation;
  final VoidCallback? onTap;

  /// 이 날 이하로 남으면 만료 표시를 경고 색으로 보인다. 만료 임박 알림(D-7 · D-1)과 같다.
  static const expiryWarningDays = 7;

  @override
  Widget build(BuildContext context) {
    final daysLeft = daysUntilExpiry(course.expiresAt, now);
    final myLocation = this.myLocation;
    return WdCourseCard(
      title: course.name,
      // Figma A6: `5.2km · 난이도 중 · 평지`. 특징은 첫 번째(FIL-04 순서)만 보인다.
      lines: [
        [formatKm(course.distanceMeters), '난이도 ${course.difficulty.label}', ?course.tags.firstOrNull?.label].join(' · '),
        if (myLocation != null) formatAway(myLocation.distanceTo(course.route.first).round()),
      ],
      thumbnail: CourseRouteThumbnail(course.route),
      thumbnailSize: const Size(64, 58),
      showChevron: true,
      tags: [
        WdTag(course.courseType.label, filled: false),
        WdTag(
          formatExpiry(daysLeft),
          tone: daysLeft <= expiryWarningDays ? WdTone.warning : WdTone.neutral,
          filled: false,
        ),
      ],
      onTap: onTap,
    );
  }
}

/// 카드 썸네일의 코스 경로. 지도 없이 경로만 칸에 맞춰 그린다. 선은 지도 코스 선과 같은 라임 + 잉크 테두리다.
class CourseRouteThumbnail extends StatelessWidget {
  const CourseRouteThumbnail(this.route, {super.key});

  final List<GeoPoint> route;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RoutePainter(route), size: Size.infinite);
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.route);

  final List<GeoPoint> route;

  static const _inset = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length < 2) return;
    // 좁은 범위라 경도는 위도 cos만큼 줄여 평면으로 본다.
    final shrink = math.cos(route.first.lat * math.pi / 180);
    final xs = [for (final point in route) point.lng * shrink];
    final ys = [for (final point in route) -point.lat];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final width = size.width - _inset * 2, height = size.height - _inset * 2;
    final spanX = maxX - minX, spanY = maxY - minY;
    final scale = math.min(spanX == 0 ? double.infinity : width / spanX, spanY == 0 ? double.infinity : height / spanY);
    if (!scale.isFinite) return;
    // 가운데에 둔다.
    final dx = _inset + (width - spanX * scale) / 2, dy = _inset + (height - spanY * scale) / 2;
    final path = Path()
      ..addPolygon([
        for (var i = 0; i < route.length; i++) Offset(dx + (xs[i] - minX) * scale, dy + (ys[i] - minY) * scale),
      ], false);

    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(path, stroke(WdColors.ink, 4))
      ..drawPath(path, stroke(WdColors.lime, 2));
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => oldDelegate.route != route;
}
