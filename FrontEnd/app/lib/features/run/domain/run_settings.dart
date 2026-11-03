enum VoiceUnit { distance, time }

class RunSettings {
  const RunSettings({
    this.enabled = true,
    this.unit = VoiceUnit.distance,
    this.distanceKm = 1,
    this.timeMinutes = 5,
    this.ghostGapEnabled = false,
    this.autoPauseEnabled = false,
    this.keepScreenOn = false,
  });
  final bool enabled;
  final bool ghostGapEnabled;
  final bool autoPauseEnabled, keepScreenOn;
  final VoiceUnit unit;
  final int distanceKm, timeMinutes;
  RunSettings copyWith({
    bool? enabled,
    VoiceUnit? unit,
    int? distanceKm,
    int? timeMinutes,
    bool? ghostGapEnabled,
    bool? autoPauseEnabled,
    bool? keepScreenOn,
  }) => RunSettings(
    enabled: enabled ?? this.enabled,
    unit: unit ?? this.unit,
    distanceKm: distanceKm ?? this.distanceKm,
    timeMinutes: timeMinutes ?? this.timeMinutes,
    ghostGapEnabled: ghostGapEnabled ?? this.ghostGapEnabled,
    autoPauseEnabled: autoPauseEnabled ?? this.autoPauseEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'unit': unit.name,
    'distanceKm': distanceKm,
    'timeMinutes': timeMinutes,
    'ghostGapEnabled': ghostGapEnabled,
    'autoPauseEnabled': autoPauseEnabled,
    'keepScreenOn': keepScreenOn,
  };
  factory RunSettings.fromJson(Map<String, dynamic> j) => RunSettings(
    enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
    unit: j['unit'] == 'time' ? VoiceUnit.time : VoiceUnit.distance,
    distanceKm: const [1, 2, 5].contains(j['distanceKm'])
        ? j['distanceKm'] as int
        : 1,
    timeMinutes: const [5, 10, 15].contains(j['timeMinutes'])
        ? j['timeMinutes'] as int
        : 5,
    ghostGapEnabled: j['ghostGapEnabled'] == true,
    autoPauseEnabled: j['autoPauseEnabled'] == true,
    keepScreenOn: j['keepScreenOn'] == true,
  );
}

/// Compatibility for the existing audio sheet and persisted settings callers.
typedef RunVoiceSettings = RunSettings;
