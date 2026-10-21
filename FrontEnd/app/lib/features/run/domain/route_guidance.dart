/// 코스 이탈·복귀 안내(정책 제3부 6·7장, AUD-01·02). 앱 안내 전용이며 기록 판정에는 영향이 없다(7.3).
/// 수치는 정책의 기존 테스트 수치로 주행 검증 전 개발값이다(D-16).
library;

import '../../../core/map/geo_point.dart';
import 'course_tracker.dart';
import 'recording_models.dart';

enum GuidanceState {
  /// 경로 위(또는 아직 판단 전)
  onRoute,

  /// 이탈 후보: 믿을 수 있는 위치가 경로에서 [RouteGuidance.offRouteM] 초과
  candidate,

  /// 이탈 확정
  off,
}

/// 화면·음성이 할 일
enum GuidanceCue {
  /// 후보 음성 1회(AUD-01)
  candidate,

  /// 팝업 "코스를 벗어났어요" + 진동 + 확정 음성(AUD-02)
  alert,

  /// 열린 팝업을 닫는다(복귀·일시정지)
  dismiss,
}

class RouteGuidance {
  RouteGuidance(this.route);
  final RouteGeometry route;

  static const offRouteM = 30.0, returnM = 20.0;
  static const confirmMs = 10000, returnMs = 5000, minFixes = 3;

  /// 확인을 누른 뒤 이탈이 계속되면 다시 안내할 때까지(7.2)
  static const repeatMs = 30000;

  /// 복귀 확정 뒤 재이탈 안내를 미루는 시간(7.2). 이탈 판정 시간과는 별개다
  static const graceMs = 15000;

  /// 서버·자유 러닝 거리와 같은 기준: 이보다 빠르게 옮겨 간 위치·이보다 긴 공백은 믿지 않는다
  static const _maxSpeedMps = 12.0, _maxIntervalMs = 10000;

  GuidanceState state = GuidanceState.onRoute;

  /// 이번 러닝에서 "다시 표시하지 않음"을 골랐다. 팝업·진동·이탈 음성을 끈다(지도 표시는 그대로)
  bool muted = false;
  bool alertOpen = false;

  /// 마지막으로 믿을 수 있는 위치에서 경로까지 거리와 가장 가까운 경로 지점
  double? distanceM;
  GeoPoint? nearestPoint;

  int _fed = 0;
  bool _paused = false, _done = false;
  RunInput? _last;
  int? _offSince, _backSince, _graceUntil, _alertAt;
  int _offFixes = 0, _backFixes = 0;

  /// 같은 기록의 입력 목록을 계속 넘긴다. 새 입력만 보고 할 일을 돌려준다. `SEGMENT_END`·`END` 뒤는 안내하지 않는다
  List<GuidanceCue> feed(List<RunInput> inputs) {
    final cues = <GuidanceCue>[];
    for (; _fed < inputs.length && !_done; _fed++) {
      final input = inputs[_fed];
      switch (input.kind) {
        case RunKind.gps:
          if (!_paused) _sample(input, cues);
        case RunKind.pause:
          _paused = true;
          _reset(cues); // 일시정지 중 안내 중단, 재개 뒤 위치를 다시 확인한다
        case RunKind.resume:
          _paused = false;
        case RunKind.gap:
          _last = null;
          _unreliable();
        case RunKind.segmentEnd || RunKind.end:
          _done = true;
          _reset(cues);
        case RunKind.start || RunKind.cadence || RunKind.barometer:
          break;
      }
    }
    return cues;
  }

  /// [확인]: 팝업만 닫는다. 이탈이 이어지면 [atMs] + 30초에 다시 안내한다
  void acknowledge(int atMs) {
    alertOpen = false;
    if (state == GuidanceState.off) _alertAt = atMs + repeatMs;
  }

  /// [다시 표시하지 않음]: 이번 러닝 끝까지 이탈 팝업·진동·음성을 끈다
  void mute() {
    muted = true;
    alertOpen = false;
  }

  void _sample(RunInput input, List<GuidanceCue> cues) {
    final last = _last;
    if (last != null && input.elapsedMs - last.elapsedMs > _maxIntervalMs) _unreliable();
    if (!_reliable(input)) {
      _unreliable(); // 판단 보류, 쌓던 지속 시간 초기화(6장 GPS 불량·순간 튐)
      return;
    }
    _last = input;
    final nearest = route.nearest(input.lat!, input.lng!);
    distanceM = nearest.d;
    nearestPoint = nearest.point;
    final ms = input.elapsedMs;

    switch (state) {
      case GuidanceState.onRoute:
        if (nearest.d > offRouteM) {
          state = GuidanceState.candidate;
          _offSince = ms;
          _offFixes = 1;
          if (!muted && !_inGrace(ms)) cues.add(GuidanceCue.candidate);
        }
      case GuidanceState.candidate:
        if (nearest.d <= offRouteM) {
          state = GuidanceState.onRoute;
          _offSince = null;
          _offFixes = 0;
        } else {
          _offSince ??= ms;
          _offFixes++;
          if (ms - _offSince! >= confirmMs && _offFixes >= minFixes) {
            state = GuidanceState.off;
            _alertAt = ms;
          }
        }
      case GuidanceState.off:
        if (nearest.d <= returnM) {
          _backSince ??= ms;
          _backFixes++;
          if (ms - _backSince! >= returnMs && _backFixes >= minFixes) {
            state = GuidanceState.onRoute;
            _backSince = null;
            _backFixes = 0;
            _alertAt = null;
            _graceUntil = ms + graceMs;
            if (alertOpen) cues.add(GuidanceCue.dismiss);
            alertOpen = false;
          }
        } else {
          _backSince = null;
          _backFixes = 0;
        }
    }
    if (state == GuidanceState.off) _maybeAlert(ms, cues);
  }

  /// 확정 직후·확인 30초 뒤·복귀 유예가 끝난 뒤 안내한다. 열려 있으면 쌓지 않는다
  void _maybeAlert(int ms, List<GuidanceCue> cues) {
    final at = _alertAt;
    if (muted || alertOpen || at == null || ms < at || _inGrace(ms)) return;
    alertOpen = true;
    _alertAt = null;
    cues.add(GuidanceCue.alert);
  }

  bool _inGrace(int ms) => _graceUntil != null && ms < _graceUntil!;

  /// 정확도와 앞 위치와의 연속성(12m/s)으로 본다(6장 "정확도 수치 하나로 판단하지 않는다")
  bool _reliable(RunInput input) {
    if (!input.good) return false;
    final last = _last;
    if (last == null) return true;
    final interval = input.elapsedMs - last.elapsedMs;
    return interval > 0 && last.distanceTo(input) <= interval / 1000 * _maxSpeedMps;
  }

  void _unreliable() {
    if (state == GuidanceState.candidate) {
      _offSince = null;
      _offFixes = 0;
    }
    _backSince = null;
    _backFixes = 0;
  }

  void _reset(List<GuidanceCue> cues) {
    if (alertOpen) cues.add(GuidanceCue.dismiss);
    alertOpen = false;
    state = GuidanceState.onRoute;
    _last = null;
    _offSince = _backSince = _alertAt = null;
    _offFixes = _backFixes = 0;
    distanceM = null;
    nearestPoint = null;
  }
}
