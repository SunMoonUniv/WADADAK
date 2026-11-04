import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/member_api_client.dart';
import '../push/push_service.dart';
import '../upload/photo_uploader.dart';
import 'social_login.dart';
import 'account_data_cleanup.dart';
import 'token_storage.dart';

sealed class AuthState {
  const AuthState();
}

final class SignedOut extends AuthState {
  const SignedOut();
}

/// 처음 로그인했다. 동의와 프로필을 받아 [signupToken]으로 가입한다.
final class SignupRequired extends AuthState {
  const SignupRequired(this.signupToken, this.provider);
  final String signupToken;
  final SocialProvider provider;
}

final class SignedIn extends AuthState {
  const SignedIn();
}

/// 로그인 상태. 라우터가 이 값으로 화면을 고른다.
class AuthController extends AsyncNotifier<AuthState> {
  /// 가입 때 이미 올린 사진과 그 키. 가입 요청이 실패해 다시 시도할 때 같은 사진을 다시 올리지 않는다.
  XFile? _uploadedPhoto;
  String? _uploadedKey;

  @override
  Future<AuthState> build() async {
    // 토큰이 있으면 서버에 묻지 않고 로그인 상태로 시작한다. 오프라인에서도 자유 러닝을 시작할 수 있어야 한다(개발 정책 4.5).
    // 토큰이 만료됐으면 첫 API 호출의 401에서 갱신하고, 갱신도 실패하면 로그아웃한다(AuthInterceptor).
    final tokens = await ref.read(tokenStorageProvider).read();
    return tokens == null ? const SignedOut() : const SignedIn();
  }

  /// 실패하면 [ApiException]을 던지고 상태는 바꾸지 않는다.
  ///
  /// [onSocialSignedIn]은 소셜 SDK 로그인이 끝나고 서버 로그인을 시작하기 직전에 부른다. 소셜 로그인은
  /// 사용자가 창을 버리면 끝나지 않을 수 있지만, 서버 로그인은 요청 시간 제한으로 반드시 끝난다.
  Future<void> login(
    SocialProvider provider, {
    void Function()? onSocialSignedIn,
  }) async {
    final socialToken = await ref.read(socialLoginProvider).signIn(provider);
    onSocialSignedIn?.call();
    switch (await ref
        .read(memberApiClientProvider)
        .login(provider, socialToken)) {
      case LoginSignedIn(:final tokens):
        await _signedIn(tokens);
      case LoginSignupRequired(:final signupToken):
        state = AsyncData(SignupRequired(signupToken, provider));
    }
  }

  /// 소셜 정보 동의 + 프로필 초기 설정으로 가입한다. 실패하면 [ApiException]을 던진다.
  /// [photo]가 있으면 가입 토큰으로 먼저 올리고 그 키로 가입한다.
  Future<void> signup({
    required Agreements agreements,
    required String nickname,
    required String? bio,
    required String regionCode,
    required String? affiliation,
    required RunningExperience runningExperience,
    XFile? photo,
    BodyInfo? bodyInfo,
  }) async {
    final current = state.value;
    if (current is! SignupRequired) throw StateError('가입 토큰이 없습니다');
    final api = ref.read(memberApiClientProvider);
    // 가입이 실패해 다시 누르면 같은 사진을 다시 올리지 않는다(업로드 폼 한도 1시간 20개)
    if (photo != null && !identical(photo, _uploadedPhoto)) {
      _uploadedKey = await ref.read(photoUploaderProvider).upload(photo, () => api.signupPhotoUploadForm(current.signupToken));
      _uploadedPhoto = photo;
    }
    final profileImageKey = photo == null ? null : _uploadedKey;
    final AuthTokens tokens;
    try {
      tokens = await api.signup(
        signupToken: current.signupToken,
        agreements: agreements,
        nickname: nickname,
        bio: bio,
        regionCode: regionCode,
        affiliation: affiliation,
        runningExperience: runningExperience,
        profileImageKey: profileImageKey,
        bodyInfo: bodyInfo,
      );
    } on ApiException catch (e) {
      // 올린 지 1시간이 지나 지워진 사진이면 기억한 키를 버린다. 다음에 누르면 다시 올린다
      if (e.code == 'MEMBER-008') _uploadedPhoto = _uploadedKey = null;
      rethrow;
    }
    await _signedIn(tokens);
    final member = tokens.memberId;
    if (member != null) {
      await ref
          .read(tokenStorageProvider)
          .rememberRunWeight(member, bodyInfo?.weightKg.toDouble());
    }
  }

  /// 기기의 토큰을 먼저 지운다. 서버의 리프레시 토큰 폐기가 실패해도 로그아웃은 끝난다.
  /// 푸시 기기 토큰은 그보다 먼저 지운다. 로그인 토큰이 있어야 서버에서 지울 수 있다(실패해도 넘어간다).
  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    final tokens = await storage.read();
    if (tokens != null) await ref.read(pushServiceProvider).unregister();
    await storage.clear();
    state = const AsyncData(SignedOut());
    if (tokens == null) return;
    try {
      await ref.read(memberApiClientProvider).logout(tokens.refreshToken);
    } on ApiException {
      // 서버에 남은 리프레시 토큰은 7일 뒤 만료된다.
    }
  }

  /// F4 회원 탈퇴. 서버가 탈퇴를 마쳐야 기기의 러닝 자료 · 토큰을 지우고 로그인 화면으로 간다.
  /// 서버 탈퇴가 실패하면 [ApiException]을 던지고 로그인 상태는 그대로다. 서버가 리프레시 토큰을 모두 지워 따로 로그아웃하지 않는다.
  /// 서버 탈퇴가 끝난 뒤의 기기 정리 실패는 던지지 않는다. 탈퇴는 이미 끝났고 되돌릴 수 없는데, 던지면 F4가
  /// "탈퇴 실패"처럼 오류를 띄운다. 못 지운 러닝 자료는 기기 DB에 표시가 남아 다음에 앱을 열 때 다시 지운다.
  Future<void> withdraw() async {
    final tokens = await ref.read(tokenStorageProvider).read();
    final member = tokens?.memberId;
    if (member == null) throw StateError('로그인 후 다시 시도해 주세요.');
    final cleanup = ref.read(accountDataCleanupProvider);
    await ref.read(memberApiClientProvider).withdraw();
    try {
      await cleanup(member);
    } on Object {
      // 위 설명처럼 다음에 앱을 열 때 다시 지운다
    }
    try {
      await ref.read(tokenStorageProvider).eraseRunWeight(member);
    } on Object {
      // 체중 캐시는 탈퇴 표시가 메모리에 남아 이번 실행에서는 다시 쓰이지 않는다
    }
    // 서버는 탈퇴 회원에게 보내지 않는다. 기기 토큰도 버려 다음 계정이 새 토큰으로 시작한다
    await ref.read(pushServiceProvider).unregister();
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(SignedOut());
  }

  /// 가입을 그만두고 로그인 화면으로 돌아간다.
  void cancelSignup() => state = const AsyncData(SignedOut());

  /// 리프레시 토큰도 만료됐다(MEMBER-004). 기기의 토큰은 AuthInterceptor가 지웠다.
  void sessionExpired() => state = const AsyncData(SignedOut());

  Future<void> _signedIn(AuthTokens tokens) async {
    await ref.read(tokenStorageProvider).write(tokens);
    state = const AsyncData(SignedIn());
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
