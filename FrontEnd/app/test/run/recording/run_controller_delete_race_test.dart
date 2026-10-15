import 'package:wadadak/core/api/run_api_client.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'run_controller_test.dart' as fake;

class ReloadStore extends fake.FailingStore {
  bool hold = false;
  final captured = Completer<void>(), release = Completer<void>();
  @override
  Future<List<LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  }) async {
    final rows = await super.list(
      owner,
      summaryOnly: summaryOnly,
      pendingOnly: pendingOnly,
      unfinishedOnly: unfinishedOnly,
      id: id,
    );
    if (hold) {
      hold = false;
      captured.complete();
      await release.future;
    }
    return rows;
  }
}

class ReloadApi extends fake.TestApi {
  VoidCallback? onStatus;
  @override
  Future<Map<String, dynamic>> status(RunUpload run) async {
    onStatus?.call();
    return {'processing': 'PROCESSING'};
  }

  @override
  Future<void> delete(String owner, String id) async {}
}

typedef VoidCallback = void Function();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a cached local reload started before deletion never exposes the deleted record again', () async {
    sqfliteFfiInit();
    final store = ReloadStore(), gps = fake.TestLocation(), api = ReloadApi();
    final c = RunController(
      store,
      gps,
      api,
      () async => 'alice',
      automaticTicks: false,
      nowMs: gps.nowMs,
    );
    try {
      await c.bindOwner();
      await fake.until(() => !c.syncing && !c.loadingHistory);
      final r = c.recorder;
      await r.start('cached', 'alice', gps.utc);
      for (var i = 0; i <= 2; i++) {
        gps.clock = i * 1000;
        await r.gps(36 + i * .00005, 127, 3);
      }
      await r.pause();
      await r.end();
      await c.sync();
      expect(c.records.single.id, 'cached');
      var resurrected = false;
      c.addListener(() {
        if (c.deletedIds.contains('cached') &&
            c.records.any((r) => r.id == 'cached')) {
          resurrected = true;
        }
      });
      api.onStatus = () => store.hold = true;
      final syncing = c.sync();
      await store.captured.future;
      await c.deleteRecord('cached');
      expect(c.records, isEmpty);
      store.release.complete();
      await syncing;
      expect(resurrected, false);
      expect(c.records, isEmpty);
      expect(await store.list('alice'), isEmpty);
    } finally {
      if (!store.release.isCompleted) store.release.complete();
      await fake.until(() => !c.syncing && !c.loadingHistory);
      await c.shutdown();
      c.dispose();
    }
  });
}
