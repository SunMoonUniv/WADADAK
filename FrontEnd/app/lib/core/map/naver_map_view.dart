import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../config.dart';
import 'map_view.dart';

/// 네이버 지도 SDK 인증. 실패하면(앱 ID 미등록·사용량 초과 등) 지도 바탕이 비어 보인다.
Future<void> initNaverMap() => FlutterNaverMap().init(
      clientId: naverMapClientId,
      onAuthFailed: (e) => debugPrint('네이버 지도 인증 실패: $e '
          '(NCP 콘솔 Application의 Dynamic Map 선택과 앱 ID com.wadadak.app 등록을 확인한다)'),
    );

/// [MapView]의 네이버 지도 구현.
class NaverMapView extends StatefulWidget {
  const NaverMapView({super.key, required this.map});

  final MapView map;

  @override
  State<NaverMapView> createState() => _NaverMapViewState();
}

class _NaverMapViewState extends State<NaverMapView> implements MapController {
  NaverMapController? _controller;

  bool _following = false;

  // showMyLocation으로 현재 위치 점을 켜 두었는지.
  bool _showingMyLocation = false;

  // 다른 하단 탭이나 위에 덮인 화면에 가려져 있는지([TickerMode]). 가려진 동안 MyLocationSource.map 위치 추적을 끈다.
  bool _hidden = false;

  // MyLocationSource.app 점을 보이게 보냈는지. 점 값 바꾸기는 보낼 때마다 메모리에 남아([MapLocationTracker])
  // 보이기 · 방향 표시는 바뀔 때만 보낸다.
  bool _appLocationVisible = false;

  // 지도에 올라가 있는 선·표지. 다시 그릴 때 이것과 비교해 바뀐 것만 반영한다.
  final _shownLines = <String, MapLine>{};
  final _shownMarkers = <String, MapMarker>{};
  final _images = <String, Future<NOverlayImage>>{};
  Future<void> _syncing = Future.value();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hidden = !TickerMode.valuesOf(context).enabled;
    if (hidden == _hidden) return;
    _hidden = hidden;
    _trackMapLocation();
  }

  @override
  void didUpdateWidget(NaverMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (widget.map.myLocation != oldWidget.map.myLocation) _placeAppLocation();
  }

  /// 표지 그림을 만드는 동안 다시 그려질 수 있어 차례로 반영한다.
  void _sync() {
    if (_controller == null) return;
    _syncing = _syncing.then((_) => _apply()).catchError((Object e, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'core/map'));
    });
  }

  Future<void> _apply() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final lines = {for (final line in widget.map.lines) if (line.points.length >= 2) line.id: line};
    // 점선은 다른 종류(polyline)라 같은 id로 바꿔 끼워지지 않는다. 실선↔점선으로 바뀌면 지우고 다시 올린다.
    for (final id in _shownLines.keys
        .where((id) => lines[id]?.style.dash.isEmpty != _shownLines[id]!.style.dash.isEmpty)
        .toList()) {
      await controller.deleteOverlay(NOverlayInfo(type: _type(_shownLines.remove(id)!), id: id));
    }
    // 화면이 같은 목록에 점을 이어 붙여도(러닝 주행선) 비교되게 점을 복사해 두고, 그 복사본을 올린다.
    // 올리기를 기다린 뒤에 복사하면 그사이 붙은 점이 올라간 것으로 기록돼 다음 반영이 빠진다.
    final changedLines = lines.values
        .where((line) {
          final shown = _shownLines[line.id];
          return shown == null ||
              shown.style != line.style ||
              shown.priority != line.priority ||
              !listEquals(shown.points, line.points);
        })
        .map((line) => MapLine(id: line.id, points: List.of(line.points), style: line.style, priority: line.priority))
        .toList();
    // 같은 id로 다시 올리면 SDK가 이전 것을 바꿔 끼운다.
    if (changedLines.isNotEmpty) await controller.addOverlayAll({for (final line in changedLines) _path(line)});
    _shownLines.addAll({for (final line in changedLines) line.id: line});

    final markers = {for (final marker in widget.map.markers) marker.id: marker};
    for (final id in _shownMarkers.keys.where((id) => !markers.containsKey(id)).toList()) {
      await controller.deleteOverlay(NOverlayInfo(type: NOverlayType.marker, id: id));
      _shownMarkers.remove(id);
    }
    final added = <NMarker>{};
    for (final marker in markers.values) {
      final shown = _shownMarkers[marker.id];
      if (shown != null &&
          shown.position == marker.position &&
          shown.look == marker.look &&
          shown.anchor == marker.anchor &&
          shown.priority == marker.priority &&
          shown.hideWhenCollided == marker.hideWhenCollided &&
          (shown.onTap == null) == (marker.onTap == null)) {
        continue;
      }
      final image = await _image(marker);
      if (!mounted) return;
      final overlay = NMarker(
        id: marker.id,
        position: _latLng(marker.position),
        icon: image,
        anchor: NPoint(marker.anchor.dx, marker.anchor.dy),
        // 겹치면 z 순서가 높은 마커가 남는다.
        isHideCollidedMarkers: marker.hideWhenCollided,
      )..setZIndex(marker.priority);
      // 누른 때의 최신 onTap을 부른다. onTap이 없으면 누름이 지도로 간다(B3 점 찍기).
      if (marker.onTap != null) overlay.setOnTapListener((_) => _shownMarkers[marker.id]?.onTap?.call());
      added.add(overlay);
    }
    if (added.isNotEmpty) await controller.addOverlayAll(added);
    _shownMarkers.addAll(markers);
  }

  static NOverlayType _type(MapLine line) =>
      line.style.dash.isEmpty ? NOverlayType.pathOverlay : NOverlayType.polylineOverlay;

  /// 모양 순서대로 겹치고, 같은 모양이면 priority가 큰 선이 위에 온다.
  static int _layer(MapLine line) => line.style.index * MapLine.maxPriority + line.priority;

  // 점선은 경로 오버레이가 못 그려 선 오버레이로 그린다. 경로 오버레이와 같은 층에 둬 모양 순서대로 겹친다.
  NAddableOverlay _path(MapLine line) => line.style.dash.isEmpty
      ? (NPathOverlay(
          id: line.id,
          // SDK는 List만 보낼 수 있다(지연 Iterable은 ArgumentError).
          coords: line.points.map(_latLng).toList(),
          width: line.style.width,
          color: line.style.color,
          outlineWidth: line.style.outlineWidth,
          outlineColor: line.style.outlineColor,
        )..setZIndex(_layer(line)))
      : (NPolylineOverlay(
          id: line.id,
          coords: line.points.map(_latLng).toList(),
          width: line.style.width,
          color: line.style.color,
          pattern: line.style.dash,
        )
          ..setGlobalZIndex(-100000)
          ..setZIndex(_layer(line)));

  Future<NOverlayImage> _image(MapMarker marker) => _images[marker.look] ??= switch (marker) {
        MapMarker(:final icon?) => _iconImage(icon),
        MapMarker(:final child?) => NOverlayImage.fromWidget(widget: child, context: context),
        _ => throw StateError('표지에 child도 icon도 없다'),
      };

  /// SDK의 위젯 → 그림 변환은 한 번만 그려 SVG가 빠진다. 아이콘은 SVG를 직접 그린다.
  /// 화면 배율로 그리면 SDK가 원래 크기(Figma 크기)로 보여 준다.
  Future<NOverlayImage> _iconImage(WdIcons icon) async {
    final ratio = View.of(context).devicePixelRatio;
    // WdIcon과 같은 에셋.
    final svg = await vg.loadPicture(SvgAssetLoader('assets/icons/${icon.file}.svg', packageName: wdPackage), null);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(ratio)
      ..drawPicture(svg.picture);
    final picture = recorder.endRecording();
    final image = await picture.toImage((svg.size.width * ratio).ceil(), (svg.size.height * ratio).ceil());
    picture.dispose();
    svg.picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return NOverlayImage.fromByteArray(png!.buffer.asUint8List(), cacheKey: 'wd-icon-${icon.file}-$ratio');
  }

  Future<void> _cameraIdle() async {
    final controller = _controller;
    final onCameraIdle = widget.map.onCameraIdle;
    if (controller == null || onCameraIdle == null) return;
    final position = await controller.getCameraPosition();
    // 여백(padding)까지 포함한 지도 전체 범위(SDK coveringBounds). 개발용 지도와 같다.
    // 빼고 받으면 화면 아래 여백 부분이 범위에서 빠진다.
    final bounds = await controller.getContentBounds(withPadding: true);
    if (!mounted) return;
    onCameraIdle(MapCamera(
      center: _geoPoint(position.target),
      zoom: position.zoom,
      southWest: _geoPoint(bounds.southWest),
      northEast: _geoPoint(bounds.northEast),
      // 화면의 축척 막대도 SDK의 이 계산으로 그린다.
      scaleMeters: ScaleBarWidget.fromMeterPerDp(
        controller.getMeterPerDpAtLatitude(latitude: position.target.latitude, zoom: position.zoom),
      ).currentMeter,
    ));
  }

  @override
  Widget build(BuildContext context) => NaverMap(
        options: NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(target: _latLng(widget.map.initialCenter), zoom: widget.map.initialZoom),
          minZoom: widget.map.minZoom,
          // 야간 모드는 내비 지도 유형에서만 된다.
          mapType: widget.map.dark ? NMapType.navi : NMapType.basic,
          nightModeEnable: widget.map.dark,
          contentPadding: widget.map.padding,
          // 기울이면 보이는 범위가 사다리꼴이 되어 화면 범위 조회가 어긋난다.
          tiltGesturesEnable: false,
          // 지명·시설 글자를 눌러도 점 찍기(onTap)가 되게 한다.
          consumeSymbolTapEvents: false,
        ),
        onMapReady: (controller) {
          _controller = controller;
          // 현재 위치를 켜기(onCreated) 전에 바꿔 끼워야 SDK 위치 추적이 이것을 쓴다.
          controller.setMyLocationTracker(
            MapLocationTracker(isOff: () => controller.locationTrackingMode == NLocationTrackingMode.none),
          );
          widget.map.onCreated?.call(this);
          _sync();
          // 처음 카메라는 준비 전에 멈춰 onCameraIdle이 오지 않는다.
          _cameraIdle();
        },
        onMapTapped: (_, latLng) => widget.map.onTap?.call(_geoPoint(latLng)),
        // SDK의 위치 추적과 같은 규칙: 따라가기 말고 다른 이유로 카메라가 움직이면 따라가기를 끈다.
        onCameraChange: (reason, _) {
          if (reason != NCameraUpdateReason.location) _setFollowing(false);
        },
        onCameraIdle: _cameraIdle,
      );

  void _setFollowing(bool following) {
    if (_following == following) return;
    _following = following;
    widget.map.onFollowingChanged?.call(following);
  }

  /// [MyLocationSource.map]의 SDK 위치 추적을 켜 두었는지 · 가려졌는지 · 따라가는지에 맞춘다.
  void _trackMapLocation() {
    final controller = _controller;
    if (controller == null || widget.map.myLocationSource != MyLocationSource.map) return;
    controller.setLocationTrackingMode(!_showingMyLocation || _hidden
        ? NLocationTrackingMode.none
        : _following
            ? NLocationTrackingMode.follow
            : NLocationTrackingMode.noFollow);
  }

  /// [MyLocationSource.app]의 현재 위치 점을 [MapView.myLocation]에 놓고, 따라가는 중이면 카메라도 옮긴다.
  void _placeAppLocation() {
    final controller = _controller;
    if (controller == null || widget.map.myLocationSource != MyLocationSource.app) return;
    final location = _showingMyLocation ? widget.map.myLocation : null;
    final overlay = controller.getLocationOverlay();
    if (location != null) overlay.setPosition(_latLng(location));
    final visible = location != null;
    if (visible != _appLocationVisible) {
      _appLocationVisible = visible;
      // 방향을 모르므로 방향 표시는 뺀다.
      if (visible) overlay.setSubIcon(null);
      overlay.setIsVisible(visible);
    }
    if (location != null && _following) {
      controller.updateCamera(NCameraUpdate.withParams(target: _latLng(location))..setReason(NCameraUpdateReason.location));
    }
  }

  @override
  Future<void> moveTo(GeoPoint center, {double? zoom, bool animate = true}) async {
    final update = NCameraUpdate.scrollAndZoomTo(target: _latLng(center), zoom: zoom);
    if (!animate) update.setAnimation(animation: NCameraAnimation.none, duration: Duration.zero);
    await _controller?.updateCamera(update);
  }

  @override
  Future<void> fitPoints(List<GeoPoint> points) async {
    if (points.isEmpty) return;
    if (points.length == 1) return moveTo(points.single);
    await _controller?.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds.from(points.map(_latLng)),
      padding: const EdgeInsets.all(WdSpace.s24),
    ));
  }

  @override
  void showMyLocation({bool follow = true}) => _setMyLocation(show: true, follow: follow);

  @override
  void hideMyLocation() => _setMyLocation(show: false, follow: false);

  void _setMyLocation({required bool show, required bool follow}) {
    if (_controller == null) return;
    _setFollowing(follow);
    _showingMyLocation = show;
    switch (widget.map.myLocationSource) {
      case MyLocationSource.map:
        _trackMapLocation();
      case MyLocationSource.app:
        _placeAppLocation();
    }
  }
}

/// [MyLocationSource.map] 현재 위치 점의 SDK 위치 추적기(4.1 `A4-05 · A5-05 현재 위치 점 보내기`). flutter_naver_map 1.4.4의
/// 두 문제를 피한다.
///
/// - 안드로이드는 지도 표지 값 바꾸기에 답하지 않아, 보낼 때마다 끝나지 않는 작업이 하나씩 남는다. SDK 기본 추적기는 나침반 값이
///   올 때마다(1초에 수십 번) 방향을 보내, 앱을 1시간 넘게 켜 두면 메모리가 모자라 응답 없음(ANR)이 났다. 그래서 방향이
///   [minTurn]° 이상 바뀌고 [minGap]이 지났을 때만 보낸다.
/// - 켜는 중(현재 위치를 받는 동안)에 끄면 SDK가 위치를 다 받은 뒤 다시 켜 버린다. 다 받았을 때 꺼져 있으면 켜지 않는다.
class MapLocationTracker extends NDefaultMyLocationTracker {
  MapLocationTracker({required this.isOff, this.nowMs});

  static const minTurn = 5.0;
  static const minGap = Duration(milliseconds: 200);

  /// 지도의 위치 추적이 지금 꺼져 있는지.
  final bool Function() isOff;

  /// 거꾸로 가지 않는 시각(ms). 테스트에서 바꾼다.
  final int Function()? nowMs;

  // 기기 시계를 되돌려도 거꾸로 가지 않는다.
  final _clock = Stopwatch()..start();
  double? _sentHeading;
  int? _sentMs;

  /// [heading]을 보낼지. 보내기로 하면 보낸 것으로 친다.
  bool shouldSend(double heading) {
    final now = nowMs?.call() ?? _clock.elapsedMilliseconds;
    final sentHeading = _sentHeading, sentMs = _sentMs;
    if (sentHeading != null && sentMs != null) {
      // 359°와 1°는 2° 차이다.
      final turn = ((heading - sentHeading + 540) % 360 - 180).abs();
      if (turn < minTurn || now - sentMs < minGap.inMilliseconds) return false;
    }
    _sentHeading = heading;
    _sentMs = now;
    return true;
  }

  @override
  void onHeadingChanged(
    double heading,
    NLocationOverlay locationOverlay,
    NaverMapController controller,
    NLocationTrackingMode mode,
  ) {
    if (shouldSend(heading)) super.onHeadingChanged(heading, locationOverlay, controller, mode);
  }

  @override
  Future<NLatLng?> startLocationService() async {
    final location = await super.startLocationService();
    // null이면 SDK가 켜기를 그만둔다.
    return isOff() ? null : location;
  }
}

NLatLng _latLng(GeoPoint point) => NLatLng(point.lat, point.lng);

GeoPoint _geoPoint(NLatLng latLng) => GeoPoint(latLng.latitude, latLng.longitude);
