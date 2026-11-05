import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/notification_api_client.dart';
import '../../core/error_message.dart';
import '../../core/push/push_service.dart';
import '../../routes.dart';
import 'notification_bell.dart';

/// F3 알림 센터(Figma `F3 · 알림 센터`). A2 종 아이콘에서 연다. 홈 탭 안에 쌓아 하단 탭이 보인다(Figma F3).
///
/// - 탭(전체 · 대결 · 코스 · 커뮤니티)은 두지 않고 한 목록이다. `모두 읽음`은 앱 바 오른쪽 하나만 둔다(2026-11-04 사용자 결정).
/// - 최근 30일 알림을 최신순으로 보이고, 끝에 닿으면 다음 쪽을 받는다. 30일이 지난 알림은 서버가 지운다.
/// - 알림을 누르면 읽음으로 바꾸고, 코스 알림이면 B1 코스 상세를 연다. 읽음 저장이 실패해도 B1은 연다.
/// - 푸시 설정(F4)을 꺼도 알림은 여기 쌓인다.
class NotificationInboxScreen extends ConsumerStatefulWidget {
  const NotificationInboxScreen({super.key, this.now = DateTime.now});

  /// 테스트에서 시각을 고정한다.
  final DateTime Function() now;

  static const emptyTitle = '아직 알림이 없어요';
  static const loadFailedTitle = '알림을 불러오지 못했어요';

  @override
  ConsumerState<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends ConsumerState<NotificationInboxScreen> {
  final _scroll = ScrollController();
  final _items = <NotificationItem>[];

  /// 다음 쪽 커서. 처음 쪽을 받기 전이나 마지막 쪽이면 없다.
  String? _next;
  bool _loaded = false;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreNearEnd);
    _refresh();
  }

  /// 끝에서 300 안이면 다음 쪽을 받는다. 한 쪽이 화면을 다 채우지 못하면 스크롤이 없으니 쪽을 받은 뒤에도 본다.
  void _loadMoreNearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 300) _loadMore();
  }

  void _checkAfterLayout() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _loadMoreNearEnd();
  });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  NotificationApiClient get _api => ref.read(notificationApiClientProvider);

  /// 처음 쪽부터 다시 받는다(처음 열 때 · 당겨서 새로 고침 · 다시 시도).
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.inbox();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _next = page.nextCursor;
        _loaded = true;
      });
      ref.invalidate(unreadNotificationCountProvider);
      _checkAfterLayout();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 다음 쪽.
  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loading) return;
    setState(() => _loading = true);
    try {
      final page = await _api.inbox(cursor: cursor);
      if (!mounted) return;
      setState(() {
        // 그 사이 새 알림이 와서 쪽이 밀리면 같은 알림이 다시 올 수 있다
        final seen = {for (final item in _items) item.id};
        _items.addAll(page.items.where((item) => !seen.contains(item.id)));
        _next = page.nextCursor;
      });
      _checkAfterLayout();
    } catch (e) {
      // 실패하면 커서를 남겨 두고, 다시 스크롤하면 또 받는다
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final before = List.of(_items);
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].asRead();
      }
    });
    try {
      await _api.markAllRead();
    } catch (e) {
      if (!mounted) return;
      setState(() => _items
        ..clear()
        ..addAll(before));
      showError(context, e);
    } finally {
      if (mounted) ref.invalidate(unreadNotificationCountProvider);
    }
  }

  Future<void> _open(NotificationItem item) async {
    final courseId = courseIdOf(item.data);
    if (!item.read) {
      final index = _items.indexWhere((e) => e.id == item.id);
      if (index >= 0) setState(() => _items[index] = item.asRead());
      // 기다리지 않고 B1을 연다. 실패하면 다음에 열 때 다시 안 읽음으로 보인다
      _api.markRead(item.id).then(
        (_) {
          if (mounted) ref.invalidate(unreadNotificationCountProvider);
        },
        onError: (Object e) => debugPrint('알림 읽음 저장 실패: $e'),
      );
    }
    if (courseId != null) await context.push(Routes.courseDetail(courseId));
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;
    final anyUnread = unread > 0 || _items.any((item) => !item.read);
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(
        title: '알림',
        onBack: () => context.pop(),
        action: WdAppBarAction.text('모두 읽음', onTap: anyUnread ? _markAllRead : null),
      ),
      body: switch ((_loaded, _error)) {
        (false, null) => const Center(child: CircularProgressIndicator(color: WdColors.ink)),
        (false, final error?) => Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WdStateMessage(
                    title: NotificationInboxScreen.loadFailedTitle,
                    message: errorMessage(error),
                    icon: WdIcons.ghostWarning,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24),
                    child: WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: _refresh),
                  ),
                ],
              ),
            ),
          ),
        _ => RefreshIndicator(
            color: WdColors.ink,
            onRefresh: _refresh,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              // Figma Body: 좌우 16 · 위 6 · 아래 14, 줄 사이 10
              padding: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s6, WdSpace.s16, WdSpace.s14),
              children: [
                _summary(unread),
                const SizedBox(height: WdSpace.s10),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: WdSpace.s32),
                    child: WdStateMessage(
                      title: NotificationInboxScreen.emptyTitle,
                      message: '최근 30일 동안 받은 알림이 여기에 쌓여요.',
                      icon: WdIcons.bell,
                    ),
                  )
                else
                  _NotificationCard(items: _items, now: widget.now(), onTap: _open),
                if (_next != null && _loading)
                  const Padding(
                    padding: EdgeInsets.all(WdSpace.s16),
                    child: Center(child: CircularProgressIndicator(color: WdColors.ink)),
                  ),
                const SizedBox(height: WdSpace.s10),
                const WdInfoBanner('코스 만료 알림은 내가 등록한 코스에만 보내요.'),
              ],
            ),
          ),
      },
    );
  }

  /// `최근 30일  읽지 않음 N`. 다 읽었으면 태그를 숨긴다.
  Widget _summary(int unread) => Row(
    spacing: WdSpace.s8,
    children: [
      Text('최근 30일', style: WdText.raw(12, FontWeight.w700, 17).copyWith(color: WdColors.neutralTextSecondary)),
      if (unread > 0) WdTag('읽지 않음 $unread', tone: WdTone.info),
    ],
  );
}

/// 알림 목록 카드(Figma: 흰 바탕 · 테두리 · 둥글기 12, 줄 사이 구분선).
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.items, required this.now, required this.onTap});

  final List<NotificationItem> items;
  final DateTime now;
  final ValueChanged<NotificationItem> onTap;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: WdColors.paper,
      border: Border.all(color: WdColors.neutralBorder),
      borderRadius: BorderRadius.circular(WdRadius.r12),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index > 0)
                const Divider(height: 1, thickness: 1, indent: WdSpace.s14, endIndent: WdSpace.s14, color: WdColors.neutralBorder),
              _NotificationRow(item: item, now: now, onTap: () => onTap(item)),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 알림 한 줄: 아이콘 칸 36 · 제목(안 읽었으면 파란 점) · 받은 때 · 본문.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item, required this.now, required this.onTap});

  final NotificationItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Semantics(
      label: item.read ? null : '읽지 않음',
      child: Padding(
        // 카드 안쪽 14 · 줄 위아래 12. 카드 위아래 1을 더해 Figma 카드 안쪽 13
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: WdSpace.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 11,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: WdColors.neutralSurface, borderRadius: BorderRadius.circular(10)),
              child: WdIcon(item.kind == 'COURSE_EXPIRING_SOON' ? WdIcons.ghostWarning : WdIcons.ghostInfo, size: 20),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WdSpace.s4,
                children: [
                  Row(
                    spacing: WdSpace.s6,
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WdText.raw(13, FontWeight.w700, 18).copyWith(color: WdColors.neutralText),
                        ),
                      ),
                      if (!item.read)
                        Container(
                          key: ValueKey('unread-${item.id}'),
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: WdColors.info, shape: BoxShape.circle),
                        ),
                      const Spacer(),
                      Text(
                        formatNotificationTime(item.createdAt, now),
                        style: WdText.raw(10, FontWeight.w400, 14).copyWith(color: WdColors.neutralTextWeak),
                      ),
                    ],
                  ),
                  Text(item.body, style: WdText.raw(11, FontWeight.w400, 16).copyWith(color: WdColors.neutralTextSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 받은 때(Figma F3): `방금` · `12분 전` · `1시간 전`(24시간 안) · `어제` · `2일 전`(Asia/Seoul 날짜 기준).
String formatNotificationTime(DateTime createdAt, DateTime now) {
  final ago = now.difference(createdAt);
  if (ago < const Duration(minutes: 1)) return '방금';
  if (ago < const Duration(hours: 1)) return '${ago.inMinutes}분 전';
  if (ago < const Duration(days: 1)) return '${ago.inHours}시간 전';
  DateTime seoulDate(DateTime time) {
    final seoul = time.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(seoul.year, seoul.month, seoul.day);
  }

  final days = seoulDate(now).difference(seoulDate(createdAt)).inDays;
  return days <= 1 ? '어제' : '$days일 전';
}
