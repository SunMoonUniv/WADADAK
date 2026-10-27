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

/// 기록 여러 개의 합계(I1 위쪽 전체 기간 요약 · "N월 분석").
class RunTotals {
  const RunTotals({required this.distanceMeters, required this.elapsed, required this.moving, required this.runs});

  /// 기록을 모두 더한다.
  factory RunTotals.of(Iterable<RunHistoryRow> rows) {
    var meters = 0.0, runs = 0;
    var elapsed = Duration.zero, moving = Duration.zero;
    for (final row in rows) {
      meters += row.distanceMeters;
      elapsed += row.elapsed;
      moving += row.moving;
      runs++;
    }
    return RunTotals(distanceMeters: meters, elapsed: elapsed, moving: moving, runs: runs);
  }

  final double distanceMeters;

  /// 총 소요 시간(일시정지 포함). 화면의 "시간"이다.
  final Duration elapsed;
  final Duration moving;
  final int runs;

  /// 움직인 시간 합 ÷ 거리 합(초/km). 기록마다의 페이스를 평균 낸 것과 다르다. 거리가 없으면 null.
  double? get paceSecondsPerKm => distanceMeters > 0 ? moving.inMilliseconds / distanceMeters : null;
}

/// [month]의 해 · 달(기기 시간대)에 시작한 기록만.
Iterable<RunHistoryRow> inMonth(Iterable<RunHistoryRow> rows, DateTime month) => rows.where((row) {
  final t = row.startedAt.toLocal();
  return t.year == month.year && t.month == month.month;
});

/// [month]에 달린 날(달력 도장).
Set<int> runDays(Iterable<RunHistoryRow> rows, DateTime month) => {
  for (final row in inMonth(rows, month)) row.startedAt.toLocal().day,
};
