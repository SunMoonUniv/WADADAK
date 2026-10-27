/// 서버 코스 판정 엔진(`BackEnd/.../run/internal/judging`: RouteGeometry·CourseTracker·RecognizedDistance)을 옮긴 것.
/// 달리는 중 진행도·남은 거리·km 표지 안내에만 쓰고 완주는 판정하지 않는다(RCR-07, 서버만 판정).
/// 알고리즘과 기준값이 서버와 같아야 화면 진행도와 서버 판정이 맞는다. 서버를 고치면 여기도 고친다.
library;

import 'dart:math' as math;

import '../../../core/map/geo_point.dart';
import 'recording_models.dart';

/// 서버 `JudgingConfig.DEFAULTS`·`GpsQuality`와 같은 값(주행 검증 전 개발값).
const _routeToleranceM = 20.0;
const _maxSpeedMps = 12.0;
const _maxIntervalMs = 10000;
const _earthRadiusM = 6371008.8;

/// 코스상 위치 s(m, 출발 0)와 경로까지 거리 d(m).
typedef Projection = ({int segment, double s, double d});

/// 코스 경로를 판정용 평면(m)으로 편다. 원점은 출발점, x = 동, y = 북, 경도 차이는 cos(출발 위도)로 줄인다.
class RouteGeometry {
  RouteGeometry(this.route, {List<int> breaks = const []})
    : breaks = Set.unmodifiable(breaks),
      assert(route.length >= 2, '경로는 점이 2개 이상이어야 한다') {
    _cosLat0 = math.cos(route.first.lat * math.pi / 180);
    _vertices = [for (final p in route) toLocal(p.lat, p.lng)];
    _cumulative = [0];
    for (var i = 1; i < _vertices.length; i++) {
      _cumulative.add(
        _cumulative[i - 1] +
            (this.breaks.contains(i)
                ? 0
                : _distance(_vertices[i - 1], _vertices[i])),
      );
    }
  }

  final List<GeoPoint> route;
  final Set<int> breaks;
  List<List<GeoPoint>> get segments {
    final edges = [0, ...(breaks.toList()..sort()), route.length];
    return [
      for (var i = 1; i < edges.length; i++)
        route.sublist(edges[i - 1], edges[i]),
    ];
  }

  GeoPoint? pointAt(double s) {
    if (breaks.any((i) => (s - _cumulative[i]).abs() < 1e-6)) return null;
    for (var i = 0; i < route.length - 1; i++) {
      if (breaks.contains(i + 1)) continue;
      final from = _cumulative[i], to = _cumulative[i + 1];
      if (s >= from && s <= to && to > from) {
        final t = (s - from) / (to - from), a = route[i], b = route[i + 1];
        return GeoPoint(
          a.lat + (b.lat - a.lat) * t,
          a.lng + (b.lng - a.lng) * t,
        );
      }
    }
    return null;
  }

  late final double _cosLat0;
  late final List<(double, double)> _vertices;

  /// 출발점부터 각 꼭짓점까지 경로 길이(m).
  late final List<double> _cumulative;

  /// 경로 전체 길이(m). 진행도의 기준(서버와 같다).
  double get length => _cumulative.last;

  (double, double) toLocal(double lat, double lng) => (
    (lng - route.first.lng) * math.pi / 180 * _cosLat0 * _earthRadiusM,
    (lat - route.first.lat) * math.pi / 180 * _earthRadiusM,
  );

  /// 선분 [segment]에 수선을 내린 위치. t = (AP·AB)/|AB|²를 0~1로 자른다.
  Projection project((double, double) p, int segment) {
    final (ax, ay) = _vertices[segment];
    final (bx, by) = _vertices[segment + 1];
    final abx = bx - ax, aby = by - ay;
    final lengthSq = abx * abx + aby * aby;
    final t = lengthSq == 0
        ? 0.0
        : (((p.$1 - ax) * abx + (p.$2 - ay) * aby) / lengthSq).clamp(0.0, 1.0);
    return (
      segment: segment,
      s: _cumulative[segment] + t * math.sqrt(lengthSq),
      d: _distance(p, (ax + t * abx, ay + t * aby)),
    );
  }

  /// 경로까지 거리가 [tolerance] 이하인 후보, s 오름차순. 꼭짓점에서 두 선분이 같은 s를 내면 하나로 친다.
  List<Projection> candidates((double, double) p, double tolerance) {
    final found =
        [
            for (var i = 0; i < _vertices.length - 1; i++)
              if (!breaks.contains(i + 1)) project(p, i),
          ].where((c) => c.d <= tolerance).toList()
          ..sort((a, b) => a.s.compareTo(b.s));
    final distinct = <Projection>[];
    for (final c in found) {
      if (distinct.isEmpty || c.s - distinct.last.s > 1e-6) distinct.add(c);
    }
    return distinct;
  }

  /// 경로 전체에서 가장 가까운 지점과 그 거리(m). 이탈 안내용(정책 6장 "코스 경로선까지의 최단거리").
  /// 판정과 달리 직전 위치를 보지 않는다: 어느 구간이든 경로 가까이 있으면 이탈이 아니다
  ({double d, GeoPoint point}) nearest(double lat, double lng) {
    final p = toLocal(lat, lng);
    var best = project(p, 0);
    for (var i = 1; i < _vertices.length - 1; i++) {
      if (breaks.contains(i + 1)) continue;
      final c = project(p, i);
      if (c.d < best.d) best = c;
    }
    final span = _cumulative[best.segment + 1] - _cumulative[best.segment];
    final t = span == 0 ? 0.0 : (best.s - _cumulative[best.segment]) / span;
    final a = route[best.segment], b = route[best.segment + 1];
    return (
      d: best.d,
      point: GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t),
    );
  }

  /// 출발점부터 1km마다의 경로 위 지점(지도 거리 표지, 안내용). 평면이 위도·경도에 선형이라 위도·경도로 보간한다.
  List<(int, GeoPoint)> kilometres() {
    final markers = <(int, GeoPoint)>[];
    var segment = 0;
    for (var km = 1; km * 1000 <= length + 1e-6; km++) {
      final at = km * 1000.0;
      while (segment < _vertices.length - 2 &&
          (_cumulative[segment + 1] < at || breaks.contains(segment + 1))) {
        segment++;
      }
      final span = _cumulative[segment + 1] - _cumulative[segment];
      final t = span == 0
          ? 0.0
          : ((at - _cumulative[segment]) / span).clamp(0.0, 1.0);
      final a = route[segment], b = route[segment + 1];
      markers.add((
        km,
        GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t),
      ));
    }
    return markers;
  }

  static double _distance((double, double) a, (double, double) b) =>
      math.sqrt((b.$1 - a.$1) * (b.$1 - a.$1) + (b.$2 - a.$2) * (b.$2 - a.$2));
}

/// 표본 하나의 추적 결과. [s]가 null이면 코스 밖·나쁜 GPS·아직 정하지 못한 보류 표본.
/// [connected]면 직전 표본과 이어져 그 사이를 인정한다.
class TrackPoint {
  TrackPoint(this.input, this.s, this.connected);
  final RunInput input;
  double? s;
  bool connected;
}

/// 윈도우 추적(서버 CourseTracker). 서버는 기록 전체를 한 번에 보지만 앱은 [feed]로 새 입력만 이어서 본다.
/// 보류했던 표본은 가설이 하나로 모이면 소급해 정한다(순환 코스 출발점 등).
class CourseTracker {
  CourseTracker(this.route);
  final RouteGeometry route;
  final points = <TrackPoint>[];

  int _fed = 0;
  bool _paused = false, _done = false;

  RunInput? _anchor;
  double _anchorS = 0;
  bool _linkable = false;
  final _held = <RunInput>[];
  final _heldIndexes = <int>[];
  var _hypotheses = <_Hypothesis>[];

  /// 같은 기록의 입력 목록을 계속 넘긴다. 앞서 본 입력은 건너뛴다. `SEGMENT_END`·`END` 뒤는 버린다.
  void feed(List<RunInput> inputs) {
    for (; _fed < inputs.length && !_done; _fed++) {
      final input = inputs[_fed];
      switch (input.kind) {
        case RunKind.segmentEnd || RunKind.end:
          _done = true;
          _forget();
        case RunKind.gps:
          if (!_paused) _sample(input); // 일시정지 중 이동은 인정하지 않는다(RCR-04)
        case RunKind.pause:
          _paused = true;
          _forget();
        case RunKind.resume:
          _paused = false;
        case RunKind.gap:
          _forget();
        case RunKind.start || RunKind.cadence || RunKind.barometer:
          break;
      }
    }
  }

  /// 마지막으로 정한 코스상 위치(m). 아직 없으면 null.
  double? get positionM => points.reversed.map((p) => p.s).nonNulls.firstOrNull;

  /// 코스 인정 거리(m): 이어진 두 표본 사이 s가 늘어난 구간 [s1, s2]의 합집합 길이(서버 RecognizedDistance).
  double get recognizedM {
    final ranges = <(double, double)>[];
    TrackPoint? previous;
    for (final point in points) {
      final from = previous?.s, to = point.s;
      if (point.connected && from != null && to != null && to > from) {
        ranges.add((from, to));
      }
      previous = point;
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    var meters = 0.0;
    (double, double)? open;
    for (final range in ranges) {
      if (open != null && range.$1 <= open.$2) {
        open = (open.$1, math.max(open.$2, range.$2));
      } else {
        if (open != null) meters += open.$2 - open.$1;
        open = range;
      }
    }
    return open == null ? meters : meters + open.$2 - open.$1;
  }

  void _forget() {
    _anchor = null;
    _linkable = false;
    _clearHeld();
  }

  void _sample(RunInput input) {
    final previous = _anchor ?? _held.lastOrNull;
    // 10초 넘게 GPS가 없으면 GAP과 같다. 예전 기준·가설로 순환·교차를 정하지 않는다
    if (previous != null &&
        input.elapsedMs - previous.elapsedMs > _maxIntervalMs) {
      _forget();
    }
    final candidates = input.good
        ? route.candidates(
            route.toLocal(input.lat!, input.lng!),
            _routeToleranceM,
          )
        : const <Projection>[];

    if (candidates.isEmpty) {
      points.add(TrackPoint(input, null, false));
      _linkable = false;
      _clearHeld();
      return;
    }
    final anchor = _anchor;
    if (anchor != null) {
      final next = _choose(candidates, anchor, _anchorS, input);
      if (next == null) {
        _place(
          input,
          _nearest(candidates, _anchorS),
          false,
        ); // 점프: 건너뛴 구간은 인정하지 않는다
      } else {
        _place(input, next, _linkable && _withinSpeed(anchor, input));
      }
      return;
    }
    if (_hypotheses.isEmpty) {
      if (candidates.length == 1) {
        _place(input, candidates.first.s, false);
      } else {
        _hold(input);
        _hypotheses = [
          for (final c in candidates) _Hypothesis([c.s], c.s),
        ];
      }
      return;
    }
    _extendHypotheses(input, candidates);
  }

  void _extendHypotheses(RunInput input, List<Projection> candidates) {
    final previous = _held.last;
    final alive = <_Hypothesis>[];
    for (final hypothesis in _hypotheses) {
      final next = _choose(candidates, previous, hypothesis.values.last, input);
      // 정방향 가설만 남긴다. GPS 흔들림만큼(경로 오차) 뒤로 가는 것은 봐준다
      if (next != null && next >= hypothesis.max - _routeToleranceM) {
        alive.add(
          _Hypothesis([
            ...hypothesis.values,
            next,
          ], math.max(hypothesis.max, next)),
        );
      }
    }
    if (alive.isEmpty) {
      _clearHeld();
      _sample(input);
      return;
    }
    _hold(input);
    _hypotheses = alive;
    final converged = alive.map((h) => h.values.last).toSet().length == 1;
    if (alive.length == 1 || converged) {
      // 같은 자리로 모이면 정방향으로 더 나아간 가설(왕복 코스의 돌아오는 길)
      _resolve(alive.reduce((a, b) => b.max > a.max ? b : a));
    }
  }

  /// 보류했던 표본들을 남은 가설의 s로 소급해 정한다.
  void _resolve(_Hypothesis hypothesis) {
    for (var i = 0; i < _held.length; i++) {
      points[_heldIndexes[i]]
        ..s = hypothesis.values[i]
        ..connected = i > 0 && _withinSpeed(_held[i - 1], _held[i]);
    }
    _anchor = _held.last;
    _anchorS = hypothesis.values.last;
    _linkable = true;
    _clearHeld();
  }

  void _place(RunInput input, double s, bool connected) {
    points.add(TrackPoint(input, s, connected));
    _anchor = input;
    _anchorS = s;
    _linkable = true;
  }

  void _hold(RunInput input) {
    _heldIndexes.add(points.length);
    _held.add(input);
    points.add(TrackPoint(input, null, false));
  }

  void _clearHeld() {
    _held.clear();
    _heldIndexes.clear();
    _hypotheses = [];
  }

  /// 창(속도 상한 × 시간 차 + 경로 오차) 안 후보 중 정방향을 먼저, 그중 직전 s에 가장 가까운 것. 없으면 null.
  double? _choose(
    List<Projection> candidates,
    RunInput previous,
    double previousS,
    RunInput input,
  ) {
    final window = _reach(previous, input) + _routeToleranceM;
    double? forward, any;
    for (final c in candidates) {
      final gap = (c.s - previousS).abs();
      if (gap > window) continue;
      if (c.s >= previousS &&
          (forward == null || gap < (forward - previousS).abs())) {
        forward = c.s;
      }
      if (any == null || gap < (any - previousS).abs()) any = c.s;
    }
    return forward ?? any;
  }

  static double _nearest(List<Projection> candidates, double s) {
    var best = candidates.first.s;
    for (final c in candidates) {
      if ((c.s - s).abs() < (best - s).abs()) best = c.s;
    }
    return best;
  }

  static double _reach(RunInput previous, RunInput input) =>
      math.max(0, input.elapsedMs - previous.elapsedMs) / 1000 * _maxSpeedMps;

  /// 실제 좌표 거리가 속도 상한 안이다(정책 "12m/s 초과 위치 튐은 연결하지 않는다", GPS 오차 여유 없음).
  static bool _withinSpeed(RunInput previous, RunInput input) {
    final interval = input.elapsedMs - previous.elapsedMs;
    return interval > 0 &&
        interval <= _maxIntervalMs &&
        previous.distanceTo(input) <= _reach(previous, input);
  }
}

class _Hypothesis {
  _Hypothesis(this.values, this.max);
  final List<double> values;
  final double max;
}
