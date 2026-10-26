import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/map/geo_point.dart';
import '../course/course_format.dart';
import '../course/course_list_card.dart';

/// 지도 범위(남서쪽 · 북동쪽 끝).
typedef MapArea = ({GeoPoint southWest, GeoPoint northEast});

/// 목록 시트가 얼마나 올라와 있나.
enum SheetStage {
  /// 제목 줄만 보인다(A4 · A5 피크).
  peek,

  /// 지도와 목록이 반씩(A2).
  half,

  /// 목록 전체 보기(A6).
  full,
}

/// 홈의 코스 목록 시트(A2 · A5 피크 · A6). 지도와 같은 범위 · 필터의 코스를 보인다(MAP-07 · A2-04).
/// 시트는 위쪽 제목 줄 · 칩 줄을 끌어 올리고 내린다. 그 아래 목록은 시트가 반이어도 따로 스크롤되고(A2-06),
/// 끝까지 내리면 다음 쪽을 이어 받는다(A6-04).
///
/// 칩 줄은 `인기순` · `평점순` · `가까운순` · `최신순` · `실시간순`(누르면 바로 정렬) · 슬라이더 아이콘(A3 열기)이다.
/// 화면이 좁아 다 들어가지 않으면 칩 줄을 옆으로 민다. G6에서 고른 검색어 · 지역이 있으면 제목이
/// `영등포구 ‘한강’ 코스 12`로 바뀐다. 조건은 홈 검색창에 보이고 거기서 푼다(A6-01).
///
/// 카드가 보이는 동안(반 · 전체 보기, 앱이 앞에 있고 홈 위에 다른 화면이 없을 때) [runnersRefreshInterval]마다
/// 카드의 현재 러너 수만 새로 받는다(공통 7 · HCR-05). 목록 순서 · 스크롤은 그대로라
/// 실시간순 순서는 지도를 움직이거나 정렬을 바꿔 목록을 다시 받을 때 바뀐다.
class CourseListSheet extends ConsumerStatefulWidget {
  const CourseListSheet({
    super.key,
    required this.area,
    required this.totalCount,
    this.filter = CourseFilter.none,
    this.pick,
    this.sort = CourseListSort.initial,
    this.period,
    this.myLocation,
    this.selected,
    required this.stage,
    required this.scrollController,
    required this.now,
    this.onExpand,
    this.onShowAll,
    this.onSort,
    this.onOpenFilter,
    this.onResetFilter,
    this.onWidenMap,
    this.onCreateCourse,
    this.onOpenCourse,
  });

  /// 제목 줄 높이. 피크일 때 이만큼만 보인다.
  static const peekHeight = 60.0;

  /// 현재 러너 수를 다시 받는 주기(공통 7 `홈은 1분마다 조회`).
  static const runnersRefreshInterval = Duration(minutes: 1);

  static const loadFailedMessage = '코스를 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';
  static const emptyMessage = '이 지역에 등록된 코스가 없어요';

  /// 칩 줄 끝 슬라이더 아이콘 칩(A3 열기)의 읽어 주는 이름.
  static const filterLabel = '필터';

  /// 필터 결과 0건(STA-04). 코스가 없는 지역(STA-01)과 다르게 보인다.
  static const filteredEmptyMessage = '조건에 맞는 코스가 없어요';

  /// G6 조건이 걸린 목록 제목 `영등포구 ‘한강’ 코스 12`. G6 줄의 `한강 코스 12개`와 같은 말이고, 수는 지도에 보이는 범위 안이다.
  static String pickTitle(CourseSearchPick pick, int? total) =>
      '${pick.region.name} ‘${pick.query}’ 코스${total == null ? '' : ' ${formatCount(total)}'}';

  /// 지금 지도 범위. 지도가 처음 멈추기 전이면 null.
  final MapArea? area;

  /// 지도에 보이는 범위 안 필터에 맞는 코스 수. 제목 `지금 달리기 좋은 코스 N`(G6 조건이 있으면 [pickTitle]),
  /// 피크 `코스 N`. 아직 모르면 null.
  final int? totalCount;

  /// 지금 걸린 필터(A3). 지도와 같다.
  final CourseFilter filter;

  /// G6에서 고른 검색어 · 지역(SEA-04). 지도와 같다. 없으면 null.
  final CourseSearchPick? pick;
  final CourseListSort sort;

  /// 인기순 기간(FIL-09, A3). 인기순일 때만 있고 목록 순서만 바꾼다. null이면 전체 기간.
  final CoursePeriod? period;

  /// 현재 위치. 가까운순의 기준점이고, 있으면 카드에 출발점까지 거리를 보인다. 가까운순이면 꼭 있다.
  final GeoPoint? myLocation;
  final SheetStage stage;

  /// 지도에서 고른 코스(MAP-03). 있으면 목록에 이 코스만 보이고 정렬 칩은 숨긴다.
  final CourseListItem? selected;

  /// 시트를 끄는 스크롤. [DraggableScrollableSheet]가 준다. 제목 줄 · 정렬 칩에만 붙인다.
  final ScrollController scrollController;

  /// 카드의 만료까지 남은 날을 세는 기준 시각.
  final DateTime Function() now;

  /// 피크일 때 제목 줄을 눌렀다(A2로 올린다).
  final VoidCallback? onExpand;

  /// 반(A2)일 때 `전체 보기`를 눌렀다(A6로 올린다, A2-06).
  final VoidCallback? onShowAll;

  /// 정렬 칩을 눌렀다. 가까운순은 현재 위치를 받은 뒤에 바뀐다.
  final ValueChanged<CourseListSort>? onSort;

  /// 슬라이더 아이콘 칩을 눌렀다(A3 열기, A2-04 · A6-02).
  final VoidCallback? onOpenFilter;

  /// 필터 결과 0건에서 `필터 초기화`를 눌렀다(STA-04). A3 필터와 G6 조건을 함께 푼다.
  final VoidCallback? onResetFilter;

  /// 코스가 없을 때 `지도 범위 넓히기`(STA-01).
  final VoidCallback? onWidenMap;

  /// 코스가 없을 때 · 전체 보기의 `코스 만들기`(STA-01 · A6-06).
  final VoidCallback? onCreateCourse;

  /// 코스 카드를 눌렀다. 코스 상세(B1)를 연다(A2-05 · A6-03).
  final ValueChanged<CourseListItem>? onOpenCourse;

  @override
  ConsumerState<CourseListSheet> createState() => _CourseListSheetState();
}

/// 목록을 받은 조건. 다음 쪽도 이 조건으로 받는다.
typedef _ListQuery = ({
  MapArea area,
  CourseFilter filter,
  CourseSearchPick? pick,
  CourseListSort sort,
  CoursePeriod? period,
  GeoPoint? origin,
});

class _CourseListSheetState extends ConsumerState<CourseListSheet> {
  /// 칩 30 + 아래 12.
  static const _chipRowHeight = 30.0 + WdSpace.s12;

  /// 제목 줄 + 칩 줄. 시트를 끄는 부분이다. 고른 코스만 보일 때는 칩이 없다.
  double get _headerExtent => CourseListSheet.peekHeight + (widget.selected == null ? _chipRowHeight : 0);

  /// 목록 스크롤. 시트 크기와 따로 움직인다.
  final _list = ScrollController();

  /// 남은 스크롤이 이보다 짧으면 다음 쪽을 받는다.
  static const _loadMoreExtent = 400.0;

  List<CourseListItem>? _courses;

  /// [_courses]를 받은 조건. 다음 쪽도 이 조건으로 받는다.
  _ListQuery? _listed;
  String? _nextCursor;

  /// 처음 조회가 실패했다(QST-02). 한 번이라도 받았으면 갱신 실패는 전에 받은 목록을 둔다.
  var _failed = false;
  var _loadingMore = false;
  var _moreFailed = false;

  /// 가장 최근 첫 쪽 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  /// 가장 최근에 받기 시작한 조건.
  _ListQuery? _requested;

  /// 1분 갱신으로 받은 현재 러너 수(courseId → 러너 수). 카드에 받아 둔 값보다 새것이라 이 값을 보인다.
  /// 목록 쪽을 새로 받으면 그 쪽 코스의 값은 버린다(목록 값이 더 새것). 지도에서 고른 코스(A5)는 목록에 없어도 남는다.
  var _runners = const <String, int>{};
  late final Timer _runnersTimer;
  late final AppLifecycleListener _lifecycle;

  /// 홈이 보이는지. 다른 하단 탭에 있거나 위에 다른 화면(B1 · A3 · G1 등)을 열면 꺼진다.
  var _onScreen = true;

  /// 카드가 안 보이는 동안 갱신 때를 지나쳤다. 다시 보이면 바로 받는다.
  var _runnersMissed = false;

  /// 지금 보여야 할 목록의 조건. 지도가 처음 멈추기 전이면 null.
  _ListQuery? get _query {
    final area = widget.area;
    if (area == null) return null;
    final nearest = widget.sort == CourseListSort.nearest;
    return (
      area: area,
      filter: widget.filter,
      pick: widget.pick,
      sort: widget.sort,
      period: widget.period,
      origin: nearest ? widget.myLocation : null,
    );
  }

  @override
  void initState() {
    super.initState();
    final query = _query;
    if (query != null) _load(query);
    _runnersTimer = Timer.periodic(CourseListSheet.runnersRefreshInterval, (_) => _refreshRunners());
    _lifecycle = AppLifecycleListener(onResume: _shownAgain);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 하단 탭이 바뀌거나 위에 연 화면이 다 덮으면 꺼진다(go_router 탭 · Navigator가 가려진 화면의 TickerMode를 끈다).
    final onScreen = TickerMode.valuesOf(context).enabled;
    final cameBack = onScreen && !_onScreen;
    _onScreen = onScreen;
    if (cameBack) _shownAgain();
  }

  @override
  void dispose() {
    _runnersTimer.cancel();
    _lifecycle.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 카드가 보이는지. 피크(제목 줄만)이거나 홈이 가려졌거나 앱이 뒤로 가면 안 보인다.
  bool get _visible =>
      _onScreen &&
      widget.stage != SheetStage.peek &&
      (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;

  /// 카드가 다시 보이거나 앱으로 돌아왔다. 가려진 동안 갱신 때를 지나쳤으면 바로 받는다.
  void _shownAgain() {
    if (_runnersMissed) _refreshRunners();
  }

  /// 보이는 카드(받은 목록 · 지도에서 고른 코스)의 현재 러너 수만 새로 받는다(공통 7 · HCR-05). 순서 · 스크롤은 그대로다.
  /// 카드가 안 보이면 받지 않고 다시 보일 때 받는다. 실패하면 다음 갱신까지 받아 둔 값을 둔다(QST-02).
  Future<void> _refreshRunners() async {
    if (!_visible) {
      _runnersMissed = true;
      return;
    }
    _runnersMissed = false;
    final ids = {...?_courses?.map((course) => course.courseId), ?widget.selected?.courseId}.toList();
    if (ids.isEmpty) return;
    final api = ref.read(courseApiClientProvider);
    final runners = <String, int>{};
    try {
      for (var start = 0; start < ids.length; start += CourseApiClient.maxRunnerCourses) {
        final end = math.min(start + CourseApiClient.maxRunnerCourses, ids.length);
        runners.addAll(await api.activeRunners(ids.sublist(start, end)));
      }
    } on ApiException {
      return;
    }
    if (!mounted) return;
    setState(() => _runners = {..._runners, ...runners});
  }

  /// [page]를 새로 받았다. 그 코스들은 1분 갱신 값보다 목록 값이 새것이다.
  void _forgetRunnersOf(List<CourseListItem> page) {
    final ids = {for (final course in page) course.courseId};
    _runners = {
      for (final MapEntry(:key, :value) in _runners.entries)
        if (!ids.contains(key)) key: value,
    };
  }

  /// [course]에 1분 갱신으로 받은 현재 러너 수를 넣는다.
  CourseListItem _latest(CourseListItem course) {
    final runners = _runners[course.courseId];
    return runners == null || runners == course.activeRunners ? course : course.withActiveRunners(runners);
  }

  /// 범위 · 필터 · G6 조건 · 정렬 · 기간이나 가까운순의 현재 위치가 바뀌면 다시 받는다. 카드 거리만 바뀌면 다시 받지 않는다.
  @override
  void didUpdateWidget(CourseListSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = _query;
    if (query != null && query != _requested) _load(query);
    if (oldWidget.stage == SheetStage.peek && widget.stage != SheetStage.peek) _shownAgain();
  }

  /// [query]의 첫 쪽을 받는다.
  Future<void> _load(_ListQuery query) async {
    final request = ++_request;
    _requested = query;
    setState(() => _failed = false);
    try {
      final page = await _page(query);
      if (!mounted || request != _request) return;
      // 새 조건의 목록은 맨 위부터 보인다.
      if (_list.hasClients) _list.jumpTo(0);
      setState(() {
        _courses = page.courses;
        _nextCursor = page.nextCursor;
        _listed = query;
        _loadingMore = false;
        _moreFailed = false;
        _forgetRunnersOf(page.courses);
      });
    } on ApiException {
      if (!mounted || request != _request) return;
      setState(() => _failed = _courses == null);
    }
  }

  Future<CourseListPage> _page(_ListQuery query, {String? cursor}) => ref.read(courseApiClientProvider).listCourses(
        southWest: query.area.southWest,
        northEast: query.area.northEast,
        filter: query.filter,
        pick: query.pick,
        sort: query.sort,
        period: query.period,
        origin: query.origin,
        cursor: cursor,
      );

  /// 지금 목록의 다음 쪽을 받아 붙인다.
  Future<void> _loadMore() async {
    final query = _listed, cursor = _nextCursor;
    if (query == null || cursor == null || _loadingMore || _moreFailed || widget.selected != null) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await _page(query, cursor: cursor);
      // 그사이 지도 · 조건이 바뀌어 첫 쪽을 다시 받았으면 버린다.
      if (!mounted || request != _request) return;
      setState(() {
        _courses = [...?_courses, ...page.courses];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
        _forgetRunnersOf(page.courses);
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

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // 고른 코스가 있으면 그 코스 하나만 보인다. 범위 목록은 계속 받아 두었다가 선택을 풀면 보인다.
    final courses = selected == null ? _courses : [selected];
    final now = widget.now();
    return Container(
      decoration: const BoxDecoration(
        color: WdColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: WdColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            // 제목 줄 · 정렬 칩을 끌면 시트가 움직인다. 피크일 때는 제목 줄만 보인다.
            SizedBox(
              height: math.min(_headerExtent, constraints.maxHeight),
              child: SingleChildScrollView(
                controller: widget.scrollController,
                // 내용이 칸에 맞아도 끌기를 받아 시트로 넘긴다.
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    if (selected == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: WdSpace.s12),
                        // 좁은 화면에서는 옆으로 민다. 칩은 화면 끝까지 밀려 나간다.
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16),
                          // Figma A2 Course filters: 간격 8, 끝에 슬라이더 아이콘 칩.
                          child: Row(
                            spacing: WdSpace.s8,
                            children: [
                              for (final sort in CourseListSort.values)
                                WdFilterChip(sort.label, selected: widget.sort == sort, onTap: () => widget.onSort?.call(sort)),
                              // 조건이나 인기순 기간이 걸려 있으면 검정(글자 칩 선택 모양).
                              WdFilterChip.icon(
                                WdIcons.sliders,
                                semanticLabel: CourseListSheet.filterLabel,
                                selected: !widget.filter.isNone || widget.period != null,
                                onTap: widget.onOpenFilter,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < _loadMoreExtent) _loadMore();
                  return false;
                },
                child: CustomScrollView(
                  controller: _list,
                  slivers: [
                    if (selected == null && courses == null && _failed)
                      SliverToBoxAdapter(
                        child: _message(CourseListSheet.loadFailedMessage, [
                          WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: () => _load(_query!)),
                        ]),
                      )
                    else if (courses == null)
                      const SliverToBoxAdapter(child: _Loading())
                    else if (courses.isEmpty && (!widget.filter.isNone || widget.pick != null))
                      // 조건은 그대로 두고 초기화를 준다(STA-04). G6 조건도 필터처럼 함께 푼다.
                      SliverToBoxAdapter(
                        child: _message(CourseListSheet.filteredEmptyMessage, [
                          WdButton('필터 초기화', variant: WdButtonVariant.secondary, onPressed: widget.onResetFilter),
                        ]),
                      )
                    else if (courses.isEmpty)
                      SliverToBoxAdapter(
                        child: _message(CourseListSheet.emptyMessage, [
                          WdButton('지도 범위 넓히기', variant: WdButtonVariant.secondary, onPressed: widget.onWidenMap),
                          WdButton('코스 만들기', onPressed: widget.onCreateCourse),
                        ]),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16),
                        sliver: SliverList.separated(
                          itemCount: courses.length,
                          separatorBuilder: (_, _) => const SizedBox(height: WdSpace.s12),
                          itemBuilder: (_, index) => CourseListCard(
                            course: _latest(courses[index]),
                            now: now,
                            myLocation: widget.myLocation,
                            onTap: () => widget.onOpenCourse?.call(courses[index]),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: selected == null ? _footer() : const SizedBox(height: WdSpace.s24)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 손잡이 + 제목 줄. 피크일 때는 이것만 보인다(Figma A5 `↑ 위로 올려 코스 목록 보기`).
  Widget _header() {
    final peek = widget.stage == SheetStage.peek;
    final total = widget.totalCount;
    final pick = widget.pick;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: peek ? widget.onExpand : null,
      child: SizedBox(
        height: CourseListSheet.peekHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s10, WdSpace.s16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WdSpace.s8,
            children: [
              // Figma 그대로 왼쪽 정렬 손잡이.
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: WdColors.map, borderRadius: BorderRadius.circular(2)),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Figma A6 `주변 인기 코스 24`처럼 제목 뒤에 지도에 보이는 범위 안 코스 수.
                      peek
                          ? '↑ 위로 올려 코스 목록 보기'
                          : widget.selected != null
                              ? '선택한 코스'
                              : pick != null
                                  ? CourseListSheet.pickTitle(pick, total)
                                  : total == null
                                      ? '지금 달리기 좋은 코스'
                                      : '지금 달리기 좋은 코스 ${formatCount(total)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WdText.ko16Bold.copyWith(color: WdColors.ink),
                    ),
                  ),
                  // 전체 보기(A6)에는 지도 위 버튼이 없어 여기서 코스를 만든다(A6-06).
                  if (widget.stage == SheetStage.full)
                    GestureDetector(
                      onTap: widget.onCreateCourse,
                      child: Text('＋ 코스 만들기', style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.green)),
                    )
                  else if (widget.stage == SheetStage.half)
                    GestureDetector(
                      onTap: widget.onShowAll,
                      child: Text('전체 보기', style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
                    )
                  else if (total != null && widget.selected == null)
                    Text('코스 ${formatCount(total)}', style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String message, List<Widget> actions) => Padding(
        padding: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s24, WdSpace.s16, WdSpace.s24),
        child: Column(
          spacing: WdSpace.s12,
          children: [
            Text(message, textAlign: TextAlign.center, style: WdText.body13.copyWith(color: WdColors.muted)),
            ...actions,
          ],
        ),
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
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(WdSpace.s24),
        child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}
