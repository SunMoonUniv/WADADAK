import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map json) =>
      AuthTokens(accessToken: json['accessToken'] as String, refreshToken: json['refreshToken'] as String);

  final String accessToken;
  final String refreshToken;
}

/// 토큰은 기기 보안 저장소(iOS Keychain · Android Keystore)에만 둔다.
/// 한 번 읽은 값은 메모리에 둬서 요청마다 저장소를 읽지 않는다.
class TokenStorage {
  TokenStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _accessKey = 'accessToken';
  static const _refreshKey = 'refreshToken';

  AuthTokens? _cached;
  bool _loaded = false;

  Future<AuthTokens?> read() async {
    if (!_loaded) {
      final access = await _storage.read(key: _accessKey);
      final refresh = await _storage.read(key: _refreshKey);
      _cached = access == null || refresh == null ? null : AuthTokens(accessToken: access, refreshToken: refresh);
      _loaded = true;
    }
    return _cached;
  }

  Future<void> write(AuthTokens tokens) async {
    _cached = tokens;
    _loaded = true;
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
  }

  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
