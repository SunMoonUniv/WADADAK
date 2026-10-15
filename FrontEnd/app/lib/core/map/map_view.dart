import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../config.dart';
import 'dev_map_view.dart';
import 'geo_point.dart';
import 'naver_map_view.dart';

export 'geo_point.dart';

/// 지도 구현. 화면은 [MapView]만 쓰고 어느 구현인지 모른다(개발 정책 10.2 외부 서비스 감싸기).
enum MapEngine {
  /// 네이버 지도 SDK
  naver,

  /// 키 없이 도는 개발용 지도. 배경색 위에 선·표지만 그린다
  dev,
}

/// config.dart `realMap`을 따른다. 위젯 테스트는 플랫폼 지도를 띄울 수 없어 [MapEngine.dev]로 바꾼다.
final mapEngineProvider = Provider<MapEngine>((ref) => realMap ? MapEngine.naver : MapEngine.dev);

/// 앱 시작 때 한 번. 네이버 지도는 첫 지도를 띄우기 전에 Client ID로 인증해야 한다.
Future<void> initMap() async {
  if (realMap) await initNaverMap();
}

/// 앱 공통 지도.
///
/// 선·표지는 값으로 넘긴다. 다시 그릴 때 바뀐 것만 지도에 반영한다(id로 구분).
/// 카메라 이동은 [onCreated]로 받은 [MapController]로 한다.
class MapView extends ConsumerWidget {
  const MapView({
    super.key,
    this.initialCenter = seoulCityHall,
    this.initialZoom = 14,
    this.minZoom = 0,
    this.lines = const [],
    this.markers = const [],
    this.padding = EdgeInsets.zero,
    this.dark = false,
    this.myLocationSource = MyLocationSource.map,
    this.myLocation,
    this.onCreated,
    this.onTap,
    this.onCameraIdle,
    this.onFollowingChanged,
  });

  static const seoulCityHall = GeoPoint(37.5666, 126.9784);

  final GeoPoint initialCenter;
  final double initialZoom;

  /// 이보다 축소하지 않는다(예: 홈은 축척 막대 50km까지, MAP-02). 지도를 띄운 뒤 바꾸지 않는다.
  final double minZoom;
  final List<MapLine> lines;
  final List<MapMarker> markers;

  /// 지도 위를 덮는 화면 요소(시트·버튼)만큼 안쪽 여백. 카메라 중심·전체 보기가 이 여백을 뺀 영역 기준이 된다.
  final EdgeInsets padding;

  /// 어두운 지도(러닝 화면). 네이버 지도는 야간 모드로 그린다(야간 모드를 지원하는 내비 지도 유형). 지도를 띄운 뒤 바꾸지 않는다.
  final bool dark;

  /// 현재 위치를 어디서 받나. 지도를 띄운 뒤 바꾸지 않는다.
  final MyLocationSource myLocationSource;

  /// [MyLocationSource.app]의 현재 위치. 아직 없으면 null.
  /// [MapController.showMyLocation] 뒤로는 바뀔 때마다 현재 위치 점이 옮겨지고, 따라가는 중이면 카메라도 옮겨진다.
  final GeoPoint? myLocation;

  final ValueChanged<MapController>? onCreated;

  /// 지도 빈 곳을 눌렀다(B3 점 찍기). 표지를 누르면 [MapMarker.onTap]만 불린다.
  final ValueChanged<GeoPoint>? onTap;

  /// 카메라가 멈췄다(처음 뜰 때 포함). 화면 범위로 코스를 다시 조회할 때 쓴다.
  final ValueChanged<MapCamera>? onCameraIdle;

  /// 현재 위치 따라가기가 켜지거나 꺼졌다. [MapController.showMyLocation]으로 켜지고,
  /// 카메라가 따라가기 말고 다른 이유로 움직이면(사용자가 지도를 끌거나 [MapController.moveTo] 등) 꺼진다.
  /// 꺼져도 현재 위치 점은 남는다.
  final ValueChanged<bool>? onFollowingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(mapEngineProvider)) {
        MapEngine.naver => NaverMapView(map: this),
        MapEngine.dev => DevMapView(map: this),
      };
}

/// 카메라 조작.
abstract interface class MapController {
  /// [center]로 옮긴다. [zoom]이 없으면 지금 줌을 유지한다.
  /// [animate]가 false면 미끄러지지 않고 바로 옮긴다(홈을 열 때 첫 자리 맞추기). 개발용 지도는 늘 바로 옮긴다.
  Future<void> moveTo(GeoPoint center, {double? zoom, bool animate = true});

  /// [points]가 모두 보이게 옮긴다(코스 전체 보기).
  Future<void> fitPoints(List<GeoPoint> points);

  /// 현재 위치 점을 보이고 따라간다. 지도를 끌면 따라가기만 멈춘다([MapView.onFollowingChanged]).
  /// [follow]가 false면 점만 보이고(점은 위치를 따라 움직인다) 카메라는 그대로 둔다(홈 현재 위치 버튼).
  /// [MyLocationSource.map]은 위치 권한이 없으면 묻는다. 개발용 지도는 기기 위치를 모르므로 이때 아무것도 하지 않는다.
  /// [MyLocationSource.app]은 [MapView.myLocation]으로 간다. 아직 없으면 생길 때 간다.
  void showMyLocation({bool follow = true});

  /// 현재 위치 점을 숨기고 따라가기를 끝낸다. [MyLocationSource.map]은 위치 받기도 멈춘다.
  void hideMyLocation();
}

/// 현재 위치를 어디서 받나.
enum MyLocationSource {
  /// 지도 SDK가 기기 위치를 받는다(홈).
  map,

  /// 화면이 [MapView.myLocation]으로 넘긴다(러닝). 측정에 쓴 좌표를 그대로 보여 지도와 측정의 위치가 어긋나지 않는다.
  app,
}

/// 멈춘 카메라와 보이는 범위.
@immutable
class MapCamera {
  const MapCamera({
    required this.center,
    required this.zoom,
    required this.southWest,
    required this.northEast,
    required this.scaleMeters,
  });

  final GeoPoint center;
  final double zoom;

  /// 지도 위젯 전체의 남서쪽 · 북동쪽 끝. [MapView.padding]으로 비운 부분도 들어간다.
  final GeoPoint southWest;
  final GeoPoint northEast;

  /// 축척 막대에 보이는 거리(m, 1·2·5 단계). 정책의 "축척 2km"·"축척 500m"가 이 값이다(MAP-02).
  /// 개발용 지도는 축척 막대가 없어 네이버 지도가 같은 위도·줌에서 보일 값을 준다.
  final int scaleMeters;

  @override
  String toString() => 'MapCamera($center, zoom: $zoom, scale: ${scaleMeters}m, $southWest ~ $northEast)';
}

/// 지도 위 선. 좌표 순서대로 잇는다. 점이 2개보다 적으면 그리지 않는다.
///
/// 화면이 같은 [points] 목록에 점을 이어 붙여 다시 넘겨도 된다(러닝 주행선).
@immutable
class MapLine {
  const MapLine({required this.id, required this.points, this.style = MapLineStyle.course});

  final String id;
  final List<GeoPoint> points;
  final MapLineStyle style;
}

/// 선 모양. 쓰는 곳마다 나눠 두어 한 곳의 색을 바꿔도 다른 곳은 그대로다. 겹치면 뒤에 적힌 모양이 위에 그려진다.
enum MapLineStyle {
  /// 홈·코스 만들기·코스 상세의 코스 경로. 라임 선 + 잉크 테두리(Figma 코스 썸네일과 같다).
  course(color: WdColors.lime, outlineColor: WdColors.ink, width: 4, outlineWidth: 2),

  /// 러닝 화면(어두운 지도)의 코스 경로. 흰 선 + 잉크 테두리. 위에 겹치는 [track]과 구분된다.
  runCourse(color: WdColors.white, outlineColor: WdColors.ink, width: 6, outlineWidth: 2),

  /// 러닝 화면의 실제 주행선(자유·코스 러닝·고스트 대결). 라임 선 + 잉크 테두리(Figma H4-1). 코스선 위에 그려진다.
  track(color: WdColors.lime, outlineColor: WdColors.ink, width: 6, outlineWidth: 2);

  const MapLineStyle({required this.color, required this.outlineColor, required this.width, required this.outlineWidth});

  final Color color;
  final Color outlineColor;
  final double width;

  /// 선 양옆에 한 번씩 붙는 테두리 두께.
  final double outlineWidth;
}

/// 지도 위 표지.
@immutable
class MapMarker {
  /// 디자인 시스템 위젯 표지(`WdKmMarker`·`WdRegionCountBubble` 등).
  ///
  /// 네이버 지도는 위젯을 한 번 그려 그림으로 올린다. 그래서 SVG·사진처럼 늦게 그려지는 위젯은 넣지 않는다.
  /// 아이콘은 [MapMarker.icon]을 쓴다.
  const MapMarker({
    required this.id,
    required this.position,
    required Widget this.child,
    required String this.imageKey,
    this.anchor = center,
    this.onTap,
  }) : icon = null;

  /// 디자인 시스템 아이콘 표지(경로 작성점 [WdIcons.routePoint] 등).
  const MapMarker.icon({required this.id, required this.position, required WdIcons this.icon, this.anchor = center, this.onTap})
      : child = null,
        imageKey = null;

  /// 표지 가운데가 [position]에 온다.
  static const center = Offset(0.5, 0.5);

  /// 표지 아래 가운데가 [position]에 온다(핀).
  static const bottom = Offset(0.5, 1);

  final String id;
  final GeoPoint position;
  final Widget? child;
  final WdIcons? icon;

  /// [child]의 모양을 나타내는 키(예: `km:3`). 키가 같으면 그림을 다시 만들지 않으므로 모양이 다르면 키도 달라야 한다.
  final String? imageKey;

  /// 표지에서 [position]에 놓을 지점. (0, 0) 왼쪽 위 ~ (1, 1) 오른쪽 아래.
  final Offset anchor;
  final VoidCallback? onTap;

  /// 지도에 올린 그림을 다시 만들어야 하는지 가리는 값.
  String get look => icon != null ? 'icon:${icon!.file}' : 'widget:$imageKey';
}
