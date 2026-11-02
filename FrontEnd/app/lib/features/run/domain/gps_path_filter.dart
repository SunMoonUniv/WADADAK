import 'dart:math' as math;

import 'recording_models.dart';

/// PACE_V4 derived coordinates. Raw inputs and time/sequence values are retained.
/// Keep this algorithm identical to the server GpsPathFilter.
class GpsPathFilter {
  bool _enabled = false;
  RunInput? _before, _pending, _stationary;
  final List<RunInput> _deferred = [];

  List<RunInput> add(RunInput p) {
    if (p.kind == RunKind.start) _enabled = p.reason == 'PACE_V4';
    if (!_enabled) return [p];
    final out = <RunInput>[];
    if (p.kind == RunKind.cadence ||
        p.kind == RunKind.barometer ||
        p.kind == RunKind.segmentEnd) {
      if (_pending != null && p.elapsedMs - _pending!.elapsedMs <= 10000) {
        _deferred.add(p);
        return out;
      }
      if (_before != null && p.elapsedMs - _before!.elapsedMs > 10000) {
        _flush(out, false);
        _reset();
      }
      out.add(p);
      return out;
    }
    if (p.kind != RunKind.gps) {
      _flush(out, true);
      _reset();
      out.add(p);
      return out;
    }
    final last = _pending ?? _before;
    if (!_usable(p) || (last != null && !_connected(last, p))) {
      _flush(out, false);
      _reset();
      out.add(p);
      if (_usable(p)) _before = p;
      return out;
    }
    // No speed evidence means no correction and no added live-display delay.
    if (!_reliable(p) || (last != null && !_reliable(last))) {
      _flush(out, false);
      _reset();
      out.add(p);
      _before = p;
      return out;
    }
    if (_before == null) {
      _before = p;
      out.add(p);
      return out;
    }
    if (_pending == null) {
      _pending = p;
      return out;
    }
    _updateStationary(_before!, _pending!, p);
    out.add(_clean(_before!, _pending!, p));
    out.addAll(_deferred);
    _deferred.clear();
    _before = _pending;
    _pending = p;
    return out;
  }

  void _updateStationary(RunInput a, RunInput b, RunInput c) {
    if (_stationary != null &&
        (!_stopped(c) || _stationary!.distanceTo(c) > _radius(_stationary!))) {
      _stationary = null;
    }
    if (_stationary == null &&
        _stopped(a) &&
        _stopped(b) &&
        _stopped(c) &&
        c.elapsedMs - a.elapsedMs >= 2000 &&
        a.distanceTo(b) <= _radius(a) &&
        a.distanceTo(c) <= _radius(a)) {
      _stationary = a;
    }
  }

  RunInput _clean(RunInput a, RunInput b, RunInput c) {
    if (_stationary != null &&
        _stopped(b) &&
        _stationary!.distanceTo(b) <= _radius(_stationary!)) {
      return _at(b, _stationary!.lat!, _stationary!.lng!);
    }
    if (!_reliable(a) || !_reliable(b) || !_reliable(c)) return b;
    final dt = c.elapsedMs - a.elapsedMs;
    if (dt <= 0 || dt > 6000) return b;
    final t = (b.elapsedMs - a.elapsedMs) / dt;
    final lat = a.lat! + (c.lat! - a.lat!) * t;
    final lng = a.lng! + (c.lng! - a.lng!) * t;
    final interpolation = _at(b, lat, lng);
    final deviation = b.distanceTo(interpolation);
    final ab = a.distanceTo(b), bc = b.distanceTo(c), ac = a.distanceTo(c);
    final expected =
        (a.speedMps! + 2 * b.speedMps! + c.speedMps!) * .25 * dt / 1000;
    if (deviation <= 6 &&
        deviation > 1 &&
        ab + bc > ac * 1.5 &&
        ab + bc > expected + 4 &&
        ac <= expected + 2) {
      return interpolation;
    }
    final cosine = ab * bc == 0
        ? -1.0
        : (ac * ac - ab * ab - bc * bc) / (2 * ab * bc);
    if (a.speedMps! >= .3 &&
        b.speedMps! >= .3 &&
        c.speedMps! >= .3 &&
        cosine >= .5 &&
        deviation <= 2 &&
        deviation >= .05) {
      final weight = math.min(.5, 1 / deviation);
      return _at(
        b,
        b.lat! + (lat - b.lat!) * weight,
        b.lng! + (lng - b.lng!) * weight,
      );
    }
    return b;
  }

  void _flush(List<RunInput> out, bool holdStop) {
    if (_pending != null) {
      final p = _pending!;
      out.add(
        holdStop &&
                _stationary != null &&
                _stopped(p) &&
                _stationary!.distanceTo(p) <= _radius(_stationary!)
            ? _at(p, _stationary!.lat!, _stationary!.lng!)
            : p,
      );
    }
    out.addAll(_deferred);
    _deferred.clear();
    _pending = null;
  }

  void _reset() {
    _before = null;
    _pending = null;
    _stationary = null;
  }

  static double _radius(RunInput p) => math.max(3, math.min(6, p.accuracyM!));
  static bool _usable(RunInput p) => p.good && p.accuracyM! <= 15;
  static bool _connected(RunInput a, RunInput b) {
    final dt = b.elapsedMs - a.elapsedMs;
    return _usable(a) &&
        dt > 0 &&
        dt <= 10000 &&
        a.distanceTo(b) * 1000 / dt <= 12;
  }

  static bool _reliable(RunInput p) =>
      _usable(p) &&
      p.speedMps != null &&
      p.speedMps!.isFinite &&
      p.speedMps! >= 0 &&
      p.speedMps! <= 12 &&
      p.speedAccuracyMps != null &&
      p.speedAccuracyMps!.isFinite &&
      p.speedAccuracyMps! > 0 &&
      p.speedAccuracyMps! <= .5;
  static bool _stopped(RunInput p) => _reliable(p) && p.speedMps! <= .2;
  static RunInput _at(RunInput p, double lat, double lng) => RunInput(
    seq: p.seq,
    kind: p.kind,
    elapsedMs: p.elapsedMs,
    measuredAt: p.measuredAt,
    lat: lat,
    lng: lng,
    accuracyM: p.accuracyM,
    reason: p.reason,
    speedMps: p.speedMps,
    speedAccuracyMps: p.speedAccuracyMps,
    steps: p.steps,
    durationMs: p.durationMs,
    sampleEndMs: p.sampleEndMs,
    altitudeM: p.altitudeM,
    altitudeAccuracyM: p.altitudeAccuracyM,
    pressureHpa: p.pressureHpa,
    pressureAccuracy: p.pressureAccuracy,
  );
}
