import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'run_controller_test.dart' show TestLocation, until;
import 'course_run_start_test.dart' show CourseApi;

class FreshLocation extends TestLocation {
  double latitude = 36;
  @override
  Future<Position> currentPosition({LocationSettings? settings}) async =>
      point(latitude);
}

class ReceiptApi extends CourseApi {
  final committed = <String, DateTime>{};
  final calls = <(String, String, DateTime)>[];
  bool loseFirstResponse = false;
  Future<void> Function()? onAck;
  @override
  Future<void> startCourse(String owner, String id, DateTime startedAt) async {
    calls.add((owner, id, startedAt));
    if (committed.containsKey(id) && committed[id] != startedAt) {
      throw const ApiException('RUN-003', 'conflict', status: 409);
    }
    committed[id] = startedAt;
    if (loseFirstResponse && calls.length == 1) {
      throw const ApiException(ApiException.network, 'lost acknowledgement');
    }
    await onAck?.call();
  }
}

class BrokenIntentStore extends RunLocalStore {
  BrokenIntentStore()
    : super(factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
  @override
  Future<void> saveCourseIntent(CourseStartIntent intent) async =>
      throw StateError('disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FreshLocation gps;
  late ReceiptApi api;
  late RunLocalStore store;
  late RunController c;
  String? member;
  String boot = 'boot-a';
  var lifecycle = AppLifecycleState.resumed;
  RunController build({Future<void> Function(Duration)? wait}) => RunController(
    store,
    gps,
    api,
    () async => member,
    nowMs: gps.nowMs,
    recoveryClock: () async => RunClockSample(gps.clock, boot),
    wait: wait ?? (_) async {},
    utcNow: () => gps.utc,
    lifecycleState: () => lifecycle,
    automaticTicks: false,
  );
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('course-start-recovery-');
    gps = FreshLocation();
    api = ReceiptApi();
    member = 'alice';
    boot = 'boot-a';
    lifecycle = AppLifecycleState.resumed;
    store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/runs.db',
    );
    c = build();
  });
  Future<void> close() async {
    await until(() => !c.syncing && !c.loadingHistory);
    await c.shutdown();
    c.dispose();
  }

  tearDown(() async {
    await close();
    for (final s in gps.streams) {
      await s.close();
    }
    await directory.delete(recursive: true);
  });
  Future<void> ready() async {
    c.selectCourse(const CourseSelection('course-1', 'test course'));
    await c.prepareStart();
    expect(c.courseStart, isNotNull);
  }

  Future<void> restart() async {
    await close();
    store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/runs.db',
    );
    c = build();
    await c.bindOwner();
  }

  test('lost acknowledgement retries the same durable id, time and clock even after moving away', () async {
    await ready();
    api.loseFirstResponse = true;
    await c.prepareStart();
    final pending = (await store.pendingCourseStarts('alice')).single;
    expect(c.recorder.active, false);
    gps.clock = 6000;
    gps.latitude = 36.001;
    await c.prepareStart();
    expect(c.recorder.active, true);
    expect(api.calls[1], api.calls[0]);
    expect(c.run!.id, pending.id);
    expect(c.run!.startedAt, pending.startedAt);
    expect(c.metrics.elapsedMs, 6000);
    expect(await store.pendingCourseStarts('alice'), isEmpty);
  });
  test(
    'a lost course start survives a process restart without a second attempt',
    () async {
      await ready();
      api.loseFirstResponse = true;
      await c.prepareStart();
      final original = api.calls.single;
      gps.clock = 6000;
      await restart();
      expect(c.courseStart!.intent, isNotNull);
      await c.prepareStart();
      expect(c.recorder.active, true);
      expect(api.calls.last, original);
      expect(c.metrics.elapsedMs, 6000);
      expect(await store.pendingCourseStarts('alice'), isEmpty);
    },
  );
  test('12 second acknowledgement delay is preserved and stale initial GPS is not recorded', () async {
    await ready();
    api.onAck = () async {
      gps.clock = 12000;
    };
    await c.prepareStart();
    expect(c.recorder.active, true);
    expect(c.metrics.elapsedMs, 12000);
    expect(c.run!.inputs.where((p) => p.kind == RunKind.gps), isEmpty);
    expect(c.run!.inputs.where((p) => p.kind == RunKind.gap), isNotEmpty);
    gps.clock = 13000;
    gps.streams.last.add(gps.point(36.00001));
    await until(() => c.run!.inputs.any((p) => p.kind == RunKind.gps));
    final point = c.run!.inputs.last;
    expect(
      point.measuredAt,
      c.run!.startedAt.add(Duration(milliseconds: point.elapsedMs)),
    );
    await c.pause();
    await c.end();
    expect(c.run!.checkpointMs, 13000);
  });
  test(
    'a fresh outside fix prevents a course start and creates no request',
    () async {
      await ready();
      gps.latitude = 36.001;
      await c.prepareStart();
      expect(c.recorder.active, false);
      expect(api.calls, isEmpty);
      expect(await store.pendingCourseStarts('alice'), isEmpty);
      expect(c.courseStart!.nearStart, false);
    },
  );
  test('moving outside during countdown prevents the start signal', () async {
    await close();
    c = build(
      wait: (_) async {
        gps.clock += 1000;
        gps.streams.last.add(gps.point(36.001));
        await Future<void>.delayed(Duration.zero);
      },
    );
    await ready();
    await c.prepareStart();
    expect(c.recorder.active, false);
    expect(api.calls, isEmpty);
  });
  for (final changedBoot in [false, true]) {
    test(
      'an expired or rebooted saved start is cancelled safely (reboot=$changedBoot)',
      () async {
        await ready();
        api.loseFirstResponse = true;
        await c.prepareStart();
        final id = api.calls.single.$2;
        gps.clock = changedBoot ? 6000 : 61000;
        if (changedBoot) boot = 'boot-b';
        await restart();
        expect(c.recorder.active, false);
        expect(c.courseStart, isNull);
        expect(await store.pendingCourseStarts('alice'), isEmpty);
        expect(await store.deletedIds('alice'), contains(id));
        expect(api.calls, hasLength(1));
      },
    );
  }
  test('intent storage failure sends no server start', () async {
    await close();
    store = BrokenIntentStore();
    c = build();
    await ready();
    await c.prepareStart();
    expect(api.calls, isEmpty);
    expect(c.recorder.active, false);
    expect(c.storageFault, true);
  });
  test('pending cancellation removes the durable request before allowing a fresh attempt', () async {
    await ready();
    api.loseFirstResponse = true;
    await c.prepareStart();
    final id = api.calls.single.$2;
    c.cancelCourseStart();
    await until(() => !c.preparing && c.courseStart == null);
    expect(await store.pendingCourseStarts('alice'), isEmpty);
    expect(await store.deletedIds('alice'), contains(id));
    await ready();
    expect(c.courseStart!.runId, isNot(id));
  });
  test('account change cancels the old request and cannot expose it to the new member', () async {
    await ready();
    api.loseFirstResponse = true;
    await c.prepareStart();
    final id = api.calls.single.$2;
    member = 'bob';
    await c.accountChanged();
    expect(c.currentOwner, 'bob');
    expect(c.courseStart, isNull);
    expect(await store.pendingCourseStarts('alice'), isEmpty);
    expect(await store.deletedIds('alice'), contains(id));
    expect(await store.pendingCourseStarts('bob'), isEmpty);
    expect(api.calls.every((r) => r.$1 == 'alice'), true);
  });
  test('acknowledgement in background stays pending and resumes with the original time', () async {
    await ready();
    api.onAck = () async {
      lifecycle = AppLifecycleState.paused;
    };
    await c.prepareStart();
    expect(c.recorder.active, false);
    expect(await store.pendingCourseStarts('alice'), hasLength(1));
    lifecycle = AppLifecycleState.resumed;
    api.onAck = null;
    gps.clock = 6000;
    await c.prepareStart();
    expect(c.recorder.active, true);
    expect(api.calls.last, api.calls.first);
    expect(c.metrics.elapsedMs, 6000);
  });
  test('version 4 migration adds pending course starts while preserving recorded inputs', () async {
    await c.prepareStart();
    await c.pause();
    await c.end();
    final old = c.run!;
    final db = await store.database;
    await db.execute('DROP TABLE course_start_intents');
    await db.execute('PRAGMA user_version=4');
    await restart();
    final saved = (await store.list('alice', id: old.id)).single;
    expect(
      saved.inputs.map((p) => p.toJson()),
      old.inputs.map((p) => p.toJson()),
    );
    expect(await store.pendingCourseStarts('alice'), isEmpty);
  });
}
