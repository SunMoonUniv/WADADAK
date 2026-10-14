import 'package:geolocator/geolocator.dart';

/// Existing run-specific GPS freshness and start accuracy rules.
abstract final class RunLocationPolicy {
  static bool fresh(Position p, DateTime now) {
    final age = now.difference(p.timestamp).inMilliseconds;
    return age >= -5000 && age <= 10000;
  }

  static bool usable(Position p, DateTime now) =>
      fresh(p, now) &&
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      p.accuracy <= 30;
}
