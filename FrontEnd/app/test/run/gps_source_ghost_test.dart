import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/ghost_playback.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/public_ghost.dart';

import 'ghost_recovery_support.dart';

const registeredVersion = 'GHOST_PLAYBACK_GPS_SOURCE_V1';

GhostStartIntent registeredIntent() {
  final old = ghostIntent();
  return GhostStartIntent(
    owner: old.owner,
    id: old.id,
    startedAt: old.startedAt,
    course: old.course,
    sourceId: old.sourceId,
    sourceSeconds: old.sourceSeconds,
    clock: old.clock,
    playbackVersion: registeredVersion,
  );
}

Map<String, dynamic> registeredApproval(GhostStartIntent intent) {
  final response = ghostApproval(intent);
  (response['playback'] as Map)['version'] = registeredVersion;
  return response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('full-session registration source replay is supported without changing its duration', () {
    final intent = registeredIntent();
    final replay = GhostPlayback.fromJson(
      (registeredApproval(intent)['playback'] as Map).cast<String, dynamic>(),
    );
    expect(replay.supported, true);
    expect(replay.durationMs, 230000);
    expect(replay.at(225000).state, GhostPlaybackState.tracked);
    expect(replay.at(230000).state, GhostPlaybackState.finished);
  });

  test('a private source version is pinned through request and approval and cannot be downgraded', () {
    final intent = registeredIntent();
    final restored = GhostStartIntent.fromJson(intent.toJson());
    expect(restored.request['playbackVersion'], registeredVersion);
    final context = GhostRunContext(restored, registeredApproval(restored));
    expect(
      GhostRunContext.fromJson(context.toJson()).replay.playback.version,
      registeredVersion,
    );
    expect(
      () => GhostRunContext(restored, ghostApproval(restored)),
      throwsFormatException,
    );
  });

  test('public source keeps the same period and original full-session comparison time', () {
    final request = registeredIntent();
    final payload = registeredApproval(request);
    final prepared = PreparedPublicGhost('another-runner', {
      'publicPeriod': 'WEEK',
      'candidate': {
        'rank': 2,
        'runRecordId': sourceId,
        'courseElapsedSeconds': 230,
      },
      'playback': payload['playback'],
    });
    expect(prepared.publicPeriod, 'WEEK');
    expect(prepared.seconds, 230);
    expect(prepared.replay.playback.version, registeredVersion);
  });

  test(
    'SQLite close and reopen retain the exact source version and receipt',
    () async {
      final dir = await Directory.systemTemp.createTemp('gps-source-ghost-');
      final path = '${dir.path}/run.db';
      RunLocalStore open() =>
          RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
      var store = open();
      try {
        final request = registeredIntent();
        await store.saveGhostIntent(request);
        await store.saveGhostApproval(
          GhostRunContext(request, registeredApproval(request)),
        );
        await store.close();
        store = open();
        final pending = await store.pendingGhostStarts(request.owner);
        expect(pending.single.intent.playbackVersion, registeredVersion);
        expect(
          pending.single.context!.replay.playback.version,
          registeredVersion,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
