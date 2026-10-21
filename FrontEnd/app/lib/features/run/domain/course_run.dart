/// 코스 러닝(F6) 앱 쪽 모델. 서버 API는 `run/코스 러닝 서버 연결 - 2026-10-20.md`.
library;

import 'dart:math' as math;

import '../../../core/map/geo_point.dart';
import 'course_tracker.dart';
import 'route_guidance.dart';

/// 코스 상세에서 고른 코스. 달리기 탭에서 시작하면 서버 준비·시작 신호를 거쳐 코스 러닝이 된다.
class CourseSelection {
  const CourseSelection(this.courseId, this.name);
  final String courseId, name;
}

/// 준비(`PUT .../course`) 응답. 서버가 이 경로로 완주를 판정한다. 첫 점이 출발점이다.
class CourseSnapshot {
  const CourseSnapshot({required this.route, required this.totalDistanceMeters});

  factory CourseSnapshot.fromJson(Map<String, dynamic> json) => CourseSnapshot(
    route: [for (final point in json['route'] as List) GeoPoint.fromJson(point as Map)],
    totalDistanceMeters: (json['totalDistanceMeters'] as num).toInt(),
  );

  final List<GeoPoint> route;
  final int totalDistanceMeters;
}

/// 준비를 마치고 측정을 시작하기 전(RCR-01). 출발점 반경 안에 들어와야 시작할 수 있다.
class CourseStart {
  CourseStart(this.runId, this.course, this.snapshot, this.position);

  /// 출발점 반경(m). 서버 경로 일치 오차(20m) 이하라야 여기서 시작한 기록의 출발이 서버에서도 확인된다(RCR-01).
  /// 주행 검증 전 개발값.
  static const radiusM = 20.0;

  /// 준비·시작 신호·기록에 같이 쓰는 세션 ID.
  final String runId;
  final CourseSelection course;
  final CourseSnapshot snapshot;

  /// 마지막으로 받은 현재 위치.
  GeoPoint position;

  GeoPoint get start => snapshot.route.first;
  double get distanceToStartM => position.distanceTo(start);
  bool get nearStart => distanceToStartM <= radiusM;
}

/// 달리는 중 코스 안내(Figma C4 코스·C4-1). 앱 추적값이라 서버 판정과 조금 다를 수 있고, 완주는 판정하지 않는다.
class CourseLive {
  CourseLive(this.name, this.tracker, [this.guidance]);
  final String name;
  final CourseTracker tracker;
  final RouteGuidance? guidance;

  /// 이탈 확정(머리말 "경로 이탈")
  bool get offRoute => guidance?.state == GuidanceState.off;

  /// 이탈 후보·확정이면 경로까지 거리와 가장 가까운 경로 지점(Figma C4-3 점선). 아니면 null
  ({double d, GeoPoint point})? get deviation {
    final g = guidance, d = g?.distanceM, point = g?.nearestPoint;
    if (g == null || g.state == GuidanceState.onRoute || d == null || point == null) return null;
    return (d: d, point: point);
  }

  List<GeoPoint> get route => tracker.route.route;
  double get lengthM => tracker.route.length;

  /// 코스 진행도 0~1 = 인정 거리 ÷ 전체(정책 용어 "코스 진행도")
  double get progress => math.min(1, tracker.recognizedM / lengthM);

  /// 남은 거리(m) = 전체 − 지금 코스상 위치. 코스에 아직 못 올라왔으면 전체
  double get remainingM => math.max(0, lengthM - (tracker.positionM ?? 0));

  /// 다음 km 지점까지, 마지막 km를 지나면 도착까지. 예: "3 km 지점까지 590 m"
  String get nextTarget {
    final position = tracker.positionM ?? 0;
    final km = position ~/ 1000 + 1;
    return lengthM - km * 1000 > 1e-6 // 끝이 딱 km 지점이면 부동소수 오차로 넘지 않게
        ? '$km km 지점까지 ${formatMeters(km * 1000 - position)}'
        : '도착까지 ${formatMeters(lengthM - position)}';
  }

  static String formatMeters(double meters) =>
      meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(2)} km';
}

/// 서버 코스 판정(`Result.course`). 코스 러닝 기록에만 있다.
class RunCourseResult {
  const RunCourseResult({
    required this.courseId,
    required this.completed,
    required this.reason,
    required this.recognizedDistanceMeters,
    required this.progressPercent,
    required this.reviewEligible,
    required this.courseElapsedSeconds,
  });

  factory RunCourseResult.fromJson(Map<String, dynamic> json) => RunCourseResult(
    courseId: json['courseId'] as String,
    completed: json['completed'] == true,
    reason: json['reason'] as String? ?? '',
    recognizedDistanceMeters: (json['recognizedDistanceMeters'] as num? ?? 0).toDouble(),
    progressPercent: (json['progressPercent'] as num? ?? 0).toDouble(),
    reviewEligible: json['reviewEligible'] == true,
    courseElapsedSeconds: (json['courseElapsedSeconds'] as num? ?? 0).toInt(),
  );

  final String courseId, reason;
  final bool completed, reviewEligible;
  final double recognizedDistanceMeters, progressPercent;
  final int courseElapsedSeconds;

  /// 미완주 이유 안내(정책 5.3). 완주면 null
  String? get shortfall => switch (reason) {
    'COMPLETED' => null,
    'START_NOT_CONFIRMED' => '출발점에서 시작한 기록이 확인되지 않았어요.',
    'FINISH_NOT_REACHED' => '코스 끝까지 도착하지 않았어요.',
    'DISTANCE_SHORT' => '코스를 달린 거리가 95%에 못 미쳐요.',
    _ => '완주 조건을 채우지 못했어요.',
  };
}
