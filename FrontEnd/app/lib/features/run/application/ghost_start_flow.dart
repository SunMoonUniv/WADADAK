import '../../../core/api/api_client.dart';
import '../../../core/time/monotonic_clock.dart';
import '../data/run_local_store.dart';
import '../data/ghost_start_api.dart';
import '../domain/ghost_run.dart';
import 'run_recorder.dart';

/// A pending request is durable before POST; GET 404 never permits a new session ID.
class GhostStartFlow {
  GhostStartFlow(this.store, this.api, this.recorder, this.clock, this.owner);
  final RunLocalStore store;
  final GhostStartSource api;
  final RunRecorder recorder;
  final Future<RunClockSample> Function() clock;
  final Future<String?> Function() owner;
  bool _busy = false;
  Future<bool> begin(GhostStartIntent intent) async {
    if (_busy) throw StateError('고스트 시작을 확인하고 있어요.');
    _busy = true;
    try {
      if (await owner() != intent.owner) return false;
      await store.saveGhostIntent(intent);
      final response = await api.start(intent);
      if (await owner() != intent.owner) return false;
      final context = GhostRunContext(intent, response);
      final reading = await clock();
      final age = reading.since(intent.clock);
      final saved = age != null && age <= 60000 ? reading : intent.clock;
      await store.saveGhostApproval(context, checkpointClock: saved);
      if (await owner() != intent.owner) return false;
      return await recorder.startGhost(context, checkpointClock: saved);
    } finally {
      _busy = false;
    }
  }

  Future<bool> recover(String member) async {
    if (_busy || recorder.active || await owner() != member) return false;
    _busy = true;
    try {
      for (final pending in await store.pendingGhostStarts(member)) {
        if (await owner() != member) return false;
        final intent = pending.intent;
        var context = pending.context;
        if (context == null) {
          Map<String, dynamic> response;
          try {
            response = await api.receipt(member, intent.id);
          } on ApiException catch (e) {
            if (e.status != 404) rethrow;
            if (await owner() != member) return false;
            RunClockSample? reading;
            try {
              reading = await clock();
            } on Object {
              /* Cannot retry an untrusted old start. */
            }
            final age = reading?.since(pending.checkpointClock);
            if (age == null || age > 60000) {
              // Cancel by tombstone, including an older POST still in flight. Sync retries the server deletion.
              await store.deleteRecord(member, intent.id);
              return false;
            }
            response = await api.start(intent);
          }
          if (await owner() != member) return false;
          context = GhostRunContext(intent, response);
          await store.saveGhostApproval(
            context,
            checkpointClock: pending.checkpointClock,
          );
        }
        if (await owner() != member) return false;
        return await recorder.startGhost(
          context,
          recovering: true,
          checkpointClock: pending.checkpointClock,
        );
      }
      return false;
    } finally {
      _busy = false;
    }
  }
}
