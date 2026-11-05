import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notification_api_client.dart';
import '../config.dart';

/// 서버가 보낸 알림 한 개. FCM의 `notification`(제목 · 본문)과 `data`(값은 모두 문자열)다.
class PushNotice {
  const PushNotice({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, String> data;

  /// 누르면 열 B1 코스 ID([courseIdOf]).
  String? get courseId => courseIdOf(data);

  /// 알림함의 그 알림 ID. 눌러 열면 읽음으로 바꾼다. 알림함 전에 보낸 푸시에는 없다.
  String? get notificationId => data['notificationId'];
}

/// 알림(푸시 · 알림함)을 누르면 열 B1 코스 ID. 서버 `NotificationKind`가 `type`, 코스 ID가 `courseId`다.
/// 모르는 종류(나중에 늘어난 알림)면 없다. 그때는 아무 화면도 열지 않는다.
String? courseIdOf(Map<String, String> data) => data['type'] == 'COURSE_EXPIRING_SOON' ? data['courseId'] : null;

/// 푸시 받기 · 토큰. Firebase를 감싸 테스트에서 가짜로 바꿔 끼운다.
abstract interface class PushMessaging {
  /// 이 기기의 FCM 토큰. 받지 못하면(구글 플레이 서비스 없음 등) 없다.
  Future<String?> token();

  /// 토큰이 바뀌었다(앱 데이터 삭제 · 복원 등).
  Stream<String> get tokenRefreshes;

  /// 이 기기의 토큰을 버린다. 서버에 남은 토큰으로 보내도 기기에 가지 않는다.
  Future<void> deleteToken();

  /// 알림 표시 권한을 아직 묻지 않았으면 묻는다(Android 13 이상 · iOS). 이미 정했으면 묻지 않는다.
  Future<void> requestPermissionOnce();

  /// 꺼져 있던 앱을 알림을 눌러 열었다.
  Future<PushNotice?> openedAtLaunch();

  /// 뒤에 있던 앱을 알림을 눌러 열었다.
  Stream<PushNotice> get opened;

  /// 앱을 보고 있을 때 온 알림. 휴대폰이 알림 창에 띄우지 않아 앱이 안내한다.
  Stream<PushNotice> get foreground;
}

/// Firebase에 연결한다(값은 config.dart). 연결이 실패해도 앱은 뜬다(푸시만 꺼진다).
Future<PushMessaging?> initPush() async {
  // iOS는 APNs 연결 전이라 켜지 않는다(config.dart)
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: firebaseApiKey,
        appId: firebaseAppId,
        messagingSenderId: firebaseSenderId,
        projectId: firebaseProjectId,
      ),
    );
    return _FirebasePushMessaging(FirebaseMessaging.instance);
  } catch (e) {
    debugPrint('Firebase 연결 실패, 푸시를 끈다: $e');
    return null;
  }
}

/// 등록 토큰 방식(getToken · onTokenRefresh · deleteToken)을 쓴다. firebase_messaging 17은 설치 ID(FID) 방식
/// (register · onRegistered)을 권하지만, 서버(FcmPushSender)는 FCM v1의 `message.token`에 등록 토큰을 넣어 보낸다.
/// 서버와 함께 바꾸기 전까지 이 방식을 유지한다.
// ignore_for_file: deprecated_member_use
class _FirebasePushMessaging implements PushMessaging {
  _FirebasePushMessaging(this._fcm);

  final FirebaseMessaging _fcm;

  static PushNotice _notice(RemoteMessage m) => PushNotice(
    title: m.notification?.title,
    body: m.notification?.body,
    data: m.data.map((k, v) => MapEntry(k, '$v')),
  );

  @override
  Future<String?> token() => _fcm.getToken();

  @override
  Stream<String> get tokenRefreshes => _fcm.onTokenRefresh;

  @override
  Future<void> deleteToken() => _fcm.deleteToken();

  @override
  Future<void> requestPermissionOnce() async {
    final settings = await _fcm.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) await _fcm.requestPermission();
  }

  @override
  Future<PushNotice?> openedAtLaunch() async {
    final m = await _fcm.getInitialMessage();
    return m == null ? null : _notice(m);
  }

  @override
  Stream<PushNotice> get opened => FirebaseMessaging.onMessageOpenedApp.map(_notice);

  @override
  Stream<PushNotice> get foreground => FirebaseMessaging.onMessage.map(_notice);
}

/// main에서 [initPush] 결과로 바꿔 끼운다. 없으면(기본) 푸시가 꺼진 것이다.
final pushMessagingProvider = Provider<PushMessaging?>((_) => null);

/// 기기 토큰을 서버에 등록하고 지운다. 푸시가 꺼져 있으면 아무것도 하지 않는다.
///
/// - 로그인하면(앱을 열 때 포함) 등록한다. 토큰이 바뀌면 다시 등록한다.
/// - 로그아웃하기 전에 서버에서 지우고 기기 토큰도 버린다. 서버 삭제가 실패해도 기기 토큰을 버려 더 오지 않는다.
/// - 실패는 던지지 않는다. 알림 때문에 로그인 · 로그아웃이 막히면 안 된다. 다음에 앱을 열 때 다시 등록한다.
class PushService {
  PushService(this._messaging, this._api);

  final PushMessaging? _messaging;
  final NotificationApiClient Function() _api;
  StreamSubscription<String>? _refreshes;

  bool get enabled => _messaging != null;

  /// 로그인했다.
  Future<void> register() async {
    final messaging = _messaging;
    if (messaging == null) return;
    _refreshes ??= messaging.tokenRefreshes.listen(_send);
    try {
      await messaging.requestPermissionOnce();
    } catch (e) {
      debugPrint('알림 권한 요청 실패: $e');
    }
    try {
      final token = await messaging.token();
      if (token != null) await _send(token);
    } catch (e) {
      debugPrint('FCM 토큰을 받지 못함: $e');
    }
  }

  Future<void> _send(String token) async {
    try {
      await _api().registerToken(token, PushPlatform.android);
    } catch (e) {
      debugPrint('기기 토큰 등록 실패(다음에 앱을 열 때 다시): $e');
    }
  }

  /// 로그아웃 · 탈퇴하기 전. 로그인 토큰이 남아 있을 때 불러야 서버에서 지울 수 있다.
  /// 오프라인이면 오래 기다리지 않는다([timeout]).
  Future<void> unregister({Duration timeout = const Duration(seconds: 3)}) async {
    final messaging = _messaging;
    if (messaging == null) return;
    await _refreshes?.cancel();
    _refreshes = null;
    try {
      final token = await messaging.token().timeout(timeout);
      if (token != null) await _api().removeToken(token).timeout(timeout);
    } catch (e) {
      debugPrint('서버의 기기 토큰 삭제 실패: $e');
    }
    try {
      await messaging.deleteToken().timeout(timeout);
    } catch (e) {
      debugPrint('기기 토큰 버리기 실패: $e');
    }
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(pushMessagingProvider), () => ref.read(notificationApiClientProvider)),
);
