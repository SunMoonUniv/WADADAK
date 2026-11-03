import 'recording_models.dart';

import 'run_settings.dart';
export 'run_settings.dart';

/// AUD-07: a signed same-position arrival-time difference, never a lap delta.
String? ghostGapVoice(double? deltaMs) {
  if (deltaMs == null || !deltaMs.isFinite) return null;
  if (deltaMs.abs() < 5000) return '고스트와 거의 나란히 달리고 있어요.';
  final seconds = (deltaMs.abs() / 5000).round() * 5;
  return '현재 고스트보다 $seconds초 ${deltaMs < 0 ? '앞서 있어요' : '뒤처져 있어요'}.';
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
