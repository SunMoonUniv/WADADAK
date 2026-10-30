import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/map/map_view.dart';

/// Fits every segment together, while keeping GPS gaps disconnected.
class RunRoutePreviewMap extends StatefulWidget {
  const RunRoutePreviewMap({
    super.key,
    required this.segments,
    this.onCameraIdle,
    this.showEndpoints = true,
  });
  final List<List<GeoPoint>> segments;
  final ValueChanged<MapCamera>? onCameraIdle;
  final bool showEndpoints;

  @override
  State<RunRoutePreviewMap> createState() => _RunRoutePreviewMapState();
}

class _RunRoutePreviewMapState extends State<RunRoutePreviewMap> {
  MapController? controller;
  List<GeoPoint> fitted = const [];
  Size? size;
  bool scheduled = false;

  void scheduleFit() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted || controller == null) return;
      final points = widget.segments.expand((s) => s).toList();
      fitted = points;
      unawaited(controller!.fitPoints(points));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.segments.expand((s) => s).toList();
    if (points.isEmpty) {
      return const WdSurface(child: Center(child: Text('표시할 경로가 없어요.')));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final next = constraints.biggest;
        if (size != next || !listEquals(points, fitted)) {
          size = next;
          scheduleFit();
        }
        return MapView(
          initialCenter: points.first,
          onCameraIdle: widget.onCameraIdle,
          padding: widget.showEndpoints
              ? const EdgeInsets.only(top: WdSpace.s16, bottom: WdSpace.s8)
              : EdgeInsets.zero,
          onCreated: (c) {
            controller = c;
            scheduleFit();
          },
          lines: [
            for (var i = 0; i < widget.segments.length; i++)
              MapLine(id: 'preview-$i', points: widget.segments[i]),
          ],
          markers: [
            if (widget.showEndpoints) ...[
              MapMarker(
                id: 'preview-start',
                position: points.first,
                child: const WdRouteEndpoint.start(),
                imageKey: 'preview-start',
                anchor: WdRouteEndpoint.startAnchor,
              ),
              MapMarker(
                id: 'preview-end',
                position: points.last,
                child: const WdRouteEndpoint.end(),
                imageKey: 'preview-end',
                anchor: WdRouteEndpoint.endAnchor,
              ),
            ],
          ],
        );
      },
    );
  }
}
