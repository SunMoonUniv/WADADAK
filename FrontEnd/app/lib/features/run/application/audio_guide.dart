import '../data/run_audio_output.dart';
import '../domain/recording_models.dart';
import '../domain/run_voice.dart';

/// Owns run audio settings, scheduling, suppression and playback failures.
/// An unavailable TTS engine must never interrupt recording or pause/end.
class AudioGuide {
  AudioGuide(this.output) {
    output.onError = () => _notice('음성 안내를 재생하지 못했어요. 휴대폰 음성 설정을 확인해 주세요.');
  }
  final RunAudioOutput output;
  final RunVoiceScheduler _scheduler = RunVoiceScheduler();
  RunVoiceSettings settings = const RunVoiceSettings();
  String? notice;
  void Function()? onChanged;
  bool _ready = false, _closed = false;
  String? _runningId;
  int _generation = 0;
  void restoreSettings(RunVoiceSettings value) {
    settings = value;
  }

  void _notice(String? value) {
    if (_closed) return;
    notice = value;
    onChanged?.call();
  }

  Future<void> prepare(RunVoiceSettings value) async {
    settings = value;
    if (!value.enabled) return;
    final generation = _generation;
    try {
      _ready = await output.initialize();
    } on Object {
      _ready = false;
    }
    if (_closed || generation != _generation) return;
    _notice(_ready ? null : '한국어 음성을 사용할 수 없어요. 휴대폰 음성 설정을 확인해 주세요.');
  }

  Future<void> configure(
    RunVoiceSettings value, {
    String? id,
    RunPhase? phase,
    RunMetrics? metrics,
  }) async {
    settings = value;
    if (!value.enabled) {
      await stop();
    } else if (!_ready) {
      await prepare(value);
    }
    if (id != null && phase != null && metrics != null) {
      _scheduler.update(id, phase, metrics, value);
    }
  }

  Future<void> update(String id, RunPhase phase, RunMetrics metrics) async {
    if (_closed) return;
    if (phase != RunPhase.running) {
      if (_runningId != null) await stop();
      _scheduler.update(id, phase, metrics, settings);
      return;
    }
    _runningId = id;
    final text = _scheduler.update(id, phase, metrics, settings);
    if (text == null || !_ready || !settings.enabled) return;
    await _speak(text);
  }

  /// 코스 안내 음성(AUD-06 완주). 음성 안내를 껐으면 재생하지 않는다
  Future<void> announce(String text) async {
    if (_closed || !_ready || !settings.enabled) return;
    await _speak(text);
  }

  Future<void> _speak(String text) async {
    try {
      if (!await output.speak(text)) {
        _notice('음성 안내를 재생하지 못했어요. 휴대폰 음성 설정과 볼륨을 확인해 주세요.');
      }
    } on Object {
      _notice('음성 안내를 재생하지 못했어요. 기록 측정은 계속돼요.');
    }
  }

  Future<void> preview(bool Function() canPlay) async {
    final generation = _generation;
    try {
      _ready = await output.initialize();
    } on Object {
      _ready = false;
    }
    if (_closed || generation != _generation || !canPlay()) return;
    if (!_ready) {
      _notice('한국어 음성을 사용할 수 없어요.');
      return;
    }
    _notice(null);
    await _speak('와다닥 음성 안내입니다. 나만의 리듬으로 달려보세요.');
  }

  Future<void> stop() async {
    ++_generation;
    _runningId = null;
    try {
      await output.stop();
    } on Object {
      _notice('음성 안내를 중단하지 못했어요. 휴대폰 음성 설정을 확인해 주세요.');
    }
  }

  Future<void> close() async {
    await stop();
    _closed = true;
    onChanged = null;
    try {
      await output.close();
    } on Object {
      /* Recording is independent. */
    }
  }
}
