import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/features/onboarding/login_screen.dart';

import 'fakes.dart';

/// 소셜 로그인 창. [hang]이면 사용자가 창을 버린 것처럼 끝내 응답하지 않는다.
class ControlledSocialLogin implements SocialLogin {
  ControlledSocialLogin({required this.hang});

  final bool hang;
  int calls = 0;

  @override
  Future<String> signIn(SocialProvider provider) {
    calls++;
    return hang ? Completer<String>().future : Future.value('social-token');
  }
}

/// 서버 로그인이 느리다. [respond]를 부르기 전까지 응답하지 않는다.
class SlowMemberApi extends FakeMemberApi {
  final _response = Completer<LoginResult>();
  int loginCalls = 0;

  void respond() => _response.complete(loginResult);

  @override
  Future<LoginResult> login(SocialProvider provider, String socialToken) {
    loginCalls++;
    return _response.future;
  }
}

void main() {
  Future<void> showLogin(WidgetTester tester, SocialLogin social, MemberApiClient api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberApiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage()),
          socialLoginProvider.overrideWithValue(social),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKakao(WidgetTester tester) async {
    await tester.tap(find.text('카카오 로그인'), warnIfMissed: false);
    await tester.pump();
  }

  /// 홈 화면으로 나갔다가 앱 아이콘으로 돌아온다.
  void leaveAndComeBack(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('shows progress instead of the buttons while logging in, and a second tap does nothing', (tester) async {
    final social = ControlledSocialLogin(hang: true);
    await showLogin(tester, social, FakeMemberApi());
    expect(find.text('로그인하는 중이에요'), findsNothing);

    await tapKakao(tester);
    expect(find.text('로그인하는 중이에요'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('카카오 로그인'), warnIfMissed: false);
    await tester.pump();
    expect(social.calls, 1);
  });

  testWidgets('an abandoned social login unlocks 3 seconds after coming back', (tester) async {
    final social = ControlledSocialLogin(hang: true);
    await showLogin(tester, social, FakeMemberApi());
    await tapKakao(tester);

    leaveAndComeBack(tester);
    await tester.pump(const Duration(seconds: 2));
    await tapKakao(tester);
    expect(social.calls, 1, reason: '돌아온 직후에는 소셜 SDK가 아직 응답할 수 있어 잠가 둔다');

    await tester.pump(const Duration(seconds: 1));
    await tapKakao(tester);
    expect(social.calls, 2, reason: '3초가 지나도 응답이 없으면 버려진 로그인으로 보고 다시 누를 수 있다');
  });

  testWidgets('stays locked while waiting for the server, however long it takes', (tester) async {
    final social = ControlledSocialLogin(hang: false);
    final api = SlowMemberApi();
    await showLogin(tester, social, api);
    await tapKakao(tester);
    expect(api.loginCalls, 1);

    leaveAndComeBack(tester);
    await tester.pump(const Duration(seconds: 10));
    await tapKakao(tester);
    expect(social.calls, 1, reason: '서버 로그인은 시간 제한으로 반드시 끝나므로 기다린다');

    api.respond();
    await tester.pump();
    expect(api.loginCalls, 1);
  });
}
