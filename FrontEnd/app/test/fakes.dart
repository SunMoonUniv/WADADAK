import 'dart:async';

import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/region_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';

const testTokens = AuthTokens(accessToken: 'access', refreshToken: 'refresh');

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
    };
    return testTokens;
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async => testTokens;

  @override
  Future<void> logout(String refreshToken) async => logouts++;
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

  /// 지도 범위와 상관없이 돌려줄 코스.
  List<MapCourse> onMap = [];
  ApiException? mapError;
  final mapRequests = <({GeoPoint southWest, GeoPoint northEast})>[];

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
  Future<CourseMap> mapCourses({required GeoPoint southWest, required GeoPoint northEast}) async {
    mapRequests.add((southWest: southWest, northEast: northEast));
    if (mapError != null) throw mapError!;
    return CourseMap(totalCount: onMap.length, courses: onMap);
  }

  static String _nameKey(String name) => name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

typedef FakeRegistration = ({
  String idempotencyKey,
  List<GeoPoint> anchorPoints,
  String name,
  Difficulty difficulty,
  Set<CourseTag> tags,
});
