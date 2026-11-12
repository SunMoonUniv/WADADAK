part of 'course_api_client.dart';

// B3 `자동 생성`(`/api/v1/courses/plans`)의 요청 · 응답 모델.

/// 코스 자동 생성의 출발(B3 `자동 생성` A7 `출발`).
enum PlanStart {
  current('CURRENT', '현재 위치'),
  place('PLACE', '장소 검색');

  const PlanStart(this.apiName, this.label);
  final String apiName;
  final String label;

  static PlanStart? fromApi(String? name) => values.where((value) => value.apiName == name).firstOrNull;
}

/// 코스 자동 생성의 모양(A7 `모양`).
enum PlanShape {
  loop('LOOP', '한 바퀴'),
  outAndBack('OUT_AND_BACK', '왕복'),
  pointToPoint('POINT_TO_POINT', '편도'),
  via('VIA', '경유');

  const PlanShape(this.apiName, this.label);
  final String apiName;
  final String label;

  /// 거리 · 시간이 필요하다. 편도 · 경유는 거리 없이 도착지 · 경유지로 만든다(정책 B3-A02).
  bool get needsTarget => this == loop || this == outAndBack;

  static PlanShape? fromApi(String? name) => values.where((value) => value.apiName == name).firstOrNull;
}

/// 원하는 길. [supported]만 반영하고, 나머지는 문장에서 읽어도 후보 화면에 `아직 반영하지 않았어요`로 알린다.
/// 평지 · 오르막은 서버에 표고점 데이터가 없으면 반영하지 않고 같은 안내가 온다.
enum PlanPref {
  avoidArterial('AVOID_ARTERIAL', '큰길 피하기'),
  noRetrace('NO_RETRACE', '같은 길 반복 없이'),
  storeOnRoute('STORE_ON_ROUTE', '편의점 들르기'),
  flat('FLAT', '평지'),
  hilly('HILLY', '오르막'),
  sidewalk('SIDEWALK', '인도'),
  toiletOnRoute('TOILET_ON_ROUTE', '화장실 들르기'),
  river('RIVER', '강변'),
  park('PARK', '공원');

  const PlanPref(this.apiName, this.label);
  final String apiName;
  final String label;

  /// A7 `원하는 길` 칩 순서. 평지와 오르막은 함께 고르지 않는다.
  static const supported = [avoidArterial, noRetrace, storeOnRoute, toiletOnRoute, flat, hilly];

  static PlanPref? fromApi(String? name) => values.where((value) => value.apiName == name).firstOrNull;
}

/// 코스 자동 생성 조건(A7 폼). 문장으로 채운 값(A7-1)이면 읽지 못한 칸이 비어 있다.
@immutable
class PlanForm {
  const PlanForm({
    this.start,
    this.startQuery,
    this.shape,
    this.endQuery,
    this.viaQuery,
    this.distanceM,
    this.durationMin,
    this.prefer = const {},
    this.message,
  });

  factory PlanForm.fromJson(Map<Object?, Object?> json) {
    final start = json['start'] as Map?;
    return PlanForm(
      start: PlanStart.fromApi(start?['kind'] as String?),
      startQuery: start?['query'] as String?,
      shape: PlanShape.fromApi(json['shape'] as String?),
      endQuery: json['endQuery'] as String?,
      viaQuery: json['viaQuery'] as String?,
      distanceM: json['distanceM'] as int?,
      durationMin: json['durationMin'] as int?,
      prefer: {for (final pref in json['prefer'] as List? ?? const []) ?PlanPref.fromApi(pref as String)},
      message: json['message'] as String?,
    );
  }

  final PlanStart? start;

  /// 출발이 [PlanStart.place]일 때 장소 이름.
  final String? startQuery;
  final PlanShape? shape;

  /// 편도의 도착지 이름.
  final String? endQuery;

  /// 경유의 경유지 이름.
  final String? viaQuery;

  /// 목표 거리(m). 거리와 시간 중 하나만 쓴다.
  final int? distanceM;

  /// 목표 시간(분). 서버가 평소 페이스로 거리로 바꾼다.
  final int? durationMin;
  final Set<PlanPref> prefer;

  /// 코스와 관련 없는 문장이면 안내 문구(A1). 이때 다른 칸은 비어 있다.
  final String? message;

  PlanForm withShape(PlanShape shape) => PlanForm(
        start: start,
        startQuery: startQuery,
        shape: shape,
        endQuery: endQuery,
        viaQuery: viaQuery,
        distanceM: distanceM,
        durationMin: durationMin,
        prefer: prefer,
      );

  /// 모양에 쓰지 않는 칸은 보내지 않는다(편도 · 경유의 거리 등).
  Map<String, Object?> toJson() => {
        'start': {'kind': start!.apiName, if (start == PlanStart.place) 'query': startQuery},
        'shape': shape!.apiName,
        if (shape == PlanShape.pointToPoint) 'endQuery': endQuery,
        if (shape == PlanShape.via) 'viaQuery': viaQuery,
        if (shape!.needsTarget) ...{'distanceM': ?distanceM, 'durationMin': ?durationMin},
        'prefer': [for (final pref in prefer) pref.apiName],
      };
}

/// 후보가 없는 이유(정책 B3-A04).
enum PlanReason {
  /// 출발 · 도착 · 경유 장소를 찾지 못했다. 폼에 서버 문구를 보인다.
  placeNotFound('PLACE_NOT_FOUND'),

  /// 도착 · 경유지가 목표 거리에 비해 너무 멀다. 폼에 서버 문구를 보인다.
  placeTooFar('PLACE_TOO_FAR'),

  /// 길을 따라 후보를 만들지 못했다(A6). 한 바퀴면 왕복을 권한다.
  noCandidates('NO_CANDIDATES'),

  /// 만든 후보가 모두 기존 코스와 85% 이상 겹친다(A6).
  similarExists('SIMILAR_EXISTS');

  const PlanReason(this.apiName);
  final String apiName;

  static PlanReason? fromApi(String? name) => values.where((value) => value.apiName == name).firstOrNull;
}

/// 코스 자동 생성 결과. 후보가 없으면 [reason]과 [message]가 있다.
@immutable
class PlanResult {
  const PlanResult({
    required this.candidates,
    this.reason,
    this.message,
    this.startName,
    this.notApplied = const {},
  });

  factory PlanResult.fromJson(Map<Object?, Object?> json) => PlanResult(
        candidates: [for (final candidate in json['candidates']! as List) PlanCandidate.fromJson(candidate as Map)],
        reason: PlanReason.fromApi(json['reason'] as String?),
        message: json['message'] as String?,
        startName: json['startName'] as String?,
        notApplied: {for (final pref in json['notApplied'] as List? ?? const []) ?PlanPref.fromApi(pref as String)},
      );

  /// 0~3개, 좋은 순.
  final List<PlanCandidate> candidates;
  final PlanReason? reason;

  /// [reason]에 맞는 서버 안내 문구. 그대로 보인다.
  final String? message;

  /// 찾은 출발 장소 이름. 현재 위치 출발이면 null.
  final String? startName;

  /// 요청한 원하는 길 중 아직 반영하지 않은 것.
  final Set<PlanPref> notApplied;
}

/// 후보 하나(A3 카드).
@immutable
class PlanCandidate {
  const PlanCandidate({
    required this.anchorPoints,
    required this.distanceMeters,
    required this.retraceRatio,
    required this.arterialRatio,
    required this.storeCount,
    this.toiletCount = 0,
    this.ascentMeters,
  });

  factory PlanCandidate.fromJson(Map<Object?, Object?> json) => PlanCandidate(
        anchorPoints: [for (final point in json['anchorPoints']! as List) GeoPoint.fromJson(point as Map)],
        distanceMeters: json['distanceMeters']! as int,
        retraceRatio: (json['retraceRatio']! as num).toDouble(),
        arterialRatio: (json['arterialRatio']! as num).toDouble(),
        storeCount: json['storeCount']! as int,
        toiletCount: json['toiletCount'] as int? ?? 0,
        ascentMeters: json['ascentMeters'] as int?,
      );

  /// 고르면 B3 입력점으로 채운다(최대 500개, 정책 B3-A08). 첫 점이 출발이다.
  final List<GeoPoint> anchorPoints;
  final int distanceMeters;

  /// 같은 길을 되돌아오는 비율(0~1).
  final double retraceRatio;

  /// 큰길(간선도로) 비율(0~1).
  final double arterialRatio;

  /// 경로 50m 안 편의점 수.
  final int storeCount;

  /// 경로 100m 안 공중화장실 수.
  final int toiletCount;

  /// 경로를 따라 오른 높이(m). 서버가 모르면 null.
  final int? ascentMeters;
}
