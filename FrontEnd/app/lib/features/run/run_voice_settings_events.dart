import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/run_voice.dart';
export 'domain/run_voice.dart' show RunVoiceSettings, VoiceUnit;

/// Public contract for a future F4 settings publisher. No MY dependency.
const ghostGapVoiceSettingLabel = '고스트 격차 음성 안내';

/// Partial change: toggling the ghost option must preserve other voice choices.
class RunVoiceSettingsChanged {
  const RunVoiceSettingsChanged({
    required this.owner,
    this.enabled,
    this.unit,
    this.distanceKm,
    this.timeMinutes,
    this.ghostGapEnabled,
  });
  final String owner;
  final bool? enabled, ghostGapEnabled;
  final VoiceUnit? unit;
  final int? distanceKm, timeMinutes;

  RunVoiceSettings applyTo(RunVoiceSettings current) {
    if (owner.isEmpty ||
        distanceKm != null && !const [1, 2, 5].contains(distanceKm) ||
        timeMinutes != null && !const [5, 10, 15].contains(timeMinutes)) {
      throw const FormatException('음성 안내 설정값이 올바르지 않아요.');
    }
    return current.copyWith(
      enabled: enabled,
      unit: unit,
      distanceKm: distanceKm,
      timeMinutes: timeMinutes,
      ghostGapEnabled: ghostGapEnabled,
    );
  }
}

class RunVoiceSettingsEvents {
  final _changes = StreamController<RunVoiceSettingsChanged>.broadcast();
  Stream<RunVoiceSettingsChanged> get changes => _changes.stream;
  void publish(RunVoiceSettingsChanged event) => _changes.add(event);
  Future<void> close() => _changes.close();
}

final runVoiceSettingsEventsProvider = Provider<RunVoiceSettingsEvents>((ref) {
  final events = RunVoiceSettingsEvents();
  ref.onDispose(() => unawaited(events.close()));
  return events;
});
