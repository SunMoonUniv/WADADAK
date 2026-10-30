import '../../../core/map/geo_point.dart';
import '../../run/domain/recording_models.dart' as recording;

/// B6 기록 카드 한 장. 서버 기록과 아직 올리지 않은 기기 기록을 같은 모양으로 맞춘다.
class RecordChoice {
  const RecordChoice({
    required this.id,
    required this.startedAt,
    required this.distanceMeters,
    required this.elapsed,
    required this.paceSecondsPerKm,
    required this.synced,
    this.onCourse = false,
    this.ghost = false,
    this.gpsGapPassed,
    this.route = const [],
  });

  final String id;
  final DateTime startedAt;
  final double distanceMeters;

  /// 총 소요 시간(일시정지 포함).
  final Duration elapsed;
  final double? paceSecondsPerKm;

  /// 서버에 올라갔다. 아니면 기기에만 있다(`동기화 대기`, D-14).
  final bool synced;

  /// 코스를 달린 기록(코스 러닝 · 코스 위 고스트 대결). 서버 판정의 `course`가 있다.
  final bool onCourse;

  /// 고스트 대결 기록(코스 위 · 자유 기록 모두).
  final bool ghost;

  /// 서버의 GPS 끊김 판정(공통 3 GPS 등록 끊긴 구간). 판정 전이면 null.
  final bool? gpsGapPassed;

  /// 카드에 그릴 달린 경로. GPS가 끊긴 구간마다 따로다. 없으면 빈 칸이다(4.1 `B6 카드 경로 그림`).
  final List<List<GeoPoint>> route;

  /// 카드의 기록 유형 태그. 아직 올리지 않은 기록은 코스 판정 전이라 I1처럼 `러닝`이다.
  String get typeLabel => !synced
      ? '러닝'
      : ghost
      ? '고스트 대결'
      : onCourse
      ? '코스 러닝'
      : '자유 러닝';
}

/// 기록을 코스로 등록할 수 있는지(B6-04). 결과 화면 카드 사유(`registerBlocker`)를 줄인 말이다.
/// [status]는 이 순서로 먼저 걸리는 것이다(4.1 B6 카드).
enum RecordStatus {
  registrable('등록 가능'),
  tooShort('1km 미만'),
  pendingSync('동기화 대기'),
  onCourse('이미 등록된 코스'),
  checking('확인 중'),
  gpsGap('GPS 끊김'),
  used('이미 등록됨');

  const RecordStatus(this.label);

  final String label;
}

/// [usedIds]는 GPS 코스 등록에 이미 쓴 기록(`registration-quota`의 `usedRunRecordIds`).
RecordStatus statusOf(RecordChoice record, Set<String> usedIds) {
  if (record.distanceMeters < 1000) return RecordStatus.tooShort;
  if (!record.synced) return RecordStatus.pendingSync;
  if (record.onCourse) return RecordStatus.onCourse;
  final passed = record.gpsGapPassed;
  if (passed == null) return RecordStatus.checking;
  if (!passed) return RecordStatus.gpsGap;
  if (usedIds.contains(record.id)) return RecordStatus.used;
  return RecordStatus.registrable;
}

/// B6 정렬(4.1 B6 화면). 세모는 방향이다. ▾는 최근 · 긴 기록부터, ▴는 짧은 기록부터. 거리가 같으면 최근 기록이 먼저다.
enum RecordSort {
  recent('최신순 ▾'),
  longest('거리순 ▾'),
  shortest('거리순 ▴');

  const RecordSort(this.label);

  final String label;

  /// `거리순` 칩을 눌렀을 때. 처음에는 긴 기록부터, 이미 거리순이면 방향을 바꾼다.
  RecordSort get distanceTapped => this == RecordSort.longest ? RecordSort.shortest : RecordSort.longest;

  int compare(RecordChoice a, RecordChoice b) {
    final byDistance = switch (this) {
      RecordSort.recent => 0,
      RecordSort.longest => b.distanceMeters.compareTo(a.distanceMeters),
      RecordSort.shortest => a.distanceMeters.compareTo(b.distanceMeters),
    };
    return byDistance != 0 ? byDistance : b.startedAt.compareTo(a.startedAt);
  }
}

/// 기기 기록과 서버 기록을 합친다(I1과 같은 기록, 4.1 B6 등록 가능 기록). 지운 기록은 뺀다.
/// 서버 목록에 있는 기록은 서버 요약을 쓴다. 기기 요약은 올린 직후 것이라 GPS 끊김 판정이 없을 수 있다.
List<RecordChoice> recordChoices({
  required List<recording.LocalRun> local,
  required List<Map<String, dynamic>> remote,
  required Set<String> deletedIds,
}) {
  final remoteById = {for (final r in remote) r['id'] as String: r};
  final localIds = {for (final r in local) r.id};
  return [
    for (final r in local)
      if (!deletedIds.contains(r.id)) _fromLocal(r, remoteById[r.id]),
    for (final r in remote)
      if (!localIds.contains(r['id']) && !deletedIds.contains(r['id'])) _fromSummary(r, synced: true),
  ];
}

RecordChoice _fromLocal(recording.LocalRun r, Map<String, dynamic>? remote) {
  if (remote != null) return _fromSummary(remote, synced: true);
  final synced = r.syncState == 'synced';
  final summary = r.summary;
  if (summary != null) {
    return _fromSummary({...summary, 'id': r.id, 'startedAt': r.startedAt.toIso8601String()}, synced: synced);
  }
  final metrics =
      (r.result?['metrics'] as Map?)?.cast<String, dynamic>() ??
      recording.RunCalculator.replay(r.inputs).at(r.checkpointMs).toJson();
  return _choice(r.id, r.startedAt, metrics, synced: synced);
}

RecordChoice _fromSummary(Map<String, dynamic> json, {required bool synced}) => _choice(
  json['id'] as String,
  DateTime.parse(json['startedAt'] as String),
  (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
  synced: synced,
  onCourse: json['course'] != null,
  ghost: json['ghost'] != null,
  gpsGapPassed: (json['gpsGap'] as Map?)?['passed'] as bool?,
  route: _route(json['routeThumbnail']),
);

/// 달리기 서버가 썸네일용으로 줄인 경로(`RecordSummary.routeThumbnail`). 이 경로가 생기기 전 예전 기록에는 없다.
/// 모르는 형식이거나 선을 그릴 수 없는 값이면 빈 칸으로 둔다(달리기 쪽 `기록 목록 경로 썸네일` 계약).
List<List<GeoPoint>> _route(Object? thumbnail) => switch (thumbnail) {
  {'version': 'RUN_ROUTE_THUMBNAIL_V1', 'segments': final List segments}
      when segments.every((s) => s is List && s.every((p) => p is Map && p['lat'] is num && p['lng'] is num)) => [
    for (final segment in segments) [for (final point in segment as List) GeoPoint.fromJson(point as Map)],
  ],
  _ => const [],
};

RecordChoice _choice(
  String id,
  DateTime startedAt,
  Map<String, dynamic> metrics, {
  required bool synced,
  bool onCourse = false,
  bool ghost = false,
  bool? gpsGapPassed,
  List<List<GeoPoint>> route = const [],
}) => RecordChoice(
  id: id,
  startedAt: startedAt,
  distanceMeters: (metrics['distanceM'] as num? ?? 0).toDouble(),
  elapsed: Duration(milliseconds: (metrics['elapsedMs'] as num? ?? 0).toInt()),
  paceSecondsPerKm: (metrics['paceSecondsPerKm'] as num?)?.toDouble(),
  synced: synced,
  onCourse: onCourse,
  ghost: ghost,
  gpsGapPassed: gpsGapPassed,
  route: route,
);
