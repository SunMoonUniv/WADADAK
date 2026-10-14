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

  static Difficulty fromApi(String name) => values.firstWhere((value) => value.apiName == name);
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

  /// 앱이 모르는 특징(서버에 새로 생긴 것)은 null.
  static CourseTag? fromApi(String name) => values.where((value) => value.apiName == name).firstOrNull;
}

/// 코스 유형(정책 공통 3). 카드 아래 줄에 보인다(Figma A2 · A6).
enum CourseType {
  /// 지도에 점을 찍어 만든 코스(B3).
  custom('CUSTOM', '그려서 만든 코스'),

  /// 러닝 기록으로 만든 코스(B5 · B6).
  gps('GPS', '달려서 만든 코스');

  const CourseType(this.apiName, this.label);
  final String apiName;
  final String label;

  static CourseType fromApi(String name) => values.firstWhere((value) => value.apiName == name);
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

/// 지도 범위 안 코스(A2·A5). 출발점이 범위 안에 있는 활성 코스다(정책 MAP-04).
@immutable
class CourseMap {
  const CourseMap({required this.totalCount, required this.courses});

  factory CourseMap.fromJson(Map<Object?, Object?> json) => CourseMap(
        totalCount: json['totalCount']! as int,
        courses: [for (final course in json['courses']! as List) MapCourse.fromJson(course as Map)],
      );

  /// 범위 안 코스 전체 수(지도의 "코스 N개").
  final int totalCount;

  /// 그중 최대 100개, 최근 등록순.
  final List<MapCourse> courses;
}

@immutable
class MapCourse {
  const MapCourse({required this.courseId, required this.name, required this.route});

  factory MapCourse.fromJson(Map<Object?, Object?> json) => MapCourse(
        courseId: json['courseId']! as String,
        name: json['name']! as String,
        route: [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)],
      );

  final String courseId;
  final String name;

  /// 첫 점 출발, 마지막 점 도착(코스 방향).
  final List<GeoPoint> route;
}

/// 지역별 코스 수를 어느 단위로 세나(MAP-02).
enum RegionLevel {
  /// 특별·광역시는 통째로, 도는 시·군마다(서울 · 수원 · 연천군). 축척 2km보다 넓을 때.
  city('CITY'),

  /// 시·군·구마다(성북구 · 장안구 · 의정부시). 축척 2km부터 500m 전까지.
  district('DISTRICT');

  const RegionLevel(this.apiName);
  final String apiName;
}

/// 지도 범위 안 코스를 출발점 지역별로 센 것(A4). 지도 범위 안 코스와 같은 조건이다(MAP-07).
@immutable
class RegionCounts {
  const RegionCounts({required this.totalCount, required this.regions});

  factory RegionCounts.fromJson(Map<Object?, Object?> json) => RegionCounts(
        totalCount: json['totalCount']! as int,
        regions: [for (final region in json['regions']! as List) RegionCount.fromJson(region as Map)],
      );

  /// 범위 안 코스 전체 수.
  final int totalCount;

  /// 코스가 많은 지역부터.
  final List<RegionCount> regions;
}

@immutable
class RegionCount {
  const RegionCount({required this.code, required this.name, required this.count, required this.center});

  factory RegionCount.fromJson(Map<Object?, Object?> json) => RegionCount(
        code: json['code']! as String,
        name: json['name']! as String,
        count: json['count']! as int,
        center: GeoPoint.fromJson(json['center']! as Map),
      );

  /// 지역을 가리는 값. 같은 단위 안에서 겹치지 않는다.
  final String code;

  /// 지도에 보일 짧은 이름(서울 · 광주 · 의정부 · 연천군 · 성북구).
  final String name;
  final int count;

  /// 이 지역의 범위 안 코스 출발점들의 가운데. 개수 배지를 놓는다(A4-01).
  final GeoPoint center;
}

/// 코스 목록 정렬(FIL-01). 인기순 · 평점순 · 실시간순은 코스 통계(F11), 가까운순은 현재 위치(`LocationService`)가 생기면 붙인다.
enum CourseListSort {
  /// 등록 시각이 늦은 코스부터.
  latest('LATEST');

  const CourseListSort(this.apiName);
  final String apiName;
}

/// 코스 목록 한 쪽(A2 · A6). 다음 쪽은 [nextCursor]로 받는다.
@immutable
class CourseListPage {
  const CourseListPage({required this.courses, required this.nextCursor});

  factory CourseListPage.fromJson(Map<Object?, Object?> json) => CourseListPage(
        courses: [for (final course in json['content']! as List) CourseListItem.fromJson(course as Map)],
        nextCursor: json['nextCursor'] as String?,
      );

  final List<CourseListItem> courses;

  /// 마지막 쪽이면 null.
  final String? nextCursor;
}

/// 코스 목록 카드(A2-05 · A6-03). 평점 · 리뷰 수 · 현재 러너는 코스 통계(F11)가 생기면 붙인다.
@immutable
class CourseListItem {
  const CourseListItem({
    required this.courseId,
    required this.name,
    required this.distanceMeters,
    required this.difficulty,
    required this.tags,
    required this.courseType,
    required this.expiresAt,
    required this.route,
  });

  factory CourseListItem.fromJson(Map<Object?, Object?> json) => CourseListItem(
        courseId: json['courseId']! as String,
        name: json['name']! as String,
        distanceMeters: json['distanceMeters']! as int,
        difficulty: Difficulty.fromApi(json['difficulty']! as String),
        tags: [for (final tag in json['tags']! as List) ?CourseTag.fromApi(tag as String)],
        courseType: CourseType.fromApi(json['courseType']! as String),
        expiresAt: DateTime.parse(json['expiresAt']! as String),
        route: [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)],
      );

  final String courseId;
  final String name;
  final int distanceMeters;
  final Difficulty difficulty;

  /// FIL-04 순서.
  final List<CourseTag> tags;
  final CourseType courseType;

  /// 공개 만료 시각(만료일 23:59:59 Asia/Seoul).
  final DateTime expiresAt;

  /// 카드 썸네일. 첫 점이 출발점이다.
  final List<GeoPoint> route;
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

  /// 지도 범위(남서쪽·북동쪽 끝) 안 코스(A2·A5).
  Future<CourseMap> mapCourses({required GeoPoint southWest, required GeoPoint northEast}) async {
    final data = await callApi(() => _dio.get('$_courses/map', queryParameters: {
          'swLat': southWest.lat,
          'swLng': southWest.lng,
          'neLat': northEast.lat,
          'neLng': northEast.lng,
        }));
    return CourseMap.fromJson(data! as Map);
  }

  /// 지도 범위 안 코스를 출발점 지역별로 센다(A4 지도 축소).
  Future<RegionCounts> regionCounts({
    required GeoPoint southWest,
    required GeoPoint northEast,
    required RegionLevel level,
  }) async {
    final data = await callApi(() => _dio.get('$_courses/map/regions', queryParameters: {
          'swLat': southWest.lat,
          'swLng': southWest.lng,
          'neLat': northEast.lat,
          'neLng': northEast.lng,
          'level': level.apiName,
        }));
    return RegionCounts.fromJson(data! as Map);
  }

  /// 지도 범위 안 코스 목록 한 쪽(A2 · A6). 조건은 [mapCourses]와 같다(MAP-07).
  /// 다음 쪽은 앞 쪽의 [CourseListPage.nextCursor]를 [cursor]로 보내고, 범위 · 정렬은 첫 쪽과 같게 보낸다.
  Future<CourseListPage> listCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseListSort sort = CourseListSort.latest,
    String? cursor,
  }) async {
    final data = await callApi(() => _dio.get(_courses, queryParameters: {
          'swLat': southWest.lat,
          'swLng': southWest.lng,
          'neLat': northEast.lat,
          'neLng': northEast.lng,
          'sort': sort.apiName,
          'cursor': ?cursor,
        }));
    return CourseListPage.fromJson(data! as Map);
  }

  /// 오늘 남은 등록 수. 0이면 그 방식의 코스 만들기를 미리 막는다(개발 정책 10.2 course).
  Future<RegistrationQuota> registrationQuota() async {
    final data = await callApi(() => _dio.get('$_courses/registration-quota'));
    return RegistrationQuota.fromJson(data! as Map);
  }
}

final courseApiClientProvider = Provider<CourseApiClient>((ref) => CourseApiClient(ref.watch(dioProvider)));
