import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/data/free_ghost_api.dart';

import 'free_ghost_flow_test.dart' show preparation;
import 'ghost_recovery_support.dart';
import 'own_ghost_api_test.dart' show Server;

class WaitingServer extends Server {
  final gate = Completer<void>();
  RequestOptions? pending;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pending = options;
    await gate.future;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class WaitingDecoder extends FusedTransformer {
  final gate = Completer<dynamic>();
  int calls = 0;

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) {
    calls++;
    return gate.future;
  }
}

Future<Map<String, dynamic>> retry(
  WidgetTester tester,
  FreeGhostApi api,
) async {
  Map<String, dynamic>? result;
  Object? failure;
  var completed = false;
  final future = api
      .prepare('alice', sourceId)
      .then<void>(
        (value) {
          result = value;
          completed = true;
        },
        onError: (Object e, StackTrace _) {
          failure = e;
          completed = true;
        },
      );
  for (var i = 0; i < 20 && !completed; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(
    completed,
    true,
    reason: 'The new request must complete independently',
  );
  expect(failure, isNull);
  await future;
  return result!;
}

void main() {
  testWidgets(
    '15-second deadline cancels an unresponsive request and permits retry',
    (tester) async {
      final server = WaitingServer()
        ..data = preparation(version: 'GHOST_PLAYBACK_FREE_V2');
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = server;
      final api = FreeGhostApi(RunApiClient(dio));
      Object? failure;
      final pending = api
          .prepare('alice', sourceId)
          .then<void>(
            (_) => fail('An unresponsive request must not succeed'),
            onError: (Object e, StackTrace _) {
              failure = e;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 14999));
      expect(failure, isNull);
      expect(server.pending!.cancelToken!.isCancelled, false);
      await tester.pump(const Duration(milliseconds: 1));
      await pending;
      expect(failure, same(freeGhostPreparationTimeoutError));
      expect(server.pending!.cancelToken!.isCancelled, true);

      server.gate.complete();
      await tester.pump();
      final result = await retry(tester, api);
      expect((result['playback'] as Map)['eligible'], true);
      expect(server.pending!.cancelToken!.isCancelled, false);
      dio.close(force: true);
    },
  );

  testWidgets('download and stalled JSON decoding share one 15-second budget', (
    tester,
  ) async {
    final server = WaitingServer()
      ..data = preparation(version: 'GHOST_PLAYBACK_FREE_V2');
    final decoder = WaitingDecoder();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server
      ..transformer = decoder;
    final api = FreeGhostApi(RunApiClient(dio));
    Object? failure;
    final pending = api
        .prepare('alice', sourceId)
        .then<void>(
          (_) => fail('A stalled decoder must not succeed'),
          onError: (Object e, StackTrace _) {
            failure = e;
          },
        );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    server.gate.complete();
    await tester.pump();
    expect(decoder.calls, 1);
    expect(server.pending!.transformTimeout, const Duration(seconds: 15));
    expect(dio.options.transformTimeout, isNull);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(failure, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    await pending;
    expect(failure, same(freeGhostPreparationTimeoutError));
    expect(server.pending!.cancelToken!.isCancelled, true);

    decoder.gate.complete({
      'data': preparation(version: 'GHOST_PLAYBACK_FREE_V2'),
    });
    await tester.pump();
    dio.transformer = FusedTransformer.sync();
    final result = await retry(tester, api);
    expect((result['playback'] as Map)['version'], 'GHOST_PLAYBACK_FREE_V2');
    dio.close(force: true);
  });
}
