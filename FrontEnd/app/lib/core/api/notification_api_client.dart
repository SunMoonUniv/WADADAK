import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 서버의 기기 종류(`DevicePlatform`).
enum PushPlatform { android, ios }

/// 알림함의 알림 한 건(F3). 서버 `NotificationItem`.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.data = const {},
    required this.createdAt,
    required this.read,
  });

  factory NotificationItem.fromJson(Map<String, Object?> json) => NotificationItem(
    id: json['id']! as String,
    kind: json['kind']! as String,
    title: json['title']! as String,
    body: json['body']! as String,
    data: {for (final e in ((json['data'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    createdAt: DateTime.parse(json['createdAt']! as String),
    read: json['read']! as bool,
  );

  final String id;

  /// 서버 `NotificationKind`. 지금은 `COURSE_EXPIRING_SOON`뿐이다.
  final String kind;
  final String title;
  final String body;

  /// 누르면 열 화면 정보. 푸시의 `data`와 같다(값은 모두 문자열).
  final Map<String, String> data;
  final DateTime createdAt;
  final bool read;

  NotificationItem asRead() =>
      NotificationItem(id: id, kind: kind, title: title, body: body, data: data, createdAt: createdAt, read: true);
}

/// 알림함 한 쪽. 마지막 쪽이면 [nextCursor]가 null.
typedef NotificationPage = ({List<NotificationItem> items, String? nextCursor});

/// 알림 서버 API(F14 기기 토큰 · F4 알림 설정 · F3 알림함).
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

  /// 최근 30일 알림을 최신순으로 한 쪽씩 받는다. 처음 쪽은 [cursor] 없이.
  Future<NotificationPage> inbox({String? cursor, int size = 20}) async {
    final data = (await callApi(() => _dio.get(_base, queryParameters: {'cursor': ?cursor, 'size': size}))) as Map;
    return (
      items: [for (final e in data['content'] as List) NotificationItem.fromJson((e as Map).cast())],
      nextCursor: data['nextCursor'] as String?,
    );
  }

  /// 안 읽은 알림 수(최근 30일). A2 종 아이콘의 점과 F3 `읽지 않음 N`.
  Future<int> unreadCount() async =>
      (((await callApi(() => _dio.get('$_base/unread-count'))) as Map)['count'] as num).toInt();

  /// 한 건을 읽음으로. 이미 읽었거나 없는 알림이어도 성공이다.
  Future<void> markRead(String notificationId) =>
      callApi(() => _dio.put('$_base/${Uri.encodeComponent(notificationId)}/read'));

  /// 최근 30일 알림을 모두 읽음으로.
  Future<void> markAllRead() => callApi(() => _dio.put('$_base/read-all'));
}

final notificationApiClientProvider = Provider<NotificationApiClient>(
  (ref) => NotificationApiClient(ref.watch(dioProvider)),
);
