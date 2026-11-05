import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/notification_api_client.dart';
import 'core/auth/auth_controller.dart';
import 'core/push/push_service.dart';
import 'features/notification/notification_bell.dart';
import 'router.dart';
import 'routes.dart';

/// 푸시를 앱 화면에 잇는다(F14). `MaterialApp.router`의 builder로 앱 전체를 감싼다.
///
/// - 로그인하면(앱을 열 때 포함) 기기 토큰을 서버에 등록한다.
/// - 알림을 누르면 알림함의 그 알림을 읽음으로 바꾸고 B1 코스 상세를 지금 화면 위에 연다. 로그인 전이면 로그인한 뒤에 한다.
/// - 앱을 보고 있을 때 온 알림은 휴대폰이 띄우지 않아 아래 안내(SnackBar)로 보이고 `보기`로 B1을 연다.
///   A2 종 아이콘의 안 읽음 점도 바로 다시 받는다.
/// - 푸시가 꺼져 있으면(Firebase 값 없음) 아무것도 하지 않는다.
class PushBinding extends ConsumerStatefulWidget {
  const PushBinding({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushBinding> createState() => _PushBindingState();
}

class _PushBindingState extends ConsumerState<PushBinding> {
  final _subscriptions = <StreamSubscription<PushNotice>>[];

  /// 눌렀지만 아직 열지 못한 알림(로그인 전).
  PushNotice? _pending;

  @override
  void initState() {
    super.initState();
    final messaging = ref.read(pushMessagingProvider);
    if (messaging == null) return;
    _subscriptions
      ..add(messaging.opened.listen(_open))
      ..add(messaging.foreground.listen(_show));
    messaging.openedAtLaunch().then((notice) {
      if (notice != null) _open(notice);
    }, onError: (Object _) {});
    ref.listenManual(authControllerProvider, (previous, next) {
      if (next.value is SignedIn && previous?.value is! SignedIn) {
        ref.read(pushServiceProvider).register();
        _openPending();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  void _open(PushNotice notice) {
    _pending = notice;
    _openPending();
  }

  void _openPending() {
    final notice = _pending;
    if (notice == null || ref.read(authControllerProvider).value is! SignedIn) return;
    _pending = null;
    final notificationId = notice.notificationId;
    if (notificationId != null) _markRead(notificationId);
    final courseId = notice.courseId;
    if (courseId == null) return; // 모르는 알림은 앱만 연다
    // 로그인 상태가 막 바뀐 프레임이면 라우터가 아직 A1에 있다. 한 프레임 뒤에 연다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = ref.read(routerProvider);
      if (router.routerDelegate.currentConfiguration.uri.path == Routes.login) router.go(Routes.home);
      router.push(Routes.courseDetail(courseId));
    });
    // 화면이 멈춰 있으면(다시 그릴 것이 없으면) 다음 프레임이 오지 않는다. 직접 요청한다
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// 기다리지 않는다. 실패하면 알림함에 안 읽음으로 남을 뿐이다.
  void _markRead(String notificationId) {
    ref.read(notificationApiClientProvider).markRead(notificationId).then(
      (_) {
        if (mounted) ref.invalidate(unreadNotificationCountProvider);
      },
      onError: (Object e) => debugPrint('알림 읽음 저장 실패: $e'),
    );
  }

  void _show(PushNotice notice) {
    if (!mounted) return;
    ref.invalidate(unreadNotificationCountProvider);
    final text = [notice.title, notice.body].whereType<String>().join('\n');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text.isEmpty ? '새 알림이 있어요.' : text),
        action: notice.courseId == null ? null : SnackBarAction(label: '보기', onPressed: () => _open(notice)),
      ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
