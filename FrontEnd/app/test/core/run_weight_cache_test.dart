import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';

class ProfileResponse implements HttpClientAdapter {
  final profile = <String, dynamic>{
    'nickname': 'runner',
    'bodyInfo': {
      'birthYear': 2000,
      'heightCm': 170,
      'weightKg': 65,
      'gender': 'MALE',
    },
  };
  Future<void> Function()? delay;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    await delay?.call();
    return ResponseBody.fromString(
      jsonEncode({'result': 'SUCCESS', 'data': profile}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const alice = AuthTokens(
    accessToken: 'x.eyJzdWIiOiJhbGljZSJ9.x',
    refreshToken: 'r',
  );
  const bob = AuthTokens(
    accessToken: 'x.eyJzdWIiOiJib2IifQ.x',
    refreshToken: 'r',
  );
  test('successful own profile populates cache; consent removal clears only that account', () async {
    final tokens = TokenStorage();
    await tokens.write(alice);
    final response = ProfileResponse();
    final dio = Dio()..httpClientAdapter = response;
    final api = MemberApiClient(dio, () => dio, tokens);
    await api.me();
    expect(await tokens.runWeight('alice'), 65);
    await tokens.rememberRunWeight('bob', 80);
    response.profile['bodyInfo'] = null;
    await api.me();
    expect(await tokens.runWeight('alice'), isNull);
    expect(await tokens.runWeight('bob'), 80);
  });
  test(
    'old profile response cannot cache weight into a newly signed in account',
    () async {
      final tokens = TokenStorage();
      await tokens.write(alice);
      final response = ProfileResponse()..delay = () => tokens.write(bob);
      final dio = Dio()..httpClientAdapter = response;
      await MemberApiClient(dio, () => dio, tokens).me();
      expect(await tokens.runWeight('alice'), isNull);
      expect(await tokens.runWeight('bob'), isNull);
    },
  );
  test('withdrawal clears encrypted weight and blocks late cache recreation after reopening', () async {
    final tokens = TokenStorage();
    await tokens.rememberRunWeight('alice', 65);
    await tokens.rememberRunWeight('bob', 80);
    await tokens.eraseRunWeight('alice');
    final reopened = TokenStorage();
    await reopened.rememberRunWeight('alice', 70);
    expect(await reopened.runWeight('alice'), isNull);
    expect(await reopened.runWeight('bob'), 80);
  });
}
