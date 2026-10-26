import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/data/own_ghost_api.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';

import 'own_ghost_test_support.dart';

class Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object? data;
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        status == 200
            ? {'data': data}
            : {'code': 'RUN-002', 'message': 'missing'},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('uses existing Dio, API envelope, owner guard, period/sort and cursor contract', () async {
    final server = Server()..data = ownGhostFixture()['page'];
    final client = RunApiClient(
      Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    );
    final api = OwnGhostApi(client);
    final page = await api.candidates(
      'owner-a',
      fixtureCourse(),
      sort: OwnGhostSort.best,
      period: OwnGhostPeriod.week,
      cursor: 'opaque-cursor',
    );
    expect(page.content, hasLength(6));
    final request = server.requests.single;
    expect(request.path, '/api/v1/runs/ghost-candidates/own');
    expect(request.queryParameters, {
      'courseId': fixtureCourse().id,
      'courseVersion': 3,
      'sort': 'BEST',
      'period': 'WEEK',
      'cursor': 'opaque-cursor',
    });
    expect(request.extra['runOwner'], 'owner-a');
    expect(request.method, 'GET');
    server.data = replayJson(page.content.first);
    final selected = await api.playback('owner-a', page.content.first.id);
    expect(selected.sourceId, page.content.first.id);
    expect(server.requests.last.extra['runOwner'], 'owner-a');
    expect(
      server.requests.last.path,
      '/api/v1/runs/records/${selected.sourceId}/ghost-playback',
    );
    expect(server.requests.every((r) => r.method == 'GET'), isTrue);
  });

  test(
    '404 remains an ApiException instead of a successful empty replay',
    () async {
      final server = Server()..status = 404;
      final api = OwnGhostApi(
        RunApiClient(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
        ),
      );
      await expectLater(
        api.playback('owner-a', 'deleted'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    },
  );
}
