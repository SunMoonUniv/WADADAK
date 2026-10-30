import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import 'api_client.dart';
import 'region_api_client.dart';
import 'upload_form.dart';

enum SocialProvider {
  kakao('카카오'),
  google('Google'),
  apple('Apple');

  const SocialProvider(this.label);

  /// F4 `연결된 소셜 계정`에 보이는 이름.
  final String label;

  /// 서버 값(`KAKAO`)으로 찾는다. 모르는 값이면 없다.
  static SocialProvider? fromApi(String? name) => values.where((e) => e.name.toUpperCase() == name).firstOrNull;
}

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

  static RunningExperience? fromApi(String? name) => values.where((e) => e.apiName == name).firstOrNull;
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

  BodyInfo.fromJson(Map json)
      : birthYear = json['birthYear'] as int,
        heightCm = json['heightCm'] as int,
        weightKg = json['weightKg'] as int,
        gender = Gender.values.firstWhere((gender) => gender.apiName == json['gender']);

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

/// 내 정보(`GET /members/me`). E3 마이페이지 · F6 프로필 편집 · F4 설정이 쓴다. 지금은 E3 · F6가 쓰는 값만 읽는다.
class MyProfile {
  MyProfile.fromJson(Map json)
      : nickname = json['nickname'] as String,
        nicknameChangeableAt = DateTime.tryParse(json['nicknameChangeableAt'] as String? ?? ''),
        bio = json['bio'] as String?,
        region = json['region'] == null ? null : Region.fromJson(json['region'] as Map),
        affiliation = json['affiliation'] as String?,
        runningExperience = RunningExperience.fromApi(json['runningExperience'] as String?),
        profileImageKey = json['profileImageKey'] as String?,
        profileImageUrl = json['profileImageUrl'] as String?,
        bodyInfo = json['bodyInfo'] == null ? null : BodyInfo.fromJson(json['bodyInfo'] as Map),
        socialProvider = SocialProvider.fromApi(json['socialProvider'] as String?),
        infoPublic = json['infoPublic'] as bool? ?? true,
        profileSearchable = json['profileSearchable'] as bool? ?? true;

  final String nickname;

  /// 닉네임을 다시 바꿀 수 있는 시각(F6 "다음 변경 가능"). 지금 바꿀 수 있으면 없다.
  final DateTime? nicknameChangeableAt;

  /// 한 줄 소개. 선택 입력이다.
  final String? bio;

  /// 활동 지역. 지역 목록에서 코드가 사라졌으면 없다.
  final Region? region;

  /// 소속(예: 선문대학교). 선택 입력이다.
  final String? affiliation;
  final RunningExperience? runningExperience;

  /// 사진을 그대로 두고 F6를 저장할 때 다시 보내는 키.
  final String? profileImageKey;
  final String? profileImageUrl;

  /// 신체 정보. 동의하지 않았으면 없다.
  final BodyInfo? bodyInfo;

  /// 가입한 소셜 계정(F4 `연결된 소셜 계정`).
  final SocialProvider? socialProvider;

  /// F4 공개 여부 두 스위치. 끄면 랭킹 · 고스트에 내 기록이 안 보이고, 러너 검색에 안 나온다.
  final bool infoPublic;
  final bool profileSearchable;
}

/// 회원 API(`/api/v1/members`). 서버 모듈 prefix 하나에 클라이언트 하나(개발 정책 9장).
class MemberApiClient {
  MemberApiClient(this._publicDio, this._authDio);

  final Dio _publicDio;

  /// 로그인한 요청용. 토큰 갱신이 이 클라이언트(`refresh`)를 쓰므로 만들 때가 아니라 부를 때 꺼낸다.
  final Dio Function() _authDio;
  static const _auth = '/api/v1/members/auth';
  static const _me = '/api/v1/members/me';

  Future<MyProfile> me() async => MyProfile.fromJson(await callApi(() => _authDio().get(_me)) as Map);

  /// F6 저장. 화면 값을 통째로 보낸다. [profileImageKey]는 그대로 두면 지금 키, 새 사진이면 올린 키, 지우면 null.
  /// [bodyInfo]가 null이면 저장된 신체 정보가 지워진다. 닉네임 30일 규칙에 걸리면 MEMBER-010, 중복이면 MEMBER-006.
  Future<MyProfile> editProfile({
    required String nickname,
    required String? bio,
    required String regionCode,
    required String? affiliation,
    required RunningExperience runningExperience,
    required String? profileImageKey,
    required BodyInfo? bodyInfo,
  }) async =>
      MyProfile.fromJson(await callApi(() => _authDio().put(_me, data: {
            'nickname': nickname,
            'bio': bio,
            'regionCode': regionCode,
            'affiliation': affiliation,
            'runningExperience': runningExperience.apiName,
            'profileImageKey': profileImageKey,
            'bodyInfo': bodyInfo?.toJson(),
          })) as Map);

  /// F4 공개 여부. 화면의 두 스위치 값을 둘 다 보낸다.
  Future<MyProfile> changeSettings({required bool infoPublic, required bool profileSearchable}) async =>
      MyProfile.fromJson(await callApi(() => _authDio().put('$_me/settings', data: {
            'infoPublic': infoPublic,
            'profileSearchable': profileSearchable,
          })) as Map);

  /// F6 새 프로필 사진 업로드 폼. 올린 키를 [editProfile]에 담는다.
  Future<UploadForm> photoUploadForm() async =>
      UploadForm.fromJson(await callApi(() => _authDio().post('$_me/photo-uploads')) as Map);

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

// dioProvider가 토큰 갱신에 이 클라이언트를 쓰고 이 클라이언트도 dioProvider를 써서, 타입을 적어 순환 추론을 끊는다
final Provider<MemberApiClient> memberApiClientProvider = Provider(
    (ref) => MemberApiClient(ref.watch(publicDioProvider), () => ref.read(dioProvider)));
