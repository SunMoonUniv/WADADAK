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

  // MyLocationSource.app일 때 현재 위치 점을 보이는 중인지. map이면 SDK가 위치 추적 모드로 관리한다.
  bool _showingAppLocation = false;

  // 지도에 올라가 있는 선·표지. 다시 그릴 때 이것과 비교해 바뀐 것만 반영한다.
  final _shownLines = <String, MapLine>{};
  final _shownMarkers = <String, MapMarker>{};
  final _images = <String, Future<NOverlayImage>>{};
  Future<void> _syncing = Future.value();

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
    for (final id in _shownLines.keys.where((id) => !lines.containsKey(id)).toList()) {
      await controller.deleteOverlay(NOverlayInfo(type: NOverlayType.pathOverlay, id: id));
      _shownLines.remove(id);
    }
    // 화면이 같은 목록에 점을 이어 붙여도(러닝 주행선) 비교되게 점을 복사해 두고, 그 복사본을 올린다.
    // 올리기를 기다린 뒤에 복사하면 그사이 붙은 점이 올라간 것으로 기록돼 다음 반영이 빠진다.
    final changedLines = lines.values
        .where((line) {
          final shown = _shownLines[line.id];
          return shown == null || shown.style != line.style || !listEquals(shown.points, line.points);
        })
        .map((line) => MapLine(id: line.id, points: List.of(line.points), style: line.style))
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
      );
      // 누른 때의 최신 onTap을 부른다. onTap이 없으면 누름이 지도로 간다(B3 점 찍기).
      if (marker.onTap != null) overlay.setOnTapListener((_) => _shownMarkers[marker.id]?.onTap?.call());
      added.add(overlay);
    }
    if (added.isNotEmpty) await controller.addOverlayAll(added);
    _shownMarkers.addAll(markers);
  }

  NPathOverlay _path(MapLine line) => NPathOverlay(
        id: line.id,
        // SDK는 List만 보낼 수 있다(지연 Iterable은 ArgumentError).
        coords: line.points.map(_latLng).toList(),
        width: line.style.width,
        color: line.style.color,
        outlineWidth: line.style.outlineWidth,
        outlineColor: line.style.outlineColor,
      )..setZIndex(line.style.index);

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

  /// [MyLocationSource.app]의 현재 위치 점을 [MapView.myLocation]에 놓고, 따라가는 중이면 카메라도 옮긴다.
  void _placeAppLocation() {
    final controller = _controller;
    if (controller == null || widget.map.myLocationSource != MyLocationSource.app) return;
    final location = widget.map.myLocation;
    final overlay = controller.getLocationOverlay();
    if (!_showingAppLocation || location == null) {
      overlay.setIsVisible(false);
      return;
    }
    overlay
      ..setPosition(_latLng(location))
      // 방향을 모르므로 방향 표시는 뺀다.
      ..setSubIcon(null)
      ..setIsVisible(true);
    if (_following) {
      controller.updateCamera(NCameraUpdate.withParams(target: _latLng(location))..setReason(NCameraUpdateReason.location));
    }
  }

  @override
  Future<void> moveTo(GeoPoint center, {double? zoom}) async {
    await _controller?.updateCamera(NCameraUpdate.scrollAndZoomTo(target: _latLng(center), zoom: zoom));
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
  void showMyLocation({bool follow = true}) {
    final controller = _controller;
    if (controller == null) return;
    _setFollowing(follow);
    switch (widget.map.myLocationSource) {
      case MyLocationSource.map:
        controller.setLocationTrackingMode(follow ? NLocationTrackingMode.follow : NLocationTrackingMode.noFollow);
      case MyLocationSource.app:
        _showingAppLocation = true;
        _placeAppLocation();
    }
  }

  @override
  void hideMyLocation() {
    final controller = _controller;
    if (controller == null) return;
    _setFollowing(false);
    switch (widget.map.myLocationSource) {
      case MyLocationSource.map:
        controller.setLocationTrackingMode(NLocationTrackingMode.none);
      case MyLocationSource.app:
        _showingAppLocation = false;
        _placeAppLocation();
    }
  }
}

NLatLng _latLng(GeoPoint point) => NLatLng(point.lat, point.lng);

GeoPoint _geoPoint(NLatLng latLng) => GeoPoint(latLng.latitude, latLng.longitude);
