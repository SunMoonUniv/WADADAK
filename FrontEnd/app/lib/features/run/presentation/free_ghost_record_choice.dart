import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/map/geo_point.dart';
import '../domain/free_ghost.dart';
import '../domain/run_models.dart';

String freeGhostRecordTitle(DateTime? date) {
  if (date == null) return '선택한 내 자유 기록';
  final local = date.toLocal();
  return '${local.month}월 ${local.day}일 자유러닝';
}

String freeGhostRecordDate(DateTime? date) {
  if (date == null) return '자유러닝 기록';
  final d = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)} · ${two(d.hour)}:${two(d.minute)}';
}

/// Free-record choice. A route thumbnail appears only after its real replay is loaded.
class FreeGhostRecordChoice extends StatelessWidget {
  const FreeGhostRecordChoice({
    super.key,
    required this.record,
    required this.onTap,
    this.prepared,
    this.checking = false,
  });
  final FreeGhostCandidate record;
  final PreparedFreeGhost? prepared;
  final bool checking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = prepared?.replay.sourceId == record.id;
    final enabled = record.distanceEligible;
    return Semantics(
      selected: selected,
      enabled: enabled && onTap != null,
      button: true,
      child: WdSurface(
        color: selected ? WdColors.limeSoft : WdColors.soft,
        border: selected
            ? const BorderSide(color: WdColors.green, width: 1.5)
            : null,
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Row(
          spacing: 12,
          children: [
            WdSurface(
              color: WdColors.map,
              radius: 10,
              width: 48,
              height: 54,
              child: selected
                  ? FreeGhostRouteThumbnail(
                      segments: prepared!.reference.routeSegments,
                    )
                  : const Center(child: WdIcon(WdIcons.run, size: 24)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Text(
                    freeGhostRecordTitle(record.startedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WdText.ko14Bold.copyWith(
                      color: enabled ? WdColors.ink : WdColors.muted,
                    ),
                  ),
                  Text(
                    freeGhostRecordDate(record.startedAt),
                    style: WdText.ko11.copyWith(color: WdColors.muted),
                  ),
                  if (!enabled)
                    Text(
                      '1km 미만 · 선택 불가',
                      style: WdText.ko12.copyWith(color: WdColors.muted),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) => Text(
                        '${(record.distanceM / 1000).toStringAsFixed(2)} km · ${formatRunTime(Duration(milliseconds: record.elapsedMs))}'
                        '${constraints.maxWidth >= 205 ? ' · ${formatRunPace(record.elapsedMs / record.distanceM)}' : ''}',
                        maxLines: 1,
                        style: WdText.ko11.copyWith(
                          color: selected ? WdColors.green : WdColors.muted,
                        ),
                      ),
                    ),
                  if (enabled && record.endReason != 'USER')
                    Text(
                      '중단된 기록 · 재생 가능 여부 확인 후 선택',
                      style: WdText.ko11.copyWith(color: WdColors.muted),
                    ),
                ],
              ),
            ),
            if (checking)
              Text('확인 중', style: WdText.ko12.copyWith(color: WdColors.green))
            else
              Icon(
                selected
                    ? Icons.check_circle
                    : enabled
                    ? Icons.radio_button_unchecked
                    : Icons.lock_outline,
                size: 20,
                color: selected ? WdColors.green : WdColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

/// Preview only the measured route segments, preserving gaps between them.
class FreeGhostRouteThumbnail extends StatelessWidget {
  const FreeGhostRouteThumbnail({super.key, required this.segments});
  final List<List<GeoPoint>> segments;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RoutePainter(segments), size: Size.infinite);
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.segments);
  final List<List<GeoPoint>> segments;
  @override
  void paint(Canvas canvas, Size size) {
    final points = segments.expand((s) => s).toList();
    if (points.length < 2) return;
    final shrink = math.cos(points.first.lat * math.pi / 180);
    final xs = points.map((p) => p.lng * shrink).toList();
    final ys = points.map((p) => -p.lat).toList();
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final width = size.width - 16, height = size.height - 16;
    final scale = math.min(
      maxX == minX ? double.infinity : width / (maxX - minX),
      maxY == minY ? double.infinity : height / (maxY - minY),
    );
    if (!scale.isFinite || scale <= 0) return;
    final dx = 8 + (width - (maxX - minX) * scale) / 2;
    final dy = 8 + (height - (maxY - minY) * scale) / 2;
    for (final segment in segments) {
      if (segment.length < 2) continue;
      final path = Path()
        ..addPolygon([
          for (final p in segment)
            Offset(
              dx + (p.lng * shrink - minX) * scale,
              dy + (-p.lat - minY) * scale,
            ),
        ], false);
      for (final stroke in [(WdColors.ink, 4.0), (WdColors.lime, 2.0)]) {
        canvas.drawPath(
          path,
          Paint()
            ..color = stroke.$1
            ..strokeWidth = stroke.$2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.segments != segments;
}
