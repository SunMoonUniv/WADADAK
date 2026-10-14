import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/map/geo_point.dart';
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

/// 홈의 코스 목록 시트(A2 · A5 피크 · A6). 지도와 같은 범위의 코스를 최신순으로 보인다(MAP-07).
/// 아래로 끝까지 내리면 다음 쪽을 이어 받는다(A6-04).
///
/// 정렬은 지금 최신순 하나다. 인기순 · 평점순 · 실시간순은 코스 통계(F11), 가까운순은 현재 위치(`LocationService`)가 생기면 붙인다.
class CourseListSheet extends ConsumerStatefulWidget {
  const CourseListSheet({
    super.key,
    required this.area,
    required this.totalCount,
    required this.stage,
    this.topPadding = 0,
    required this.scrollController,
    required this.now,
    this.onExpand,
    this.onWidenMap,
    this.onCreateCourse,
  });

  /// 제목 줄 높이. 피크일 때 이만큼만 보인다.
  static const peekHeight = 60.0;

  static const loadFailedMessage = '코스를 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';
  static const emptyMessage = '이 지역에 등록된 코스가 없어요';

  /// 지금 지도 범위. 지도가 처음 멈추기 전이면 null.
  final MapArea? area;

  /// 지도가 센 범위 안 코스 수(`코스 N`). 아직 모르면 null.
  final int? totalCount;
  final SheetStage stage;

  /// 시트 위쪽이 상태 표시줄 밑에 들어간 만큼. 내용을 이만큼 내린다.
  final double topPadding;

  /// 시트를 끄는 스크롤. [DraggableScrollableSheet]가 준다.
  final ScrollController scrollController;

  /// 카드의 만료까지 남은 날을 세는 기준 시각.
  final DateTime Function() now;

  /// 피크일 때 제목 줄을 눌렀다(A2로 올린다).
  final VoidCallback? onExpand;

  /// 코스가 없을 때 `지도 범위 넓히기`(STA-01).
  final VoidCallback? onWidenMap;

  /// 코스가 없을 때 · 전체 보기의 `코스 만들기`(STA-01 · A6-06).
  final VoidCallback? onCreateCourse;

  @override
  ConsumerState<CourseListSheet> createState() => _CourseListSheetState();
}

class _CourseListSheetState extends ConsumerState<CourseListSheet> {
  /// 남은 스크롤이 이보다 짧으면 다음 쪽을 받는다.
  static const _loadMoreExtent = 400.0;

  List<CourseListItem>? _courses;

  /// [_courses]를 받은 범위. 다음 쪽도 이 범위로 받는다.
  MapArea? _listedArea;
  String? _nextCursor;

  /// 처음 조회가 실패했다(QST-02). 한 번이라도 받았으면 갱신 실패는 전에 받은 목록을 둔다.
  var _failed = false;
  var _loadingMore = false;
  var _moreFailed = false;

  /// 가장 최근 첫 쪽 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.area != null) _load(widget.area!);
  }

  @override
  void didUpdateWidget(CourseListSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.area != null && widget.area != oldWidget.area) _load(widget.area!);
  }

  /// [area]의 첫 쪽을 받는다.
  Future<void> _load(MapArea area) async {
    final request = ++_request;
    setState(() => _failed = false);
    try {
      final page = await ref
          .read(courseApiClientProvider)
          .listCourses(southWest: area.southWest, northEast: area.northEast);
      if (!mounted || request != _request) return;
      setState(() {
        _courses = page.courses;
        _nextCursor = page.nextCursor;
        _listedArea = area;
        _loadingMore = false;
        _moreFailed = false;
      });
    } on ApiException {
      if (!mounted || request != _request) return;
      setState(() => _failed = _courses == null);
    }
  }

  /// 지금 목록의 다음 쪽을 받아 붙인다.
  Future<void> _loadMore() async {
    final area = _listedArea, cursor = _nextCursor;
    if (area == null || cursor == null || _loadingMore || _moreFailed) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(courseApiClientProvider)
          .listCourses(southWest: area.southWest, northEast: area.northEast, cursor: cursor);
      // 그사이 지도가 움직여 첫 쪽을 다시 받았으면 버린다.
      if (!mounted || request != _request) return;
      setState(() {
        _courses = [...?_courses, ...page.courses];
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

  /// 3412 → "3,412".
  static String _count(int count) => count.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final courses = _courses;
    final now = widget.now();
    return Container(
      decoration: const BoxDecoration(
        color: WdColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: WdColors.line)),
      ),
      padding: EdgeInsets.only(top: widget.topPadding),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < _loadMoreExtent) _loadMore();
          return false;
        },
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(WdSpace.s16, 0, WdSpace.s16, WdSpace.s12),
                child: Row(children: [WdFilterChip('최신순', selected: true, onTap: () {})]),
              ),
            ),
            if (courses == null && _failed)
              SliverToBoxAdapter(
                child: _message(CourseListSheet.loadFailedMessage, [
                  WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: () => _load(widget.area!)),
                ]),
              )
            else if (courses == null)
              const SliverToBoxAdapter(child: _Loading())
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
                  // 코스 상세(B1)가 생기면 카드를 눌러 연다(A2-05).
                  itemBuilder: (_, index) => CourseListCard(course: courses[index], now: now),
                ),
              ),
              SliverToBoxAdapter(child: _footer()),
            ],
          ],
        ),
      ),
    );
  }

  /// 손잡이 + 제목 줄. 피크일 때는 이것만 보인다(Figma A5 `↑ 위로 올려 코스 목록 보기`).
  Widget _header() {
    final peek = widget.stage == SheetStage.peek;
    final total = widget.totalCount;
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
                      peek ? '↑ 위로 올려 코스 목록 보기' : '지금 달리기 좋은 코스',
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
                  else if (total != null)
                    Text('코스 ${_count(total)}', style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
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
