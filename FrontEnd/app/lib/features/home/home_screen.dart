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

/// 홈(A2). 지도, `＋ 코스 만들기`, 현재 위치 버튼, 아래 코스 목록 시트가 있다.
/// 지도는 축척에 따라 범위 안 코스(경로 · 이름표, A5)나 지역별 코스 수 배지(A4)를 보인다(MAP-02).
/// 목록 시트는 지도와 같은 범위의 코스이고(MAP-07), 끌어서 피크(A4 · A5) · 반(A2) · 전체(A6)에 멈춘다.
/// 인사말·검색·필터는 F2 다음 단계에서 붙인다.
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

  /// 지도가 센 범위 안 코스 수(시트의 `코스 N`). 아직 모르면 null.
  int? _totalCount;

  /// 가장 최근 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  final _sheet = DraggableScrollableController();
  var _sheetSize = _halfSize;

  /// 시트 처음 크기. 지도와 목록이 반씩이다(A2).
  static const _halfSize = 0.5;

  /// 최대 축소. 축척 막대가 50km보다 넓어지지 않는다(MAP-02). 줌 6은 제주(위도 33°)부터 강원 북쪽(38.6°)까지 50km다.
  static const _minZoom = 6.0;

  // 위아래 여백 + 현재 위치 버튼.
  static const _buttonRowHeight = WdSpace.s16 * 2 + WdMapLocateButton.size;

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

  /// 축척으로 정하는 지도 표시(MAP-02). 축척 2km보다 넓으면 시 단위, 2km부터 500m 전까지 구 단위 코스 수,
  /// 500m부터는 개별 코스(null)다.
  static RegionLevel? _regionLevel(MapCamera camera) => switch (camera.scaleMeters) {
        > 2000 => RegionLevel.city,
        > 500 => RegionLevel.district,
        _ => null,
      };

  /// 지도가 멈출 때마다 범위 안 코스나 지역별 코스 수를 다시 받는다.
  Future<void> _load(MapCamera camera) async {
    final request = ++_request;
    final api = ref.read(courseApiClientProvider);
    try {
      var courses = const <MapCourse>[];
      var regions = const <RegionCount>[];
      final int total;
      switch (_regionLevel(camera)) {
        case null:
          final map = await api.mapCourses(southWest: camera.southWest, northEast: camera.northEast);
          (courses, total) = (map.courses, map.totalCount);
        case final level:
          final counts = await api.regionCounts(southWest: camera.southWest, northEast: camera.northEast, level: level);
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
          final height = constraints.maxHeight;
          final peekSize = CourseListSheet.peekHeight / height;
          // 전체 보기도 상태 표시줄은 가리지 않는다.
          final fullSize = 1 - MediaQuery.paddingOf(context).top / height;
          final stage = _stage(_sheetSize, peekSize);
          final camera = _camera;
          return Stack(
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
                      padding: const EdgeInsets.all(WdSpace.s16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Figma A4·A5와 같이 왼쪽 24.
                          Padding(
                            padding: const EdgeInsets.only(left: WdSpace.s8),
                            child: WdMapPillButton.small('＋ 코스 만들기', onPressed: _createCourse),
                          ),
                          WdMapLocateButton(onPressed: () => _map?.showMyLocation()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  setState(() => _sheetSize = notification.extent);
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: _halfSize,
                  minChildSize: peekSize,
                  maxChildSize: fullSize,
                  snap: true,
                  snapSizes: const [_halfSize],
                  builder: (context, scrollController) => CourseListSheet(
                    area: camera == null ? null : (southWest: camera.southWest, northEast: camera.northEast),
                    totalCount: _totalCount,
                    stage: stage,
                    scrollController: scrollController,
                    now: widget.now,
                    onExpand: () => _moveSheet(_halfSize),
                    onWidenMap: _widenMap,
                    onCreateCourse: _createCourse,
                  ),
                ),
              ),
            ],
          );
        }),
      );
}
