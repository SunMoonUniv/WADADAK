import '../data/run_api_client.dart';
import '../data/run_local_store.dart';
import '../domain/recording_models.dart';
import '../../../core/api/api_client.dart';

class RunSyncWorker {
  RunSyncWorker(this.api, this.store, this.owner);
  final RunApiClient api;
  final RunStore store;
  final Future<String?> Function() owner;
  bool _busy = false;
  Future<void> sync(String expectedOwner, {bool retryBlocked = false}) async {
    if (_busy || await owner() != expectedOwner) return;
    _busy = true;
    try {
      for (final run in await store.list(expectedOwner)) {
        if (!run.pending || run.phase != RunPhase.ended) continue;
        if (run.syncState == 'blocked' && !retryBlocked) continue;
        if (await owner() != expectedOwner) return;
        try {
          var state = await api.prepare(run);
          if (state['processing'] == 'FAILED') {
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
              if (await owner() != expectedOwner) return;
              state = await api.upload(
                run,
                run.inputs.sublist(i, (i + 500).clamp(0, run.inputs.length)),
              );
            }
          }
          state = await api.status(run);
          if (state['processing'] == 'FAILED') {
            await store.syncStatus(
              run,
              'blocked',
              failure: '${state['failure']}',
            );
            continue;
          }
          if (state['processing'] == 'DONE') {
            if (await owner() != expectedOwner) return;
            final result = await api.result(expectedOwner, run.id);
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
      _busy = false;
    }
  }
}
