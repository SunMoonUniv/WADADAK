import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/data/own_ghost_api.dart';
import 'package:wadadak/features/run/data/public_ghost_api.dart';
import 'package:wadadak/features/run/domain/ghost_playback.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/domain/public_ghost.dart';

// Real HTTP to the local Postman simulation; no account data or auth required.
const simulation = String.fromEnvironment('GHOST_SIM_URL');

void main() {
  for (final size in [3600, 7200]) {
    test('own and public $size-sample responses prepare usable replays', () async {
      final container = ProviderContainer();
      final dio = container.read(publicDioProvider)
        ..options.baseUrl = simulation;
      addTearDown(() {
        dio.close(force: true);
        container.dispose();
      });
      var responseBytes = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (r, handler) {
            responseBytes = int.parse(
              r.headers.value(Headers.contentLengthHeader)!,
            );
            handler.next(r);
          },
        ),
      );
      // The mock's record name selects the fixture size while preserving API query contracts.
      final api = RunApiClient(dio);
      final watch = Stopwatch()..start();
      final own = await OwnGhostApi(api).playback(
        'owner',
        'synthetic-$size',
        course: const GhostCourseContext('course', 3),
      );
      expect(responseBytes, greaterThan(50 * 1024));
      expect(own.playback.eligible, isTrue);
      expect(own.playback.samples, hasLength(size + 1));
      expect(own.playback.at(size * 500).state, GhostPlaybackState.tracked);
      expect(own.playback.at(size * 1000).state, GhostPlaybackState.finished);
      final ownMs = watch.elapsedMilliseconds;
      watch.reset();
      final json = await PublicGhostApi(api)
          .prepare('owner', 'synthetic-$size', 'course', 'ALL');
      final public = PreparedPublicGhost('owner', json);
      expect(responseBytes, greaterThan(50 * 1024));
      expect(public.replay.playback.samples, hasLength(size + 1));
      expect(public.course.id, 'course');
      expect(public.seconds, size);
      expect(
        public.replay.playback.at(size * 1000).state,
        GhostPlaybackState.finished,
      );
      debugPrint(
        'GHOST_HTTP_BENCH samples=$size ownMs=$ownMs publicMs=${watch.elapsedMilliseconds} bytes=$responseBytes',
      );
    }, skip: simulation.isEmpty);
  }
  test(
    'own and public course detours hide and resume replay positions',
    () async {
      final container = ProviderContainer();
      final dio = container.read(publicDioProvider)
        ..options.baseUrl = simulation;
      addTearDown(() {
        dio.close(force: true);
        container.dispose();
      });
      final api = RunApiClient(dio);
      final own = await OwnGhostApi(api).playback(
        'owner',
        'course-detour',
        course: const GhostCourseContext('course', 3),
      );
      final public = PreparedPublicGhost(
        'owner',
        await PublicGhostApi(api)
            .prepare('owner', 'course-detour', 'course', 'ALL'),
      );
      for (final replay in [own.playback, public.replay.playback]) {
        expect(replay.eligible, isTrue);
        expect(replay.at(20000).coursePositionM, isNotNull);
        expect(replay.at(30000).state, GhostPlaybackState.unknown);
        expect(replay.at(30000).coursePositionM, isNull);
        expect(replay.at(48000).state, GhostPlaybackState.tracked);
        expect(replay.at(48000).coursePositionM, isNotNull);
      }
    },
    skip: simulation.isEmpty,
  );
  test('deleted own and public replays retain server rejection', () async {
    final container = ProviderContainer();
    final dio = container.read(publicDioProvider)..options.baseUrl = simulation;
    addTearDown(() {
      dio.close(force: true);
      container.dispose();
    });
    final api = RunApiClient(dio);
    final rejected = throwsA(
      isA<ApiException>().having((e) => e.status, 'status', 404),
    );
    await expectLater(OwnGhostApi(api).playback('owner', 'deleted'), rejected);
    await expectLater(
      PublicGhostApi(api).prepare('owner', 'deleted', 'course', 'ALL'),
      rejected,
    );
  }, skip: simulation.isEmpty);
}
