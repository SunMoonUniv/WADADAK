import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'map_view.dart';

/// [MapView]의 개발용 구현. 지도 키·네트워크 없이 돈다(개발 정책 10.2). 위젯 테스트도 이것을 쓴다.
///
/// 지도 바탕은 없고 배경색 위에 선·표지만 웹 메르카토르로 놓는다. 줌 단계는 네이버 지도와 같다(256px 타일).
class DevMapView extends StatefulWidget {
  const DevMapView({super.key, required this.map});

  final MapView map;

  /// 현재 위치 점([MyLocationSource.app]만 그린다). 테스트에서 찾을 때 쓴다.
  static const myLocationKey = ValueKey('dev-map-my-location');

  @override
  State<DevMapView> createState() => _DevMapViewState();
}

class _DevMapViewState extends State<DevMapView> implements MapController {
  static const _tileSize = 256.0;
  static const _minZoom = 0.0;
  static const _maxZoom = 21.0;

  late GeoPoint _center = widget.map.initialCenter;
  late double _zoom = widget.map.initialZoom;
  Size _size = Size.zero;

  // 끌기·벌리기를 시작할 때 손가락 아래 있던 곳과 그때 줌.
  GeoPoint? _gestureAnchor;
  double _gestureZoom = 0;

  bool _following = false;
  bool _showingAppLocation = false;

  bool get _usesAppLocation => widget.map.myLocationSource == MyLocationSource.app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.map.onCreated?.call(this);
      _idle();
    });
  }

  @override
  void didUpdateWidget(DevMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final location = widget.map.myLocation;
    if (_following && _showingAppLocation && location != null && location != oldWidget.map.myLocation) {
      // 다시 그리는 중이라 카메라 보고는 그린 뒤에 한다(받는 화면이 setState할 수 있다).
      _center = location;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _idle();
      });
    }
  }

  void _setFollowing(bool following) {
    if (_following == following) return;
    _following = following;
    widget.map.onFollowingChanged?.call(following);
  }

  /// 카메라 중심이 놓이는 화면 위치. [MapView.padding]을 뺀 영역의 가운데다.
  Offset get _focus {
    final padding = widget.map.padding;
    return Offset(
      padding.left + (_size.width - padding.horizontal) / 2,
      padding.top + (_size.height - padding.vertical) / 2,
    );
  }

  static Offset _world(GeoPoint point, double zoom) {
    final scale = _tileSize * math.pow(2, zoom);
    final sinLat = math.sin(point.lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return Offset(
      (point.lng + 180) / 360 * scale,
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale,
    );
  }

  static GeoPoint _geo(Offset world, double zoom) {
    final scale = _tileSize * math.pow(2, zoom);
    final n = math.pi - 2 * math.pi * world.dy / scale;
    return GeoPoint(180 / math.pi * math.atan((math.exp(n) - math.exp(-n)) / 2), world.dx / scale * 360 - 180);
  }

  Offset _toScreen(GeoPoint point) => _world(point, _zoom) - _world(_center, _zoom) + _focus;

  GeoPoint _toGeo(Offset screen) => _geo(_world(_center, _zoom) + screen - _focus, _zoom);

  void _idle() => widget.map.onCameraIdle?.call(MapCamera(
        center: _center,
        zoom: _zoom,
        southWest: _toGeo(Offset(0, _size.height)),
        northEast: _toGeo(Offset(_size.width, 0)),
      ));

  void _setCamera(GeoPoint center, double zoom) {
    setState(() {
      _center = center;
      _zoom = zoom.clamp(_minZoom, _maxZoom);
    });
    _idle();
  }

  @override
  Future<void> moveTo(GeoPoint center, {double? zoom}) async {
    _setFollowing(false);
    _setCamera(center, zoom ?? _zoom);
  }

  @override
  Future<void> fitPoints(List<GeoPoint> points) async {
    if (points.isEmpty) return;
    // 줌 0에서의 범위를 구해 화면(여백 제외)에 들어가는 줌을 고른다.
    final world = points.map((p) => _world(p, 0)).toList();
    final xs = world.map((o) => o.dx);
    final ys = world.map((o) => o.dy);
    final topLeft = Offset(xs.reduce(math.min), ys.reduce(math.min));
    final span = Offset(xs.reduce(math.max), ys.reduce(math.max)) - topLeft;
    final room = Size(
      _size.width - widget.map.padding.horizontal - WdSpace.s24 * 2,
      _size.height - widget.map.padding.vertical - WdSpace.s24 * 2,
    );
    final zoom = span == Offset.zero
        ? _zoom
        : math.log(math.min(room.width / span.dx, room.height / span.dy)) / math.ln2;
    _setFollowing(false);
    _setCamera(_geo(topLeft + span / 2, 0), zoom);
  }

  /// 기기 위치를 모르므로 [MyLocationSource.app]만 한다.
  @override
  void showMyLocation() {
    if (!_usesAppLocation) return;
    _setFollowing(true);
    setState(() => _showingAppLocation = true);
    final location = widget.map.myLocation;
    if (location != null) _setCamera(location, _zoom);
  }

  @override
  void hideMyLocation() {
    if (!_usesAppLocation) return;
    _setFollowing(false);
    setState(() => _showingAppLocation = false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        _size = constraints.biggest;
        final map = widget.map;
        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => map.onTap?.call(_toGeo(details.localPosition)),
            onScaleStart: (details) {
              _setFollowing(false);
              _gestureAnchor = _toGeo(details.localFocalPoint);
              _gestureZoom = _zoom;
            },
            onScaleUpdate: (details) => setState(() {
              _zoom = (_gestureZoom + math.log(details.scale) / math.ln2).clamp(_minZoom, _maxZoom);
              // 시작 때 손가락 아래 있던 곳이 지금 손가락 아래 오게 한다.
              _center = _geo(_world(_gestureAnchor!, _zoom) - details.localFocalPoint + _focus, _zoom);
            }),
            onScaleEnd: (_) => _idle(),
            child: ColoredBox(
              color: map.dark ? WdColors.dark : WdColors.map,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _LinesPainter([
                      // 뒤에 적힌 모양이 위에 오게 모양 순서대로 그린다.
                      for (final line in [...map.lines]..sort((a, b) => a.style.index - b.style.index))
                        if (line.points.length >= 2) (line.style, line.points.map(_toScreen).toList()),
                    ])),
                  ),
                  for (final marker in map.markers) _marker(marker),
                  if (_showingAppLocation && map.myLocation != null) _myLocation(map.myLocation!),
                  Positioned(
                    left: WdSpace.s8,
                    bottom: WdSpace.s8,
                    child: Text('개발용 지도', style: WdText.ko11.copyWith(color: WdColors.muted)),
                  ),
                ],
              ),
            ),
          ),
        );
      });

  Widget _marker(MapMarker marker) {
    final position = _toScreen(marker.position);
    final look = marker.icon != null ? WdIcon(marker.icon!) : marker.child!;
    final onTap = marker.onTap;
    return Positioned(
      key: ValueKey(marker.id),
      left: position.dx,
      top: position.dy,
      child: FractionalTranslation(
        translation: -marker.anchor,
        // onTap이 없으면 누름이 지도로 간다(네이버 지도와 같다).
        child: onTap == null ? IgnorePointer(child: look) : GestureDetector(onTap: onTap, child: look),
      ),
    );
  }

  Widget _myLocation(GeoPoint location) {
    final position = _toScreen(location);
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: FractionalTranslation(
        translation: -MapMarker.center,
        child: IgnorePointer(
          child: Container(
            key: DevMapView.myLocationKey,
            width: WdSpace.s16,
            height: WdSpace.s16,
            decoration: BoxDecoration(
              color: WdColors.info,
              shape: BoxShape.circle,
              border: Border.all(color: WdColors.white, width: 3),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.lines);

  final List<(MapLineStyle, List<Offset>)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final (style, points) in lines) {
      final path = Path()..addPolygon(points, false);
      canvas
        ..drawPath(path, stroke(style.outlineColor, style.width + style.outlineWidth * 2))
        ..drawPath(path, stroke(style.color, style.width));
    }
  }

  @override
  bool shouldRepaint(_LinesPainter oldDelegate) => true;
}
