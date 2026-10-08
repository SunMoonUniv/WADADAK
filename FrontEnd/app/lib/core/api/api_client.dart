import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_interceptor.dart';
import '../auth/token_storage.dart';
import '../config.dart';
import 'member_api_client.dart';

/// 서버가 돌려준 오류(ApiResult의 code · message) 또는 통신 실패.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status});

  /// 서버에 닿지 못했다(오프라인 · 시간 초과). 로그아웃할 이유가 아니다.
  static const network = 'NETWORK';

  final String code;
  final String message;
  final int? status;

  @override
  String toString() => 'ApiException($code, $message)';
}

BaseOptions _options() => BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    );

/// 토큰 없이 보내는 요청용: 로그인 · 가입 · 갱신 · 로그아웃, 그리고 갱신 후 재시도.
final publicDioProvider = Provider<Dio>((ref) => Dio(_options()));

/// 인증이 필요한 API용. 액세스 토큰을 붙이고, 401이면 갱신한 뒤 다시 보낸다.
final dioProvider = Provider<Dio>(
  (ref) => Dio(_options())
    ..interceptors.add(AuthInterceptor(
      storage: ref.watch(tokenStorageProvider),
      retryDio: ref.watch(publicDioProvider),
      refresh: (refreshToken) => ref.read(memberApiClientProvider).refresh(refreshToken),
      onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
    )),
);

/// 응답의 ApiResult에서 data를 꺼낸다. 실패는 [ApiException]으로 바꾼다.
Future<Object?> callApi(Future<Response<Object?>> Function() request) async {
  try {
    final body = (await request()).data;
    return body is Map ? body['data'] : null;
  } on DioException catch (e) {
    throw toApiException(e);
  }
}

ApiException toApiException(DioException e) {
  final response = e.response;
  final body = response?.data;
  if (body is Map && body['code'] is String) {
    return ApiException(body['code'] as String, body['message'] as String? ?? '', status: response?.statusCode);
  }
  if (response == null) {
    return const ApiException(ApiException.network, '네트워크에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.');
  }
  return ApiException('HTTP_${response.statusCode}', '잠시 후 다시 시도해 주세요.', status: response.statusCode);
}
