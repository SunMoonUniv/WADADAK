import '../data/run_device.dart';
import 'run_recorder.dart';

/// Sensor lifecycle and sample admission for one recording session.
/// The controller retains permission, audio and durable shutdown ordering.
class RunSensorSession {
  RunSensorSession(this.device, this.recorder, {required this.canSample});

  final RunDevice? device;
  final RunRecorder recorder;
  final bool Function(String runId) canSample;
  String? runId;
  bool _pressureStarted = false;
  String cadenceStatus = '측정 전';

  Future<void> start(String id) async {
    runId = id;
    try {
      cadenceStatus = await device?.startSteps() ?? '센서 미지원';
    } on Object {
      cadenceStatus = '센서 연결 실패';
    }
    // Pressure support is independent of the step sensor.
    try {
      _pressureStarted = await device?.startPressure() ?? false;
    } on Object {
      _pressureStarted = false;
    }
  }

  Future<void> sampleCadence({bool force = false}) async {
    final id = runId;
    if (device == null || id == null || !canSample(id)) return;
    final sample = await device!.sampleSteps(force: force);
    if (sample == null || !canSample(id)) return;
    await recorder.cadence(
      (sample['steps'] as num).toInt(),
      (sample['durationMs'] as num).toInt(),
      sampleEndClockMs: (sample['sampleEndClockMs'] as num?)?.toInt(),
    );
    cadenceStatus = '측정 중';
  }

  Future<void> samplePressure() async {
    final id = runId;
    if (!_pressureStarted || id == null || !canSample(id)) return;
    try {
      final sample = await device?.samplePressure();
      if (sample == null || !canSample(id)) return;
      await recorder.barometer(
        (sample['pressureHpa'] as num).toDouble(),
        (sample['pressureAccuracy'] as num).toInt(),
        sampleClockMs: (sample['sampleClockMs'] as num).toInt(),
      );
    } on RunStorageFailure {
      rethrow;
    } on Object {
      // Optional hardware failure must not stop GPS or durable recording.
    }
  }

  Future<void> stopPressure() async {
    runId = null;
    _pressureStarted = false;
    try {
      await device?.stopPressure();
    } on Object {
      // Recording remains durable when optional hardware is unavailable.
    }
  }

  Future<void> stopSteps() async {
    try {
      await device?.stopSteps();
    } on Object {
      // Recording remains durable when optional hardware is unavailable.
    }
  }
}
