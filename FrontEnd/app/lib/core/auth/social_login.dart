import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/member_api_client.dart';

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

/// ponytail: 카카오 · Google SDK를 붙이기 전까지는 가짜 로그인뿐이다. 운영 서버는 가짜 토큰을 거부한다(MEMBER-002).
final socialLoginProvider = Provider<SocialLogin>((ref) => DevSocialLogin());
