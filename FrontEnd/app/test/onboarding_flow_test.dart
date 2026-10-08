import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';

import 'fakes.dart';

void main() {
  late FakeMemberApi api;
  late MemoryTokenStorage storage;
  late FakeRunPermissions permissions;

  Future<void> startApp(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberApiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(storage),
        socialLoginProvider.overrideWithValue(FakeSocialLogin()),
        runPermissionsProvider.overrideWithValue(permissions),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> reachProfile(WidgetTester tester) async {
    await tap(tester, find.text('카카오 로그인'));
    await tap(tester, find.text('전체 동의하기'));
    await tap(tester, find.text('동의하고 계속하기'));
    await tap(tester, find.text('권한 허용하기'));
  }

  Future<void> fillProfile(WidgetTester tester, String nickname) async {
    await tester.enterText(find.byType(TextField).first, nickname);
    await tap(tester, find.ancestor(of: find.text('활동 지역을 선택하세요'), matching: find.byType(TextField)));
    await tap(tester, find.text('충남 아산시'));
    await tap(tester, find.text('6개월+'));
  }

  setUp(() {
    api = FakeMemberApi();
    storage = MemoryTokenStorage();
    permissions = FakeRunPermissions();
  });

  testWidgets('first login goes through consent, permissions and profile, then home', (tester) async {
    await startApp(tester);
    expect(find.text('카카오 로그인'), findsOneWidget);
    expect(find.text('Google 계정으로 로그인', findRichText: true), findsOneWidget);
    expect(find.text('Apple로 로그인'), findsNothing);

    await tap(tester, find.text('카카오 로그인'));
    expect(find.text('[선택] 카카오 계정 이메일 제공'), findsOneWidget);

    // 필수 동의 전에는 계속할 수 없다.
    await tap(tester, find.text('동의하고 계속하기'));
    expect(find.text('서비스 이용 동의'), findsOneWidget);
    expect(find.text('필수 항목에 모두 동의해야 계속할 수 있어요.'), findsOneWidget);

    await tap(tester, find.text('전체 동의하기'));
    expect(find.text('선택 항목에 동의하지 않아도 서비스를 이용할 수 있어요.'), findsOneWidget);
    await tap(tester, find.text('동의하고 계속하기'));

    await tap(tester, find.text('권한 허용하기'));
    expect(permissions.requests, 1);

    await fillProfile(tester, '흐름러너');
    await tap(tester, find.text('시작하기'));

    expect(find.text('준비 중인 화면이에요'), findsOneWidget);
    expect(api.signedUp, {
      'signupToken': 'signup-token',
      'agreements': const Agreements.all(true).toJson(),
      'nickname': '흐름러너',
      'bio': null,
      'regionCode': '4420000000',
      'affiliation': null,
      'runningExperience': 'MONTHS_6',
    });
    expect(storage.tokens?.refreshToken, testTokens.refreshToken);
  });

  testWidgets('cannot start until the nickname follows the rules', (tester) async {
    await startApp(tester);
    await reachProfile(tester);

    await fillProfile(tester, '러너!');
    expect(find.text('한글 · 영문 · 숫자만 쓸 수 있어요'), findsOneWidget);
    await tap(tester, find.text('시작하기'));

    expect(api.signedUp, isNull);
  });

  testWidgets('shows the server message under the nickname when it is taken', (tester) async {
    api.signupError = const ApiException('MEMBER-006', '이미 사용 중인 닉네임입니다.');
    await startApp(tester);
    await reachProfile(tester);

    await fillProfile(tester, '중복러너');
    await tap(tester, find.text('시작하기'));

    expect(find.text('이미 사용 중인 닉네임입니다.'), findsOneWidget);
    expect(find.text('프로필 설정'), findsOneWidget);
  });

  testWidgets('back on the consent screen cancels the signup', (tester) async {
    await startApp(tester);
    await tap(tester, find.text('카카오 로그인'));

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));

    expect(find.text('카카오 로그인'), findsOneWidget);
  });

  testWidgets('a member logs in straight to home and can log out', (tester) async {
    api.loginResult = const LoginSignedIn(testTokens);
    await startApp(tester);

    await tap(tester, find.text('카카오 로그인'));
    expect(find.text('준비 중인 화면이에요'), findsOneWidget);

    await tap(tester, find.text('MY'));
    await tap(tester, find.text('로그아웃'));

    expect(find.text('카카오 로그인'), findsOneWidget);
    expect(storage.tokens, isNull);
    expect(api.logouts, 1);
  });

  testWidgets('starts at home when tokens are stored', (tester) async {
    storage.tokens = testTokens;
    await startApp(tester);

    expect(find.text('준비 중인 화면이에요'), findsOneWidget);
  });
}
