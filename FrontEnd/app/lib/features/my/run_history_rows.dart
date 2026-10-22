import '../run/domain/recording_models.dart' as recording;

/// 기록 목록 한 줄의 코스 요약(`RecordSummary.course`). 자유 러닝이면 없다.
class RecordCourse {
  RecordCourse.fromJson(Map json)
    : courseId = json['courseId'] as String,
      courseName = json['courseName'] as String? ?? '',
      completed = json['completed'] == true,
      progressPercent = (json['progressPercent'] as num? ?? 0).toDouble(),
      reviewEligible = json['reviewEligible'] == true;

  final String courseId;

  /// 달릴 때의 코스 이름. 코스 이름이 바뀌어도 기록에는 그때 이름이 남는다.
  final String courseName;

  /// 서버 완주 판정.
  final bool completed;

  /// 0~100.
  final double progressPercent;

  /// 이 기록으로 리뷰를 쓸 수 있다. 쓸지는 `openReviewWriter`가 서버에 다시 묻는다.
  final bool reviewEligible;
}

/// I1 기록 카드 한 장. 서버 기록과 아직 올리지 않은 기기 기록을 같은 모양으로 맞춘다.
class RunHistoryRow {
  const RunHistoryRow({
    required this.id,
    required this.startedAt,
    required this.distanceMeters,
    required this.elapsed,
    required this.moving,
    required this.paceSecondsPerKm,
    required this.syncState,
    this.course,
  });

  final String id;
  final DateTime startedAt;
  final double distanceMeters;
  final Duration elapsed;

  /// 움직인 시간. 여러 기록의 평균 페이스를 낼 때 쓴다(일시정지 · 정지 제외).
  final Duration moving;
  final double? paceSecondsPerKm;

  /// `synced`면 서버에 저장됐다. 그 밖에는 기기에만 있다(정책 D-14 "동기화 대기").
  final String syncState;

  /// 서버가 판정한 코스 요약. 자유 러닝이거나 아직 올리지 않았으면 없다.
  final RecordCourse? course;

  bool get synced => syncState == 'synced';
}

/// 기기 기록과 서버 기록을 합쳐 최근 순으로 늘어놓는다. 같은 기록은 기기 것을 쓰고, 지운 기록은 뺀다.
List<RunHistoryRow> runHistoryRows({
  required List<recording.LocalRun> local,
  required List<Map<String, dynamic>> remote,
  required Set<String> deletedIds,
}) {
  final localIds = {for (final r in local) r.id};
  return [
    for (final r in local) _fromLocal(r),
    for (final r in remote)
      if (!localIds.contains(r['id']) && !deletedIds.contains(r['id'])) _fromSummary(r, 'synced'),
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
}

RunHistoryRow _fromLocal(recording.LocalRun r) {
  // 서버에 올라간 기기 기록은 서버 요약(코스 포함)이 붙어 있다
  final summary = r.summary;
  if (summary != null) return _fromSummary({...summary, 'id': r.id, 'startedAt': r.startedAt.toIso8601String()}, r.syncState);
  final metrics =
      (r.result?['metrics'] as Map?)?.cast<String, dynamic>() ??
      recording.RunCalculator.replay(r.inputs).at(r.checkpointMs).toJson();
  return _row(r.id, r.startedAt, metrics, r.syncState, null);
}

RunHistoryRow _fromSummary(Map<String, dynamic> json, String syncState) => _row(
  json['id'] as String,
  DateTime.parse(json['startedAt'] as String),
  (json['metrics'] as Map).cast<String, dynamic>(),
  syncState,
  json['course'] == null ? null : RecordCourse.fromJson(json['course'] as Map),
);

RunHistoryRow _row(String id, DateTime startedAt, Map<String, dynamic> metrics, String syncState, RecordCourse? course) =>
    RunHistoryRow(
      id: id,
      startedAt: startedAt,
      distanceMeters: (metrics['distanceM'] as num? ?? 0).toDouble(),
      elapsed: Duration(milliseconds: (metrics['elapsedMs'] as num? ?? 0).toInt()),
      moving: Duration(milliseconds: (metrics['movingMs'] as num? ?? metrics['elapsedMs'] as num? ?? 0).toInt()),
      paceSecondsPerKm: (metrics['paceSecondsPerKm'] as num?)?.toDouble(),
      syncState: syncState,
      course: course,
    );

/// I1 유형 탭. 아직 올리지 않은 기록은 코스 판정 전이라 전체에만 보인다.
enum RunType {
  all('전체'),
  free('자유 러닝'),
  course('코스 러닝'),
  // 고스트 대결(F9)이 생기면 기록에 대결 정보가 붙는다. 그때까지 비어 있다
  ghost('고스트 대결');

  const RunType(this.label);

  final String label;

  bool includes(RunHistoryRow row) => switch (this) {
    RunType.all => true,
    RunType.free => row.synced && row.course == null,
    RunType.course => row.course != null,
    RunType.ghost => false,
  };
}

/// 한 달 요약(I1 위 3칸). [paceSecondsPerKm]은 움직인 시간 합 ÷ 거리 합이라, 기록마다의 페이스를 평균 낸 것과 다르다.
typedef MonthSummary = ({double distanceMeters, int runs, double? paceSecondsPerKm});

/// [month]의 해 · 달(기기 시간대)에 시작한 기록을 더한다.
MonthSummary monthSummary(Iterable<RunHistoryRow> rows, DateTime month) {
  var meters = 0.0, runs = 0;
  var moving = Duration.zero;
  for (final row in rows) {
    final t = row.startedAt.toLocal();
    if (t.year != month.year || t.month != month.month) continue;
    meters += row.distanceMeters;
    moving += row.moving;
    runs++;
  }
  return (
    distanceMeters: meters,
    runs: runs,
    paceSecondsPerKm: meters > 0 ? moving.inMilliseconds / meters : null,
  );
}

/// [today]가 든 주(월~일, 기기 시간대)의 요일별 거리(m). 0이 월요일이다.
List<double> weekDistances(Iterable<RunHistoryRow> rows, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final monday = day.subtract(Duration(days: day.weekday - 1));
  final meters = List.filled(7, 0.0);
  for (final row in rows) {
    final t = row.startedAt.toLocal();
    final index = DateTime(t.year, t.month, t.day).difference(monday).inDays;
    if (index >= 0 && index < 7) meters[index] += row.distanceMeters;
  }
  return meters;
}
