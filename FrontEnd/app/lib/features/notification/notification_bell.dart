import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/notification_api_client.dart';
import '../../routes.dart';

/// 안 읽은 알림 수(최근 30일). A2 종 아이콘의 점과 F3 `읽지 않음 N`이 함께 본다.
/// 읽음으로 바꾸거나 새 알림이 오면 `ref.invalidate`로 다시 받는다. 못 받으면 점을 보이지 않는다(다시 묻지 않는다).
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationApiClientProvider).unreadCount(),
  retry: (_, _) => null,
);

/// A2 오른쪽 위 종 아이콘(Figma에 없음, 2026-11-04 사용자 결정). 누르면 F3 알림함을 연다.
/// 안 읽은 알림이 있으면 오른쪽 위에 파란 점(F3 목록의 안 읽음 점과 같은 색)을 붙인다.
/// 앱으로 돌아오면(다른 앱에 있는 동안 푸시가 왔을 수 있다) 수를 다시 받는다.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(unreadNotificationCountProvider));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await context.push(Routes.notifications);
    // 알림함에서 읽은 만큼 점을 바로 지운다
    if (mounted) ref.invalidate(unreadNotificationCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;
    return Semantics(
      button: true,
      label: unread > 0 ? '알림, 읽지 않은 알림 $unread개' : '알림',
      excludeSemantics: true,
      onTap: _open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        // 누르는 자리는 44로 넉넉히, 아이콘은 22
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const WdIcon(WdIcons.bell),
                if (unread > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      key: const ValueKey('notification-bell-dot'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: WdColors.info,
                        shape: BoxShape.circle,
                        // 종 선 위에 얹혀도 점이 또렷하게 흰 테두리
                        border: Border.all(color: WdColors.paper, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
