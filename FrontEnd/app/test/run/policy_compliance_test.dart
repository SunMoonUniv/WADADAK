import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'recording/run_controller_test.dart' as fake;
import 'run_device_controller_test.dart' as devices;

import 'package:wadadak/features/run/application/audio_guide.dart';
import 'package:wadadak/core/api/run_api_client.dart';

class ProbeApi extends fake.TestApi {
  int preparations = 0, statuses = 0;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> prepare(RunUpload run) async {
    preparations++;
    if (pending != null) return pending!.future;
    return {'processing': 'PROCESSING'};
  }

  @override
  Future<Map<String, dynamic>> status(RunUpload run) async {
    statuses++;
    return {'processing': 'PROCESSING'};
  }
}

class BrokenOptionalDevice extends devices.Device {
  bool breakForcedSample = false;
  @override
  Future<Map<String, dynamic>?> sampleSteps({bool force = false}) async {
    if (force && breakForcedSample) {
      throw PlatformException(code: 'SENSOR_FAILURE');
    }
    return super.sampleSteps(force: force);
  }
}

class BrokenOutput extends devices.Output {
  bool breakVoiceStop = false;
  @override
  Future<void> stop() async {
    if (breakVoiceStop) throw PlatformException(code: 'TTS_FAILURE');
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late fake.FailingStore store;
  late fake.TestLocation location;
  late ProbeApi api;
  late BrokenOptionalDevice device;
  late RunController c;
  late BrokenOutput output;
  setUp(() {
    store = fake.FailingStore();
    location = fake.TestLocation();
    api = ProbeApi();
    device = BrokenOptionalDevice();
    output = BrokenOutput();
    c = RunController(
      store,
      location,
      api,
      () async => 'alice',
      device: device,
      audio: AudioGuide(output),
      nowMs: location.nowMs,
      automaticTicks: false,
      wait: (_) async {},
      utcNow: () => location.utc,
      lifecycleState: () => AppLifecycleState.resumed,
    );
  });
  tearDown(() async {
    output.breakVoiceStop = false;
    device.breakForcedSample = false;
    await fake.until(() => !c.syncing && !c.loadingHistory);
    await c.shutdown();
    c.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });

  test('policy: TTS failure must not prevent manual pause', () async {
    await c.prepareStart();
    output.breakVoiceStop = true;
    await c.pause();
    expect(
      c.run!.phase,
      RunPhase.paused,
      reason:
          'RUN-06 / optional audio failures must not block recording control',
    );
  });

  test(
    'policy: optional step sample failure must not prevent manual pause',
    () async {
      await c.prepareStart();
      device.breakForcedSample = true;
      await c.pause();
      expect(
        c.run!.phase,
        RunPhase.paused,
        reason: 'RUN-06 / missing sensor data must not block recording control',
      );
    },
  );

  test(
    'policy: recording must defer automatic upload of older pending runs',
    () async {
      await c.prepareStart();
      location.clock = 1000;
      await c.recorder.gps(36.00005, 127, 3);
      location.clock = 2000;
      await c.recorder.gps(36.0001, 127, 3);
      await c.pause();
      await c.end();
      await fake.until(() => !c.syncing);
      expect(c.records.single.pending, true);
      await c.prepareStart();
      await fake.until(() => !c.syncing && !c.loadingHistory);
      final before = api.preparations;
      for (var i = 1; i <= 15; i++) {
        location.clock = 2000 + i * 1000;
        await c.refreshMeasurement();
      }
      await fake.until(() => !c.syncing);
      expect(c.run!.phase, RunPhase.running);
      expect(
        api.preparations - before,
        0,
        reason:
            'Development policy 4.5: no server communication during recording',
      );
    },
  );

  test(
    'policy: synced result display must use the authoritative server metrics',
    () {
      final run = LocalRun(
        id: 'record',
        owner: 'alice',
        startedAt: fake.epoch,
        phase: RunPhase.ended,
        checkpointMs: 2000,
        syncState: 'synced',
        result: {
          'id': 'record',
          'startedAt': fake.epoch.toIso8601String(),
          'metrics': {
            'distanceM': 999.0,
            'elapsedMs': 2000,
            'activeMs': 2000,
            'movingMs': 2000,
            'paceSecondsPerKm': 2.002,
          },
        },
        inputs: [
          RunInput(
            seq: 0,
            kind: RunKind.start,
            elapsedMs: 0,
            measuredAt: fake.epoch,
          ),
          RunInput(
            seq: 1,
            kind: RunKind.gps,
            elapsedMs: 0,
            measuredAt: fake.epoch,
            lat: 36,
            lng: 127,
            accuracyM: 3,
          ),
          RunInput(
            seq: 2,
            kind: RunKind.gps,
            elapsedMs: 1000,
            measuredAt: fake.epoch.add(const Duration(seconds: 1)),
            lat: 36.0001,
            lng: 127,
            accuracyM: 3,
          ),
          RunInput(
            seq: 3,
            kind: RunKind.end,
            elapsedMs: 2000,
            measuredAt: fake.epoch.add(const Duration(seconds: 2)),
          ),
        ],
      );
      final adapter = FreeRunController.recording(c);
      try {
        expect(
          adapter.savedSnapshot(run).distanceMeters,
          999.0,
          reason: 'Development policy 4.5: replace local result after server confirmation',
        );
      } finally {
        adapter.dispose();
      }
    },
  );

  test(
    'policy: GPS fix timestamp must remain distinct from arrival timestamp',
    () async {
      await c.prepareStart();
      location.clock = 5000;
      final measured = fake.epoch.add(const Duration(seconds: 1));
      location.streams.single.add(
        location.point(36.00005, timestamp: measured),
      );
      await fake.until(() => c.run!.inputs.last.elapsedMs == 5000);
      expect(
        c.run!.inputs.last.measuredAt,
        measured,
        reason:
            'Running architecture 5: preserve the GPS measurement timestamp',
      );
    },
  );
  test('in-flight synchronization finishes before measurement starts and makes no follow-up request', () async {
    await c.prepareStart();
    location.clock = 1000;
    await c.recorder.gps(36.00005, 127, 3);
    location.clock = 2000;
    await c.recorder.gps(36.0001, 127, 3);
    await c.pause();
    await c.end();
    await fake.until(() => !c.syncing);
    api.pending = Completer<Map<String, dynamic>>();
    final before = api.preparations;
    final syncing = c.sync(manual: true);
    await fake.until(() => api.preparations > before);
    final statuses = api.statuses;
    final starting = c.prepareStart();
    await fake.until(() => c.preparing);
    expect(c.run!.phase, RunPhase.ended);
    api.pending!.complete({'processing': 'PROCESSING'});
    await syncing;
    await starting;
    expect(c.run!.phase, RunPhase.running);
    expect(api.statuses, statuses);
    expect(c.run!.id[14], '7');
  });
  test(
    'current result and saved result both use the persisted server result',
    () async {
      await c.prepareStart();
      location.clock = 1000;
      await c.recorder.gps(36.00005, 127, 3);
      location.clock = 2000;
      await c.recorder.gps(36.0001, 127, 3);
      await c.pause();
      await c.end();
      await fake.until(() => !c.syncing);
      final run = c.run!;
      final result = <String, dynamic>{
        'id': run.id,
        'startedAt': run.startedAt.toIso8601String(),
        'metrics': {
          'distanceM': 999.0,
          'elapsedMs': 2000,
          'activeMs': 1900,
          'movingMs': 1800,
          'paceSecondsPerKm': 1.8018,
        },
      };
      await store.synced(run, result);
      final adapter = FreeRunController.recording(c);
      try {
        expect(adapter.snapshot.distanceMeters, 999);
        expect(adapter.savedSnapshot(run).distanceMeters, 999);
        expect(adapter.snapshot.movingTime.inMilliseconds, 1800);
      } finally {
        adapter.dispose();
      }
    },
  );
}
