import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_device.dart';
import 'package:wadadak/features/run/data/run_location.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_voice.dart';

import 'recording/run_controller_test.dart' as fake;

class Device extends RunDevice {
  bool allowed = true, supported = true;
  int starts = 0, stops = 0, voiceStops = 0;
  Map<String, dynamic>? next;
  final speech = <String>[];
  @override
  Future<void> requestPermission() async {
    if (!allowed) {
      throw const RunSetupException(
        '신체 활동 권한 필요',
        action: RunSetupAction.appSettings,
      );
    }
  }

  @override
  Future<bool> permissionGranted() async => allowed;
  @override
  Future<String> startSteps() async {
    starts++;
    return supported ? '걸음 감지 대기' : '센서 미지원';
  }

  @override
  Future<Map<String, dynamic>?> sampleSteps({bool force = false}) async {
    final value = next;
    next = null;
    return value;
  }

  @override
  Future<void> stopSteps() async {
    stops++;
  }

  @override
  Future<bool> initializeVoice() async => true;
  @override
  Future<bool> speak(String text) async {
    speech.add(text);
    return true;
  }

  @override
  Future<void> stopVoice() async {
    voiceStops++;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fake.FailingStore store;
  late fake.TestLocation gps;
  late Device device;
  late RunController c;
  setUp(() {
    sqfliteFfiInit();
    store = fake.FailingStore();
    gps = fake.TestLocation();
    device = Device();
    c = RunController(
      store,
      gps,
      fake.TestApi(),
      () async => 'alice',
      device: device,
      automaticTicks: false,
      wait: (_) async {},
      utcNow: () => gps.utc,
      lifecycleState: () => AppLifecycleState.resumed,
    );
  });
  tearDown(() async {
    await fake.until(() => !c.syncing && !c.loadingHistory);
    await c.shutdown();
    c.dispose();
    for (final stream in gps.streams) {
      await stream.close();
    }
  });
  test(
    'fitness permission is requested at every start; denial creates no run',
    () async {
      device.allowed = false;
      await c.prepareStart();
      expect(c.run, isNull);
      expect(await store.list('alice'), isEmpty);
      expect(c.setupAction, RunSetupAction.appSettings);
      device.allowed = true;
      await c.prepareStart();
      expect(c.run?.phase, RunPhase.running);
    },
  );
  test('real sample clock is persisted; pause stops sensor and audio, resume resets the sensor baseline', () async {
    await c.prepareStart();
    await fake.until(() => device.starts == 1);
    gps.clock = 5000;
    device.next = {'steps': 15, 'durationMs': 5000, 'sampleEndClockMs': 5000};
    await c.refreshMeasurement();
    expect(c.metrics.averageCadence, 180);
    expect(c.metrics.cadenceCoverageMs, 5000);
    expect(
      c.run!.inputs.where((p) => p.kind == RunKind.cadence).single.sampleEndMs,
      5000,
    );
    gps.clock = 6000;
    device.next = {'steps': 3, 'durationMs': 1000, 'sampleEndClockMs': 6000};
    await c.pause();
    expect(c.metrics.steps, 18);
    expect(c.metrics.cadenceCoverageMs, 6000);
    expect(c.metrics.currentCadence, isNull);
    expect(device.voiceStops, greaterThan(0));
    gps.clock = 12000;
    await c.resume();
    await fake.until(() => device.starts == 2);
    gps.clock = 17000;
    device.next = {'steps': 10, 'durationMs': 5000, 'sampleEndClockMs': 17000};
    await c.refreshMeasurement();
    expect(c.metrics.steps, 28);
    expect(c.metrics.cadenceCoverageMs, 11000);
    final calc = RunCalculator.replay(c.run!.inputs);
    expect(
      calc.at(17000).averageCadence,
      closeTo(c.metrics.averageCadence!, .000001),
    );
  });
  test('time announcement uses active time and does not repeat or speak during pause', () async {
    await c.bindOwner();
    await c.saveVoiceSettings(const RunVoiceSettings(unit: VoiceUnit.time));
    await c.prepareStart();
    gps.clock = 300000;
    await c.refreshMeasurement();
    expect(device.speech.length, 1);
    expect(device.speech.single, contains('5분'));
    await c.refreshMeasurement();
    expect(device.speech.length, 1);
    await c.pause();
    gps.clock = 600000;
    await c.refreshMeasurement();
    await c.testVoice();
    expect(device.speech.length, 1);
    await c.resume();
    await c.refreshMeasurement();
    expect(device.speech.length, 1);
    gps.clock = 900000;
    await c.refreshMeasurement();
    expect(device.speech.length, 2);
  });
  test('unsupported step sensor does not block GPS recording; revoked required permission ends durably', () async {
    device.supported = false;
    await c.prepareStart();
    expect(c.run?.phase, RunPhase.running);
    expect(c.cadenceStatus, '센서 미지원');
    device.onVoiceError?.call('음성 생성 실패');
    expect(c.voiceNotice, '음성 생성 실패');
    expect(c.run?.phase, RunPhase.running);
    expect(c.metrics.averageCadence, isNull);
    device.allowed = false;
    for (var i = 1; i <= 5; i++) {
      gps.clock = i * 1000;
      await c.refreshMeasurement();
    }
    expect(c.run?.phase, RunPhase.ended);
    expect(c.run?.endReason, 'PERMISSION_REVOKED');
    expect(c.setupAction, RunSetupAction.appSettings);
  });
  test('idle refresh never cancels a user-requested voice preview', () async {
    await c.bindOwner();
    await fake.until(() => !c.syncing && !c.loadingHistory);
    final stopped = device.voiceStops;
    await c.testVoice();
    expect(device.speech.length, 1);
    for (var i = 1; i <= 5; i++) {
      gps.clock = i * 1000;
      await c.refreshMeasurement();
    }
    expect(device.voiceStops, stopped);
    expect(device.speech.length, 1);
  });
}
