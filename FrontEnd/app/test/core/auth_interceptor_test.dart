import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/auth/auth_interceptor.dart';
import 'package:wadadak/core/auth/token_storage.dart';

import '../fakes.dart';

/// 유효한 액세스 토큰이면 200, 아니면 401을 주는 서버.
class _FakeServer implements HttpClientAdapter {
  String validAccess = 'A2';
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final authorization = options.headers['Authorization'];
    requests.add('${options.path} $authorization');
    final ok = authorization == 'Bearer $validAccess';
    final body = ok
        ? {'result': 'SUCCESS', 'data': 'ok'}
        : {'result': 'ERROR', 'code': 'COMMON-002', 'message': '인증이 필요합니다.'};
    return ResponseBody.fromString(jsonEncode(body), ok ? 200 : 401, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeServer server;
  late MemoryTokenStorage storage;
  late int refreshCalls;
  late bool sessionExpired;

  Dio dio({Future<AuthTokens> Function(String refreshToken)? refresh}) {
    Dio plain() => Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server;
    return plain()
      ..interceptors.add(AuthInterceptor(
        storage: storage,
        retryDio: plain(),
        refresh: refresh ??
            (refreshToken) async {
              refreshCalls++;
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return const AuthTokens(accessToken: 'A2', refreshToken: 'R2');
            },
        onSessionExpired: () => sessionExpired = true,
      ));
  }

  setUp(() {
    server = _FakeServer();
    storage = MemoryTokenStorage(const AuthTokens(accessToken: 'A1', refreshToken: 'R1'));
    refreshCalls = 0;
    sessionExpired = false;
  });

  test('attaches the stored access token', () async {
    storage.tokens = const AuthTokens(accessToken: 'A2', refreshToken: 'R1');

    await dio().get<Object?>('/x');

    expect(server.requests, ['/x Bearer A2']);
    expect(refreshCalls, 0);
  });

  test('refreshes once on 401 and retries with the new token', () async {
    final response = await dio().get<Object?>('/x');

    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
    expect(server.requests, ['/x Bearer A1', '/x Bearer A2']);
    expect(storage.tokens?.refreshToken, 'R2');
  });

  test('refreshes only once when several requests get 401 together', () async {
    final client = dio();

    final responses = await Future.wait([client.get<Object?>('/a'), client.get<Object?>('/b'), client.get<Object?>('/c')]);

    expect(responses.map((r) => r.statusCode), [200, 200, 200]);
    expect(refreshCalls, 1);
  });

  test('logs out when the refresh token has expired', () async {
    final client = dio(refresh: (_) async => throw const ApiException('MEMBER-004', '로그인이 만료되었습니다.'));

    await expectLater(client.get<Object?>('/x'), throwsA(isA<DioException>()));

    expect(sessionExpired, isTrue);
    expect(storage.tokens, isNull);
  });

  test('keeps the session when the refresh fails because of the network', () async {
    final client = dio(refresh: (_) async => throw const ApiException(ApiException.network, '네트워크'));

    await expectLater(client.get<Object?>('/x'), throwsA(isA<DioException>()));

    expect(sessionExpired, isFalse);
    expect(storage.tokens?.refreshToken, 'R1');
  });
}
