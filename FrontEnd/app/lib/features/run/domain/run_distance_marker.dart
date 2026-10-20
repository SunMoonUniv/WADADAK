import 'run_models.dart';

/// A display-only kilometre reached on an accepted movement segment.
class RunDistanceMarker {
  const RunDistanceMarker(this.km, this.point);
  final int km;
  final RunPoint point;
}

/// Uses the same metre distances as recording, never the map SDK's geometry.
/// Each inner list is continuous; gaps/pauses contribute no connecting edge.
List<RunDistanceMarker> runDistanceMarkers(RunSnapshot run) {
  const epsilonM = .000001; // Same boundary tolerance as automatic laps.
  if (!run.distanceMeters.isFinite || run.distanceMeters < 1000 - epsilonM) {
    return const [];
  }
  final limit = ((run.distanceMeters + epsilonM) / 1000).floor();
  final markers = <RunDistanceMarker>[];
  var distanceM = 0.0;
  var km = 1;
  for (final segment in run.segments) {
    for (var i = 1; i < segment.length; i++) {
      final a = segment[i - 1], b = segment[i];
      if (!_valid(a) || !_valid(b)) continue;
      final length = a.distanceTo(b);
      if (!length.isFinite || length <= 0) continue;
      final end = distanceM + length;
      while (km <= limit && km * 1000 <= end + epsilonM) {
        final fraction = ((km * 1000 - distanceM) / length).clamp(0.0, 1.0);
        // Follow the short longitude direction, including an antimeridian edge.
        final deltaLng = (b.longitude - a.longitude + 540) % 360 - 180;
        markers.add(
          RunDistanceMarker(
            km,
            RunPoint(
              a.latitude + (b.latitude - a.latitude) * fraction,
              (a.longitude + deltaLng * fraction + 540) % 360 - 180,
            ),
          ),
        );
        km++;
      }
      distanceM = end;
      if (km > limit) return List.unmodifiable(markers);
    }
  }
  return List.unmodifiable(markers);
}

bool _valid(RunPoint p) =>
    p.latitude.isFinite &&
    p.longitude.isFinite &&
    p.latitude.abs() <= 90 &&
    p.longitude.abs() <= 180;
