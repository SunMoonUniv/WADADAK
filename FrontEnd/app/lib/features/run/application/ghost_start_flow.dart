import '../../../core/api/api_client.dart';
import '../../../core/time/monotonic_clock.dart';
import '../data/run_local_store.dart';
import '../data/ghost_start_api.dart';
import '../domain/ghost_run.dart';
import 'run_recorder.dart';

/// The server definitively refused this attempt and its absence was confirmed before cancellation.
class GhostStartRejected implements Exception {
  const GhostStartRejected(this.owner, this.id, this.failure);
  final String owner, id;
  final ApiException failure;
  String get message => '사용할 수 없는 고스트입니다. 다른 기록을 선택해 주세요.';
}

/// A pending request is durable before POST; GET 404 alone never permits a new session ID.
class GhostStartFlow {
  GhostStartFlow(this.store, this.api, this.recorder, this.clock, this.owner);
  final RunLocalStore store;
  final GhostStartSource api;
  final RunRecorder recorder;
  final Future<RunClockSample> Function() clock;
  final Future<String?> Function() owner;
  bool _busy = false;
  static bool _definitive(ApiException error) =>
      switch ((error.code, error.status)) {
        ('RUN-001', 400) ||
        ('RUN-002', 404) ||
        ('RUN-003', 409) ||
        ('RUN-004', 409) ||
        ('COURSE-001', 404) ||
        ('COURSE-002', 409) => true,
        _ => false,
      };

  Future<Map<String, dynamic>> _post(GhostStartIntent intent) async {
    try {
      return await api.start(intent);
    } on ApiException catch (failure) {
      if (!_definitive(failure) || await owner() != intent.owner) rethrow;
      try {
        // An already committed receipt wins over a failed/late retry response.
        return await api.receipt(intent.owner, intent.id);
      } on ApiException catch (check) {
        if (check.code != 'RUN-002' ||
            check.status != 404 ||
            await owner() != intent.owner) {
          rethrow;
        }
        // Keep the cancellation durable: late uploads/approvals must not resurrect this ID.
        await store.deleteRecord(intent.owner, intent.id);
        throw GhostStartRejected(intent.owner, intent.id, failure);
      }
    }
  }

  Future<bool> begin(GhostStartIntent intent) async {
    if (_busy) throw StateError('고스트 시작을 확인하고 있어요.');
    _busy = true;
    try {
      if (await owner() != intent.owner) return false;
      await store.saveGhostIntent(intent);
      final response = await _post(intent);
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
            response = await _post(intent);
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
