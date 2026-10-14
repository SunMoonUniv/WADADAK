import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/error_message.dart';
import '../../core/map/map_view.dart';
import '../../routes.dart';
import 'course_list_sheet.dart';

/// 홈(A2). 위에 상단 배너(인사말 · 검색창), 아래에 지도, `＋ 코스 만들기`, 현재 위치 버튼, 코스 목록 시트가 있다.
/// 지도는 축척에 따라 범위 안 코스(경로 · 이름표, A5)나 지역별 코스 수 배지(A4)를 보인다(MAP-02).
/// 목록 시트는 지도와 같은 범위의 코스이고(MAP-07), 끌어서 피크(A4 · A5) · 반(A2) · 전체(A6, 배너 밑까지)에 멈춘다.
/// 검색 화면(G1) 연결과 필터는 F2 다음 단계에서 붙인다.
/// 확대·축소 버튼은 두지 않는다(정책 MAP-02, 제스처로 한다).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.now = DateTime.now});

  /// 카드의 만료까지 남은 날을 세는 기준 시각. 테스트가 바꾼다.
  final DateTime Function() now;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _loadFailedMessage = '코스를 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';

  MapController? _map;

  /// 지금 보고 있는 지도 위치. 코스 만들기를 같은 곳에서 시작한다(A2-07).
  MapCamera? _camera;

  /// 지금 지도 범위 안 코스. 출발점이 범위 안에 있는 코스다(MAP-04). 축척 500m부터 보인다.
  List<MapCourse> _courses = const [];

  /// 지금 지도 범위 안 지역별 코스 수. 축척 500m보다 넓을 때 [_courses] 대신 보인다.
  List<RegionCount> _regions = const [];
  var _loaded = false;

  /// 지도가 센 범위 안 코스 수(시트 제목 `지금 달리기 좋은 코스 N`). 아직 모르면 null.
  int? _totalCount;

  /// 지금 조회한 범위. 시트에 가리지 않고 보이는 지도 부분이다. 목록도 이 범위다(MAP-07).
  MapArea? _area;

  /// 가장 최근 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  final _sheet = DraggableScrollableController();
  var _sheetSize = _halfSize;

  /// 시트가 멈춘 단계. 끄는 중에는 바뀌지 않는다.
  var _settledStage = SheetStage.half;

  /// 지도가 보이는 마지막 단계(피크 · 반). 전체 보기(A6)는 이 단계에서 보이던 범위를 그대로 쓴다.
  var _mapStage = SheetStage.half;

  /// 시트 아래 지도 영역 높이. 화면을 그릴 때 정한다.
  var _mapHeight = 0.0;

  /// 시트 처음 크기. 지도와 목록이 반씩이다(A2).
  static const _halfSize = 0.5;

  /// 최대 축소. 축척 막대가 50km보다 넓어지지 않는다(MAP-02). 줌 6은 제주(위도 33°)부터 강원 북쪽(38.6°)까지 50km다.
  static const _minZoom = 6.0;

  /// 버튼 줄 여백. 양옆은 검색창 테두리와 같은 16, 아래는 시트까지 12.
  static const _buttonRowPadding = EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s16, WdSpace.s16, WdSpace.s12);

  // 위아래 여백 + 현재 위치 버튼.
  static const _buttonRowHeight = WdSpace.s16 + WdSpace.s12 + WdMapLocateButton.size;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  /// 코스를 등록하고 돌아오면 지도를 새 코스 출발점으로 옮긴다(B4-07). 줌은 그대로 둔다.
  Future<void> _createCourse() async {
    final course = await context.push<RegisteredCourse>(Routes.courseCreate, extra: _camera);
    if (course != null) await _map?.moveTo(course.startPoint);
  }

  void _onCameraIdle(MapCamera camera) {
    setState(() => _camera = camera);
    _load(camera);
  }

  /// 시트가 피크 · 반 · 전체 중 한 곳에 멈췄다. 보이는 지도 부분이 바뀌었으면 다시 받는다.
  /// 전체 보기(A6)는 지도가 안 보이니 그 전 범위를 그대로 둔다.
  void _onSheetSettled(SheetStage stage) {
    _settledStage = stage;
    if (stage == SheetStage.full || stage == _mapStage) return;
    _mapStage = stage;
    final camera = _camera;
    if (camera != null) _load(camera);
  }

  /// [camera] 범위 중 시트에 가리지 않은 위쪽 부분. 지도는 메르카토르라 위도가 화면 높이에 비례하지 않아 메르카토르 y로 나눈다.
  /// 버튼 · 코스 수 칩은 작고 그 사이로 지도가 보여 가린 것으로 치지 않는다.
  MapArea _visibleArea(MapCamera camera) {
    final covered = switch (_mapStage) {
      SheetStage.peek => CourseListSheet.peekHeight,
      _ => _mapHeight * _halfSize,
    };
    final visible = _mapHeight <= 0 ? 1.0 : (1 - covered / _mapHeight).clamp(0.0, 1.0);
    double mercator(double lat) => math.log(math.tan(math.pi / 4 + lat * math.pi / 360));
    double latitude(double y) => (2 * math.atan(math.exp(y)) - math.pi / 2) * 180 / math.pi;
    final top = mercator(camera.northEast.lat), bottom = mercator(camera.southWest.lat);
    return (
      southWest: GeoPoint(latitude(top + (bottom - top) * visible), camera.southWest.lng),
      northEast: camera.northEast,
    );
  }

  /// 축척으로 정하는 지도 표시(MAP-02). 축척 2km보다 넓으면 시 단위, 2km부터 500m 전까지 구 단위 코스 수,
  /// 500m부터는 개별 코스(null)다.
  static RegionLevel? _regionLevel(MapCamera camera) => switch (camera.scaleMeters) {
        > 2000 => RegionLevel.city,
        > 500 => RegionLevel.district,
        _ => null,
      };

  /// 지도가 멈추거나 시트가 다른 단계에 멈출 때마다 보이는 범위 안 코스나 지역별 코스 수를 다시 받는다.
  Future<void> _load(MapCamera camera) async {
    final request = ++_request;
    final api = ref.read(courseApiClientProvider);
    final area = _visibleArea(camera);
    setState(() => _area = area);
    try {
      var courses = const <MapCourse>[];
      var regions = const <RegionCount>[];
      final int total;
      switch (_regionLevel(camera)) {
        case null:
          final map = await api.mapCourses(southWest: area.southWest, northEast: area.northEast);
          (courses, total) = (map.courses, map.totalCount);
        case final level:
          final counts = await api.regionCounts(southWest: area.southWest, northEast: area.northEast, level: level);
          (regions, total) = (counts.regions, counts.totalCount);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _courses = courses;
        _regions = regions;
        _totalCount = total;
        _loaded = true;
      });
    } on ApiException catch (e) {
      // 처음 조회가 실패하면 알리고 다시 시도하게 한다. 그 뒤 갱신이 실패하면 전에 받은 것을 둔다(QST-02 · STA-02).
      if (!mounted || request != _request || _loaded) return;
      showError(context, e, message: _loadFailedMessage, onRetry: () => _load(_camera ?? camera));
    }
  }

  /// 시트를 [size]로 옮긴다.
  void _moveSheet(double size) =>
      _sheet.animateTo(size, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);

  /// 코스가 없을 때 한 단계 축소한다(STA-01 `지도 범위 넓히기`).
  void _widenMap() {
    final camera = _camera;
    if (camera != null) _map?.moveTo(camera.center, zoom: camera.zoom - 1);
  }

  static SheetStage _stage(double size, double peekSize) {
    if (size <= peekSize + 0.01) return SheetStage.peek;
    if (size <= _halfSize + 0.01) return SheetStage.half;
    return SheetStage.full;
  }

  /// 1240 → "1,240"(Figma A4).
  static String _count(int count) => count.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

  @override
  Widget build(BuildContext context) => Scaffold(
        body: LayoutBuilder(builder: (context, constraints) {
          // 상단 배너 아래 영역 높이. 시트 크기는 이 높이에 대한 비율이다.
          final height = constraints.maxHeight - MediaQuery.paddingOf(context).top - _HomeHeader.height;
          _mapHeight = height;
          final peekSize = CourseListSheet.peekHeight / height;
          final stage = _stage(_sheetSize, peekSize);
          return Column(children: [
            _HomeHeader(stage: stage),
            Expanded(child: Stack(
            children: [
              MapView(
                minZoom: _minZoom,
                // 피크 시트와 아래 버튼 줄만큼 비워 네이버 로고·축척이 가리지 않게 한다.
                padding: const EdgeInsets.only(bottom: CourseListSheet.peekHeight + _buttonRowHeight),
                lines: [for (final course in _courses) MapLine(id: 'course-${course.courseId}', points: course.route)],
                markers: [
                  // 이름표 아래 가운데가 출발점에 온다.
                  for (final course in _courses)
                    MapMarker(
                      id: 'course-${course.courseId}',
                      position: course.route.first,
                      child: WdMapCourseLabel(course.name),
                      imageKey: 'course-label:${course.name}',
                      anchor: MapMarker.bottom,
                    ),
                  // 배지 가운데가 그 지역 코스 출발점들의 가운데에 온다(A4-01).
                  for (final region in _regions)
                    MapMarker(
                      id: 'region-${region.code}',
                      position: region.center,
                      child: WdRegionCountBubble(count: _count(region.count), region: region.name),
                      imageKey: 'region-count:${region.name}:${region.count}',
                    ),
                ],
                onCreated: (map) => _map = map,
                onCameraIdle: _onCameraIdle,
                // 지도를 누르면 시트를 내려 지도 전체 보기(A2-03).
                onTap: (_) {
                  if (stage != SheetStage.peek) _moveSheet(peekSize);
                },
              ),
              // 버튼 줄은 시트 바로 위에 붙어 다닌다. 전체 보기(A6)에서는 숨긴다.
              Positioned(
                left: 0,
                right: 0,
                bottom: _sheetSize * height,
                child: IgnorePointer(
                  ignoring: stage == SheetStage.full,
                  child: AnimatedOpacity(
                    opacity: stage == SheetStage.full ? 0 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: _buttonRowPadding,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          WdMapPillButton.small('＋ 코스 만들기', onPressed: _createCourse),
                          WdMapLocateButton(onPressed: () => _map?.showMyLocation()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  final size = notification.extent;
                  setState(() => _sheetSize = size);
                  // 멈출 수 있는 크기(피크 · 반 · 전체)에 닿았을 때만 멈춘 것으로 본다.
                  final settled = [peekSize, _halfSize, notification.maxExtent]
                      .indexWhere((snap) => (size - snap).abs() < 0.002);
                  if (settled >= 0 && SheetStage.values[settled] != _settledStage) {
                    _onSheetSettled(SheetStage.values[settled]);
                  }
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: _halfSize,
                  minChildSize: peekSize,
                  maxChildSize: 1,
                  snap: true,
                  snapSizes: const [_halfSize],
                  builder: (context, scrollController) => CourseListSheet(
                    area: _area,
                    totalCount: _totalCount,
                    stage: stage,
                    scrollController: scrollController,
                    now: widget.now,
                    onExpand: () => _moveSheet(_halfSize),
                    onShowAll: () => _moveSheet(1),
                    onWidenMap: _widenMap,
                    onCreateCourse: _createCourse,
                  ),
                ),
              ),
            ],
          )),
          ]);
        }),
      );
}

/// 상단 배너(A2-01 · A2-02). A2(반)는 인사말, 피크(A4 · A5) · 전체 보기(A6)는 고정 제목 `코스`, 아래는 검색창.
/// 높이가 같아 바뀌어도 지도 크기가 그대로다.
///
/// 검색창은 검색 화면(G1)이 생기면 연결한다(SEA-01). Figma A2의 위치 핀 버튼은 정책에 동작이 없어 두지 않는다.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.stage});

  final SheetStage stage;

  /// Figma A6: 앱 바 70.5 + 검색 52.
  static const height = 122.5;
  static const _titleHeight = 70.5;

  @override
  Widget build(BuildContext context) {
    final greeting = stage == SheetStage.half;
    return ColoredBox(
      color: WdColors.paper,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _titleHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: greeting
                        ? [
                            Text('오늘, 어디까지 달려볼까요?', style: WdText.ko12.copyWith(color: WdColors.muted)),
                            Text('나의 다음 코스', style: WdText.ko23Bold.copyWith(color: WdColors.ink)),
                          ]
                        : [Text('코스', style: WdText.ko20Bold.copyWith(color: WdColors.ink))],
                  ),
                ),
              ),
              Padding(
                // 검색창 42 + 아래 10 = Figma 검색 52.
                padding: const EdgeInsets.fromLTRB(WdSpace.s16, 0, WdSpace.s16, WdSpace.s10),
                child: WdSearchBar(
                  hintText: '원하는 키워드를 검색하세요',
                  // 검색 화면(G1)이 생기면 연다. 그때까지 키보드가 뜨지 않게 누르기만 받는다.
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

