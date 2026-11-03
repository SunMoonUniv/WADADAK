import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_screen_awake.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/run_settings_events.dart';

import 'recording/run_controller_test.dart' as fake;

class Screen extends RunScreenAwake {
  final values = <bool>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) await gate?.future;
    if (enabled && fail) throw StateError('screen unavailable');
    values.add(enabled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late fake.FailingStore store;
  late fake.TestLocation location;
  late RunController runs;
  late Screen screen;
  String? owner;
  setUp(() {
    owner = 'alice';
    store = fake.FailingStore();
    location = fake.TestLocation();
    screen = Screen();
    runs = RunController(
      store,
      location,
      fake.TestApi(),
      () async => owner,
      screenAwake: screen,
      automaticTicks: false,
      nowMs: location.nowMs,
      utcNow: () => location.utc,
      wait: (_) async {},
      lifecycleState: () => AppLifecycleState.resumed,
    );
  });
  tearDown(() async {
    await fake.until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });

  test('screen option applies only to an active foreground session, including pause, and releases on finish', () async {
    await runs.bindOwner();
    await runs.receiveSettings(
      const RunSettingsChanged(owner: 'alice', keepScreenOn: true),
    );
    expect(screen.values.last, false);
    await runs.prepareStart();
    await fake.until(() => screen.values.last);
    await runs.pause();
    expect(screen.values.last, true);
    runs.didChangeAppLifecycleState(AppLifecycleState.paused);
    await fake.until(() => !screen.values.last);
    runs.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await fake.until(() => screen.values.last);
    await runs.receiveSettings(
      const RunSettingsChanged(owner: 'alice', keepScreenOn: false),
    );
    expect(screen.values.last, false);
    await runs.receiveSettings(
      const RunSettingsChanged(owner: 'alice', keepScreenOn: true),
    );
    expect(screen.values.last, true);
    await runs.end();
    await fake.until(() => !screen.values.last);
  });

  test(
    'sign out releases screen and another account restores default OFF',
    () async {
      await runs.bindOwner();
      await runs.receiveSettings(
        const RunSettingsChanged(
          owner: 'alice',
          keepScreenOn: true,
          autoPauseEnabled: true,
        ),
      );
      await runs.prepareStart();
      await fake.until(() => screen.values.last);
      owner = 'bob';
      await runs.bindOwner();
      expect(screen.values.last, false);
      expect(runs.settings.keepScreenOn, false);
      expect(runs.settings.autoPauseEnabled, false);
    },
  );

  test(
    'late enable request cannot leave screen awake after backgrounding',
    () async {
      await runs.bindOwner();
      await runs.prepareStart();
      screen.gate = Completer<void>();
      final pending = runs.receiveSettings(
        const RunSettingsChanged(owner: 'alice', keepScreenOn: true),
      );
      await fake.until(() => runs.settings.keepScreenOn);
      runs.didChangeAppLifecycleState(AppLifecycleState.paused);
      screen.gate!.complete();
      await pending;
      await fake.until(() => !screen.values.last);
    },
  );

  test(
    'screen failure cannot stop recording or lose the saved preference',
    () async {
      await runs.bindOwner();
      await runs.prepareStart();
      screen.fail = true;
      await runs.receiveSettings(
        const RunSettingsChanged(owner: 'alice', keepScreenOn: true),
      );
      expect(runs.run!.phase, RunPhase.running);
      expect(runs.screenNotice, isNotNull);
      expect((await store.voiceSettings('alice')).keepScreenOn, true);
      screen.fail = false;
    },
  );

  test('settings event activates automatic pause in the real GPS controller flow without dropping tracking', () async {
    await runs.bindOwner();
    await runs.receiveSettings(
      const RunSettingsChanged(
        owner: 'alice',
        autoPauseEnabled: true,
        keepScreenOn: true,
      ),
    );
    await runs.prepareStart();
    for (final ms in [1000, 6000, 11000]) {
      location.clock = ms;
      final count = runs.run!.inputs.length;
      location.streams.last.add(location.point(36));
      await fake.until(() => runs.run!.inputs.length > count);
      await runs.refreshMeasurement();
    }
    await fake.until(() => runs.run!.phase == RunPhase.paused);
    expect(location.streams.last.hasListener, true);
    expect(screen.values.last, true);
    location.clock = 15000;
    await runs.refreshMeasurement();
    expect(runs.metrics.elapsedMs, 15000);
    expect(runs.metrics.activeMs, 11000);
  });

  test(
    'screen platform adapter sends only the requested foreground flag',
    () async {
      const channel = MethodChannel('test/run_screen');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final output = RunScreenAwake(channel: channel, supported: true);
      await output.setEnabled(true);
      await output.close();
      expect(calls.map((call) => call.method), [
        'setKeepScreenOn',
        'setKeepScreenOn',
      ]);
      expect(calls.map((call) => (call.arguments as Map)['enabled']), [
        true,
        false,
      ]);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
