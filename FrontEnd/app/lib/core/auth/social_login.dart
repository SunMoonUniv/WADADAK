import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import '../api/member_api_client.dart';
import '../config.dart';

/// 소셜 SDK로 로그인해 서버에 보낼 소셜 토큰을 받는다. 카카오는 액세스 토큰, Google은 ID 토큰.
abstract interface class SocialLogin {
  Future<String> signIn(SocialProvider provider);
}

/// 로컬 서버 전용 가짜 로그인. 서버의 가짜 소셜 검증(`app.member.social.fake`)은 토큰 문자열을 소셜 ID로 쓴다.
///
/// 설치마다 같은 ID를 쓰므로 같은 기기는 같은 회원으로 로그인한다. 새 회원으로 시험하려면 앱 데이터를 지운다.
class DevSocialLogin implements SocialLogin {
  DevSocialLogin([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'devSocialId';

  @override
  Future<String> signIn(SocialProvider provider) async {
    var id = await _storage.read(key: _key);
    if (id == null) {
      final random = Random.secure();
      id = List.generate(6, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _storage.write(key: _key, value: id);
    }
    return 'dev-${provider.name}-$id';
  }
}

/// 사용자가 소셜 로그인 창을 닫았다. 오류로 안내하지 않고 로그인 화면에 머문다.
class SocialLoginCanceled implements Exception {
  const SocialLoginCanceled();
}

/// 소셜 SDK 로그인. 서버는 실제 검증(`app.member.social.fake: false`)으로 띄운다.
class SdkSocialLogin implements SocialLogin {
  @override
  Future<String> signIn(SocialProvider provider) async => switch (provider) {
        SocialProvider.kakao => await _kakao(),
        // ponytail: Google·Apple SDK는 콘솔 키를 받은 뒤 붙인다.
        SocialProvider.google || SocialProvider.apple => throw UnsupportedError('${provider.name} 로그인은 아직 연결하지 않았습니다'),
      };

  /// 카카오톡이 있으면 카카오톡으로, 없거나 카카오톡 로그인이 실패하면 카카오계정(웹)으로 로그인한다.
  Future<String> _kakao() async {
    try {
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          return (await kakao.UserApi.instance.loginWithKakaoTalk()).accessToken;
        } catch (e) {
          // 취소는 그대로 끝낸다. 그 밖의 실패(카카오톡에 연결된 계정 없음 등)는 카카오계정 로그인으로 넘어간다.
          if (_isCanceled(e)) rethrow;
        }
      }
      return (await kakao.UserApi.instance.loginWithKakaoAccount()).accessToken;
    } catch (e) {
      if (_isCanceled(e)) throw const SocialLoginCanceled();
      rethrow;
    }
  }

  static bool _isCanceled(Object e) => e is PlatformException && e.code == 'CANCELED';
}

/// 서버의 소셜 검증 방식과 짝을 맞춘다(config.dart `realSocialLogin`). 운영 서버는 가짜 토큰을 거부한다(MEMBER-002).
final socialLoginProvider = Provider<SocialLogin>((ref) => realSocialLogin ? SdkSocialLogin() : DevSocialLogin());
