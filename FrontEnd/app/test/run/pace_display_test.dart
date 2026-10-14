import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/domain/run_models.dart';

import 'recording/run_controller_test.dart' as fake;
import 'motion_pace_test.dart' as motion;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pace is held between 3-second refreshes while time and GPS still advance',
    () async {
      sqfliteFfiInit();
      final store = fake.FailingStore(), location = fake.TestLocation();
      final driver = RunController(
        store,
        location,
        fake.TestApi(),
        () async => 'alice',
        automaticTicks: false,
        utcNow: () => location.utc,
        lifecycleState: () => AppLifecycleState.resumed,
      );
      final ui = FreeRunController.recording(driver);
      try {
        await driver.bindOwner();
        await driver.recorder.start('pace', 'alice', location.utc);
        for (var i = 0; i <= 10; i++) {
          location.clock = i * 1000;
          final p = motion.fix(location.clock, i * 3);
          await driver.recorder.gps(
            p.lat!,
            p.lng!,
            3,
            speedMps: 3,
            speedAccuracyMps: .1,
          );
          ui.snapshot;
        }
        location.clock = 12000;
        await driver.recorder.tick();
        final at12 = ui.snapshot;
        expect(at12.paceSecondsPerKm, isNotNull);
        expect(at12.currentPaceDisplay, 335);
        location.clock = 13000;
        await driver.recorder.tick();
        expect(ui.snapshot.elapsed.inMilliseconds, 13000);
        expect(ui.snapshot.paceSecondsPerKm, at12.paceSecondsPerKm);
        location.clock = 14999;
        await driver.recorder.tick();
        expect(ui.snapshot.paceSecondsPerKm, at12.paceSecondsPerKm);
        location.clock = 15000;
        await driver.recorder.tick();
        expect(
          ui.snapshot.paceSecondsPerKm,
          greaterThan(at12.paceSecondsPerKm!),
        );
        await driver.pause();
        final paused = ui.snapshot;
        expect(paused.state, RunState.paused);
        expect(paused.currentPaceDisplay, isNull);
        location.clock = 25000;
        await driver.recorder.tick();
        expect(ui.snapshot.paceSecondsPerKm, paused.paceSecondsPerKm);
        expect(
          ui.snapshot.elapsedPaceSecondsPerKm,
          greaterThan(paused.elapsedPaceSecondsPerKm!),
        );
        await driver.end();
        expect(ui.snapshot.state, RunState.finished);
        expect(ui.snapshot.paceSecondsPerKm, driver.metrics.paceSecondsPerKm);
      } finally {
        ui.dispose();
        await fake.until(() => !driver.syncing && !driver.loadingHistory);
        await driver.shutdown();
        driver.dispose();
      }
    },
  );
  test('GPS status changes clear current pace immediately between display refreshes', () async {
    sqfliteFfiInit();
    final store = fake.FailingStore(), location = fake.TestLocation();
    final driver = RunController(
      store,
      location,
      fake.TestApi(),
      () async => 'alice',
      automaticTicks: false,
    );
    final ui = FreeRunController.recording(driver);
    try {
      await driver.bindOwner();
      await driver.recorder.start('gps', 'alice', location.utc);
      for (var i = 0; i <= 10; i++) {
        location.clock = i * 1000;
        final p = motion.fix(location.clock, i * 3);
        await driver.recorder.gps(p.lat!, p.lng!, 3);
        ui.snapshot;
      }
      expect(ui.snapshot.currentPaceDisplay, isNotNull);
      driver.gpsNotice = '신호 확인 중';
      expect(ui.snapshot.currentPaceDisplay, isNull);
    } finally {
      ui.dispose();
      await driver.shutdown();
      driver.dispose();
    }
  });
  test('v2 storage failure keeps confirmed distance and moving time at last durable input', () async {
    sqfliteFfiInit();
    final store = fake.FailingStore();
    var clock = 0;
    final recorder = RunRecorder(store, () async => clock);
    try {
      await recorder.start('durable', 'alice', DateTime.utc(2026));
      for (var i = 0; i <= 10; i++) {
        clock = i * 1000;
        final p = motion.fix(clock, i * 3);
        await recorder.gps(p.lat!, p.lng!, 3);
      }
      final before = recorder.metrics;
      store.failAppend = true;
      clock = 11000;
      await expectLater(
        recorder.gps(36.001, 127, 3),
        throwsA(isA<RunStorageFailure>()),
      );
      expect(recorder.metrics.distanceM, before.distanceM);
      expect(recorder.metrics.movingMs, before.movingMs);
      store.failAppend = false;
      final saved = (await store.list('alice')).single;
      expect(saved.checkpointMs, 10000);
    } finally {
      await recorder.close();
      await store.close();
    }
  });
}
