import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/run_settings.dart';
export 'domain/run_settings.dart';

/// Public settings contract. The running module has no MY dependency.
const ghostGapVoiceSettingLabel = '고스트 격차 음성 안내';

/// A partial change preserves every omitted voice and device preference.
class RunSettingsChanged {
  const RunSettingsChanged({
    required this.owner,
    this.enabled,
    this.unit,
    this.distanceKm,
    this.timeMinutes,
    this.ghostGapEnabled,
    this.autoPauseEnabled,
    this.keepScreenOn,
    this.defaultGhost,
  });
  final String owner;
  final bool? enabled, ghostGapEnabled, autoPauseEnabled, keepScreenOn;
  final VoiceUnit? unit;
  final int? distanceKm, timeMinutes;
  final DefaultGhost? defaultGhost;

  RunSettings applyTo(RunSettings current) {
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
      autoPauseEnabled: autoPauseEnabled,
      keepScreenOn: keepScreenOn,
      defaultGhost: defaultGhost,
    );
  }
}

class RunSettingsEvents {
  final _changes = StreamController<RunSettingsChanged>.broadcast();
  Stream<RunSettingsChanged> get changes => _changes.stream;
  void publish(RunSettingsChanged event) => _changes.add(event);
  Future<void> close() => _changes.close();
}

final runSettingsEventsProvider = Provider<RunSettingsEvents>((ref) {
  final events = RunSettingsEvents();
  ref.onDispose(() => unawaited(events.close()));
  return events;
});

// Existing integrations keep the same event and provider identity.
typedef RunVoiceSettingsChanged = RunSettingsChanged;
typedef RunVoiceSettingsEvents = RunSettingsEvents;
final runVoiceSettingsEventsProvider = runSettingsEventsProvider;
