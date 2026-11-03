import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_settings.dart';

import 'recording/run_controller_test.dart' show FailingStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late RunRecorder recorder;
  late FailingStore store;
  var clock = 0;
  setUp(() async {
    clock = 0;
    store = FailingStore();
    recorder = RunRecorder(store, () async => clock);
    await recorder.start('run', 'alice', DateTime.utc(2026, 11, 3));
  });
  tearDown(() async {
    await recorder.close();
    await store.close();
  });
  Future<void> fix(
    int ms, {
    double lat = 36,
    double accuracy = 3,
    double? speed,
    double? speedAccuracy,
  }) async {
    clock = ms;
    await recorder.gps(
      lat,
      127,
      accuracy,
      speedMps: speed,
      speedAccuracyMps: speedAccuracy,
    );
  }

  test('default OFF; enabling waits ten seconds of fresh stationary fixes and persists a normal PAUSE', () async {
    await fix(0);
    await fix(5000);
    await fix(10000);
    expect(recorder.current!.phase, RunPhase.running);
    recorder.autoPauseEnabled = true;
    await fix(11000);
    await fix(16000);
    expect(recorder.current!.phase, RunPhase.running);
    await fix(21000);
    expect(recorder.current!.phase, RunPhase.paused);
    final pause = recorder.current!.inputs.last;
    expect(pause.kind, RunKind.pause);
    expect(pause.elapsedMs, 21000);
    expect(
      recorder.current!.inputs.map((p) => p.seq).toSet().length,
      recorder.current!.inputs.length,
    );
    final saved = (await store.list('alice', id: 'run')).single;
    expect(saved.phase, RunPhase.paused);
    expect(saved.inputs.last.kind, RunKind.pause);
  });

  test('auto pause freezes active time, keeps elapsed clock and uses existing movement resume', () async {
    recorder.autoPauseEnabled = true;
    await fix(0);
    await fix(5000);
    await fix(10000);
    clock = 15000;
    await recorder.tick();
    expect(recorder.metrics.elapsedMs, 15000);
    expect(recorder.metrics.activeMs, 10000);
    for (var i = 1; i <= 4; i++) {
      await fix(14000 + i * 2000, lat: 36 + i * .00003);
    }
    expect(recorder.current!.phase, RunPhase.running);
    expect(
      recorder.current!.inputs
          .where((p) => p.kind == RunKind.resume)
          .single
          .reason,
      'MOVEMENT',
    );
    expect(recorder.metrics.elapsedMs, 22000);
    expect(recorder.metrics.activeMs, 10000);
    clock = 23000;
    await recorder.tick();
    expect(recorder.metrics.activeMs, 11000);
  });

  test(
    'GPS gap or missing signal never accumulates stationary duration',
    () async {
      recorder.autoPauseEnabled = true;
      await fix(0);
      await fix(5000);
      clock = 6000;
      await recorder.gap('NO_FIX');
      clock = 60000;
      await recorder.tick();
      expect(recorder.current!.phase, RunPhase.running);
      await fix(61000);
      await fix(66000);
      expect(recorder.current!.phase, RunPhase.running);
      await fix(71000);
      expect(recorder.current!.phase, RunPhase.paused);
    },
  );

  test(
    'poor fixes and long collection intervals reset the confirmation window',
    () async {
      recorder.autoPauseEnabled = true;
      await fix(0);
      await fix(5000, accuracy: 40);
      await fix(10000);
      await fix(15000);
      expect(recorder.current!.phase, RunPhase.running);
      await fix(30001);
      await fix(35001);
      await fix(40001);
      expect(recorder.current!.phase, RunPhase.running);
      await fix(45001);
      expect(recorder.current!.phase, RunPhase.paused);
    },
  );

  test('real walking or reliable velocity cannot be mistaken for a stationary cluster', () async {
    recorder.autoPauseEnabled = true;
    for (var i = 0; i <= 10; i++) {
      await fix(i * 2000, lat: 36 + i * .00002);
    }
    expect(recorder.current!.phase, RunPhase.running);
    for (var i = 11; i <= 20; i++) {
      await fix(i * 2000, lat: 36.0002, speed: 1, speedAccuracy: .2);
    }
    expect(recorder.current!.phase, RunPhase.running);
  });

  test('turning OFF clears pending automatic pause but does not undo an existing pause', () async {
    recorder.autoPauseEnabled = true;
    await fix(0);
    await fix(5000);
    recorder.autoPauseEnabled = false;
    await fix(10000);
    await fix(15000);
    expect(recorder.current!.phase, RunPhase.running);
    recorder.autoPauseEnabled = true;
    await fix(16000);
    await fix(21000);
    await fix(26000);
    expect(recorder.current!.phase, RunPhase.paused);
    recorder.autoPauseEnabled = false;
    expect(recorder.current!.phase, RunPhase.paused);
    await recorder.resume();
    expect(recorder.current!.phase, RunPhase.running);
  });

  test('general settings remain compatible with old voice JSON and round-trip per account across restart', () async {
    final old = RunVoiceSettings.fromJson({
      'enabled': false,
      'ghostGapEnabled': true,
    });
    expect(old.autoPauseEnabled, false);
    expect(old.keepScreenOn, false);
    final directory = await Directory.systemTemp.createTemp('run-settings-');
    final path = '${directory.path}/runs.db';
    final first = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final settings = old.copyWith(autoPauseEnabled: true, keepScreenOn: true);
    await first.saveVoiceSettings('alice', settings);
    await first.close();
    final reopened = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    try {
      expect(
        (await reopened.voiceSettings('alice')).toJson(),
        settings.toJson(),
      );
      expect((await reopened.voiceSettings('bob')).autoPauseEnabled, false);
      expect((await reopened.voiceSettings('bob')).keepScreenOn, false);
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });
}
