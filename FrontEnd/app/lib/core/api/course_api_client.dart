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
        route: _routeFromJson(json),
        distanceMeters: json['distanceMeters']! as int,
        distanceMarkers: _distanceMarkersFromJson(json),
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

/// 러닝 기록 경로의 한 점(F7 GPS 코스 등록 D4 · B6). 달리기 서버 course-source의 점을 그대로 코스 서버에 보낸다.
/// 정확도 · 고도는 재지 못했으면 null이다. 코스 경로에는 위도 · 경도만 쓰고, 나머지는 서버가 원본으로 따로 둔다.
@immutable
class GpsSourcePoint {
  const GpsSourcePoint(this.lat, this.lng, {this.accuracyM, this.altitudeM, this.altitudeAccuracyM});

  factory GpsSourcePoint.fromJson(Map<Object?, Object?> json) => GpsSourcePoint(
        (json['lat']! as num).toDouble(),
        (json['lng']! as num).toDouble(),
        accuracyM: (json['accuracyM'] as num?)?.toDouble(),
        altitudeM: (json['altitudeM'] as num?)?.toDouble(),
        altitudeAccuracyM: (json['altitudeAccuracyM'] as num?)?.toDouble(),
      );

  final double lat;
  final double lng;
  final double? accuracyM;
  final double? altitudeM;
  final double? altitudeAccuracyM;

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracyM': accuracyM,
        'altitudeM': altitudeM,
        'altitudeAccuracyM': altitudeAccuracyM,
      };
}

/// 러닝 기록 경로로 만든 최종 경로(D4 미리보기). 서버가 만들고 저장하지 않는다.
/// 경로 조각을 달린 순서대로 잇고 모양이 2m 넘게 바뀌지 않게 점을 줄였다(4.1 F7 GPS 코스 등록 저장).
@immutable
class GpsCourseRoute {
  const GpsCourseRoute({
    required this.recordId,
    required this.segments,
    required this.route,
    required this.distanceMeters,
    required this.distanceMarkers,
  });

  factory GpsCourseRoute.fromJson(
    Map<Object?, Object?> json, {
    required String recordId,
    required List<List<GpsSourcePoint>> segments,
  }) =>
      GpsCourseRoute(
        recordId: recordId,
        segments: segments,
        route: _routeFromJson(json),
        distanceMeters: json['distanceMeters']! as int,
        distanceMarkers: _distanceMarkersFromJson(json),
      );

  /// 코스로 만들 러닝 기록 ID. 등록할 때 다시 보낸다.
  final String recordId;

  /// 그 기록의 경로 조각(달린 순서, 조각 사이는 잇지 않았다). 등록할 때 다시 보낸다(서버는 미리보기를 믿지 않고 다시 만든다).
  final List<List<GpsSourcePoint>> segments;

  /// 첫 점 출발, 마지막 점 도착.
  final List<GeoPoint> route;

  /// 줄인 경로의 WGS84 타원체 길이(m, 반올림). 상한이 없다.
  final int distanceMeters;

  /// 출발점부터 1km마다의 지점.
  final List<DistanceMarker> distanceMarkers;
}

List<GeoPoint> _routeFromJson(Map<Object?, Object?> json) =>
    [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)];

List<DistanceMarker> _distanceMarkersFromJson(Map<Object?, Object?> json) => [
      for (final marker in json['distanceMarkers']! as List)
        DistanceMarker((marker as Map)['km']! as int, GeoPoint.fromJson(marker['point']! as Map)),
    ];

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
        courses: [for (final course in json['courses']! as List) CourseListItem.fromJson(course as Map)],
      );

  /// 범위 안 코스 전체 수(목록 제목 `지금 달리기 좋은 코스 N`).
  final int totalCount;

  /// 그중 최대 100개, 최근 등록순. 목록 카드와 같은 값이라 지도에서 고른 코스(A5)를 바로 카드로 보인다.
  final List<CourseListItem> courses;
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
  const RegionCount({
    required this.code,
    required this.name,
    required this.count,
    required this.center,
    this.southWest,
    this.northEast,
  });

  factory RegionCount.fromJson(Map<Object?, Object?> json) => RegionCount(
        code: json['code']! as String,
        name: json['name']! as String,
        count: json['count']! as int,
        center: GeoPoint.fromJson(json['center']! as Map),
        southWest: switch (json['southWest']) { final Map point => GeoPoint.fromJson(point), _ => null },
        northEast: switch (json['northEast']) { final Map point => GeoPoint.fromJson(point), _ => null },
      );

  /// 지역을 가리는 값. 같은 단위 안에서 겹치지 않는다.
  final String code;

  /// 지도에 보일 짧은 이름(서울 · 광주 · 의정부 · 연천군 · 성북구).
  final String name;
  final int count;

  /// 이 지역의 범위 안 코스 출발점들의 가운데. 개수 배지를 놓는다(A4-01).
  final GeoPoint center;

  /// 구 단위만. 이 시·군·구에서 필터에 맞는 코스 전체(지도 범위 밖 포함)의 출발점 범위. 배지를 누르면 이 범위로 지도를 맞춘다(A4-06).
  /// 시 단위는 null.
  final GeoPoint? southWest;
  final GeoPoint? northEast;
}

/// 검색어에 걸린 코스가 있는 시·군·구 하나(G6, SEA-04).
@immutable
class SearchRegion {
  const SearchRegion({
    required this.code,
    required this.name,
    required this.count,
    required this.southWest,
    required this.northEast,
  });

  factory SearchRegion.fromJson(Map<Object?, Object?> json) => SearchRegion(
        code: json['code']! as String,
        name: json['name']! as String,
        count: json['count']! as int,
        southWest: GeoPoint.fromJson(json['southWest']! as Map),
        northEast: GeoPoint.fromJson(json['northEast']! as Map),
      );

  /// 시·군·구 법정동 코드. 이 지역을 고르면 홈 지도 · 목록 조건으로 보낸다([CourseSearchPick]).
  final String code;

  /// 보일 이름(영등포구 · 수원시 장안구). 전국에 같은 이름이 있으면 시·도가 붙는다(서울특별시 중구).
  final String name;

  /// 이 지역에서 검색어에 걸린 코스 수.
  final int count;

  /// 그 코스들 출발점의 남서쪽 · 북동쪽 끝. 지역을 고르면 홈 지도가 이 범위를 보인다.
  final GeoPoint southWest;
  final GeoPoint northEast;
}

/// G6에서 고른 검색어와 지역(SEA-04 · SEA-07). 홈 지도 · 지역별 코스 수 · 목록 · A3 예상 코스 수에 A3 필터와 함께 건다.
/// 그래서 지도 범위가 그 지역의 걸린 코스를 모두 담으면 목록 수가 G6 수와 같다.
@immutable
class CourseSearchPick {
  const CourseSearchPick({required this.query, required this.region});

  /// 검색어. 이름에 이 말이 들어간 코스만 남는다(공백 · 대소문자는 보지 않는다).
  final String query;
  final SearchRegion region;

  /// 홈 검색창 글자. `한강 · 영등포구`.
  String get label => '$query · ${region.name}';

  Map<String, Object> _query() => {'query': query, 'regionCode': region.code};

  @override
  bool operator ==(Object other) => other is CourseSearchPick && other.query == query && other.region.code == region.code;

  @override
  int get hashCode => Object.hash(query, region.code);
}

/// 코스 목록 정렬(FIL-01). 칩 · 메뉴는 이 순서다(Figma A3). 처음은 [popular]다.
enum CourseListSort {
  /// 도전 수(코스 러닝을 실제로 시작한 세션 수)가 많은 코스부터. 같으면 조회 수, 리뷰 수가 많은 코스, 그다음 최신순.
  /// 기간([CoursePeriod], FIL-09)이 있으면 그 기간의 수로 정하고, 기간에 값이 없는 코스도 빠지지 않고 뒤에 온다.
  popular('POPULAR', '인기순'),

  /// 전체 기간 평점(카드에 보이는 값)이 높은 코스부터. 같으면 리뷰 수가 많은 코스, 그다음 최신순. 리뷰가 없으면 맨 뒤.
  rating('RATING', '평점순'),

  /// 현재 위치에서 출발점까지 직선 거리가 가까운 코스부터. 현재 위치가 필요하다.
  nearest('NEAREST', '가까운순'),

  /// 등록 시각이 늦은 코스부터.
  latest('LATEST', '최신순'),

  /// 지금 달리는 러너가 많은 코스부터. 같으면 인기순(전체 기간) 순서다.
  live('LIVE', '실시간순');

  /// 처음 정렬(FIL-01). 홈 · G1을 처음 열 때 · A3 `초기화`.
  static const initial = popular;

  const CourseListSort(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 코스 필터(FIL-02~05). 지도 · 지역별 코스 수 · 목록이 같은 조건을 쓴다(A2-04 · A4-01).
/// 값이 없는 조건은 걸지 않는다.
@immutable
class CourseFilter {
  const CourseFilter({
    this.minDistanceMeters,
    this.maxDistanceMeters,
    this.difficulties = const {},
    this.minRating,
    this.tags = const {},
    this.courseType,
  });

  /// A3 최소 평점 칩(FIL-03). `전체`는 null이다.
  static const minRatings = [3.0, 4.0, 4.5];

  /// 조건 없음. A3를 처음 열거나 `초기화`한 상태다.
  static const none = CourseFilter();

  /// 거리 하한(m, 포함, FIL-02). null이면 1km부터다. 코스는 모두 1km 이상이라 조건이 없는 것과 같다.
  final int? minDistanceMeters;

  /// 거리 상한(m, 포함). null이면 `20km+`(상한 없음)다.
  final int? maxDistanceMeters;

  /// 난이도(FIL-03). 그중 하나면 된다. 비면 전체.
  final Set<Difficulty> difficulties;

  /// 최소 평점(FIL-03, 포함). 카드에 보이는 전체 기간 평점으로 거르고 리뷰가 없는 코스는 빠진다. null이면 전체.
  final double? minRating;

  /// 특징(FIL-04). 모두 가진 코스만 남는다. 비면 조건이 없다.
  final Set<CourseTag> tags;

  /// 코스 유형(FIL-05). null이면 전체.
  final CourseType? courseType;

  bool get isNone => this == none;

  Map<String, Object> _query() => {
        'minDistanceMeters': ?minDistanceMeters,
        'maxDistanceMeters': ?maxDistanceMeters,
        if (difficulties.isNotEmpty) 'difficulties': [for (final difficulty in difficulties) difficulty.apiName],
        'minRating': ?minRating,
        if (tags.isNotEmpty) 'tags': [for (final tag in tags) tag.apiName],
        'courseType': ?courseType?.apiName,
      };

  @override
  bool operator ==(Object other) =>
      other is CourseFilter &&
      other.minDistanceMeters == minDistanceMeters &&
      other.maxDistanceMeters == maxDistanceMeters &&
      setEquals(other.difficulties, difficulties) &&
      other.minRating == minRating &&
      setEquals(other.tags, tags) &&
      other.courseType == courseType;

  @override
  int get hashCode => Object.hash(
        minDistanceMeters,
        maxDistanceMeters,
        Object.hashAllUnordered(difficulties),
        minRating,
        Object.hashAllUnordered(tags),
        courseType,
      );
}

/// 인기순 기간(FIL-09, A3 기간 슬라이더). Asia/Seoul 날짜이고 두 날짜를 모두 포함한다. 날짜만 쓰고 시각은 보지 않는다.
/// 목록 순서만 바꾸고 코스를 빼지 않아, 지도 · 지역별 코스 수 · 예상 코스 수와는 상관없다. 카드 값도 늘 전체 기간이다.
@immutable
class CoursePeriod {
  const CoursePeriod({this.start, required this.end});

  /// 코스 통계(F11)를 쌓기 시작한 날. 그 전 날짜는 데이터가 없어 시작일 · 종료일 모두 이날로 보낸다.
  /// [start] · [end]는 A3 눈금 날짜 그대로 둬서 다시 열면 핸들이 고른 자리로 돌아온다.
  static final dataStart = DateTime.utc(2026, 10, 19);

  /// 시작일. null이면 처음부터(A3 `전체`)다.
  final DateTime? start;

  /// 종료일.
  final DateTime end;

  Map<String, Object> _query() => {'startDate': ?_date(_fromData(start)), 'endDate': _date(_fromData(end))!};

  /// [dataStart]보다 앞 날짜는 [dataStart]로.
  static DateTime? _fromData(DateTime? date) => date == null || !date.isBefore(dataStart) ? date : dataStart;

  /// 2026-10-19.
  static String? _date(DateTime? date) {
    if (date == null) return null;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  @override
  bool operator ==(Object other) => other is CoursePeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'CoursePeriod(${_date(start)} ~ ${_date(end)})';
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

/// 코스 검색 결과 한 쪽(G1). 카드는 코스 목록과 같다. 다음 쪽은 [nextCursor]로 받는다.
@immutable
class CourseSearchPage {
  const CourseSearchPage({required this.totalCount, required this.courses, required this.nextCursor});

  factory CourseSearchPage.fromJson(Map<Object?, Object?> json) => CourseSearchPage(
        totalCount: json['totalCount']! as int,
        courses: [for (final course in json['content']! as List) CourseListItem.fromJson(course as Map)],
        nextCursor: json['nextCursor'] as String?,
      );

  /// 검색어에 걸린 코스 수(`코스 검색 결과 N`, SEA-02). 쪽마다 같은 값이다.
  final int totalCount;
  final List<CourseListItem> courses;

  /// 마지막 쪽이면 null.
  final String? nextCursor;
}

/// 코스 목록 카드(A2-05 · A6-03). 지도 범위 안 코스(A5 이름표 · 선택 카드)와 검색 결과 카드(G1-04)도 이 값이다.
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
    this.averageRating,
    this.reviewCount = 0,
    this.activeRunners = 0,
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
        averageRating: (json['averageRating'] as num?)?.toDouble(),
        reviewCount: json['reviewCount'] as int? ?? 0,
        activeRunners: json['activeRunners'] as int? ?? 0,
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

  /// 전체 기간 평점(소수 첫째 자리 반올림). 리뷰가 없으면 null.
  final double? averageRating;
  final int reviewCount;

  /// 지금 그 코스를 달리는 러너 수(카드의 `지금 N명 달리는 중`). 서버가 받은 마지막 값이다.
  final int activeRunners;

  /// 카드 썸네일 · 지도 코스 선. 첫 점 출발, 마지막 점 도착(코스 방향).
  final List<GeoPoint> route;

  /// 현재 러너 수만 [activeRunners]로 바꾼 카드(홈 1분 갱신, 공통 7 · HCR-05).
  CourseListItem withActiveRunners(int activeRunners) => CourseListItem(
        courseId: courseId,
        name: name,
        distanceMeters: distanceMeters,
        difficulty: difficulty,
        tags: tags,
        courseType: courseType,
        expiresAt: expiresAt,
        averageRating: averageRating,
        reviewCount: reviewCount,
        activeRunners: activeRunners,
        route: route,
      );
}

/// 코스 상세(B1 공통 헤더 · 정보 탭). 평점 · 리뷰 수 · 항목 평가는 리뷰 API에서 받는다.
@immutable
class CourseDetail {
  const CourseDetail({
    required this.courseId,
    required this.name,
    required this.courseType,
    required this.difficulty,
    required this.tags,
    required this.distanceMeters,
    required this.route,
    required this.distanceMarkers,
    required this.expiresAt,
    this.averagePaceSecondsPerKm,
    this.creatorNickname,
    this.activeRunners = 0,
  });

  factory CourseDetail.fromJson(Map<Object?, Object?> json) => CourseDetail(
        courseId: json['courseId']! as String,
        name: json['name']! as String,
        courseType: CourseType.fromApi(json['courseType']! as String),
        difficulty: Difficulty.fromApi(json['difficulty']! as String),
        tags: [for (final tag in json['tags']! as List) ?CourseTag.fromApi(tag as String)],
        distanceMeters: json['distanceMeters']! as int,
        route: [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)],
        distanceMarkers: [
          for (final marker in json['distanceMarkers']! as List)
            DistanceMarker((marker as Map)['km']! as int, GeoPoint.fromJson(marker['point']! as Map)),
        ],
        expiresAt: DateTime.parse(json['expiresAt']! as String),
        averagePaceSecondsPerKm: json['averagePaceSecondsPerKm'] as int?,
        creatorNickname: json['creatorNickname'] as String?,
        activeRunners: json['activeRunners'] as int? ?? 0,
      );

  final String courseId;
  final String name;
  final CourseType courseType;
  final Difficulty difficulty;

  /// FIL-04 순서.
  final List<CourseTag> tags;
  final int distanceMeters;

  /// 첫 점 출발, 마지막 점 도착(코스 방향).
  final List<GeoPoint> route;

  /// 출발점부터 1km마다의 지점(B1-02). 표시용이다.
  final List<DistanceMarker> distanceMarkers;

  /// 공개 만료 시각(만료일 23:59:59 Asia/Seoul). 완주로 연장되면 바뀐다(B1-04).
  final DateTime expiresAt;

  /// 코스 평균 페이스(초/km). 모든 완주의 코스 완주 페이스 평균이다. 완주가 없으면 null.
  final int? averagePaceSecondsPerKm;

  /// 등록자 닉네임. 탈퇴했으면 `탈퇴한 사용자`. 서버가 회원 정보를 받지 못하면 null이다.
  final String? creatorNickname;

  /// 지금 그 코스를 달리는 러너 수(B1-01 현재 러너). 서버가 받은 마지막 값이다.
  final int activeRunners;
}

/// 오늘(Asia/Seoul) 남은 등록 수. 유형마다 따로 센다.
@immutable
class RegistrationQuota {
  const RegistrationQuota({required this.custom, required this.gps, this.usedRunRecordIds = const []});

  factory RegistrationQuota.fromJson(Map<Object?, Object?> json) => RegistrationQuota(
        custom: TypeQuota._fromJson(json['custom']! as Map),
        gps: TypeQuota._fromJson(json['gps']! as Map),
        usedRunRecordIds: [for (final id in json['usedRunRecordIds'] as List? ?? const []) id as String],
      );

  /// 사용자 지정(B3 지도에 점 찍기). 하루 1개.
  final TypeQuota custom;

  /// GPS 주행 등록(B5·B6 합산). 하루 3개.
  final TypeQuota gps;

  /// 이 회원이 GPS 코스 등록에 쓴 러닝 기록 ID. B6·결과 화면의 `이미 등록됨`(코스가 지워지거나 만료돼도 남는다)
  final List<String> usedRunRecordIds;
}

@immutable
class TypeQuota {
  const TypeQuota({required this.limit, required this.remaining});

  factory TypeQuota._fromJson(Map<Object?, Object?> json) =>
      TypeQuota(limit: json['limit']! as int, remaining: json['remaining']! as int);

  final int limit;
  final int remaining;
}

/// 다른 러너가 등록한 코스 카드(I3 `등록한 코스`). 공개 중인 코스만 온다.
@immutable
class RunnerCourse {
  RunnerCourse.fromJson(Map<Object?, Object?> json)
      : courseId = json['courseId']! as String,
        name = json['name']! as String,
        distanceMeters = json['distanceMeters']! as int,
        averageRating = (json['averageRating'] as num?)?.toDouble(),
        completionCount = json['completionCount']! as int,
        route = _routeFromJson(json);

  final String courseId;
  final String name;
  final int distanceMeters;

  /// 전체 기간 평점(소수 첫째 자리 반올림). 리뷰가 없으면 null.
  final double? averageRating;

  /// 완주 수(`주행 N회`, G4 `누적 주행`과 같다).
  final int completionCount;

  /// 썸네일.
  final List<GeoPoint> route;
}

/// 다른 러너가 등록한 코스 한 쪽. 마지막 쪽이면 [nextCursor]가 null.
typedef RunnerCoursePage = ({List<RunnerCourse> courses, String? nextCursor});

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
  /// B7 코스 수정은 [courseId]를 보내 그 코스의 지금 이름은 빼고 본다.
  Future<bool> isNameAvailable(String name, {String? courseId}) async {
    final data = await callApi(() =>
        _dio.get('$_courses/name-availability', queryParameters: {'name': name, 'courseId': ?courseId}));
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

  /// 러닝 기록의 경로 조각 → 최종 경로 · 거리 · 1km 표지(D4 미리보기, 저장하지 않는다).
  /// 이미 코스로 만든 기록 COURSE-010, 점 2개 미만 003, 1km 미만 004, GPS 정확도 부족 011 순으로 본다.
  Future<GpsCourseRoute> previewGpsRoute({
    required String recordId,
    required List<List<GpsSourcePoint>> segments,
  }) async {
    final data = await callApi(() => _dio.post('$_courses/gps/route', data: {
          'sourceRunRecordId': recordId,
          'segments': _segmentsJson(segments),
        }));
    return GpsCourseRoute.fromJson(data! as Map, recordId: recordId, segments: segments);
  }

  /// GPS 주행 코스 등록(D4). 서버가 [segments]로 경로를 다시 만들어 확인하고 바로 공개한다.
  ///
  /// [idempotencyKey]는 [registerCustom]과 같다. 미리보기의 오류에 더해 이름 중복 COURSE-006, 85% 겹침 007,
  /// 오늘 GPS 한도 008, 출발점 지역 없음 009.
  Future<RegisteredCourse> registerGps({
    required String idempotencyKey,
    required String recordId,
    required List<List<GpsSourcePoint>> segments,
    required String name,
    required Difficulty difficulty,
    required Set<CourseTag> tags,
  }) async {
    final data = await callApi(() => _dio.post(
          '$_courses/gps',
          data: {
            'sourceRunRecordId': recordId,
            'segments': _segmentsJson(segments),
            'name': name,
            'difficulty': difficulty.apiName,
            'tags': [for (final tag in tags) tag.apiName],
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        ));
    return RegisteredCourse.fromJson(data! as Map);
  }

  static List<List<Map<String, Object?>>> _segmentsJson(List<List<GpsSourcePoint>> segments) =>
      [for (final segment in segments) [for (final point in segment) point.toJson()]];

  /// 지도 범위(남서쪽·북동쪽 끝) 안 [filter]에 맞는 코스(A2·A5). A3의 예상 코스 수도 이것으로 센다.
  /// [pick]이 있으면 G6에서 고른 검색어 · 지역의 코스만이다.
  Future<CourseMap> mapCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
  }) async {
    final data = await callApi(() => _dio.get('$_courses/map', queryParameters: {
          ..._area(southWest, northEast),
          ...filter._query(),
          ...?pick?._query(),
        }));
    return CourseMap.fromJson(data! as Map);
  }

  /// 지도 범위 안 [filter] · [pick]에 맞는 코스를 출발점 지역별로 센다(A4 지도 축소).
  Future<RegionCounts> regionCounts({
    required GeoPoint southWest,
    required GeoPoint northEast,
    required RegionLevel level,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
  }) async {
    final data = await callApi(() => _dio.get('$_courses/map/regions', queryParameters: {
          ..._area(southWest, northEast),
          ...filter._query(),
          ...?pick?._query(),
          'level': level.apiName,
        }));
    return RegionCounts.fromJson(data! as Map);
  }

  /// 지도 범위 안 코스 목록 한 쪽(A2 · A6). 범위 · 필터 · [pick]은 [mapCourses]와 같다(MAP-07).
  /// 가까운순은 현재 위치 [origin]이 필요하다. [period]는 인기순에만 보낸다(FIL-09, 다른 정렬이면 COMMON-001).
  /// 다음 쪽은 앞 쪽의 [CourseListPage.nextCursor]를 [cursor]로 보내고, 범위 · 필터 · 정렬 · 기간 · 현재 위치는 첫 쪽과 같게 보낸다.
  Future<CourseListPage> listCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
    CourseListSort sort = CourseListSort.initial,
    CoursePeriod? period,
    GeoPoint? origin,
    String? cursor,
  }) async {
    final data = await callApi(() => _dio.get(_courses, queryParameters: {
          ..._area(southWest, northEast),
          ...filter._query(),
          ...?pick?._query(),
          'sort': sort.apiName,
          ...?period?._query(),
          'lat': ?origin?.lat,
          'lng': ?origin?.lng,
          'cursor': ?cursor,
        }));
    return CourseListPage.fromJson(data! as Map);
  }

  /// 검색어는 공백을 빼고 이만큼 글자가 있어야 검색한다(SEA-01). 서버도 같은 기준으로 거른다.
  static const minSearchLength = 2;

  /// [query]로 검색할 수 있나. 공백을 빼고 [minSearchLength]글자 이상이다.
  static bool isSearchable(String query) => query.replaceAll(RegExp(r'\s'), '').runes.length >= minSearchLength;

  /// 이름에 [query]가 들어간 활성 코스 한 쪽(G1, SEA-03). 지도 범위 · A3 필터와 상관없이 전국에서 찾는다.
  /// 공백 · 대소문자는 보지 않는다. 정렬 · 현재 위치 · 커서는 [listCourses]와 같다.
  /// [isSearchable]이 아닌 검색어는 COMMON-001이다.
  Future<CourseSearchPage> searchCourses({
    required String query,
    CourseListSort sort = CourseListSort.initial,
    GeoPoint? origin,
    String? cursor,
  }) async {
    final data = await callApi(() => _dio.get('$_courses/search', queryParameters: {
          'query': query,
          'sort': sort.apiName,
          'lat': ?origin?.lat,
          'lng': ?origin?.lng,
          'cursor': ?cursor,
        }));
    return CourseSearchPage.fromJson(data! as Map);
  }

  /// 이름에 [query]가 들어간 활성 코스를 출발점 시·군·구별로 센다(G6, SEA-04). 검색어 규칙은 [searchCourses]와 같고
  /// A3 필터는 쓰지 않는다. 코스가 많은 지역부터다. [isSearchable]이 아닌 검색어는 COMMON-001이다.
  Future<List<SearchRegion>> searchRegions(String query) async {
    final data = await callApi(() => _dio.get('$_courses/search/regions', queryParameters: {'query': query}));
    return [for (final region in (data! as Map)['regions']! as List) SearchRegion.fromJson(region as Map)];
  }

  /// 한 번에 현재 러너 수를 물을 수 있는 코스 수. 서버도 같은 기준으로 거른다.
  static const maxRunnerCourses = 100;

  /// [courseIds](1 ~ [maxRunnerCourses]개) 중 공개 중인 코스의 현재 러너 수(courseId → 러너 수). 홈 카드의 1분 갱신에 쓴다(공통 7 · HCR-05).
  /// 값은 카드의 [CourseListItem.activeRunners]와 같다. 없거나 공개 중이 아닌 코스는 빠진다.
  Future<Map<String, int>> activeRunners(List<String> courseIds) async {
    final data = await callApi(() => _dio.get('$_courses/active-runners', queryParameters: {'courseIds': courseIds}));
    return {
      for (final course in (data! as List).cast<Map<Object?, Object?>>())
        course['courseId']! as String: course['activeRunners']! as int,
    };
  }

  static Map<String, Object> _area(GeoPoint southWest, GeoPoint northEast) =>
      {'swLat': southWest.lat, 'swLng': southWest.lng, 'neLat': northEast.lat, 'neLng': northEast.lng};

  /// 코스 상세(B1). 없는 코스는 [courseNotFoundCode], 비공개 · 삭제된 코스는 [courseNotAvailableCode] 오류다.
  Future<CourseDetail> courseDetail(String courseId) async {
    final data = await callApi(() => _dio.get('$_courses/${Uri.encodeComponent(courseId)}'));
    return CourseDetail.fromJson(data! as Map);
  }

  /// 없는 코스.
  static const courseNotFoundCode = 'COURSE-001';

  /// 비공개 · 삭제된 코스(B1-04 신규 상세 진입 차단).
  static const courseNotAvailableCode = 'COURSE-002';

  /// 다른 러너가 등록한 공개 중인 코스(I3). 최근 등록순이고 다음 쪽은 [RunnerCoursePage]의 nextCursor를 [cursor]로 보낸다.
  Future<RunnerCoursePage> runnerCourses(String memberId, {String? cursor}) async {
    final data = await callApi(() => _dio
        .get('$_courses/members/${Uri.encodeComponent(memberId)}', queryParameters: {'cursor': ?cursor})) as Map;
    return (
      courses: [for (final course in data['content']! as List) RunnerCourse.fromJson(course as Map)],
      nextCursor: data['nextCursor'] as String?,
    );
  }

  /// 다른 러너가 등록한 공개 중인 코스 수(I3 `등록 코스`, MY와 같은 기준).
  Future<int> runnerCourseCount(String memberId) async {
    final data = await callApi(() => _dio.get('$_courses/members/${Uri.encodeComponent(memberId)}/summary')) as Map;
    return data['courseCount']! as int;
  }

  /// 오늘 남은 등록 수. 0이면 그 방식의 코스 만들기를 미리 막는다(개발 정책 10.2 course).
  Future<RegistrationQuota> registrationQuota() async {
    final data = await callApi(() => _dio.get('$_courses/registration-quota'));
    return RegistrationQuota.fromJson(data! as Map);
  }

  /// 내가 등록한 코스 한 쪽(G4). 만료 임박 공개 코스가 먼저(만료가 가까운 순), 나머지는 최근 등록순이다.
  /// 삭제 예정 코스(만료 · 내가 삭제)도 들어 있고 삭제가 끝난 코스는 없다. 다음 쪽은 앞 쪽의 nextCursor를 [cursor]로 보낸다.
  Future<MyCoursePage> myCourses({String? cursor, int? size}) async {
    final data = await callApi(() => _dio.get('$_courses/mine', queryParameters: {'cursor': ?cursor, 'size': ?size}));
    return MyCoursePage.fromJson(data! as Map);
  }

  /// G4 위 칸과 탭의 `등록한 코스 N`. 공개 중인 코스만 센다.
  Future<MyCourseSummary> myCourseSummary() async {
    final data = await callApi(() => _dio.get('$_courses/mine/summary'));
    return MyCourseSummary.fromJson(data! as Map);
  }

  /// 코스 수정(B7). 이름 · 난이도 · 특징을 통째로 바꾼다. 경로 · 유형 · 만료일은 그대로다. 응답은 바뀐 G4 카드 값이다.
  /// 다른 공개 코스와 같은 이름 COURSE-006, 삭제 예정 · 만료된 코스 COURSE-002.
  Future<MyCourseItem> editCourse(
    String courseId, {
    required String name,
    required Difficulty difficulty,
    required Set<CourseTag> tags,
  }) async {
    final data = await callApi(() => _dio.put('$_courses/${Uri.encodeComponent(courseId)}', data: {
          'name': name,
          'difficulty': difficulty.apiName,
          'tags': [for (final tag in tags) tag.apiName],
        }));
    return MyCourseItem.fromJson(data! as Map);
  }

  /// 코스 삭제(B7). 바로 비공개가 되고 24시간 뒤 지워진다. 응답은 삭제 예정으로 바뀐 G4 카드 값이다.
  /// 이미 삭제 예정이면 그 값을 그대로 준다.
  Future<MyCourseItem> deleteCourse(String courseId) async {
    final data = await callApi(() => _dio.delete('$_courses/${Uri.encodeComponent(courseId)}'));
    return MyCourseItem.fromJson(data! as Map);
  }

  static const _bookmarks = '$_courses/bookmarks';

  /// 저장 해제 · 저장 여부에 한 번에 보낼 수 있는 코스 수. 서버도 같은 기준으로 거른다.
  static const maxBookmarkIds = 100;

  /// 코스 저장(B1-09). 공개 중인 코스만 새로 저장하고, 이미 저장했으면 그대로다.
  /// 없는 코스 [courseNotFoundCode], 삭제 예정 · 삭제 · 만료된 코스 [courseNotAvailableCode].
  Future<void> saveBookmark(String courseId) =>
      callApi(() => _dio.put('$_bookmarks/${Uri.encodeComponent(courseId)}'));

  /// 저장 해제(B1-09 · G5 편집). 1 ~ [maxBookmarkIds]개. 저장하지 않은 코스는 그냥 넘어간다.
  Future<void> removeBookmarks(Iterable<String> courseIds) =>
      callApi(() => _dio.delete(_bookmarks, queryParameters: {'courseIds': courseIds.toList()}));

  /// [courseIds](1 ~ [maxBookmarkIds]개) 중 내가 저장한 코스.
  Future<Set<String>> bookmarkedIds(Iterable<String> courseIds) async {
    final data = await callApi(() => _dio.get('$_bookmarks/status', queryParameters: {'courseIds': courseIds.toList()}));
    return {for (final id in data! as List) id as String};
  }

  /// 저장한 코스 한 쪽(G5). 공개 중인 코스를 [sort]로, 그 뒤에 삭제 예정 코스를 최근 저장순으로 준다.
  /// 가까운순은 현재 위치 [origin]이 필요하다. 다음 쪽은 앞 쪽의 nextCursor를 [cursor]로 보내고 정렬 · 위치는 첫 쪽과 같게 보낸다.
  Future<BookmarkPage> bookmarks({BookmarkSort sort = BookmarkSort.recent, GeoPoint? origin, String? cursor}) async {
    final data = await callApi(() => _dio.get(_bookmarks, queryParameters: {
          'sort': sort.apiName,
          'lat': ?origin?.lat,
          'lng': ?origin?.lng,
          'cursor': ?cursor,
        }));
    return BookmarkPage.fromJson(data! as Map);
  }

  /// G5 위 칸과 탭의 `저장한 코스 N`, E3 메뉴. 공개 중인 코스만 센다.
  Future<BookmarkSummary> bookmarkSummary() async {
    final data = await callApi(() => _dio.get('$_bookmarks/summary'));
    return BookmarkSummary.fromJson(data! as Map);
  }
}

/// 저장한 코스 정렬(Figma G5). 같으면 최근 저장순이고, 삭제 예정 코스는 늘 공개 중인 코스 뒤에 온다.
enum BookmarkSort {
  recent('RECENT', '최근 저장순'),
  nearest('NEAREST', '가까운순'),
  rating('RATING', '평점순'),
  expiring('EXPIRING', '만료 임박');

  const BookmarkSort(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 저장한 코스 한 쪽(G5).
@immutable
class BookmarkPage {
  const BookmarkPage({required this.courses, required this.nextCursor});

  factory BookmarkPage.fromJson(Map<Object?, Object?> json) => BookmarkPage(
        courses: [for (final course in json['content']! as List) BookmarkCourse.fromJson(course as Map)],
        nextCursor: json['nextCursor'] as String?,
      );

  final List<BookmarkCourse> courses;

  /// 마지막 쪽이면 null.
  final String? nextCursor;
}

/// G5 위 칸. 공개 중인 코스만 센다(삭제 예정 코스는 목록에만 보인다).
@immutable
class BookmarkSummary {
  const BookmarkSummary({required this.courseCount, required this.expiringSoonCount});

  factory BookmarkSummary.fromJson(Map<Object?, Object?> json) => BookmarkSummary(
        courseCount: json['courseCount']! as int,
        expiringSoonCount: json['expiringSoonCount']! as int,
      );

  /// `저장한 코스`. 탭 · E3 메뉴에도 보인다.
  final int courseCount;

  /// `만료 임박`. 만료일까지 7일 이내(D-7 ~ D-0).
  final int expiringSoonCount;
}

/// 저장한 코스 카드(G5). `8.1km · 난이도 상 · ★ 4.4`, `만든 사람 러너_하늘`, `만료 D-18`과 썸네일이다.
@immutable
class BookmarkCourse {
  BookmarkCourse.fromJson(Map<Object?, Object?> json)
      : courseId = json['courseId']! as String,
        name = json['name']! as String,
        distanceMeters = json['distanceMeters']! as int,
        difficulty = Difficulty.fromApi(json['difficulty']! as String),
        averageRating = (json['averageRating'] as num?)?.toDouble(),
        creatorNickname = json['creatorNickname'] as String?,
        route = _routeFromJson(json),
        pendingDelete = json['status'] != 'ACTIVE',
        expiresAt = DateTime.parse(json['expiresAt']! as String),
        card = CourseListItem.fromJson(json);

  final String courseId;
  final String name;
  final int distanceMeters;
  final Difficulty difficulty;

  /// 전체 기간 평점. 리뷰가 없으면 null.
  final double? averageRating;

  /// 등록자 닉네임. 탈퇴했으면 `탈퇴한 사용자`, 서버가 받지 못하면 null.
  final String? creatorNickname;

  /// 썸네일. 첫 점이 출발점.
  final List<GeoPoint> route;

  /// 삭제 예정(만료됐거나 등록자가 삭제해 비공개). 24시간 안에 목록에서 사라지고 다시 저장할 수 없다.
  final bool pendingDelete;

  /// 공개 만료 시각(만료일 23:59:59 Asia/Seoul).
  final DateTime expiresAt;

  /// 코스 목록 카드와 같은 값(특징 · 유형 · 리뷰 수 · 현재 러너 수 포함). C8이 다른 탭과 같은 카드로 보인다.
  final CourseListItem card;
}

/// 내가 등록한 코스 한 쪽(G4).
@immutable
class MyCoursePage {
  const MyCoursePage({required this.courses, required this.nextCursor});

  factory MyCoursePage.fromJson(Map<Object?, Object?> json) => MyCoursePage(
        courses: [for (final course in json['content']! as List) MyCourseItem.fromJson(course as Map)],
        nextCursor: json['nextCursor'] as String?,
      );

  final List<MyCourseItem> courses;

  /// 마지막 쪽이면 null.
  final String? nextCursor;
}

/// G4 위 칸. 공개 중인 코스만 센다(삭제 예정 코스는 목록에만 보인다).
@immutable
class MyCourseSummary {
  const MyCourseSummary({required this.courseCount, required this.completionCount, required this.expiringSoonCount});

  factory MyCourseSummary.fromJson(Map<Object?, Object?> json) => MyCourseSummary(
        courseCount: json['courseCount']! as int,
        completionCount: json['completionCount']! as int,
        expiringSoonCount: json['expiringSoonCount']! as int,
      );

  /// `등록 코스`. E3 통계 · 메뉴에도 보인다.
  final int courseCount;

  /// `누적 주행`. 그 코스들의 완주 수 합.
  final int completionCount;

  /// `만료 임박`. 만료일까지 7일 이내(D-7 ~ D-0).
  final int expiringSoonCount;
}

/// 삭제 예정이 된 이유.
enum CourseHiddenReason {
  /// 공개 기간이 끝났다.
  expired('EXPIRED'),

  /// 내가 삭제했다(B7).
  userDeleted('USER_DELETED');

  const CourseHiddenReason(this.apiName);
  final String apiName;

  static CourseHiddenReason? fromApi(String? name) => values.where((value) => value.apiName == name).firstOrNull;
}

/// 내가 등록한 코스 카드(G4). B7 코스 수정 화면도 이 값으로 채운다. 평점 · 리뷰 수는 리뷰 API가 준다.
@immutable
class MyCourseItem {
  const MyCourseItem({
    required this.courseId,
    required this.name,
    required this.courseType,
    required this.difficulty,
    required this.tags,
    required this.route,
    required this.expiresAt,
    this.hiddenReason,
    this.deleteAt,
    this.completionCount = 0,
    this.lastCompletedOn,
  });

  factory MyCourseItem.fromJson(Map<Object?, Object?> json) {
    final lastCompletedOn = json['lastCompletedOn'] as String?;
    final deleteAt = json['deleteAt'] as String?;
    final active = json['status'] == 'ACTIVE';
    return MyCourseItem(
      courseId: json['courseId']! as String,
      name: json['name']! as String,
      courseType: CourseType.fromApi(json['courseType']! as String),
      difficulty: Difficulty.fromApi(json['difficulty']! as String),
      tags: [for (final tag in json['tags']! as List) ?CourseTag.fromApi(tag as String)],
      route: [for (final point in json['route']! as List) GeoPoint.fromJson(point as Map)],
      expiresAt: DateTime.parse(json['expiresAt']! as String),
      // 공개 중이 아니면 사유를 모르더라도 삭제 예정으로 본다(만료로 둔다)
      hiddenReason: active ? null : CourseHiddenReason.fromApi(json['statusReason'] as String?) ?? CourseHiddenReason.expired,
      deleteAt: deleteAt == null ? null : DateTime.parse(deleteAt),
      completionCount: json['completionCount'] as int? ?? 0,
      // `2026-10-30` 같은 날짜(Asia/Seoul)라 시각 없이 날짜로만 둔다
      lastCompletedOn: lastCompletedOn == null ? null : DateTime.parse(lastCompletedOn),
    );
  }

  final String courseId;
  final String name;
  final CourseType courseType;
  final Difficulty difficulty;

  /// FIL-04 순서.
  final List<CourseTag> tags;

  /// 카드 · B7 지도 그림. 첫 점이 출발점.
  final List<GeoPoint> route;

  /// 공개 만료 시각(만료일 23:59:59 Asia/Seoul).
  final DateTime expiresAt;

  /// 삭제 예정이면 그 이유. 공개 중이면 null.
  final CourseHiddenReason? hiddenReason;

  /// 삭제 예정 시각(비공개가 된 때 + 24시간). 공개 중이면 null.
  final DateTime? deleteAt;

  /// `누적 주행 N회`. 서버가 확정한 완주 수.
  final int completionCount;

  /// `최근 주행`. 마지막으로 완주한 날(Asia/Seoul 날짜). 완주가 없으면 null.
  final DateTime? lastCompletedOn;

  /// 공개 중이 아니라 24시간 안에 지워진다. 수정 · 삭제할 수 없다.
  bool get pendingDelete => hiddenReason != null;
}

final courseApiClientProvider = Provider<CourseApiClient>((ref) => CourseApiClient(ref.watch(dioProvider)));
