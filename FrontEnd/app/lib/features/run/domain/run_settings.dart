enum VoiceUnit { distance, time }

/// F4 기본 고스트: 코스 고스트 선택 화면(C2)에 들어가면 미리 골라 둘 내 기록.
/// manual이면 지금처럼 아무것도 고르지 않는다. 기본값은 Figma F4대로 내 최고 기록이다.
enum DefaultGhost { best, recent, manual }

class RunSettings {
  const RunSettings({
    this.enabled = true,
    this.unit = VoiceUnit.distance,
    this.distanceKm = 1,
    this.timeMinutes = 5,
    this.ghostGapEnabled = false,
    this.autoPauseEnabled = false,
    this.keepScreenOn = false,
    this.defaultGhost = DefaultGhost.best,
  });
  final bool enabled;
  final bool ghostGapEnabled;
  final bool autoPauseEnabled, keepScreenOn;
  final DefaultGhost defaultGhost;
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
    DefaultGhost? defaultGhost,
  }) => RunSettings(
    enabled: enabled ?? this.enabled,
    unit: unit ?? this.unit,
    distanceKm: distanceKm ?? this.distanceKm,
    timeMinutes: timeMinutes ?? this.timeMinutes,
    ghostGapEnabled: ghostGapEnabled ?? this.ghostGapEnabled,
    autoPauseEnabled: autoPauseEnabled ?? this.autoPauseEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    defaultGhost: defaultGhost ?? this.defaultGhost,
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'unit': unit.name,
    'distanceKm': distanceKm,
    'timeMinutes': timeMinutes,
    'ghostGapEnabled': ghostGapEnabled,
    'autoPauseEnabled': autoPauseEnabled,
    'keepScreenOn': keepScreenOn,
    'defaultGhost': defaultGhost.name,
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
    // 저장된 값이 없던 기존 기기는 기본값(최고 기록)으로 읽는다
    defaultGhost: DefaultGhost.values.asNameMap()[j['defaultGhost']] ?? DefaultGhost.best,
  );
}

/// Compatibility for the existing audio sheet and persisted settings callers.
typedef RunVoiceSettings = RunSettings;
