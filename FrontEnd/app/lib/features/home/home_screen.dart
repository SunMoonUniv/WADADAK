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
import '../course/course_format.dart';
import 'course_filter_screen.dart';
import 'course_list_sheet.dart';
import 'home_tab_exits.dart';
import 'my_location.dart';

/// 홈(A2). 위에 상단 배너(인사말 · 검색창), 아래에 지도, `＋ 코스 만들기`, 현재 위치 버튼, 코스 목록 시트가 있다.
/// 지도는 축척에 따라 범위 안 코스(경로 · 이름표, A5)나 지역별 코스 수 배지(A4)를 보인다(MAP-02).
/// 목록 시트는 지도와 같은 범위의 코스이고(MAP-07), 끌어서 피크(A4 · A5) · 반(A2) · 전체(A6, 배너 밑까지)에 멈춘다.
/// 지도에서 코스 이름표를 누르면 그 코스만 남기고 목록에도 그 코스만 보인다(MAP-03 선택). 지도의 다른 곳을 누르면 풀린다.
/// 이름표가 겹치면 인기순 위 코스의 이름표만 보이고, 경로는 모두 그리되 인기순 위 코스를 위에 그린다(MAP-03 겹침).
/// 필터(A3)를 걸면 지도 · 지역별 코스 수 · 목록이 모두 그 조건의 코스만 보인다(A2-04).
/// 검색 화면(G1) 연결은 F2 다음 단계에서 붙인다.
/// 확대·축소 버튼은 두지 않는다(정책 MAP-02, 제스처로 한다).
/// 다른 하단 탭으로 떠나면 탐색 상태를 처음으로 되돌려 둔다(FIL-08, [HomeTabExits]).
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
  /// 서버가 인기순(전체 기간)으로 준다. 앞 코스일수록 겹칠 때 위에 보인다(MAP-03).
  List<CourseListItem> _courses = const [];

  /// 지도에서 고른 코스(MAP-03). 고르는 동안 지도 · 목록에 이 코스만 보이고, 지도를 움직이거나 축소해도 그대로다.
  CourseListItem? _selected;

  /// 지금 지도 범위 안 지역별 코스 수. 축척 500m보다 넓을 때 [_courses] 대신 보인다.
  List<RegionCount> _regions = const [];

  /// [_regions]를 센 단위(시 · 구). 배지를 누르면 다음 단계로 확대한다.
  var _regionsLevel = RegionLevel.city;
  var _loaded = false;

  /// 지도가 센 범위 안 코스 수(시트 제목 `지금 달리기 좋은 코스 N`). 아직 모르면 null.
  int? _totalCount;

  /// 지금 조회한 범위. 시트에 가리지 않고 보이는 지도 부분이다. 목록도 이 범위다(MAP-07).
  MapArea? _area;

  /// 지금 걸린 필터 · 정렬(A3 · 목록 칩). 지도 · 목록이 같은 필터를 쓴다.
  var _filter = CourseFilter.none;
  var _sort = CourseListSort.initial;

  /// 인기순 기간(A3 기간 슬라이더, FIL-09). 인기순일 때만 있고 목록 순서만 바꾼다. 다른 정렬로 바꾸면 전체로 되돌린다.
  CoursePeriod? _period;

  /// 현재 위치. 가까운순의 기준점이고 카드의 `0.8km 거리`에 쓴다. 위치 권한이 이미 있으면 홈을 열 때 받는다.
  GeoPoint? _myLocation;

  /// 지도가 준비되면(처음 멈추면) 옮길 현재 위치. 지도보다 위치가 먼저 오면 여기 두었다가 바로 맞춘다.
  GeoPoint? _pendingMine;

  /// 홈을 열 때 · 다른 하단 탭에서 돌아올 때 카메라 중심을 둔 자리. 카메라가 여기 그대로면 그 사이 지도를 움직이지 않았다.
  GeoPoint? _placedCenter = _startCenter;

  /// 가장 최근 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  /// 다른 하단 탭으로 떠난 횟수([HomeTabExits]). 바뀌면 탐색 상태를 처음으로 되돌린다.
  int? _exits;

  /// 목록 시트를 새로 만든 횟수. 바꾸면 목록이 맨 위 첫 쪽부터 다시 시작한다.
  var _listGeneration = 0;

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

  /// 위치 권한이 없거나 기기에 남은 위치가 없을 때 홈을 여는 자리, 그리고 홈을 여는 줌(축척 200m).
  static const _startCenter = MapView.seoulCityHall;
  static const _startZoom = 14.0;

  /// 최대 축소. 축척 막대가 50km보다 넓어지지 않는다(MAP-02). 줌 6은 제주(위도 33°)부터 강원 북쪽(38.6°)까지 50km다.
  static const _minZoom = 6.0;

  /// 내 위치 버튼의 줌. 제주부터 강원 북쪽까지 축척 막대가 100m다(A4-05).
  static const _myLocationZoom = 15.0;

  /// 시 배지를 누르면 가는 줌. 제주부터 강원 북쪽까지 축척 2km라 구 단위 배지가 보인다(A4-06).
  static const _districtZoom = 11.0;

  /// 구 배지를 누르면 가는 줌. 제주부터 강원 북쪽까지 축척 500m라 개별 코스가 보인다(A4-06).
  static const _coursesZoom = 13.0;

  /// 버튼 줄 여백. 양옆은 검색창 테두리와 같은 16, 아래는 시트까지 12.
  static const _buttonRowPadding = EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s16, WdSpace.s16, WdSpace.s12);

  // 위아래 여백 + 현재 위치 버튼.
  static const _buttonRowHeight = WdSpace.s16 + WdSpace.s12 + WdMapLocateButton.size;

  /// 지도 아래 여백. 피크 시트와 버튼 줄만큼 비워 네이버 로고·축척이 가리지 않게 한다. 카메라 중심은 이 여백을 뺀 영역의 가운데다.
  static const _mapPadding = EdgeInsets.only(bottom: CourseListSheet.peekHeight + _buttonRowHeight);

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final exits = HomeTabExits.of(context);
    if (_exits != null && exits != _exits) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startOver();
      });
    }
    _exits = exits;
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  /// 다른 하단 탭으로 떠났다(FIL-08). 필터 · 정렬 · 고른 코스 · 시트 · 목록 스크롤을 처음으로 되돌리고 지도를 홈을 여는 자리로 옮겨 둔다.
  /// 홈이 가려져 있는 동안 하므로 지도가 움직이는 모습은 보이지 않는다.
  void _startOver() {
    setState(() {
      _filter = CourseFilter.none;
      _sort = CourseListSort.initial;
      _period = null;
      _selected = null;
      _sheetSize = _halfSize;
      _settledStage = SheetStage.half;
      _mapStage = SheetStage.half;
      _listGeneration++;
    });
    // 가려진 동안에는 애니메이션이 멈춰 있어 바로 옮긴다.
    if (_sheet.isAttached) _sheet.jumpTo(_halfSize);
    _goToStart();
  }

  /// 홈을 연다. 지도는 서울시청에서 열고, 위치 권한이 있으면 기기에 남은 마지막 위치로 바로 맞춘다(보통 지도가 준비되기 전에 와서
  /// 서울시청은 보이지 않는다). 이어서 지금 위치를 받는다([_refineStart]). 권한은 묻지 않는다.
  Future<void> _open() async {
    final last = await ref.read(myLocationProvider).lastIfAllowed();
    if (last != null && mounted) _moveToMine(last, animate: false);
    await _refineStart();
  }

  /// 다른 하단 탭에서 돌아올 때 볼 자리로 지도를 옮겨 둔다. 홈을 열 때와 같다.
  Future<void> _goToStart() async {
    final last = await ref.read(myLocationProvider).lastIfAllowed();
    if (!mounted) return;
    _placeStart(last, animate: false);
    await _refineStart();
  }

  /// 지금 위치를 받아 카드 거리에 쓰고 지도도 그 위치로 맞춘다([_moveToMine]).
  Future<void> _refineStart() async {
    final location = await ref.read(myLocationProvider).ifAllowed();
    if (location == null || !mounted) return;
    setState(() => _myLocation = location);
    _moveToMine(location);
  }

  /// 홈을 여는 자리를 현재 위치 [location]으로 맞춘다. 지도가 아직 준비 전이면 처음 멈출 때 맞춘다.
  /// 그 사이 지도를 움직이거나 코스를 골랐으면 옮기지 않는다.
  void _moveToMine(GeoPoint location, {bool animate = true}) {
    if (_camera == null) {
      _pendingMine = location;
    } else if (_untouched) {
      _placeStart(location, animate: animate);
    }
  }

  /// 홈을 여는 자리에 지도를 둔다. [mine](현재 위치)이 있으면 그 위치를 보이는 지도의 한가운데에 두고 현재 위치 점을 켠다(따라가지 않음).
  /// 없으면 서울시청에 두고 점을 끈다. 줌은 [_startZoom]이다.
  void _placeStart(GeoPoint? mine, {bool animate = true}) {
    final center = mine == null ? _startCenter : _viewCenter(mine, zoom: _startZoom);
    _placedCenter = center;
    final camera = _camera;
    if (camera != null && _isAt(camera, center)) {
      // 이미 그 자리라 지도가 멈춤을 알리지 않을 수 있어 바로 다시 받는다.
      _load(camera);
    } else {
      _map?.moveTo(center, zoom: _startZoom, animate: animate);
    }
    if (mine == null) {
      _map?.hideMyLocation();
    } else {
      _map?.showMyLocation(follow: false);
    }
  }

  /// 홈을 연 뒤 지도를 움직이거나 코스를 고르지 않았다.
  bool get _untouched {
    final camera = _camera, placed = _placedCenter;
    return camera != null && placed != null && _selected == null && _isAt(camera, placed);
  }

  static bool _isAt(MapCamera camera, GeoPoint center) =>
      (camera.zoom - _startZoom).abs() < 0.01 && camera.center.distanceTo(center) < 1;

  /// 가까운순 · 내 위치 버튼에 쓸 현재 위치를 받는다. 권한이 없으면 묻는다. 못 받으면 알리고 null이다.
  Future<GeoPoint?> _locate() async {
    final location = await requestMyLocation(context, ref.read(myLocationProvider));
    if (location != null && mounted) setState(() => _myLocation = location);
    return location;
  }

  /// 내 위치 버튼(A4-05). 현재 위치를 보이는 지도의 한가운데에 두고 축척 100m로 확대한다. 현재 위치 점을 보이고(점은 위치를 따라 움직인다)
  /// 지도는 따라가지 않는다. 권한이 없으면 묻고, 거부했거나 위치를 못 받으면 안내만 하고 옮기지 않는다.
  Future<void> _goToMyLocation() async {
    final location = await _locate();
    if (location == null || !mounted) return;
    await _centerInView(location, zoom: _myLocationZoom);
    _map?.showMyLocation(follow: false);
  }

  /// 지역 배지를 눌렀다(A4-06). 그 지역을 보이는 지도의 한가운데에 두고 한 단계 확대한다. 시 → 구 단위, 구 → 개별 코스.
  void _zoomInto(RegionCount region) =>
      _centerInView(region.center, zoom: _regionsLevel == RegionLevel.city ? _districtZoom : _coursesZoom);

  /// [point]를 [stage] 시트(기본은 지금 지도가 보이는 단계) 위로 보이는 지도 부분의 한가운데에 두고 [zoom](기본은 지금 줌)으로 옮긴다.
  /// 지도는 아래 여백([_mapPadding])을 뺀 영역의 가운데에 카메라 중심을 두므로, 그 자리와 보이는 부분의 가운데 차이만큼 카메라를 남북으로 비켜 둔다.
  Future<void> _centerInView(GeoPoint point, {double? zoom, SheetStage? stage}) async {
    final targetZoom = zoom ?? _camera?.zoom;
    await _map?.moveTo(_viewCenter(point, zoom: targetZoom, stage: stage), zoom: targetZoom);
  }

  /// [_centerInView]의 카메라 중심. 지도 범위를 아직 모르면 [point]다.
  GeoPoint _viewCenter(GeoPoint point, {double? zoom, SheetStage? stage}) {
    final camera = _camera;
    if (camera == null || _mapHeight <= 0) return point;
    final targetZoom = zoom ?? camera.zoom;
    final visibleBottom = switch (stage ?? _mapStage) {
      SheetStage.peek => _mapHeight - CourseListSheet.peekHeight,
      _ => _mapHeight * (1 - _halfSize),
    };
    // 카메라 중심이 보이는 부분의 가운데보다 이만큼(dp) 아래에 온다.
    final below = (_mapHeight - _mapPadding.bottom) / 2 - visibleBottom / 2;
    // 지금 범위(지도 전체)로 1dp가 메르카토르 y로 얼마인지 재고, 옮길 줌만큼 줄인다.
    final perDp = (_mercator(camera.northEast.lat) - _mercator(camera.southWest.lat)) /
        _mapHeight /
        math.pow(2, targetZoom - camera.zoom);
    return GeoPoint(_latitude(_mercator(point.lat) - below * perDp), point.lng);
  }

  static double _mercator(double lat) => math.log(math.tan(math.pi / 4 + lat * math.pi / 360));
  static double _latitude(double y) => (2 * math.atan(math.exp(y)) - math.pi / 2) * 180 / math.pi;

  /// 목록 정렬을 바꾼다. 가까운순은 현재 위치를 새로 받은 뒤에 바꾸고, 못 받으면 정렬을 그대로 둔다.
  /// 기간은 인기순에만 있어 정렬을 바꾸면 전체로 되돌린다(FIL-09).
  Future<void> _sortBy(CourseListSort sort) async {
    if (sort == _sort) return;
    if (sort == CourseListSort.nearest && await _locate() == null) return;
    if (!mounted) return;
    setState(() {
      _sort = sort;
      _period = null;
    });
  }

  /// A3를 연다(A2-04 · A6-02). `코스 N개 보기`로 돌아오면 지도 · 목록에 적용한다.
  Future<void> _openFilter() async {
    final area = _area;
    if (area == null) return;
    final choice = await context.push<CourseFilterChoice>(
      Routes.courseFilter,
      extra: (filter: _filter, sort: _sort, period: _period, area: area),
    );
    if (choice == null || !mounted) return;
    _applyFilter(choice.filter);
    await _sortBy(choice.sort);
    // 가까운순을 고르다 위치를 못 받아 정렬이 그대로면 기간도 그대로 둔다.
    if (mounted && _sort == choice.sort && _period != choice.period) setState(() => _period = choice.period);
  }

  /// [filter]를 지도 · 지역별 코스 수 · 목록에 적용한다.
  void _applyFilter(CourseFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    final camera = _camera;
    if (camera != null) _load(camera);
  }

  /// 코스를 등록하고 돌아오면 지도를 새 코스 출발점으로 옮긴다(B4-07). 줌은 그대로 둔다.
  /// 카메라 중심이 출발점이라 다음 코스 만들기도 그곳에서 열린다(A2-07).
  Future<void> _createCourse() async {
    final course = await context.push<RegisteredCourse>(Routes.courseCreate, extra: _camera);
    if (course != null) await _map?.moveTo(course.startPoint);
  }

  void _onCameraIdle(MapCamera camera) {
    setState(() => _camera = camera);
    final mine = _pendingMine;
    if (mine != null) {
      // 지도가 처음 멈췄다. 범위를 알았으니 현재 위치를 보이는 지도의 한가운데로 바로 맞추고, 맞춘 뒤 받는다.
      _pendingMine = null;
      _placeStart(mine, animate: false);
      return;
    }
    _load(camera);
  }

  /// 이름표를 눌러 [course]를 고른다(MAP-03). 피크면 목록 시트를 반으로 올리고, 올라온 시트에 출발점이 가리면 지도를 옮겨 보인다.
  void _select(CourseListItem course) {
    setState(() => _selected = course);
    if (_settledStage != SheetStage.peek) return;
    _moveSheet(_halfSize);
    final camera = _camera;
    if (camera != null && !_contains(_visibleArea(camera, SheetStage.half), course.route.first)) {
      _centerInView(course.route.first, stage: SheetStage.half);
    }
  }

  static bool _contains(MapArea area, GeoPoint point) =>
      point.lat >= area.southWest.lat &&
      point.lat <= area.northEast.lat &&
      point.lng >= area.southWest.lng &&
      point.lng <= area.northEast.lng;

  /// 시트가 피크 · 반 · 전체 중 한 곳에 멈췄다. 보이는 지도 부분이 바뀌었으면 다시 받는다.
  /// 전체 보기(A6)는 지도가 안 보이니 그 전 범위를 그대로 둔다.
  void _onSheetSettled(SheetStage stage) {
    _settledStage = stage;
    if (stage == SheetStage.full || stage == _mapStage) return;
    _mapStage = stage;
    final camera = _camera;
    if (camera != null) _load(camera);
  }

  /// [camera] 범위 중 [stage] 시트에 가리지 않은 위쪽 부분. 지도는 메르카토르라 위도가 화면 높이에 비례하지 않아 메르카토르 y로 나눈다.
  /// 버튼은 작고 그 사이로 지도가 보여 가린 것으로 치지 않는다.
  MapArea _visibleArea(MapCamera camera, SheetStage stage) {
    final covered = switch (stage) {
      SheetStage.peek => CourseListSheet.peekHeight,
      _ => _mapHeight * _halfSize,
    };
    final visible = _mapHeight <= 0 ? 1.0 : (1 - covered / _mapHeight).clamp(0.0, 1.0);
    final top = _mercator(camera.northEast.lat), bottom = _mercator(camera.southWest.lat);
    return (
      southWest: GeoPoint(_latitude(top + (bottom - top) * visible), camera.southWest.lng),
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
    final area = _visibleArea(camera, _mapStage);
    setState(() => _area = area);
    try {
      var courses = const <CourseListItem>[];
      var regions = const <RegionCount>[];
      final int total;
      final regionLevel = _regionLevel(camera);
      switch (regionLevel) {
        case null:
          final map = await api.mapCourses(southWest: area.southWest, northEast: area.northEast, filter: _filter);
          (courses, total) = (map.courses, map.totalCount);
        case final level:
          final counts = await api.regionCounts(
            southWest: area.southWest,
            northEast: area.northEast,
            level: level,
            filter: _filter,
          );
          (regions, total) = (counts.regions, counts.totalCount);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _courses = courses;
        _regions = regions;
        _regionsLevel = regionLevel ?? _regionsLevel;
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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: LayoutBuilder(builder: (context, constraints) {
          // 상단 배너 아래 영역 높이. 시트 크기는 이 높이에 대한 비율이다.
          final height = constraints.maxHeight - MediaQuery.paddingOf(context).top - _HomeHeader.height;
          _mapHeight = height;
          final peekSize = CourseListSheet.peekHeight / height;
          final stage = _stage(_sheetSize, peekSize);
          final selected = _selected;
          final shown = selected == null ? _courses : [selected];
          return Column(children: [
            _HomeHeader(stage: stage),
            Expanded(child: Stack(
            children: [
              MapView(
                initialCenter: _startCenter,
                initialZoom: _startZoom,
                minZoom: _minZoom,
                padding: _mapPadding,
                // 고른 코스가 있으면 그 코스만 보인다. 축척이 500m보다 넓어져도 지역별 배지로 바꾸지 않는다(MAP-03).
                // 앞 코스(인기순 위)일수록 priority가 커서 경로가 위에 그려진다.
                lines: [
                  for (final (index, course) in shown.indexed)
                    MapLine(id: 'course-${course.courseId}', points: course.route, priority: shown.length - index),
                ],
                markers: [
                  // 이름표 아래 가운데가 출발점에 온다. 고른 코스는 배경이 파랗다. 리뷰가 있으면 평점을 붙인다(Figma A5).
                  // 이름표가 겹치면 인기순 위 코스의 이름표만 보이고, 숨은 코스도 목록에는 있다(MAP-03).
                  for (final (index, course) in shown.indexed)
                    MapMarker(
                      id: 'course-${course.courseId}',
                      position: course.route.first,
                      child: WdMapCourseLabel(formatMapLabel(course.name, course.averageRating), selected: selected != null),
                      imageKey: 'course-label:${formatMapLabel(course.name, course.averageRating)}'
                          '${selected != null ? ':selected' : ''}',
                      anchor: MapMarker.bottom,
                      priority: shown.length - index,
                      hideWhenCollided: true,
                      onTap: () => _select(course),
                    ),
                  // 배지 가운데가 그 지역 코스 출발점들의 가운데에 온다(A4-01). 누르면 한 단계 확대한다(A4-06).
                  if (selected == null)
                    for (final region in _regions)
                      MapMarker(
                        id: 'region-${region.code}',
                        position: region.center,
                        child: WdRegionCountBubble(count: formatCount(region.count), region: region.name),
                        imageKey: 'region-count:${region.name}:${region.count}',
                        onTap: () => _zoomInto(region),
                      ),
                ],
                onCreated: (map) => _map = map,
                onCameraIdle: _onCameraIdle,
                // 고른 코스가 있으면 지도의 다른 곳을 눌러 푼다(MAP-03). 없으면 시트를 내려 지도 전체 보기(A2-03).
                onTap: (_) {
                  if (selected != null) {
                    setState(() => _selected = null);
                  } else if (stage != SheetStage.peek) {
                    _moveSheet(peekSize);
                  }
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
                          WdMapLocateButton(onPressed: _goToMyLocation),
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
                    key: ValueKey(_listGeneration),
                    area: _area,
                    totalCount: _totalCount,
                    filter: _filter,
                    sort: _sort,
                    period: _period,
                    myLocation: _myLocation,
                    selected: selected,
                    stage: stage,
                    scrollController: scrollController,
                    now: widget.now,
                    onExpand: () => _moveSheet(_halfSize),
                    onShowAll: () => _moveSheet(1),
                    onSort: _sortBy,
                    onOpenFilter: _openFilter,
                    onResetFilter: () => _applyFilter(CourseFilter.none),
                    onWidenMap: _widenMap,
                    onCreateCourse: _createCourse,
                    onOpenCourse: (course) => context.push(Routes.courseDetail(course.courseId)),
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
                  // 여기서는 입력하지 않고 검색(G1)을 빈 입력으로 연다(SEA-01). 돌아오면 홈 상태는 그대로다.
                  onTap: () => context.push(Routes.courseSearch),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

