import 'recording_models.dart';

enum VoiceUnit { distance, time }

class RunVoiceSettings {
  const RunVoiceSettings({
    this.enabled = true,
    this.unit = VoiceUnit.distance,
    this.distanceKm = 1,
    this.timeMinutes = 5,
  });
  final bool enabled;
  final VoiceUnit unit;
  final int distanceKm, timeMinutes;
  RunVoiceSettings copyWith({
    bool? enabled,
    VoiceUnit? unit,
    int? distanceKm,
    int? timeMinutes,
  }) => RunVoiceSettings(
    enabled: enabled ?? this.enabled,
    unit: unit ?? this.unit,
    distanceKm: distanceKm ?? this.distanceKm,
    timeMinutes: timeMinutes ?? this.timeMinutes,
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'unit': unit.name,
    'distanceKm': distanceKm,
    'timeMinutes': timeMinutes,
  };
  factory RunVoiceSettings.fromJson(Map<String, dynamic> j) => RunVoiceSettings(
    enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
    unit: j['unit'] == 'time' ? VoiceUnit.time : VoiceUnit.distance,
    distanceKm: const [1, 2, 5].contains(j['distanceKm'])
        ? j['distanceKm'] as int
        : 1,
    timeMinutes: const [5, 10, 15].contains(j['timeMinutes'])
        ? j['timeMinutes'] as int
        : 5,
  );
}

/// One announcement per crossed interval; pause and setting changes never replay old intervals.
class RunVoiceScheduler {
  String? _id, _settingsKey;
  int _distanceBucket = 0, _timeBucket = 0;
  String? update(
    String id,
    RunPhase phase,
    RunMetrics metrics,
    RunVoiceSettings settings,
  ) {
    final key =
        '${settings.enabled}:${settings.unit.name}:${settings.distanceKm}:${settings.timeMinutes}';
    final distance = (metrics.distanceM / (settings.distanceKm * 1000)).floor();
    final time = metrics.activeMs ~/ (settings.timeMinutes * 60000);
    if (_id != id || _settingsKey != key) {
      _id = id;
      _settingsKey = key;
      _distanceBucket = distance;
      _timeBucket = time;
      return null;
    }
    final due = settings.unit == VoiceUnit.distance
        ? distance > _distanceBucket
        : time > _timeBucket;
    _distanceBucket = distance;
    _timeBucket = time;
    if (!due || !settings.enabled || phase != RunPhase.running) return null;
    final pace = metrics.distanceM >= 25 ? metrics.paceSecondsPerKm : null;
    final seconds = pace?.round();
    final paceText = seconds == null
        ? ''
        : ' 평균 페이스 ${seconds ~/ 60}분 ${seconds % 60}초입니다.';
    return '거리 ${(metrics.distanceM / 1000).toStringAsFixed(2)}킬로미터, '
        '달린 시간 ${metrics.activeMs ~/ 60000}분 ${metrics.activeMs ~/ 1000 % 60}초.$paceText';
  }
}
