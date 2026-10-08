import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import 'api_client.dart';

enum SocialProvider { kakao, google, apple }

/// 로그인 결과: 가입된 회원이면 토큰, 처음이면 가입 토큰(1시간 유효).
sealed class LoginResult {
  const LoginResult();
}

final class LoginSignedIn extends LoginResult {
  const LoginSignedIn(this.tokens);
  final AuthTokens tokens;
}

final class LoginSignupRequired extends LoginResult {
  const LoginSignupRequired(this.signupToken);
  final String signupToken;
}

/// 소셜 정보 동의. 필수 5개를 모두 동의해야 가입할 수 있다. [email]만 선택.
class Agreements {
  const Agreements({
    this.over14 = false,
    this.serviceTerms = false,
    this.privacyPolicy = false,
    this.locationTerms = false,
    this.profileInfo = false,
    this.email = false,
  });

  const Agreements.all(bool value)
      : over14 = value,
        serviceTerms = value,
        privacyPolicy = value,
        locationTerms = value,
        profileInfo = value,
        email = value;

  final bool over14, serviceTerms, privacyPolicy, locationTerms, profileInfo, email;

  bool get allRequired => over14 && serviceTerms && privacyPolicy && locationTerms && profileInfo;
  bool get all => allRequired && email;

  Agreements copyWith({
    bool? over14,
    bool? serviceTerms,
    bool? privacyPolicy,
    bool? locationTerms,
    bool? profileInfo,
    bool? email,
  }) =>
      Agreements(
        over14: over14 ?? this.over14,
        serviceTerms: serviceTerms ?? this.serviceTerms,
        privacyPolicy: privacyPolicy ?? this.privacyPolicy,
        locationTerms: locationTerms ?? this.locationTerms,
        profileInfo: profileInfo ?? this.profileInfo,
        email: email ?? this.email,
      );

  Map<String, Object?> toJson() => {
        'over14': over14,
        'serviceTerms': serviceTerms,
        'privacyPolicy': privacyPolicy,
        'locationTerms': locationTerms,
        'profileInfo': profileInfo,
        'email': email,
      };
}

enum RunningExperience {
  beginner('BEGINNER', '입문'),
  months6('MONTHS_6', '6개월+'),
  year1('YEAR_1', '1년+'),
  year3('YEAR_3', '3년+');

  const RunningExperience(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 회원 API(`/api/v1/members`). 서버 모듈 prefix 하나에 클라이언트 하나(개발 정책 9장).
class MemberApiClient {
  MemberApiClient(this._publicDio);

  final Dio _publicDio;
  static const _auth = '/api/v1/members/auth';

  Future<LoginResult> login(SocialProvider provider, String socialToken) async {
    final data = await callApi(
        () => _publicDio.post('$_auth/login', data: {'provider': provider.name.toUpperCase(), 'token': socialToken}));
    data as Map;
    return data['signupRequired'] == true
        ? LoginSignupRequired(data['signupToken'] as String)
        : LoginSignedIn(AuthTokens.fromJson(data['tokens'] as Map));
  }

  Future<AuthTokens> signup({
    required String signupToken,
    required Agreements agreements,
    required String nickname,
    required String? bio,
    required String regionCode,
    required String? affiliation,
    required RunningExperience runningExperience,
  }) async {
    final data = await callApi(() => _publicDio.post('$_auth/signup', data: {
          'signupToken': signupToken,
          'agreements': agreements.toJson(),
          'nickname': nickname,
          'bio': bio,
          'regionCode': regionCode,
          'affiliation': affiliation,
          'runningExperience': runningExperience.apiName,
        }));
    return AuthTokens.fromJson(data as Map);
  }

  /// 보낸 리프레시 토큰은 폐기되고 새 토큰을 받는다. 같은 토큰을 다시 쓰면 MEMBER-004.
  Future<AuthTokens> refresh(String refreshToken) async {
    final data = await callApi(() => _publicDio.post('$_auth/refresh', data: {'refreshToken': refreshToken}));
    return AuthTokens.fromJson(data as Map);
  }

  Future<void> logout(String refreshToken) =>
      callApi(() => _publicDio.post('$_auth/logout', data: {'refreshToken': refreshToken}));
}

final memberApiClientProvider = Provider<MemberApiClient>((ref) => MemberApiClient(ref.watch(publicDioProvider)));
