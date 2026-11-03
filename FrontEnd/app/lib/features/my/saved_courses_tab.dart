import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/course_api_client.dart';
import '../../core/error_message.dart';
import '../../core/map/geo_point.dart';
import '../../routes.dart';
import '../course/course_format.dart';
import '../course/course_list_card.dart';
import '../home/my_location.dart';
import '../run/application/course_run_entry.dart';
import '../run/domain/course_run.dart';
import 'bookmark_state.dart';

/// G5 · 내 코스 — 저장한 코스(Figma G5 · G5-1). G4 화면의 두 번째 탭이다.
///
/// - 위 칸(저장한 코스 · 만료 임박) · 공개 기간 안내 · 정렬 칩 · `저장한 코스 N` · 카드 목록(아래로 내리면 다음 쪽) · 자동 삭제 안내 순서다.
/// - 정렬은 최근 저장순(처음) · 가까운순 · 평점순 · 만료 임박이다. 가까운순은 현재 위치를 받고, 못 받으면 정렬을 그대로 둔다.
/// - 카드를 누르면 B1, `이 코스로 달리기 ›`는 그 코스로 달리기 탭의 코스 러닝이다. B1에서 돌아오면 저장을 풀었을 수 있어 다시 받는다.
/// - 삭제 예정 코스는 맨 뒤에 흐리게 `삭제 예정`이고 달리기는 없다. 누르면 B1이 `볼 수 없는 코스예요`를 보인다.
/// - [편집]을 누르면 카드를 여러 개 골라 한 번에 저장을 푼다(G5-1). 풀기 전에 한 번 묻는다. 삭제 예정 코스는 풀면 다시 저장할 수 없다.
/// (2026-11-02 사용자 결정)
class SavedCoursesTab extends ConsumerStatefulWidget {
  const SavedCoursesTab({super.key, required this.now});

  /// 만료까지 남은 날을 세는 기준 시각.
  final DateTime Function() now;

  static const emptyTitle = '저장한 코스가 없어요';
  static const emptyMessage = '코스 상세에서 북마크를 눌러\n마음에 드는 코스를 저장해 보세요.';

  @override
  ConsumerState<SavedCoursesTab> createState() => _SavedCoursesTabState();
}

class _SavedCoursesTabState extends ConsumerState<SavedCoursesTab> with AutomaticKeepAliveClientMixin {
  var _sort = BookmarkSort.recent;

  /// 바꾸는 중인 정렬([_chooseSort]). 받기 전까지 칩은 이 정렬로 보인다.
  BookmarkSort? _pendingSort;

  /// 가까운순의 현재 위치. 다음 쪽도 같은 위치로 받는다.
  GeoPoint? _origin;
  List<BookmarkCourse> _courses = [];
  String? _nextCursor;
  bool _loaded = false;
  bool _loading = false;
  Object? _error;

  /// 편집 중이면 고른 코스 ID. 편집 중이 아니면 null.
  Set<String>? _selected;
  bool _removing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [more]가 false면 첫 쪽부터 다시 받는다. [sort] · [origin]을 주면 그 정렬로 받고, 받은 뒤에 정렬을 바꾼다.
  Future<void> _load({bool more = false, BookmarkSort? sort, GeoPoint? origin}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final nextSort = sort ?? _sort;
    final nextOrigin = sort == null ? _origin : origin;
    try {
      final page = await ref
          .read(courseApiClientProvider)
          .bookmarks(sort: nextSort, origin: nextOrigin, cursor: more ? _nextCursor : null);
      if (!mounted) return;
      setState(() {
        _sort = nextSort;
        _origin = nextOrigin;
        _courses = more ? [..._courses, ...page.courses] : page.courses;
        _nextCursor = page.nextCursor;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      // 정렬을 바꾸다 실패하면 보이던 목록 · 정렬을 그대로 두고 알린다
      if (sort != null && _loaded) {
        showError(context, e);
      } else {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() {
    ref.invalidate(bookmarkSummaryProvider);
    return _load();
  }

  /// 칩을 누르면 바로 그 칩을 고른 것으로 보이고, 위치 · 목록을 받는 동안 목록 자리에 로딩을 보인다.
  /// 못 받으면 칩과 목록을 그대로 둔다.
  Future<void> _chooseSort(BookmarkSort sort) async {
    if (sort == _sort || _loading || _pendingSort != null) return;
    setState(() => _pendingSort = sort);
    try {
      GeoPoint? origin;
      if (sort == BookmarkSort.nearest) {
        origin = await requestMyLocation(context, ref.read(myLocationProvider));
        if (origin == null || !mounted) return;
      }
      await _load(sort: sort, origin: origin);
    } finally {
      if (mounted) setState(() => _pendingSort = null);
    }
  }

  Future<void> _open(BookmarkCourse course) async {
    await context.push(Routes.courseDetail(course.courseId));
    if (mounted) await _reload();
  }

  void _toggle(BookmarkCourse course) {
    final selected = {...?_selected};
    if (!selected.remove(course.courseId)) selected.add(course.courseId);
    setState(() => _selected = selected);
  }

  Future<void> _removeSelected() async {
    final ids = _selected ?? const {};
    if (ids.isEmpty || !await _confirmRemove(ids.length) || !mounted) return;
    setState(() => _removing = true);
    try {
      // 한 번에 보낼 수 있는 만큼씩 나눠 보낸다
      final list = ids.toList();
      for (var i = 0; i < list.length; i += CourseApiClient.maxBookmarkIds) {
        await ref.read(courseApiClientProvider).removeBookmarks(list.skip(i).take(CourseApiClient.maxBookmarkIds));
      }
      if (!mounted) return;
      setState(() {
        _courses = [for (final course in _courses) if (!ids.contains(course.courseId)) course];
        _selected = null;
      });
      ref.invalidate(bookmarkSummaryProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('코스 ${ids.length}개의 저장을 풀었어요.')));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<bool> _confirmRemove(int count) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('코스 $count개의 저장을 풀까요?'),
          content: const Text('삭제 예정 코스는 풀면 다시 저장할 수 없어요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('저장 해제', style: TextStyle(color: WdColors.negative)),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final summary = ref.watch(bookmarkSummaryProvider).value;
    final selected = _selected;
    final now = widget.now();
    final header = <Widget>[
      WdStatSummary([
        ('저장한 코스', summary == null ? '—' : '${formatCount(summary.courseCount)}개'),
        ('만료 임박', summary == null ? '—' : '${formatCount(summary.expiringSoonCount)}개'),
      ]),
      const SizedBox(height: WdSpace.s16),
      const WdInfoBanner('저장만으로는 공개 기간이 늘지 않아요. 기간 안에 완주하면 30일 연장돼요.', tone: WdBannerTone.warning, plain: true),
      const SizedBox(height: WdSpace.s16),
      Wrap(
        spacing: WdSpace.s6,
        runSpacing: WdSpace.s6,
        children: [
          for (final sort in BookmarkSort.values)
            WdFilterChip(sort.label,
                height: 36, selected: sort == (_pendingSort ?? _sort), onTap: () => _chooseSort(sort)),
        ],
      ),
      const SizedBox(height: WdSpace.s16),
      Row(
        children: [
          Expanded(
            child: Text(
              selected == null
                  ? '저장한 코스${summary == null ? '' : ' ${formatCount(summary.courseCount)}'}'
                  : '${selected.length}개 선택됨',
              style: WdText.ko16Bold.copyWith(color: WdColors.muted),
            ),
          ),
          if (_courses.isNotEmpty)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removing ? null : () => setState(() => _selected = selected == null ? <String>{} : null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: WdSpace.s4),
                  child: Text(selected == null ? '편집' : '완료',
                      style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.green)),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: WdSpace.s16),
    ];
    const loading = Padding(
      padding: EdgeInsets.all(WdSpace.s24),
      child: Center(child: CircularProgressIndicator()),
    );
    final Widget? status = switch ((_loaded, _error)) {
      _ when _pendingSort != null => loading,
      (false, null) => loading,
      (_, _?) when _courses.isEmpty => _Retry(onRetry: _load),
      (true, _) when _courses.isEmpty =>
        const WdStateMessage(title: SavedCoursesTab.emptyTitle, message: SavedCoursesTab.emptyMessage),
      _ => null,
    };
    final footer = _courses.isEmpty
        ? null
        : const Padding(
            padding: EdgeInsets.only(top: WdSpace.s4),
            child: WdInfoBanner('원작자가 삭제하거나 만료된 코스는 목록에서 자동으로 사라져요.', plain: true),
          );
    final more = _nextCursor != null ? 1 : 0;
    final list = RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        itemCount: header.length + (status != null ? 1 : _courses.length + more + (footer != null ? 1 : 0)),
        itemBuilder: (context, index) {
          if (index < header.length) return header[index];
          if (status != null) return status;
          final i = index - header.length;
          if (i < _courses.length) {
            final course = _courses[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: WdSpace.s16),
              child: SavedCourseCard(
                course: course,
                now: now,
                selected: selected?.contains(course.courseId),
                onTap: selected != null ? () => _toggle(course) : () => _open(course),
                onRun: () => runCourse(context, ref, CourseSelection(course.courseId, course.name)),
              ),
            );
          }
          if (i == _courses.length && more == 1) {
            // 끝까지 내려와 다음 쪽 자리가 보이면 받는다. 실패하면 누를 때 다시 받는다
            if (_error == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load(more: true));
            return _error == null
                ? const Padding(
                    padding: EdgeInsets.all(WdSpace.s16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _Retry(onRetry: () => _load(more: true));
          }
          return footer!;
        },
      ),
    );
    if (selected == null) return list;
    return Column(
      children: [
        Expanded(child: list),
        WdBottomBar.pinned(
          primary: WdButton(
            selected.isEmpty ? '저장 해제' : '${selected.length}개 저장 해제',
            onPressed: selected.isEmpty || _removing ? null : _removeSelected,
          ),
        ),
      ],
    );
  }
}

/// 저장한 코스 카드(Figma G5 Course card · Saved). 썸네일 · 이름 · `5.2km · 난이도 중 · ★ 4.6` · `만든 사람 닉네임`,
/// 아래 줄은 만료 표시(7일 이하면 주황) · `이 코스로 달리기 ›`다. 삭제 예정 코스는 흐리게 `삭제 예정`이고 달리기가 없다.
/// [selected]가 null이 아니면 편집 중이라 왼쪽에 선택 체크를 두고 달리기를 숨긴다(G5-1).
class SavedCourseCard extends StatelessWidget {
  const SavedCourseCard({
    super.key,
    required this.course,
    required this.now,
    this.selected,
    required this.onTap,
    required this.onRun,
  });

  final BookmarkCourse course;
  final DateTime now;
  final bool? selected;
  final VoidCallback onTap;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final pending = course.pendingDelete;
    final daysLeft = daysUntilExpiry(course.expiresAt, now);
    final editing = selected != null;
    final card = WdCourseCard(
      title: course.name,
      leading: editing
          ? Semantics(
              checked: selected,
              label: '선택',
              child: WdIcon(WdIcons.check, size: 20, color: selected! ? WdColors.green : WdColors.checkOff),
            )
          : null,
      lines: [
        [
          formatKm(course.distanceMeters),
          '난이도 ${course.difficulty.label}',
          if (course.averageRating case final rating?) '★ ${rating.toStringAsFixed(1)}',
        ].join(' · '),
        if (course.creatorNickname case final nickname?) '만든 사람 $nickname',
      ],
      thumbnail: CourseRouteThumbnail(course.route),
      thumbnailSize: const Size(54, 54),
      tags: [
        WdTag(
          pending ? '삭제 예정' : formatExpiry(daysLeft),
          tone: pending || daysLeft <= CourseListCard.expiryWarningDays ? WdTone.warning : WdTone.neutral,
          filled: false,
        ),
      ],
      actionLabel: editing || pending ? null : '이 코스로 달리기 ›',
      onAction: onRun,
      onTap: onTap,
    );
    // 편집 중에는 삭제 예정 코스도 골라야 해서 흐리게 하지 않는다
    return pending && !editing ? Opacity(opacity: 0.5, child: card) : card;
  }
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
            Text('저장한 코스를 불러오지 못했어요.', style: WdText.body13.copyWith(color: WdColors.muted)),
            TextButton(
              onPressed: onRetry,
              child: Text('다시 불러오기', style: WdText.body13Bold.copyWith(color: WdColors.green)),
            ),
          ],
        ),
      );
}
