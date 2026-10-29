import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/data/free_ghost_api.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';

import 'ghost_recovery_support.dart';
import 'free_ghost_flow_test.dart' show preparation, approval;
import 'own_ghost_api_test.dart' show Server;

void main() {
  GhostStartIntent intent([String? version]) => GhostStartIntent(
    owner: 'alice',
    id: ghostId,
    startedAt: ghostEpoch,
    course: CourseSnapshot(
      sessionId: ghostId,
      route: ghostCourse().route,
      totalDistanceMeters: 1112,
      version: 1,
    ),
    sourceId: sourceId,
    sourceSeconds: 230,
    clock: ghostIntent().clock,
    referenceHash: 'a' * 64,
    playbackVersion: version,
  );
  test(
    'new requests explicitly negotiate V2 and reject a silent V1 downgrade',
    () async {
      final server = Server()
        ..data = preparation(version: 'GHOST_PLAYBACK_FREE_V2');
      final api = FreeGhostApi(
        RunApiClient(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
        ),
      );
      final result = await api.prepare('alice', sourceId);
      expect((result['playback'] as Map)['version'], 'GHOST_PLAYBACK_FREE_V2');
      expect(server.requests.single.queryParameters, {
        'playbackVersion': 'GHOST_PLAYBACK_FREE_V2',
      });
      expect(server.requests.single.extra['runOwner'], 'alice');
      server.data = preparation();
      await expectLater(api.prepare('alice', sourceId), throwsFormatException);
    },
  );
  test('V2 is durable and receipt cannot change its pinned matcher', () {
    final request = intent('GHOST_PLAYBACK_FREE_V2');
    final restored = GhostStartIntent.fromJson(request.toJson());
    expect(restored.freeGhostV2, true);
    expect(restored.request, request.request);
    expect(
      GhostRunContext.fromJson(
        GhostRunContext(restored, approval(restored)).toJson(),
      ).intent.freeGhostV2,
      true,
    );
    final changed = approval(restored);
    (changed['playback'] as Map)['version'] = 'GHOST_PLAYBACK_FREE_V1';
    expect(() => GhostRunContext(restored, changed), throwsFormatException);
  });
  test('legacy stored request without version remains V1', () {
    final old = intent().toJson()..remove('playbackVersion');
    final restored = GhostStartIntent.fromJson(old);
    expect(restored.playbackVersion, 'GHOST_PLAYBACK_FREE_V1');
    expect(restored.freeGhostV2, false);
    expect(
      GhostRunContext(restored, approval(restored)).intent.freeGhostV2,
      false,
    );
  });
  test('course and free matching versions cannot be mixed', () {
    final c = ghostIntent();
    expect(
      () => GhostStartIntent(
        owner: c.owner,
        id: c.id,
        startedAt: c.startedAt,
        course: c.course,
        sourceId: c.sourceId,
        sourceSeconds: c.sourceSeconds,
        clock: c.clock,
        playbackVersion: 'GHOST_PLAYBACK_FREE_V2',
      ),
      throwsFormatException,
    );
    expect(() => intent('GHOST_PLAYBACK_V1'), throwsFormatException);
  });
}
