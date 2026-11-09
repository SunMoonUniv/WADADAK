import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/course_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';
import '../../routes.dart';
import '../course/course_format.dart';
import '../course/course_list_card.dart';
import 'bookmark_state.dart';
import 'saved_courses_tab.dart';

/// 내가 등록한 코스 합계(`GET /courses/mine/summary`). G4 위 칸 · 탭과 E3 `등록 코스`가 같이 쓴다.
/// B7에서 수정 · 삭제하면 `ref.invalidate`로 다시 받는다.
final myCourseSummaryProvider = FutureProvider<MyCourseSummary>((ref) async {
  // 로그인 상태가 정해질 때까지 기다리고, 로그아웃 뒤 다시 로그인했을 때만 다시 받는다
  await ref.watch(authControllerProvider.selectAsync((auth) => auth is SignedIn));
  return ref.read(courseApiClientProvider).myCourseSummary();
}, retry: (_, _) => null);

/// G4 · 내 코스(Figma `G4 · 내 코스 관리`). E3 `내가 등록한 코스` · `저장한 코스`에서 연다.
///
/// - 탭은 `등록한 코스 N` · `저장한 코스 N`이다. E3 `저장한 코스`에서 열면 저장한 코스 탭([SavedCoursesTab], G5)으로 연다.
/// - 등록한 코스: 위 칸(등록 코스 · 누적 주행 · 만료 임박) · 공개 기간 안내 · 카드 목록(아래로 내리면 다음 쪽).
/// - 카드의 [수정]은 B7을 열고, [삭제]는 한 번 물은 뒤 지운다. 지운 코스는 24시간 동안 흐리게 `삭제 예정`으로 남는다.
/// - 오른쪽 위 [+ 만들기]는 B3 코스 만들기다.
/// (2026-11-02 사용자 결정)
class MyCoursesScreen extends ConsumerStatefulWidget {
  const MyCoursesScreen({super.key, this.now, this.saved = false});

  /// 만료 · 최근 주행 · 삭제까지 남은 시간을 세는 기준 시각. 테스트만 넣는다.
  final DateTime Function()? now;

  /// 저장한 코스 탭으로 연다(E3 `저장한 코스`).
  final bool saved;

  @override
  ConsumerState<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends ConsumerState<MyCoursesScreen> {
  List<MyCourseItem> _courses = [];
  String? _nextCursor;

  /// 첫 쪽을 받았나. 받기 전에는 목록 자리에 로딩을 보인다.
  bool _loaded = false;
  bool _loading = false;
  Object? _error;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [more]가 false면 첫 쪽부터 다시 받는다.
  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(courseApiClientProvider).myCourses(cursor: more ? _nextCursor : null);
      if (!mounted) return;
      setState(() {
        _courses = more ? [..._courses, ...page.courses] : page.courses;
        _nextCursor = page.nextCursor;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// B7에서 저장 · 삭제했거나 카드에서 삭제했다. 카드를 바꾸고 위 칸 · E3 합계를 다시 받는다.
  void _replace(MyCourseItem changed) {
    setState(() => _courses = [for (final course in _courses) course.courseId == changed.courseId ? changed : course]);
    ref.invalidate(myCourseSummaryProvider);
  }

  Future<void> _edit(MyCourseItem course) async {
    final changed = await context.push<MyCourseItem>(Routes.myCourseEdit, extra: course);
    if (changed != null && mounted) _replace(changed);
  }

  /// `+ 만들기`로 코스를 등록하고 돌아오면 첫 쪽부터 다시 받는다. 새 코스가 목록에 보여야 해서다.
  /// 등록 화면은 만든 코스를 들고 돌아오고, 그냥 뒤로 나오면 null이라 다시 받지 않는다.
  /// (위 칸 숫자는 등록 화면이 이미 다시 받게 한다.)
  Future<void> _create() async {
    final created = await context.push<Object?>(Routes.courseCreate);
    if (created != null && mounted) _load();
  }

  Future<void> _delete(MyCourseItem course) async {
    if (!await confirmCourseDelete(context, course.name) || !mounted) return;
    try {
      _replace(await ref.read(courseApiClientProvider).deleteCourse(course.courseId));
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('코스를 삭제했어요. 24시간 뒤 완전히 지워져요.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(myCourseSummaryProvider).value;
    final saved = ref.watch(bookmarkSummaryProvider).value;
    return DefaultTabController(
      length: 2,
      initialIndex: widget.saved ? 1 : 0,
      child: Scaffold(
        backgroundColor: WdColors.paper,
        appBar: WdAppBar(
          title: '내 코스',
          onBack: () => context.pop(),
          action: WdAppBarAction.button('+ 만들기', onTap: _create),
        ),
        body: Column(
          children: [
            WdTabBar(tabs: [
              summary == null ? '등록한 코스' : '등록한 코스 ${summary.courseCount}',
              saved == null ? '저장한 코스' : '저장한 코스 ${saved.courseCount}',
            ]),
            const Divider(height: 1, thickness: 1, color: WdColors.map),
            Expanded(
              child: TabBarView(
                children: [
                  _registered(summary),
                  SavedCoursesTab(now: () => _now),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registered(MyCourseSummary? summary) {
    final now = _now;
    final header = [
      Row(
        spacing: WdSpace.s8,
        children: [
          _SummaryTile('등록 코스', summary == null ? '—' : '${formatCount(summary.courseCount)}개'),
          _SummaryTile('누적 주행', summary == null ? '—' : '${formatCount(summary.completionCount)}회'),
          _SummaryTile('만료 임박', summary == null ? '—' : '${formatCount(summary.expiringSoonCount)}개'),
        ],
      ),
      const SizedBox(height: WdSpace.s8),
      const WdInfoBanner(
        '모든 코스는 등록한 날부터 30일 동안 공개돼요. 그 안에 누군가 완주하면 30일 연장돼요.',
        tone: WdBannerTone.warning,
        plain: true,
      ),
      const SizedBox(height: WdSpace.s8),
    ];
    final Widget? status = switch ((_loaded, _error)) {
      (false, null) => const Padding(
        padding: EdgeInsets.all(WdSpace.s24),
        child: Center(child: CircularProgressIndicator()),
      ),
      (_, _?) when _courses.isEmpty => _Retry(onRetry: _load),
      (true, _) when _courses.isEmpty => const WdStateMessage(
        title: '등록한 코스가 없어요',
        message: '지도에 그리거나 달린 기록으로\n코스를 만들어 보세요.',
      ),
      _ => null,
    };
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(myCourseSummaryProvider);
        return _load();
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        itemCount: header.length + (status != null ? 1 : _courses.length + (_nextCursor != null ? 1 : 0)),
        itemBuilder: (context, index) {
          if (index < header.length) return header[index];
          if (status != null) return status;
          final i = index - header.length;
          if (i == _courses.length) {
            // 끝까지 내려와 다음 쪽 자리가 보이면 받는다. 실패하면 누를 때 다시 받는다
            if (_error == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load(more: true));
            return _error == null
                ? const Padding(
                    padding: EdgeInsets.all(WdSpace.s16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _Retry(onRetry: () => _load(more: true));
          }
          final course = _courses[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: WdSpace.s12),
            child: MyCourseCard(
              course: course,
              now: now,
              onTap: course.pendingDelete ? null : () => context.push(Routes.courseDetail(course.courseId)),
              onEdit: () => _edit(course),
              onDelete: () => _delete(course),
            ),
          );
        },
      ),
    );
  }
}

/// 코스 삭제를 한 번 묻는다(G4 카드 [삭제] · B7 [코스 삭제]). 지우기로 하면 true.
Future<bool> confirmCourseDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name 코스를 삭제할까요?'),
        content: const Text('바로 비공개가 되고 24시간 뒤 지워져요. 이 코스의 리뷰 · 순위도 함께 사라지고, 러닝 기록은 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('삭제', style: TextStyle(color: WdColors.negative)),
          ),
        ],
      ),
    ) ??
    false;

/// 내 코스 카드(Figma G4). 썸네일 · 이름 · `최근 주행 · 누적` · 만료 표시, 아래 줄은 코스 유형 · [수정] · [삭제]다.
/// 삭제 예정 코스는 흐리게 보이고 만료 표시 자리에 `삭제 예정`, 아래 줄에 사유 · 남은 시간을 보인다(수정 · 삭제 없음).
class MyCourseCard extends StatelessWidget {
  const MyCourseCard({
    super.key,
    required this.course,
    required this.now,
    this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final MyCourseItem course;
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final small = WdText.raw(12, FontWeight.w400, 18);
    final pending = course.pendingDelete;
    final daysLeft = daysUntilExpiry(course.expiresAt, now);
    final (expiry, expiryColor) = pending
        ? ('삭제 예정', WdColors.warningText)
        : daysLeft <= CourseListCard.expiryWarningDays
        ? (formatExpiry(daysLeft), WdColors.warningText)
        : ('D-$daysLeft', WdColors.muted);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s12,
      children: [
        Row(
          spacing: WdSpace.s12,
          children: [
            WdRouteThumbnail(width: 54, height: 54, child: CourseRouteThumbnail(course.route)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WdText.cardTitle14.copyWith(color: WdColors.ink),
                  ),
                  Text(
                    '${formatLastRun(course.lastCompletedOn, now)} · 누적 ${formatCount(course.completionCount)}회',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small.copyWith(color: WdColors.muted),
                  ),
                ],
              ),
            ),
            Text(expiry, style: small.copyWith(color: expiryColor)),
          ],
        ),
        Row(
          spacing: WdSpace.s16,
          children: [
            Expanded(
              child: Text(
                pending ? formatPendingDelete(course, now) : course.courseType.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small.copyWith(color: WdColors.muted),
              ),
            ),
            if (!pending) ...[
              _CardAction('수정', color: WdColors.green, onTap: onEdit),
              _CardAction('삭제', color: WdColors.muted, onTap: onDelete),
            ],
          ],
        ),
      ],
    );
    return WdSurface(
      padding: const EdgeInsets.fromLTRB(WdSpace.s14, WdSpace.s14, WdSpace.s14, WdSpace.s12),
      onTap: onTap,
      child: pending ? Opacity(opacity: 0.5, child: content) : content,
    );
  }
}

/// 카드 아래 줄 오른쪽 글자 버튼. 누르기 쉽게 위아래로 조금 넓힌다.
class _CardAction extends StatelessWidget {
  const _CardAction(this.label, {required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WdSpace.s4),
        child: Text(label, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: color)),
      ),
    ),
  );
}

/// `최근 주행 오늘 · 어제 · N일 전`(Asia/Seoul 날짜 기준). 완주가 없으면 `최근 주행 없음`.
String formatLastRun(DateTime? lastCompletedOn, DateTime now) {
  if (lastCompletedOn == null) return '최근 주행 없음';
  final seoul = now.toUtc().add(const Duration(hours: 9));
  final days = DateTime.utc(seoul.year, seoul.month, seoul.day)
      .difference(DateTime.utc(lastCompletedOn.year, lastCompletedOn.month, lastCompletedOn.day))
      .inDays;
  return switch (days) {
    <= 0 => '최근 주행 오늘',
    1 => '최근 주행 어제',
    _ => '최근 주행 $days일 전',
  };
}

/// 삭제 예정 카드 아래 줄. `내가 삭제함 · 23시간 뒤 삭제` / `기간 만료 · 1시간 안에 삭제`.
String formatPendingDelete(MyCourseItem course, DateTime now) {
  final reason = course.hiddenReason == CourseHiddenReason.userDeleted ? '내가 삭제함' : '기간 만료';
  final deleteAt = course.deleteAt;
  if (deleteAt == null) return reason;
  final hours = deleteAt.difference(now).inHours;
  return '$reason · ${hours < 1 ? '1시간 안에 삭제' : '$hours시간 뒤 삭제'}';
}

/// 위 칸 하나: 작은 라벨 + 큰 값(Figma G4, 높이 76).
class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: WdSurface(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          Text(label, style: WdText.raw(11, FontWeight.w400, 14).copyWith(color: WdColors.muted)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WdText.raw(20, FontWeight.w700, 26).copyWith(color: WdColors.ink),
          ),
        ],
      ),
    ),
  );
}

/// 목록을 받지 못했을 때 안내 + [다시 불러오기].
class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(WdSpace.s16),
    child: Column(
      children: [
        Text('코스를 불러오지 못했어요.', style: WdText.body13.copyWith(color: WdColors.muted)),
        TextButton(
          onPressed: onRetry,
          child: Text('다시 불러오기', style: WdText.body13Bold.copyWith(color: WdColors.green)),
        ),
      ],
    ),
  );
}
