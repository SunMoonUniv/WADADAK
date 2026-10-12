import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/geo_point.dart';
import 'api_client.dart';

/// 입력점을 직선으로 이은 최종 경로(B3 다음 → B4). 서버가 만들고 저장하지 않는다.
@immutable
class GeneratedRoute {
  const GeneratedRoute({required this.route, required this.distanceMeters, required this.distanceMarkers});

  factory GeneratedRoute.fromJson(Map<Object?, Object?> json) => GeneratedRoute(
        route: [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)],
        distanceMeters: json['distanceMeters']! as int,
        distanceMarkers: [
          for (final marker in json['distanceMarkers']! as List)
            DistanceMarker((marker as Map)['km']! as int, GeoPoint.fromJson(marker['point']! as Map)),
        ],
      );

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
    return GeneratedRoute.fromJson(data! as Map);
  }

  /// 오늘 남은 등록 수. 0이면 그 방식의 코스 만들기를 미리 막는다(개발 정책 10.2 course).
  Future<RegistrationQuota> registrationQuota() async {
    final data = await callApi(() => _dio.get('$_courses/registration-quota'));
    return RegistrationQuota.fromJson(data! as Map);
  }
}

final courseApiClientProvider = Provider<CourseApiClient>((ref) => CourseApiClient(ref.watch(dioProvider)));
