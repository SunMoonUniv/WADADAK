import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/course/create/run_course_source_api.dart';

/// 받은 요청을 남기고 [body]로 답하는 달리기 서버.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.body, {this.status = 200});

  final Object body;
  final int status;
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  RunCourseSourceApi api(_FakeServer server) =>
      RunCourseSourceApi(RunApiClient(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server));

  test('reads the segments of a run record in the order run', () async {
    final server = _FakeServer({
      'result': 'SUCCESS',
      'data': {
        'recordId': 'record-1',
        'distanceMeters': 1520.4,
        'segments': [
          [
            {'lat': 37.51, 'lng': 126.995, 'accuracyM': 5.0, 'altitudeM': 12.5, 'altitudeAccuracyM': 3.0},
            {'lat': 37.515, 'lng': 126.999, 'accuracyM': 6.0, 'altitudeM': null, 'altitudeAccuracyM': null},
          ],
          [
            {'lat': 37.516, 'lng': 127, 'accuracyM': null, 'altitudeM': null, 'altitudeAccuracyM': null},
          ],
        ],
      },
    });

    final segments = await api(server).segments('record/1');

    expect(server.request.method, 'GET');
    expect(server.request.path, '/api/v1/runs/records/record%2F1/course-source');
    expect(server.request.extra['runOwner'], isNull, reason: '로그인한 회원의 기록이면 된다');
    expect(segments.map((segment) => segment.length), [2, 1], reason: '조각 사이는 잇지 않는다');
    final first = segments.first.first;
    expect((first.lat, first.lng, first.accuracyM, first.altitudeM, first.altitudeAccuracyM),
        (37.51, 126.995, 5.0, 12.5, 3.0));
    expect(segments.last.single.lng, 127.0);
  });

  test('passes on the run server error of a missing record', () async {
    final server = _FakeServer({'code': 'RUN-002', 'message': '러닝 기록을 찾을 수 없어요.'}, status: 404);

    await expectLater(
      api(server).segments('record-9'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'RUN-002')),
    );
  });
}
