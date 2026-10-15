import 'dart:async';
import 'dart:convert';

import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak/core/api/region_api_client.dart';
import 'package:wadadak/core/api/upload_form.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/core/permissions/device_setup.dart';
import 'package:wadadak/core/upload/photo_uploader.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';

const testTokens = AuthTokens(accessToken: 'access', refreshToken: 'refresh');

/// 지도 · 목록 테스트용 코스(카드 값). 이름 · 경로 말고는 정해 둔 값이다.
CourseListItem testCourse(
  String name, {
  String? courseId,
  List<GeoPoint> route = const [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800)],
  int distanceMeters = 1000,
  Difficulty difficulty = Difficulty.easy,
  List<CourseTag> tags = const [],
  CourseType courseType = CourseType.custom,
  DateTime? expiresAt,
}) =>
    CourseListItem(
      courseId: courseId ?? 'id-$name',
      name: name,
      distanceMeters: distanceMeters,
      difficulty: difficulty,
      tags: tags,
      courseType: courseType,
      expiresAt: expiresAt ?? DateTime.utc(2026, 11, 13, 14, 59, 59),
      route: route,
    );

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

class FakeMemberApi implements MemberApiClient {
  LoginResult loginResult = const LoginSignupRequired('signup-token');
  ApiException? signupError;
  Map<String, Object?>? signedUp;
  int logouts = 0;

  /// 프로필 사진 업로드 폼을 받을 때 보낸 가입 토큰
  final photoFormTokens = <String>[];

  @override
  Future<LoginResult> login(SocialProvider provider, String socialToken) async => loginResult;

  @override
  Future<AuthTokens> signup({
    required String signupToken,
    required Agreements agreements,
    required String nickname,
    required String? bio,
    required String regionCode,
    required String? affiliation,
    required RunningExperience runningExperience,
    required String? profileImageKey,
  }) async {
    if (signupError != null) throw signupError!;
    signedUp = {
      'signupToken': signupToken,
      'agreements': agreements.toJson(),
      'nickname': nickname,
      'bio': bio,
      'regionCode': regionCode,
      'affiliation': affiliation,
      'runningExperience': runningExperience.apiName,
      'profileImageKey': profileImageKey,
    };
    return testTokens;
  }

  @override
  Future<UploadForm> signupPhotoUploadForm(String signupToken) async {
    photoFormTokens.add(signupToken);
    return UploadForm.fromJson({'url': 'https://files.test/wadadak', 'key': 'member/photo.jpg', 'fields': <String, String>{}});
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async => testTokens;

  @override
  Future<void> logout(String refreshToken) async => logouts++;
}

/// 1×1 PNG. 미리보기가 그림으로 읽을 수 있는 사진이다.
final testPhoto = XFile.fromData(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='),
  name: 'me.png',
);

/// 고르면 [photo] 한 장. 올리면 서버 업로드 폼을 받아 그 키를 돌려준다(저장소에는 보내지 않는다).
class FakePhotoUploader implements PhotoUploader {
  XFile? photo;
  final uploaded = <XFile>[];

  @override
  Future<List<XFile>> pick({int limit = 1}) async => [?photo];

  @override
  Future<String> upload(XFile photo, Future<UploadForm> Function() requestForm) async {
    uploaded.add(photo);
    return (await requestForm()).key;
  }
}

class FakeSocialLogin implements SocialLogin {
  @override
  Future<String> signIn(SocialProvider provider) async => 'social-token';
}

/// 성북구 · 아산시만 있다. 서버처럼 이름이나 상위 구역 이름에 검색어가 들어가면 찾는다.
class FakeRegionApi implements RegionApiClient {
  static const _regions = [
    {'code': '1129000000', 'name': '성북구', 'fullName': '서울특별시 성북구'},
    {'code': '4420000000', 'name': '아산시', 'fullName': '충청남도 아산시'},
  ];

  @override
  Future<List<Region>> search(String query) async =>
      [for (final region in _regions) if (region['fullName']!.contains(query)) Region.fromJson(region)];
}

class FakeRunPermissions implements RunPermissions {
  int requests = 0;

  @override
  Future<void> request() async => requests++;
}

class FakeCourseApi implements CourseApiClient {
  RegistrationQuota quota = const RegistrationQuota(
    custom: TypeQuota(limit: 1, remaining: 1),
    gps: TypeQuota(limit: 3, remaining: 3),
  );
  ApiException? routeError;
  List<GeoPoint>? sentPoints;

  /// 이미 있는 코스 이름. 서버처럼 공백 · 대소문자를 무시하고 비교한다.
  Set<String> takenNames = {};
  ApiException? registerError;

  /// 있으면 끝날 때까지 등록 응답을 미룬다(등록 중 화면).
  Completer<void>? registerGate;
  final registrations = <FakeRegistration>[];

  /// 지도 범위와 상관없이 돌려줄 코스. 필터는 거리 · 난이도 · 특징 · 유형을 서버처럼 적용한다.
  List<CourseListItem> onMap = [];
  ApiException? mapError;
  final mapRequests = <({GeoPoint southWest, GeoPoint northEast, CourseFilter filter})>[];

  /// 지도 범위 · 단위 · 필터와 상관없이 돌려줄 지역별 코스 수.
  List<RegionCount> regions = [];
  ApiException? regionsError;
  final regionRequests = <({GeoPoint southWest, GeoPoint northEast, RegionLevel level, CourseFilter filter})>[];

  @override
  Future<RegistrationQuota> registrationQuota() async => quota;

  /// 서버처럼 입력점을 그대로 잇고, 끝점에 1km 표지 하나를 둔다.
  @override
  Future<GeneratedRoute> generateRoute(List<GeoPoint> anchorPoints) async {
    sentPoints = anchorPoints;
    if (routeError != null) throw routeError!;
    return GeneratedRoute(
      anchorPoints: anchorPoints,
      route: anchorPoints,
      distanceMeters: GeoPoint.pathLength(anchorPoints).round(),
      distanceMarkers: [DistanceMarker(1, anchorPoints.last)],
    );
  }

  @override
  Future<bool> isNameAvailable(String name) async => !takenNames.map(_nameKey).contains(_nameKey(name));

  @override
  Future<RegisteredCourse> registerCustom({
    required String idempotencyKey,
    required List<GeoPoint> anchorPoints,
    required String name,
    required Difficulty difficulty,
    required Set<CourseTag> tags,
  }) async {
    registrations.add((
      idempotencyKey: idempotencyKey,
      anchorPoints: anchorPoints,
      name: name,
      difficulty: difficulty,
      tags: {...tags},
    ));
    await registerGate?.future;
    if (registerError != null) throw registerError!;
    return RegisteredCourse(courseId: 'course-${registrations.length}', name: name, startPoint: anchorPoints.first);
  }

  @override
  Future<CourseMap> mapCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
  }) async {
    mapRequests.add((southWest: southWest, northEast: northEast, filter: filter));
    if (mapError != null) throw mapError!;
    final courses = [for (final course in onMap) if (matches(course, filter)) course];
    return CourseMap(totalCount: courses.length, courses: courses);
  }

  /// 서버처럼 [course]가 [filter]에 맞나(FIL-02~05).
  static bool matches(CourseListItem course, CourseFilter filter) =>
      course.distanceMeters >= (filter.minDistanceMeters ?? 0) &&
      course.distanceMeters <= (filter.maxDistanceMeters ?? course.distanceMeters) &&
      (filter.difficulties.isEmpty || filter.difficulties.contains(course.difficulty)) &&
      course.tags.toSet().containsAll(filter.tags) &&
      (filter.courseType == null || filter.courseType == course.courseType);

  @override
  Future<RegionCounts> regionCounts({
    required GeoPoint southWest,
    required GeoPoint northEast,
    required RegionLevel level,
    CourseFilter filter = CourseFilter.none,
  }) async {
    regionRequests.add((southWest: southWest, northEast: northEast, level: level, filter: filter));
    if (regionsError != null) throw regionsError!;
    return RegionCounts(totalCount: regions.fold(0, (sum, region) => sum + region.count), regions: regions);
  }

  /// 지도 범위 · 정렬과 상관없이 돌려줄 목록. 필터는 [matches]로 거른다.
  /// [listPageSize]개씩 쪽을 나누고, 커서는 다음 쪽 첫 위치다.
  List<CourseListItem> listed = [];
  int listPageSize = 20;
  ApiException? listError;
  final listRequests = <ListRequest>[];

  @override
  Future<CourseListPage> listCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
    CourseListSort sort = CourseListSort.latest,
    GeoPoint? origin,
    String? cursor,
  }) async {
    listRequests.add((
      southWest: southWest,
      northEast: northEast,
      filter: filter,
      sort: sort,
      origin: origin,
      cursor: cursor,
    ));
    if (listError != null) throw listError!;
    final courses = [for (final course in listed) if (matches(course, filter)) course];
    final from = cursor == null ? 0 : int.parse(cursor);
    final to = (from + listPageSize).clamp(0, courses.length);
    return CourseListPage(courses: courses.sublist(from, to), nextCursor: to < courses.length ? '$to' : null);
  }

  static String _nameKey(String name) => name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

typedef ListRequest = ({
  GeoPoint southWest,
  GeoPoint northEast,
  CourseFilter filter,
  CourseListSort sort,
  GeoPoint? origin,
  String? cursor,
});

/// 홈의 현재 위치는 [location]이다. [allowed]가 아니면 권한을 물어야 받고, [error]가 있으면 물어도 못 받는다.
class FakeMyLocation implements MyLocation {
  FakeMyLocation({this.location, this.allowed = false, this.error});

  GeoPoint? location;
  bool allowed;
  DeviceSetupException? error;

  /// 권한을 물어서라도 받은 횟수(가까운순).
  int requests = 0;
  final openedSettings = <DeviceSettingsAction>[];

  /// 기기에 남은 마지막 위치. 권한이 있을 때만 준다.
  GeoPoint? last;

  /// 있으면 [ifAllowed]가 이것이 끝날 때까지 기다린다(지금 위치를 받는 데 걸리는 시간).
  Completer<void>? fix;

  @override
  Future<GeoPoint?> ifAllowed() async {
    await fix?.future;
    return allowed ? location : null;
  }

  @override
  Future<GeoPoint?> lastIfAllowed() async => allowed ? last : null;

  @override
  Future<GeoPoint> request() async {
    requests++;
    if (error != null) throw error!;
    allowed = true;
    return location!;
  }

  @override
  Future<void> openSettings(DeviceSettingsAction action) async => openedSettings.add(action);
}

typedef FakeRegistration = ({
  String idempotencyKey,
  List<GeoPoint> anchorPoints,
  String name,
  Difficulty difficulty,
  Set<CourseTag> tags,
});
