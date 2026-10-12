import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
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

  @override
  Future<RegistrationQuota> registrationQuota() async => quota;

  /// 서버처럼 입력점을 그대로 잇고, 끝점에 1km 표지 하나를 둔다.
  @override
  Future<GeneratedRoute> generateRoute(List<GeoPoint> anchorPoints) async {
    sentPoints = anchorPoints;
    if (routeError != null) throw routeError!;
    return GeneratedRoute(
      route: anchorPoints,
      distanceMeters: GeoPoint.pathLength(anchorPoints).round(),
      distanceMarkers: [DistanceMarker(1, anchorPoints.last)],
    );
  }
}
