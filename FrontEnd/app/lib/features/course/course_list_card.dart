import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/course_api_client.dart';
import '../../core/map/geo_point.dart';
import 'course_format.dart';

/// 코스 목록 카드(A2-05 · A6-03). Figma A6 카드 모양이다(썸네일 64×58 · 오른쪽 `›`).
/// 아래 줄은 현재 러너(1명 이상이면 초록) · 코스 유형 · 만료 표시다.
class CourseListCard extends StatelessWidget {
  const CourseListCard({super.key, required this.course, required this.now, this.myLocation, this.onTap});

  final CourseListItem course;

  /// 만료까지 남은 날을 세는 기준 시각.
  final DateTime now;

  /// 현재 위치. 있으면 출발점까지 직선 거리를 둘째 줄 평점 뒤에 보인다(Figma A2 `★ 4.6 (128) · 0.8 km 거리`).
  final GeoPoint? myLocation;
  final VoidCallback? onTap;

  /// 이 날 이하로 남으면 만료 표시를 경고 색으로 보인다. 만료 임박 알림(D-7 · D-1)과 같다.
  static const expiryWarningDays = 7;

  @override
  Widget build(BuildContext context) {
    final daysLeft = daysUntilExpiry(course.expiresAt, now);
    final myLocation = this.myLocation;
    // Figma A2: `★ 4.6 (128) · 0.8 km 거리`. 리뷰가 없으면 거리만, 둘 다 없으면 줄이 없다.
    final second = [
      ?formatCardRating(course.averageRating, course.reviewCount),
      if (myLocation != null) formatAway(myLocation.distanceTo(course.route.first).round()),
    ];
    return WdCourseCard(
      title: course.name,
      // Figma A6: `5.2km · 난이도 중 · 평지`. 특징은 첫 번째(FIL-04 순서)만 보인다.
      lines: [
        [formatKm(course.distanceMeters), '난이도 ${course.difficulty.label}', ?course.tags.firstOrNull?.label].join(' · '),
        if (second.isNotEmpty) second.join(' · '),
      ],
      thumbnail: CourseRouteThumbnail(course.route),
      thumbnailSize: const Size(64, 58),
      showChevron: true,
      tags: [
        CourseRunnersTag(course.activeRunners),
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

/// 코스 검색 결과 카드(G1-04). Figma G1 카드 모양이다(썸네일 58×58 · 한 줄 `5.2km · 난이도 중 · ★ 4.6 (128)` · 오른쪽 `›`).
/// 아래 줄은 현재 러너 · 코스 유형이다.
class CourseSearchCard extends StatelessWidget {
  const CourseSearchCard({super.key, required this.course, this.onTap});

  final CourseListItem course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WdCourseCard(
        title: course.name,
        // 리뷰가 없으면 평점은 빠진다. 평점은 전체 기간 값이다(G1-04).
        lines: [
          [
            formatKm(course.distanceMeters),
            '난이도 ${course.difficulty.label}',
            ?formatCardRating(course.averageRating, course.reviewCount),
          ].join(' · '),
        ],
        thumbnail: CourseRouteThumbnail(course.route),
        showChevron: true,
        tags: [CourseRunnersTag(course.activeRunners), WdTag(course.courseType.label, filled: false)],
        onTap: onTap,
      );
}

/// 카드 아래 줄의 현재 러너(Figma A6 · G1). 1명 이상이면 초록 `지금 N명 달리는 중`, 0명이면 회색 `달리는 러너 없음`.
class CourseRunnersTag extends StatelessWidget {
  const CourseRunnersTag(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) =>
      WdTag(formatActiveRunners(count), tone: count > 0 ? WdTone.success : WdTone.neutral, filled: false);
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
