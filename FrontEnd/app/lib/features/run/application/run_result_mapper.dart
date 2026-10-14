import '../domain/run_lap.dart';
import '../domain/run_models.dart';

RunSnapshot remoteRunSnapshot(
  Map<String, dynamic> json, {
  String storageStatus = '서버 저장 완료',
}) {
  final m = (json['metrics'] as Map).cast<String, dynamic>();
  int ms(String key) => (m[key] as num?)?.toInt() ?? 0;
  final distance = (m['distanceM'] as num).toDouble();
  final route = (json['routeSegments'] as List? ?? [])
      .map(
        (segment) => (segment as List)
            .map(
              (p) => RunPoint(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ),
            )
            .toList(),
      )
      .toList();
  return RunSnapshot(
    state: RunState.finished,
    sessionId: json['id'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    elapsed: Duration(milliseconds: ms('elapsedMs')),
    active: Duration(milliseconds: ms('activeMs')),
    moving: Duration(
      milliseconds: m['movingMs'] == null ? ms('activeMs') : ms('movingMs'),
    ),
    distanceMeters: distance,
    inputs: const [],
    segments: route,
    paceDisplayManaged: true,
    averagePaceDisplay: (m['paceSecondsPerKm'] as num?)?.toDouble(),
    storageStatus: storageStatus,
    endReason: json['endReason'] as String?,
    gapCount: ms('gapCount'),
    laps: (json['laps'] as List? ?? [])
        .map((l) => RunLap.fromJson((l as Map).cast<String, dynamic>()))
        .toList(),
    averageCadence: (m['averageCadence'] as num?)?.toDouble(),
    cadenceCoverageMs: ms('cadenceCoverageMs'),
    cadenceStatus: m['averageCadence'] == null ? '측정 없음' : '측정 완료',
  );
}
