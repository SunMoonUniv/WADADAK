/// 코스 러닝(F6) 앱 쪽 모델. 서버 API는 `run/코스 러닝 서버 연결 - 2026-10-20.md`.
library;

/// 코스 상세에서 고른 코스. 달리기 탭에서 시작하면 서버 준비·시작 신호를 거쳐 코스 러닝이 된다.
class CourseSelection {
  const CourseSelection(this.courseId, this.name);
  final String courseId, name;
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
