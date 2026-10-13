import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/geo_point.dart';
import 'api_client.dart';

/// 입력점을 직선으로 이은 최종 경로(B3 다음 → B4). 서버가 만들고 저장하지 않는다.
@immutable
class GeneratedRoute {
  const GeneratedRoute({
    required this.anchorPoints,
    required this.route,
    required this.distanceMeters,
    required this.distanceMarkers,
  });

  factory GeneratedRoute.fromJson(Map<Object?, Object?> json, {required List<GeoPoint> anchorPoints}) => GeneratedRoute(
        anchorPoints: anchorPoints,
        route: [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)],
        distanceMeters: json['distanceMeters']! as int,
        distanceMarkers: [
          for (final marker in json['distanceMarkers']! as List)
            DistanceMarker((marker as Map)['km']! as int, GeoPoint.fromJson(marker['point']! as Map)),
        ],
      );

  /// 이 경로를 만든 B3 입력점. 등록할 때 다시 보낸다(서버는 받은 경로를 믿지 않고 입력점으로 다시 만든다).
  /// B4에는 보이지 않는다(정책 공통 3).
  final List<GeoPoint> anchorPoints;

  /// 첫 점 출발, 마지막 점 도착. 연속으로 같은 입력점은 서버가 하나로 합친다.
  final List<GeoPoint> route;

  /// WGS84 타원체 기준 경로 길이(m, 반올림).
  final int distanceMeters;

  /// 출발점부터 1km마다의 지점(B4-01 거리 표지).
  final List<DistanceMarker> distanceMarkers;
}

@immutable
class DistanceMarker {
  const DistanceMarker(this.km, this.point);

  /// 출발점부터의 거리(km).
  final int km;
  final GeoPoint point;
}

/// 난이도 하/중/상(B4-03).
enum Difficulty {
  easy('EASY', '하'),
  medium('MEDIUM', '중'),
  hard('HARD', '상');

  const Difficulty(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 코스 특징(B4-04). 순서는 정책 FIL-04와 같다.
enum CourseTag {
  flat('FLAT', '평지'),
  uphill('UPHILL', '오르막'),
  shade('SHADE', '그늘'),
  riverside('RIVERSIDE', '강변'),
  nightLight('NIGHT_LIGHT', '야간 조명'),
  restroom('RESTROOM', '화장실'),
  convenienceStore('CONVENIENCE_STORE', '편의점'),
  track('TRACK', '트랙');

  const CourseTag(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 등록한 코스(B4-07). 성공 팝업 뒤 홈(A2)이 [startPoint]로 새 코스 위치를 보여 준다.
@immutable
class RegisteredCourse {
  const RegisteredCourse({required this.courseId, required this.name, required this.startPoint});

  factory RegisteredCourse.fromJson(Map<Object?, Object?> json) => RegisteredCourse(
        courseId: json['courseId']! as String,
        name: json['name']! as String,
        startPoint: GeoPoint.fromJson(json['startPoint']! as Map),
      );

  final String courseId;

  /// 서버가 정리한 이름(앞뒤 공백 제거, 연속 공백 한 칸).
  final String name;
  final GeoPoint startPoint;
}

/// 오늘(Asia/Seoul) 남은 등록 수. 유형마다 따로 센다.
@immutable
class RegistrationQuota {
  const RegistrationQuota({required this.custom, required this.gps});

  factory RegistrationQuota.fromJson(Map<Object?, Object?> json) =>
      RegistrationQuota(custom: TypeQuota._fromJson(json['custom']! as Map), gps: TypeQuota._fromJson(json['gps']! as Map));

  /// 사용자 지정(B3 지도에 점 찍기). 하루 1개.
  final TypeQuota custom;

  /// GPS 주행 등록(B5·B6 합산). 하루 3개.
  final TypeQuota gps;
}

@immutable
class TypeQuota {
  const TypeQuota({required this.limit, required this.remaining});

  factory TypeQuota._fromJson(Map<Object?, Object?> json) =>
      TypeQuota(limit: json['limit']! as int, remaining: json['remaining']! as int);

  final int limit;
  final int remaining;
}

/// 코스 API(`/api/v1/courses`). 서버 모듈 prefix 하나에 클라이언트 하나(개발 정책 9장).
class CourseApiClient {
  CourseApiClient(this._dio);

  final Dio _dio;
  static const _courses = '/api/v1/courses';

  /// 입력점 → 최종 경로·거리·1km 표지(B3-06). 2개 미만 COURSE-003, 1km 미만 COURSE-004, 100km 초과 COURSE-005.
  Future<GeneratedRoute> generateRoute(List<GeoPoint> anchorPoints) async {
    final data = await callApi(() => _dio.post('$_courses/routes', data: {
          'anchorPoints': [for (final point in anchorPoints) point.toJson()],
        }));
    return GeneratedRoute.fromJson(data! as Map, anchorPoints: anchorPoints);
  }

  /// 활성 코스 중 같은 이름이 없으면 true(B4-02). 공백·대소문자만 다른 이름도 같은 이름이다. 2~50자 밖이면 COMMON-001.
  Future<bool> isNameAvailable(String name) async {
    final data = await callApi(() => _dio.get('$_courses/name-availability', queryParameters: {'name': name}));
    return (data! as Map)['available']! as bool;
  }

  /// 사용자 지정 코스 등록(B4-07). 서버가 [anchorPoints]로 경로를 다시 만들어 검증하고 바로 공개한다.
  ///
  /// [idempotencyKey]는 등록 시도마다 만들고, 같은 등록을 다시 보낼 때는 같은 값을 쓴다(개발 정책 10.2 course).
  /// 이름 중복 COURSE-006, 85% 겹침 007, 오늘 한도 008, 출발점 지역 없음 009.
  Future<RegisteredCourse> registerCustom({
    required String idempotencyKey,
    required List<GeoPoint> anchorPoints,
    required String name,
    required Difficulty difficulty,
    required Set<CourseTag> tags,
  }) async {
    final data = await callApi(() => _dio.post(
          _courses,
          data: {
            'anchorPoints': [for (final point in anchorPoints) point.toJson()],
            'name': name,
            'difficulty': difficulty.apiName,
            'tags': [for (final tag in tags) tag.apiName],
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        ));
    return RegisteredCourse.fromJson(data! as Map);
  }

  /// 오늘 남은 등록 수. 0이면 그 방식의 코스 만들기를 미리 막는다(개발 정책 10.2 course).
  Future<RegistrationQuota> registrationQuota() async {
    final data = await callApi(() => _dio.get('$_courses/registration-quota'));
    return RegistrationQuota.fromJson(data! as Map);
  }
}

final courseApiClientProvider = Provider<CourseApiClient>((ref) => CourseApiClient(ref.watch(dioProvider)));
