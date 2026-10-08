import 'package:dio/dio.dart';

import '../api/api_client.dart';
import 'token_storage.dart';

/// 요청에 액세스 토큰을 붙인다. 401이면 리프레시 토큰으로 갱신하고 원래 요청을 다시 보낸다.
///
/// 리프레시 토큰은 한 번만 쓸 수 있어서, 동시에 받은 401에도 갱신은 한 번만 한다.
/// [QueuedInterceptor]가 오류를 하나씩 처리하므로 뒤에 처리되는 요청은 이미 바뀐 토큰을 보고,
/// 갱신하지 않고 그 토큰으로 다시 보낸다.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.storage,
    required this.retryDio,
    required this.refresh,
    required this.onSessionExpired,
  });

  final TokenStorage storage;

  /// 다시 보낼 때 쓰는, 인터셉터가 없는 Dio. 같은 Dio로 다시 보내면 오류 큐에서 서로를 기다려 멈춘다.
  final Dio retryDio;
  final Future<AuthTokens> Function(String refreshToken) refresh;

  /// 리프레시 토큰도 만료됐을 때(MEMBER-004)만 부른다. 통신 오류로는 로그아웃하지 않는다.
  final void Function() onSessionExpired;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final tokens = await storage.read();
    if (tokens != null) options.headers['Authorization'] = _bearer(tokens);
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final current = await storage.read();
    if (err.response?.statusCode != 401 || current == null) {
      handler.next(err);
      return;
    }
    final options = err.requestOptions;
    try {
      var tokens = current;
      if (options.headers['Authorization'] == _bearer(current)) {
        tokens = await refresh(current.refreshToken);
        await storage.write(tokens);
      }
      options.headers['Authorization'] = _bearer(tokens);
      handler.resolve(await retryDio.fetch(options));
    } on ApiException catch (e) {
      if (e.code == 'MEMBER-004') {
        await storage.clear();
        onSessionExpired();
      }
      handler.next(err);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static String _bearer(AuthTokens tokens) => 'Bearer ${tokens.accessToken}';
}
