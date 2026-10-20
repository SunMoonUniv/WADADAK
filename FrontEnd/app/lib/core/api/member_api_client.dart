import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import 'api_client.dart';
import 'upload_form.dart';

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

/// 약관 동의. 모두 필수라 전부 동의해야 가입할 수 있다.
class Agreements {
  const Agreements({
    this.over14 = false,
    this.serviceTerms = false,
    this.privacyPolicy = false,
    this.locationTerms = false,
    this.profileInfo = false,
  });

  const Agreements.all(bool value)
      : over14 = value,
        serviceTerms = value,
        privacyPolicy = value,
        locationTerms = value,
        profileInfo = value;

  final bool over14, serviceTerms, privacyPolicy, locationTerms, profileInfo;

  bool get all => over14 && serviceTerms && privacyPolicy && locationTerms && profileInfo;

  Agreements copyWith({
    bool? over14,
    bool? serviceTerms,
    bool? privacyPolicy,
    bool? locationTerms,
    bool? profileInfo,
  }) =>
      Agreements(
        over14: over14 ?? this.over14,
        serviceTerms: serviceTerms ?? this.serviceTerms,
        privacyPolicy: privacyPolicy ?? this.privacyPolicy,
        locationTerms: locationTerms ?? this.locationTerms,
        profileInfo: profileInfo ?? this.profileInfo,
      );

  Map<String, Object?> toJson() => {
        'over14': over14,
        'serviceTerms': serviceTerms,
        'privacyPolicy': privacyPolicy,
        'locationTerms': locationTerms,
        'profileInfo': profileInfo,
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

enum Gender {
  male('MALE', '남성'),
  female('FEMALE', '여성');

  const Gender(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 신체 정보(정책 공통 9). 선택 입력이고 네 값은 한 묶음이다. 보내면 신체 정보 수집 및 이용에 동의한 것이다.
class BodyInfo {
  const BodyInfo({required this.birthYear, required this.heightCm, required this.weightKg, required this.gender});

  final int birthYear, heightCm, weightKg;
  final Gender gender;

  /// 고를 수 있는 출생연도, 최근 순. 연도만으로 만 14세 이상이 확실한 해(올해 − 15)부터 100년 전까지. 올해는 Asia/Seoul 기준.
  static List<int> birthYears(DateTime now) {
    final thisYear = now.toUtc().add(const Duration(hours: 9)).year;
    return [for (var year = thisYear - 15; year >= thisYear - 100; year--) year];
  }

  /// 키 100~250cm, 체중 20~300kg 정수. 서버도 같은 범위를 확인한다.
  static bool isValidHeight(int cm) => cm >= 100 && cm <= 250;
  static bool isValidWeight(int kg) => kg >= 20 && kg <= 300;

  Map<String, Object?> toJson() =>
      {'birthYear': birthYear, 'heightCm': heightCm, 'weightKg': weightKg, 'gender': gender.apiName};
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
    required String? profileImageKey,
    required BodyInfo? bodyInfo,
  }) async {
    final data = await callApi(() => _publicDio.post('$_auth/signup', data: {
          'signupToken': signupToken,
          'agreements': agreements.toJson(),
          'nickname': nickname,
          'bio': bio,
          'regionCode': regionCode,
          'affiliation': affiliation,
          'runningExperience': runningExperience.apiName,
          'profileImageKey': profileImageKey,
          'bodyInfo': bodyInfo?.toJson(),
        }));
    return AuthTokens.fromJson(data as Map);
  }

  /// 가입 전 프로필 사진 업로드 폼. 로그인 전이라 가입 토큰으로 받는다(만료 MEMBER-003).
  Future<UploadForm> signupPhotoUploadForm(String signupToken) async =>
      UploadForm.fromJson(await callApi(() => _publicDio.post('$_auth/photo-uploads', data: {'signupToken': signupToken})) as Map);

  /// 보낸 리프레시 토큰은 폐기되고 새 토큰을 받는다. 같은 토큰을 다시 쓰면 MEMBER-004.
  Future<AuthTokens> refresh(String refreshToken) async {
    final data = await callApi(() => _publicDio.post('$_auth/refresh', data: {'refreshToken': refreshToken}));
    return AuthTokens.fromJson(data as Map);
  }

  Future<void> logout(String refreshToken) =>
      callApi(() => _publicDio.post('$_auth/logout', data: {'refreshToken': refreshToken}));
}

final memberApiClientProvider = Provider<MemberApiClient>((ref) => MemberApiClient(ref.watch(publicDioProvider)));
