import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/member_api_client.dart';
import 'social_login.dart';
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
  @override
  Future<AuthState> build() async {
    // 토큰이 있으면 서버에 묻지 않고 로그인 상태로 시작한다. 오프라인에서도 자유 러닝을 시작할 수 있어야 한다(개발 정책 4.5).
    // 토큰이 만료됐으면 첫 API 호출의 401에서 갱신하고, 갱신도 실패하면 로그아웃한다(AuthInterceptor).
    final tokens = await ref.read(tokenStorageProvider).read();
    return tokens == null ? const SignedOut() : const SignedIn();
  }

  /// 실패하면 [ApiException]을 던지고 상태는 바꾸지 않는다.
  Future<void> login(SocialProvider provider) async {
    final socialToken = await ref.read(socialLoginProvider).signIn(provider);
    switch (await ref.read(memberApiClientProvider).login(provider, socialToken)) {
      case LoginSignedIn(:final tokens):
        await _signedIn(tokens);
      case LoginSignupRequired(:final signupToken):
        state = AsyncData(SignupRequired(signupToken, provider));
    }
  }

  /// 소셜 정보 동의 + 프로필 초기 설정으로 가입한다. 실패하면 [ApiException]을 던진다.
  Future<void> signup({
    required Agreements agreements,
    required String nickname,
    required String? bio,
    required String regionCode,
    required String? affiliation,
    required RunningExperience runningExperience,
  }) async {
    final current = state.value;
    if (current is! SignupRequired) throw StateError('가입 토큰이 없습니다');
    final tokens = await ref.read(memberApiClientProvider).signup(
          signupToken: current.signupToken,
          agreements: agreements,
          nickname: nickname,
          bio: bio,
          regionCode: regionCode,
          affiliation: affiliation,
          runningExperience: runningExperience,
        );
    await _signedIn(tokens);
  }

  /// 기기의 토큰을 먼저 지운다. 서버의 리프레시 토큰 폐기가 실패해도 로그아웃은 끝난다.
  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    final tokens = await storage.read();
    await storage.clear();
    state = const AsyncData(SignedOut());
    if (tokens == null) return;
    try {
      await ref.read(memberApiClientProvider).logout(tokens.refreshToken);
    } on ApiException {
      // 서버에 남은 리프레시 토큰은 7일 뒤 만료된다.
    }
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

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
