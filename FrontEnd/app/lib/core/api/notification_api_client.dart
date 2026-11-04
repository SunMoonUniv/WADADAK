import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 서버의 기기 종류(`DevicePlatform`).
enum PushPlatform { android, ios }

/// 알림 서버 API(F14 기기 토큰 · F4 알림 설정).
class NotificationApiClient {
  NotificationApiClient(this._dio);

  final Dio _dio;

  static const _base = '/api/v1/notifications';

  /// 이 기기의 FCM 토큰을 내 기기로 등록한다. 같은 토큰을 다시 보내도 된다(등록 시각만 바뀐다).
  Future<void> registerToken(String token, PushPlatform platform) => callApi(
    () => _dio.put('$_base/tokens', data: {'token': token, 'platform': platform.name.toUpperCase()}),
  );

  /// 로그아웃 전에 보낸다. 이 기기에는 더 알림을 보내지 않는다. 토큰은 주소에 남지 않게 본문으로 보낸다.
  Future<void> removeToken(String token) => callApi(() => _dio.delete('$_base/tokens', data: {'token': token}));

  /// `내 코스 만료 임박`이 켜져 있는가. 한 번도 바꾸지 않았으면 켜져 있다.
  Future<bool> courseExpiringSoon() async =>
      ((await callApi(() => _dio.get('$_base/settings'))) as Map)['courseExpiringSoon'] as bool;

  /// 바꾸는 즉시 저장하고 저장된 값을 돌려준다.
  Future<bool> changeCourseExpiringSoon(bool on) async =>
      ((await callApi(() => _dio.put('$_base/settings', data: {'courseExpiringSoon': on}))) as Map)['courseExpiringSoon']
          as bool;
}

final notificationApiClientProvider = Provider<NotificationApiClient>(
  (ref) => NotificationApiClient(ref.watch(dioProvider)),
);
