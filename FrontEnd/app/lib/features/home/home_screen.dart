import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/error_message.dart';
import '../../core/map/map_view.dart';
import '../../routes.dart';

/// 홈(A2). 지금은 지도, `＋ 코스 만들기`, 현재 위치 버튼만 있다.
/// 지도는 축척에 따라 범위 안 코스(경로 · 이름표, A5)나 지역별 코스 수 배지(A4)를 보인다(MAP-02).
/// 인사말·검색·필터·코스 목록 시트는 F2 다음 단계에서 붙인다.
/// 확대·축소 버튼은 두지 않는다(정책 MAP-02, 제스처로 한다).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

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

  /// 가장 최근 조회 번호. 늦게 도착한 예전 응답은 버린다.
  var _request = 0;

  // 위아래 여백 + 현재 위치 버튼.
  static const _buttonRowHeight = WdSpace.s16 * 2 + WdMapLocateButton.size;

  /// 코스를 등록하고 돌아오면 지도를 새 코스 출발점으로 옮긴다(B4-07). 줌은 그대로 둔다.
  Future<void> _createCourse() async {
    final course = await context.push<RegisteredCourse>(Routes.courseCreate, extra: _camera);
    if (course != null) await _map?.moveTo(course.startPoint);
  }

  void _onCameraIdle(MapCamera camera) {
    _camera = camera;
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
      switch (_regionLevel(camera)) {
        case null:
          courses = (await api.mapCourses(southWest: camera.southWest, northEast: camera.northEast)).courses;
        case final level:
          regions = (await api.regionCounts(southWest: camera.southWest, northEast: camera.northEast, level: level)).regions;
      }
      if (!mounted || request != _request) return;
      setState(() {
        _courses = courses;
        _regions = regions;
        _loaded = true;
      });
    } on ApiException catch (e) {
      // 처음 조회가 실패하면 알리고 다시 시도하게 한다. 그 뒤 갱신이 실패하면 전에 받은 것을 둔다(QST-02 · STA-02).
      if (!mounted || request != _request || _loaded) return;
      showError(context, e, message: _loadFailedMessage, onRetry: () => _load(_camera ?? camera));
    }
  }

  /// 1240 → "1,240"(Figma A4).
  static String _count(int count) => count.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            MapView(
              // 아래 버튼 줄만큼 비워 네이버 로고·축척이 버튼에 가리지 않게 한다.
              padding: const EdgeInsets.only(bottom: _buttonRowHeight),
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
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
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
          ],
        ),
      );
}
