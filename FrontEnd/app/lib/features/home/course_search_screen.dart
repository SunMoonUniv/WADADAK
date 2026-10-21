import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/error_message.dart';
import '../../core/map/geo_point.dart';
import '../../routes.dart';
import '../course/course_format.dart';
import '../course/course_list_card.dart';
import 'my_location.dart';

/// G1 · 검색 결과 — 코스. 홈 검색창에서 빈 입력으로 연다(SEA-01). 홈 탭 안에 쌓아 하단 탭이 보인다(Figma G1).
///
/// - 공백을 빼고 2글자 이상 입력한 뒤 키보드의 검색을 누르면 이름에 검색어가 들어간 코스를 전국에서 찾는다(SEA-03).
///   ✕는 검색어와 결과를 지운다(G1-01). 최근 검색어는 없다.
/// - 코스 · 지역 · 러너 탭. 지역(G6) · 러너(G7)는 아직 없어 준비 중이라고 보인다. 탭을 바꿔도 검색어는 그대로다(G1-02).
/// - 정렬은 홈 목록과 같은 인기순(처음) · 평점순 · 가까운순 · 최신순 · 실시간순이다(G1-03). A3 필터 · 기간 슬라이더는 쓰지 않는다.
/// - 카드를 누르면 B1. 돌아오면 검색어 · 결과 · 스크롤이 그대로다(FIL-08).
class CourseSearchScreen extends ConsumerStatefulWidget {
  const CourseSearchScreen({super.key});

  static const tabs = ['코스', '지역', '러너'];
  static const hint = '원하는 키워드를 검색하세요';
  static const tooShortMessage = '검색어를 2글자 이상 입력해 주세요.';
  static const tooLongMessage = '검색어는 100자까지 입력할 수 있어요.';
  static const loadFailedMessage = '검색 결과를 불러오지 못했어요.';

  /// 서버가 받는 검색어 길이 상한.
  static const maxLength = 100;

  /// G8 · 검색 결과 없음 제목. 코스 만들기 버튼은 두지 않는다(SEA-06).
  static String emptyTitle(String query) => '‘$query’ 검색 결과가 없어요';
  static const emptyMessage = '다른 검색어로 찾아보거나\n직접 코스를 만들어 보세요.';

  /// 지역(G6) · 러너(G7) 탭 안내.
  static String notReadyMessage(String tab) => '$tab 검색은 준비 중이에요';

  @override
  ConsumerState<CourseSearchScreen> createState() => _CourseSearchScreenState();
}

/// 검색한 조건. 다음 쪽도 이 조건으로 받는다.
typedef _SearchQuery = ({String text, CourseListSort sort, GeoPoint? origin});

class _CourseSearchScreenState extends ConsumerState<CourseSearchScreen> with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  late final _tabs = TabController(length: CourseSearchScreen.tabs.length, vsync: this)
    ..addListener(() => setState(() {}));
  final _list = ScrollController();

  /// `인기순 ▾` 글자. 정렬 목록을 이 바로 아래에 띄운다.
  final _sortButton = GlobalKey();

  /// 남은 스크롤이 이보다 짧으면 다음 쪽을 받는다.
  static const _loadMoreExtent = 400.0;

  var _sort = CourseListSort.initial;

  /// 가까운순의 현재 위치. 가까운순을 고를 때 새로 받는다.
  GeoPoint? _origin;

  /// 가장 최근에 받기 시작한 조건. 아직 검색하지 않았거나 지웠으면 null.
  _SearchQuery? _requested;

  /// [_courses]를 받은 조건. 다음 쪽도 이 조건으로 받는다.
  _SearchQuery? _shown;
  List<CourseListItem>? _courses;
  var _total = 0;
  String? _nextCursor;

  /// 새 검색어의 첫 쪽을 받지 못했다(QST-02). 같은 검색어의 정렬만 바꾸다 실패하면 전 결과를 둔다.
  var _failed = false;
  var _loadingMore = false;
  var _moreFailed = false;

  /// 가장 최근 첫 쪽 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  @override
  void dispose() {
    _input.dispose();
    _tabs.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 키보드의 검색. 공백을 빼고 2글자 미만이면 검색하지 않고 알린다(G1-01).
  void _submit(String value) {
    final text = value.trim();
    final message = !CourseApiClient.isSearchable(text)
        ? CourseSearchScreen.tooShortMessage
        : text.length > CourseSearchScreen.maxLength
            ? CourseSearchScreen.tooLongMessage
            : null;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _search((text: text, sort: _sort, origin: _origin));
  }

  /// 검색어를 모두 지우면(✕ 포함) 처음 상태로 돌아간다(G1-01). 입력만 바꾸는 동안은 전 결과를 둔다.
  void _onChanged(String value) {
    if (value.isNotEmpty) return;
    _request++;
    setState(() {
      _requested = null;
      _shown = null;
      _courses = null;
      _failed = false;
      _loadingMore = false;
      _moreFailed = false;
    });
  }

  /// [query]의 첫 쪽을 받는다. 검색어가 바뀌면 처음부터 받고, 같은 검색어면 받는 동안 전 결과를 둔다.
  Future<void> _search(_SearchQuery query) async {
    final request = ++_request;
    final fresh = query.text != _shown?.text;
    setState(() {
      _requested = query;
      _failed = false;
      if (fresh) {
        _shown = null;
        _courses = null;
      }
    });
    try {
      final page = await _page(query);
      if (!mounted || request != _request) return;
      // 새 결과는 맨 위부터 보인다.
      if (_list.hasClients) _list.jumpTo(0);
      setState(() {
        _shown = query;
        _courses = page.courses;
        _total = page.totalCount;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
        _moreFailed = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      final shown = _shown;
      if (shown == null) {
        setState(() => _failed = true);
        return;
      }
      // 정렬만 바꾸다 실패했다. 보이는 결과의 정렬로 되돌린다.
      setState(() {
        _requested = shown;
        _sort = shown.sort;
        _origin = shown.origin;
      });
      showError(context, e);
    }
  }

  Future<CourseSearchPage> _page(_SearchQuery query, {String? cursor}) => ref
      .read(courseApiClientProvider)
      .searchCourses(query: query.text, sort: query.sort, origin: query.origin, cursor: cursor);

  /// 지금 결과의 다음 쪽을 받아 붙인다.
  Future<void> _loadMore() async {
    final query = _shown, cursor = _nextCursor;
    if (query == null || cursor == null || _loadingMore || _moreFailed) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await _page(query, cursor: cursor);
      // 그사이 다시 검색했으면 버린다.
      if (!mounted || request != _request) return;
      setState(() {
        _courses = [...?_courses, ...page.courses];
        _total = page.totalCount;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on ApiException {
      if (!mounted || request != _request) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  void _retryMore() {
    setState(() => _moreFailed = false);
    _loadMore();
  }

  /// 정렬 고르기(G1-03). `인기순 ▾` 바로 아래에 나머지 정렬이 든 메뉴가 뜨고, 하나를 누르면 바뀐다.
  /// 바깥 · 뒤로는 그대로 닫는다. 가까운순은 현재 위치를 새로 받은 뒤에 바꾸고, 못 받으면 정렬을 그대로 둔다.
  Future<void> _chooseSort() async {
    final button = _sortButton.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context, rootNavigator: true).overlay?.context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    final label = button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final options = [for (final sort in CourseListSort.values) if (sort != _sort) sort];
    final sort = await showGeneralDialog<CourseListSort>(
      context: context,
      // 하단 탭을 눌러도 먼저 닫히게 화면 전체를 덮는다. 바깥은 어두워지지 않는다.
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, _, _) => _SortMenu(label: label, options: options),
    );
    if (sort == null || sort == _sort || !mounted) return;
    GeoPoint? origin;
    if (sort == CourseListSort.nearest) {
      origin = await requestMyLocation(context, ref.read(myLocationProvider));
      if (origin == null || !mounted) return;
    }
    setState(() {
      _sort = sort;
      _origin = origin;
    });
    final text = _requested?.text;
    if (text != null) _search((text: text, sort: sort, origin: origin));
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs.index;
    return Scaffold(
      backgroundColor: WdColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            WdSearchHeader(
              controller: _input,
              onBack: () => context.pop(),
              hintText: CourseSearchScreen.hint,
              onChanged: _onChanged,
              onSubmitted: _submit,
              autofocus: true,
            ),
            WdTabBar(tabs: CourseSearchScreen.tabs, controller: _tabs),
            const Divider(height: 1, thickness: 1, color: WdColors.line),
            Expanded(
              child: tab == 0
                  ? _results()
                  : _centered(Text(
                      CourseSearchScreen.notReadyMessage(CourseSearchScreen.tabs[tab]),
                      style: WdText.body13.copyWith(color: WdColors.muted),
                    )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    final courses = _courses, shown = _shown;
    if (_requested == null) return const SizedBox.shrink();
    if (_failed) {
      return _centered(Column(
        spacing: WdSpace.s12,
        children: [
          Text(CourseSearchScreen.loadFailedMessage, style: WdText.body13.copyWith(color: WdColors.muted)),
          WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: () => _search(_requested!)),
        ],
      ));
    }
    if (courses == null || shown == null) return const _Loading();
    if (courses.isEmpty) {
      // Figma G8: 탭 아래 76쯤에 안내. 코스 만들기 버튼은 두지 않는다(SEA-06).
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: WdSpace.s56),
        child: Center(
          child: WdStateMessage(
            icon: WdIcons.search,
            title: CourseSearchScreen.emptyTitle(shown.text),
            message: CourseSearchScreen.emptyMessage,
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < _loadMoreExtent) _loadMore();
        return false;
      },
      // Figma G1 Body: 위 20 · 옆 24, 제목 줄과 카드 사이 16.
      child: ListView.separated(
        controller: _list,
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, 0),
        itemCount: courses.length + 2,
        separatorBuilder: (_, index) => SizedBox(height: index == courses.length ? 0 : WdSpace.s16),
        itemBuilder: (_, index) {
          if (index == 0) return _header();
          if (index > courses.length) return _footer();
          final course = courses[index - 1];
          return CourseSearchCard(course: course, onTap: () => context.push(Routes.courseDetail(course.courseId)));
        },
      ),
    );
  }

  /// `코스 검색 결과 12` · `인기순 ▾`(Figma G1).
  Widget _header() => Row(
        children: [
          Expanded(
            child: Text(
              '코스 검색 결과 ${formatCount(_total)}',
              style: WdText.ko16Bold.copyWith(color: WdColors.muted),
            ),
          ),
          // 옆의 `코스 검색 결과 N`과 합쳐 읽히지 않게 따로 둔다.
          Semantics(
            container: true,
            button: true,
            label: '정렬 ${_sort.label}',
            excludeSemantics: true,
            onTap: _chooseSort,
            child: GestureDetector(
              key: _sortButton,
              behavior: HitTestBehavior.opaque,
              onTap: _chooseSort,
              child: Text('${_sort.label} ▾', style: _SortMenu.text.copyWith(color: WdColors.green)),
            ),
          ),
        ],
      );

  /// 다음 쪽을 받는 중이면 표시, 실패했으면 다시 시도(QST-01 · QST-02).
  Widget _footer() {
    if (_loadingMore) return const _Loading();
    if (_moreFailed) {
      return Padding(
        padding: const EdgeInsets.all(WdSpace.s16),
        child: Center(
          child: GestureDetector(
            onTap: _retryMore,
            child: Text('더 불러오지 못했어요 · 다시 시도', style: WdText.body13.copyWith(color: WdColors.green)),
          ),
        ),
      );
    }
    return const SizedBox(height: WdSpace.s24);
  }

  static Widget _centered(Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s56, WdSpace.s24, WdSpace.s24),
        child: Align(alignment: Alignment.topCenter, child: child),
      );
}

/// `인기순 ▾` 바로 아래에 띄우는 정렬 메뉴(G1-03). 흰 상자 안에 나머지 정렬이 회색 글씨로 보인다.
/// 메뉴 안 글자의 왼쪽 끝을 `인기순 ▾`에 맞추고, `인기순 ▾`부터 모든 줄 사이를 12로 같게 둔다.
/// 고른 정렬을 돌려준다. 바깥 · 뒤로 닫으면 null이다.
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.label, required this.options});

  /// `인기순 ▾`과 같은 글씨.
  static final text = WdText.raw(12, FontWeight.w400, 18);

  /// 메뉴 안 글자 옆 여백. 메뉴는 이만큼 `인기순 ▾`보다 왼쪽에서 시작한다.
  static const side = WdSpace.s12;

  /// `인기순 ▾`과 메뉴 사이. 메뉴 위 여백 2와 줄 위 여백 6을 더해 첫 줄도 `인기순 ▾`에서 12 떨어진다.
  static const gap = WdSpace.s4;
  static const _menuPadding = WdSpace.s2;

  /// 줄마다 글씨 위아래 여백. 줄 사이는 이 두 배인 12다.
  static const _rowPadding = WdSpace.s6;

  /// 화면에서 `인기순 ▾` 글자가 있는 곳.
  final Rect label;
  final List<CourseListSort> options;

  // 따로 뜨는 화면이라 글씨 기본 모양(밑줄 없음)을 투명한 Material로 준다.
  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: CustomSingleChildLayout(
          delegate: _SortMenuLayout(label),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: _menuPadding),
            decoration: BoxDecoration(
              color: WdColors.paper,
              borderRadius: BorderRadius.circular(WdRadius.r12),
              boxShadow: WdShadows.floating,
            ),
            // 테두리는 위에 그려 글자 자리를 밀지 않는다.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WdRadius.r12),
              border: Border.all(color: WdColors.line),
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final sort in options)
                    Semantics(
                      container: true,
                      button: true,
                      label: sort.label,
                      excludeSemantics: true,
                      onTap: () => Navigator.of(context).pop(sort),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(sort),
                        // 메뉴는 적어도 `인기순 ▾`보다 양옆으로 여백만큼 넓다.
                        child: Container(
                          constraints: BoxConstraints(minWidth: label.width + side * 2),
                          padding: const EdgeInsets.symmetric(horizontal: side, vertical: _rowPadding),
                          child: Text(sort.label, style: text.copyWith(color: WdColors.muted)),
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

/// 정렬 메뉴를 `인기순 ▾` 바로 아래, 메뉴 안 글자가 `인기순 ▾`과 같은 왼쪽 끝에 오게 둔다. 화면을 넘으면 안으로 민다.
class _SortMenuLayout extends SingleChildLayoutDelegate {
  const _SortMenuLayout(this.label);

  final Rect label;

  static const _screenMargin = WdSpace.s8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width - _screenMargin;
    final left = math.max(_screenMargin, math.min(label.left - _SortMenu.side, maxLeft));
    return Offset(left, label.bottom + _SortMenu.gap);
  }

  @override
  bool shouldRelayout(_SortMenuLayout oldDelegate) => oldDelegate.label != label;
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(WdSpace.s24),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}
