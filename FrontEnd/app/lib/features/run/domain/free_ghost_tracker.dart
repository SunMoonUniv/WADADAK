part of 'course_tracker.dart';

/// FREE_V2 only. Keep scoring, branch limits and hard boundaries identical to Java FreeGhostTracker.
class _FreeGhostTracker {
  _FreeGhostTracker(this.route);
  final RouteGeometry route;
  final points = <TrackPoint>[];
  List<_FreeState> _states = [];
  RunInput? _previous;
  bool _confirmed = false, _paused = false, _done = false;
  int _fed = 0;
  static const _maxBranches = 8,
      _branchSeparationM = 20.0,
      _confidenceMargin = 9.0,
      _eps = 1e-6;

  void feed(List<RunInput> inputs) {
    for (; _fed < inputs.length && !_done; _fed++) {
      final input = inputs[_fed];
      switch (input.kind) {
        case RunKind.end || RunKind.segmentEnd:
          _done = true;
          _reset();
        case RunKind.gps:
          if (!_paused) _sample(input);
        case RunKind.pause:
          _paused = true;
          _reset();
        case RunKind.resume:
          _paused = false;
          _reset();
        case RunKind.gap:
          _reset();
        default:
          break;
      }
    }
  }

  void _reset() {
    _states = [];
    _previous = null;
    _confirmed = false;
  }

  double _heading(RunInput from, RunInput to, int segment) {
    final a = route.toLocal(from.lat!, from.lng!),
        b = route.toLocal(to.lat!, to.lng!);
    final u = route._vertices[segment], v = route._vertices[segment + 1];
    final dx = b.$1 - a.$1,
        dy = b.$2 - a.$2,
        rx = v.$1 - u.$1,
        ry = v.$2 - u.$2;
    final scale = math.sqrt(dx * dx + dy * dy) * math.sqrt(rx * rx + ry * ry);
    return scale < 1e-9 ? 1 : ((dx * rx + dy * ry) / scale).clamp(-1.0, 1.0);
  }

  void _sample(RunInput input) {
    final index = points.length;
    points.add(TrackPoint(input, null, false));
    if (!input.good) {
      _reset();
      return;
    }
    var prior = _previous;
    final dt = prior == null ? 0 : input.elapsedMs - prior.elapsedMs;
    final moved = prior == null ? 0.0 : prior.distanceTo(input);
    if (prior != null && (dt <= 0 || dt > _maxIntervalMs)) {
      _reset();
      prior = null;
    } else if (prior != null && moved * 1000 / dt > _maxSpeedMps) {
      _reset();
      _previous = input;
      return;
    }
    final candidates = route.candidates(
      route.toLocal(input.lat!, input.lng!),
      _routeToleranceM,
    );
    if (candidates.isEmpty) {
      _reset();
      return;
    }
    final expanded = <_FreeState>[];
    if (_states.isNotEmpty && prior != null) {
      final reach = dt / 1000 * _maxSpeedMps + _routeToleranceM;
      for (final state in _states) {
        for (final candidate in candidates) {
          final delta = candidate.s - state.s;
          if (delta.abs() > reach + _eps ||
              (!_confirmed &&
                  candidate.s < state.max - _routeToleranceM - _eps)) {
            continue;
          }
          final error = delta.abs() - moved;
          var heading = _heading(prior, input, candidate.segment);
          if (delta < 0) heading = -heading;
          final cost =
              state.cost +
              candidate.d * candidate.d +
              .25 * error * error +
              (delta < 0 ? .25 * moved * moved : 0) +
              (moved < .25 || delta.abs() < .25
                  ? 0
                  : .5 * moved * moved * (1 - heading));
          expanded.add(
            _FreeState(
              candidate.s,
              math.max(state.max, candidate.s),
              cost,
              _FreeNode(index, candidate.s, true, state.path),
            ),
          );
        }
      }
    }
    if (expanded.isEmpty) {
      _states = [];
      _confirmed = false;
      for (final c in candidates) {
        expanded.add(
          _FreeState(c.s, c.s, c.d * c.d, _FreeNode(index, c.s, false, null)),
        );
      }
    }
    expanded.sort((a, b) {
      final c = a.cost.compareTo(b.cost);
      return c == 0 ? a.s.compareTo(b.s) : c;
    });
    final branches = <_FreeState>[];
    for (final state in expanded) {
      if (!branches.any(
        (b) => (b.s - state.s).abs() <= _branchSeparationM + _eps,
      )) {
        branches.add(state);
      }
      if (branches.length > _maxBranches) {
        _reset();
        _previous = input;
        return;
      }
    }
    final best = branches.first;
    final clear =
        branches.length == 1 ||
        branches[1].cost - best.cost > _confidenceMargin;
    _previous = input;
    if (clear) {
      for (var node = best.path; node != null; node = node.previous) {
        points[node.index]
          ..s = node.s
          ..connected = node.connected;
      }
      _states = [_FreeState(best.s, best.max, 0, null)];
      _confirmed = true;
    } else {
      _states = [
        for (final s in branches)
          _FreeState(s.s, s.max, s.cost - best.cost, s.path),
      ];
    }
  }
}

class _FreeNode {
  const _FreeNode(this.index, this.s, this.connected, this.previous);
  final int index;
  final double s;
  final bool connected;
  final _FreeNode? previous;
}

class _FreeState {
  const _FreeState(this.s, this.max, this.cost, this.path);
  final double s, max, cost;
  final _FreeNode? path;
}
