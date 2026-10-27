import '../../../core/api/run_api_client.dart';
import '../data/run_local_store.dart';
import '../domain/recording_models.dart';
import '../../../core/api/api_client.dart';

class RunSyncWorker {
  RunSyncWorker(this.api, this.store, this.owner, {this.canSync});
  final bool Function()? canSync;
  Future<bool> _allowed(String expected) async =>
      await owner() == expected && (canSync?.call() ?? true);
  final RunApiClient api;
  final RunStore store;
  final Future<String?> Function() owner;
  bool _busy = false;
  Future<bool> _zeroGhost(
    LocalRun run,
    String expectedOwner,
    Map<String, dynamic> state,
  ) async {
    if (run.ghost == null || state['failure'] != 'ZERO_DISTANCE') return false;
    final verdict = await api.ghostResult(expectedOwner, run.id);
    if (!await _allowed(expectedOwner) || await _deleted(expectedOwner, run.id)) {
      return true;
    }
    final result = <String, dynamic>{
      'id': run.id,
      'startedAt': run.startedAt.toUtc().toIso8601String(),
      'endReason': run.endReason,
      'ghost': verdict,
      'routeSegments': <Object>[],
      'metrics':
          run.summary?['metrics'] ??
          {
            'distanceM': 0.0,
            'elapsedMs': run.checkpointMs,
            'activeMs': 0,
            'gapCount': 0,
          },
      'laps': <Object>[],
    };
    await store.synced(run, result);
    return true;
  }

  Future<bool> _deleted(String expectedOwner, String id) async =>
      store is RunHistoryStore &&
      (await (store as RunHistoryStore).deletedIds(expectedOwner)).contains(id);
  Future<void> _deletions(String expectedOwner) async {
    if (store is! RunHistoryStore) return;
    final history = store as RunHistoryStore;
    for (final id in await history.pendingDeletions(expectedOwner)) {
      if (!await _allowed(expectedOwner)) return;
      await api.delete(expectedOwner, id);
      if (!await _allowed(expectedOwner)) return;
      await history.deletionSynced(expectedOwner, id);
    }
  }

  Future<void> sync(String expectedOwner, {bool retryBlocked = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _allowed(expectedOwner)) return;
      if (store is RunGhostStore) {
        final ghosts = store as RunGhostStore;
        for (final id in await ghosts.pendingGhostClosures(expectedOwner)) {
          if (!await _allowed(expectedOwner)) return;
          if (await _deleted(expectedOwner, id)) continue;
          await api.segmentEnd(expectedOwner, id);
          if (!await _allowed(expectedOwner)) return;
          await ghosts.ghostClosureSynced(expectedOwner, id);
        }
      }
      await _deletions(expectedOwner);
      for (final run in await store.list(expectedOwner, pendingOnly: true)) {
        if (!await _allowed(expectedOwner)) return;
        final upload = RunUpload(
          id: run.id,
          owner: run.owner,
          startedAt: run.startedAt,
          inputs: run.inputs.map((p) => p.toJson()).toList(),
        );
        if (await _deleted(expectedOwner, run.id)) continue;
        if (!run.pending || run.phase != RunPhase.ended) continue;
        if (run.syncState == 'blocked' && !retryBlocked) continue;
        if (!await _allowed(expectedOwner)) return;
        try {
          if (!await _allowed(expectedOwner)) return;
          var state = await api.prepare(upload);
          if (await _deleted(expectedOwner, run.id)) continue;
          if (state['processing'] == 'FAILED') {
            if (await _zeroGhost(run, expectedOwner, state)) continue;
            await store.syncStatus(
              run,
              'blocked',
              failure: '${state['failure']}',
            );
            continue;
          }
          if (state['processing'] == 'PREPARED' ||
              state['processing'] == 'NEEDS_DATA') {
            await store.syncStatus(run, 'uploading');
            for (var i = 0; i < run.inputs.length; i += 500) {
              if (!await _allowed(expectedOwner)) return;
              if (await _deleted(expectedOwner, run.id)) break;
              if (!await _allowed(expectedOwner)) return;
              state = await api.upload(
                upload,
                upload.inputs.sublist(i, (i + 500).clamp(0, run.inputs.length)),
              );
            }
          }
          if (!await _allowed(expectedOwner)) return;
          if (await _deleted(expectedOwner, run.id)) continue;
          state = await api.status(upload);
          if (state['processing'] == 'FAILED') {
            if (await _zeroGhost(run, expectedOwner, state)) continue;
            await store.syncStatus(
              run,
              'blocked',
              failure: '${state['failure']}',
            );
            continue;
          }
          if (state['processing'] == 'DONE') {
            if (!await _allowed(expectedOwner)) return;
            final result = await api.result(expectedOwner, run.id);
            if (await owner() != expectedOwner ||
                await _deleted(expectedOwner, run.id)) {
              continue;
            }
            await store.synced(run, result);
          } else {
            await store.syncStatus(
              run,
              state['processing'] == 'PROCESSING' ? 'processing' : 'pending',
            );
          }
        } on ApiException catch (e) {
          if (e.status != null &&
              e.status! >= 400 &&
              e.status! < 500 &&
              e.status != 401 &&
              e.status != 429) {
            await store.syncStatus(run, 'blocked', failure: e.message);
            continue;
          }
          await store.syncStatus(run, 'pending');
          rethrow;
        }
      }
    } finally {
      try {
        if (await _allowed(expectedOwner)) await _deletions(expectedOwner);
      } finally {
        _busy = false;
      }
    }
  }
}
