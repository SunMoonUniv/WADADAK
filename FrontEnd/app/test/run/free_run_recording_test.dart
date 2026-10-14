import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/run_models.dart';

import 'recording/run_controller_test.dart' as fake;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('existing running UI receives GPS distance, automatic resume and saved results', () async {
    sqfliteFfiInit();
    final store = fake.FailingStore();
    final location = fake.TestLocation();
    final driver = RunController(
      store,
      location,
      fake.TestApi(),
      () async => 'alice',
      wait: (_) async {},
      utcNow: () => location.utc,
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
    final controller = FreeRunController.recording(driver);
    try {
      controller.prepareStart();
      await fake.until(
        () =>
            controller.snapshot.state == RunState.running &&
            !controller.preparing,
      );
      expect(controller.snapshot.hasLocation, true);
      expect(controller.snapshot.gpsStatus, '위치 수신 중');
      location.clock = 1000;
      location.streams.single.add(location.point(36.00005));
      await fake.until(
        () => controller.snapshot.elapsed.inMilliseconds == 1000,
      );
      expect(controller.snapshot.distanceMeters, 0);
      location.clock = 2000;
      location.streams.single.add(location.point(36.0001));
      await fake.until(
        () => controller.snapshot.elapsed.inMilliseconds == 2000,
      );
      expect(controller.snapshot.distanceMeters, closeTo(11.119508, .00001));
      controller.pause();
      await fake.until(() => controller.snapshot.state == RunState.paused);
      for (var step = 0; step < 3; step++) {
        location.clock = 3000 + step * 1000;
        location.streams.single.add(location.point(36.01 + step * .00005));
        await fake.until(
          () => controller.snapshot.elapsed.inMilliseconds == location.clock,
        );
      }
      expect(controller.snapshot.state, RunState.running);
      expect(controller.snapshot.distanceMeters, closeTo(11.119508, .00001));
      location.clock = 6000;
      location.streams.single.add(location.point(36.01015));
      await fake.until(
        () => controller.snapshot.elapsed.inMilliseconds == 6000,
      );
      location.clock = 7000;
      location.streams.single.add(location.point(36.01020));
      await fake.until(
        () => controller.snapshot.elapsed.inMilliseconds == 7000,
      );
      expect(controller.snapshot.distanceMeters, closeTo(22.239016, .00001));
      controller.pause();
      await fake.until(() => controller.snapshot.state == RunState.paused);
      controller.setEndConfirmation(true);
      await controller.finish();
      controller.setEndConfirmation(false);
      expect(controller.snapshot.state, RunState.finished);
      expect(controller.snapshot.storageStatus, '기기 저장');
      expect(controller.snapshot.segments.length, 2);
      expect((await store.list('alice')).single.pending, true);
      controller.newRun();
      expect(controller.snapshot.state, RunState.ready);
      expect(controller.recent!.distanceMeters, closeTo(22.239016, .00001));
    } finally {
      controller.dispose();
      await fake.until(() => !driver.syncing && !driver.loadingHistory);
      await driver.shutdown();
      driver.dispose();
      for (final stream in location.streams) {
        await stream.close();
      }
    }
  });
}
