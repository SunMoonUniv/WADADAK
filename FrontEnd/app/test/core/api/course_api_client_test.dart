import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/map/geo_point.dart';

/// 받은 요청을 남기고 정해 둔 `data`로 답하는 서버.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.data);

  final Object data;
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(jsonEncode({'result': 'SUCCESS', 'data': data}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  CourseApiClient client(_FakeServer server) =>
      CourseApiClient(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server);

  const start = GeoPoint(37.5894, 127.0167);
  const end = GeoPoint(37.5826, 127.0286);

  test('registers with the idempotency key and the server enum names', () async {
    final server = _FakeServer({
      'courseId': '0b7e2d4a-6c1f-4e8a-9d3b-5f2a7c9e1b60',
      'name': '한강 러닝',
      'startPoint': start.toJson(),
      'distanceMeters': 1520,
      'expiresAt': '2026-11-11T14:59:59Z',
    });

    final course = await client(server).registerCustom(
      idempotencyKey: 'key-1',
      anchorPoints: const [start, end],
      name: '한강 러닝',
      difficulty: Difficulty.medium,
      tags: {CourseTag.nightLight, CourseTag.convenienceStore},
    );

    expect(server.request.method, 'POST');
    expect(server.request.path, '/api/v1/courses');
    expect(server.request.headers['Idempotency-Key'], 'key-1');
    expect(server.request.data, {
      'anchorPoints': [start.toJson(), end.toJson()],
      'name': '한강 러닝',
      'difficulty': 'MEDIUM',
      'tags': ['NIGHT_LIGHT', 'CONVENIENCE_STORE'],
    });
    expect(course.courseId, '0b7e2d4a-6c1f-4e8a-9d3b-5f2a7c9e1b60');
    expect(course.name, '한강 러닝');
    expect(course.startPoint, start);
  });

  test('checks a name', () async {
    final server = _FakeServer({'name': '한강 러닝', 'available': false});

    expect(await client(server).isNameAvailable('한강 러닝'), isFalse);
    expect(server.request.path, '/api/v1/courses/name-availability');
    expect(server.request.queryParameters, {'name': '한강 러닝'});
  });

  test('asks for the courses in a map area', () async {
    final server = _FakeServer({
      'totalCount': 24,
      'courses': [
        {
          'courseId': 'c1',
          'name': '성북천 벚꽃길 3K',
          'distanceMeters': 3412,
          'difficulty': 'EASY',
          'tags': ['SHADE', 'RIVERSIDE'],
          'courseType': 'GPS',
          'expiresAt': '2026-11-13T14:59:59Z',
          'route': [start.toJson(), end.toJson()],
        },
      ],
    });

    final map = await client(server).mapCourses(southWest: const GeoPoint(37.58, 127.01), northEast: const GeoPoint(37.60, 127.03));

    expect(server.request.method, 'GET');
    expect(server.request.path, '/api/v1/courses/map');
    expect(server.request.queryParameters, {'swLat': 37.58, 'swLng': 127.01, 'neLat': 37.60, 'neLng': 127.03});
    expect(map.totalCount, 24);
    expect(map.courses.single.name, '성북천 벚꽃길 3K');
    expect(map.courses.single.route, const [start, end]);
    // 목록 카드와 같은 값(A5 선택 카드).
    final course = map.courses.single;
    expect(course.distanceMeters, 3412);
    expect(course.difficulty, Difficulty.easy);
    expect(course.tags, [CourseTag.shade, CourseTag.riverside]);
    expect(course.courseType, CourseType.gps);
    expect(course.expiresAt, DateTime.utc(2026, 11, 13, 14, 59, 59));
  });

  test('counts the courses in the map area by region', () async {
    final server = _FakeServer({
      'totalCount': 3,
      'regions': [
        {'code': '1129000000', 'name': '성북구', 'count': 2, 'center': start.toJson()},
        {'code': '1144000000', 'name': '마포구', 'count': 1, 'center': end.toJson()},
      ],
    });

    final counts = await client(server).regionCounts(
      southWest: const GeoPoint(37.58, 127.01),
      northEast: const GeoPoint(37.60, 127.03),
      level: RegionLevel.district,
    );

    expect(server.request.path, '/api/v1/courses/map/regions');
    expect(server.request.queryParameters,
        {'swLat': 37.58, 'swLng': 127.01, 'neLat': 37.60, 'neLng': 127.03, 'level': 'DISTRICT'});
    expect(counts.totalCount, 3);
    expect([for (final region in counts.regions) '${region.name} ${region.count}'], ['성북구 2', '마포구 1']);
    expect(counts.regions.first.code, '1129000000');
    expect(counts.regions.first.center, start);
  });

  test('sends the filter to the map, the region counts and the list the same way', () async {
    const filter = CourseFilter(
      minDistanceMeters: 3000,
      maxDistanceMeters: 8000,
      difficulties: {Difficulty.easy, Difficulty.hard},
      tags: {CourseTag.flat, CourseTag.nightLight},
      courseType: CourseType.custom,
    );
    const area = {'swLat': 37.58, 'swLng': 127.01, 'neLat': 37.60, 'neLng': 127.03};
    const filterQuery = {
      'minDistanceMeters': 3000,
      'maxDistanceMeters': 8000,
      'difficulties': ['EASY', 'HARD'],
      'tags': ['FLAT', 'NIGHT_LIGHT'],
      'courseType': 'CUSTOM',
    };
    const southWest = GeoPoint(37.58, 127.01), northEast = GeoPoint(37.60, 127.03);

    final map = _FakeServer({'totalCount': 0, 'courses': <Object>[]});
    await client(map).mapCourses(southWest: southWest, northEast: northEast, filter: filter);
    expect(map.request.queryParameters, {...area, ...filterQuery});
    // 서버(Spring)는 여러 값을 같은 이름으로 여러 번 받는다.
    expect(map.request.uri.query, contains('difficulties=EASY&difficulties=HARD'));

    final regions = _FakeServer({'totalCount': 0, 'regions': <Object>[]});
    await client(regions).regionCounts(southWest: southWest, northEast: northEast, level: RegionLevel.city, filter: filter);
    expect(regions.request.queryParameters, {...area, ...filterQuery, 'level': 'CITY'});

    final list = _FakeServer({'content': <Object>[], 'nextCursor': null});
    await client(list).listCourses(southWest: southWest, northEast: northEast, filter: filter);
    expect(list.request.path, '/api/v1/courses');
    expect(list.request.queryParameters, {...area, ...filterQuery, 'sort': 'LATEST'});
  });

  test('sends no filter conditions when nothing is chosen', () async {
    final map = _FakeServer({'totalCount': 0, 'courses': <Object>[]});
    await client(map).mapCourses(southWest: start, northEast: end, filter: CourseFilter.none);
    expect(map.request.queryParameters.keys, ['swLat', 'swLng', 'neLat', 'neLng']);
    expect(CourseFilter.none.isNone, isTrue);
    expect(const CourseFilter(difficulties: {Difficulty.easy}).isNone, isFalse);
    expect(const CourseFilter(tags: {CourseTag.flat, CourseTag.shade}),
        const CourseFilter(tags: {CourseTag.shade, CourseTag.flat}), reason: '고른 순서와 상관없이 같은 조건');
  });

  test('lists the nearest courses from the current location, page after page', () async {
    final server = _FakeServer({
      'content': <Object>[],
      'nextCursor': null,
    });

    await client(server).listCourses(
      southWest: const GeoPoint(37.58, 127.01),
      northEast: const GeoPoint(37.60, 127.03),
      sort: CourseListSort.nearest,
      origin: start,
      cursor: 'next',
    );

    expect(server.request.queryParameters, {
      'swLat': 37.58,
      'swLng': 127.01,
      'neLat': 37.60,
      'neLng': 127.03,
      'sort': 'NEAREST',
      'lat': start.lat,
      'lng': start.lng,
      'cursor': 'next',
    });
  });

  test('keeps the anchor points a route was made from', () async {
    final server = _FakeServer({
      'route': [start.toJson(), end.toJson()],
      'distanceMeters': 1520,
      'distanceMarkers': [
        {'km': 1, 'point': end.toJson()},
      ],
    });

    final route = await client(server).generateRoute(const [start, end]);

    expect(route.anchorPoints, const [start, end]);
    expect(route.route, const [start, end]);
    expect(route.distanceMarkers.single.km, 1);
  });
}
