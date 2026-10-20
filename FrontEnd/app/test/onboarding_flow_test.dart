import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/region_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/core/upload/photo_uploader.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';

import 'fakes.dart';

void main() {
  late FakeMemberApi api;
  late MemoryTokenStorage storage;
  late FakeRunPermissions permissions;
  late FakePhotoUploader uploader;

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
        mapEngineProvider.overrideWithValue(MapEngine.dev),
        courseApiClientProvider.overrideWithValue(FakeCourseApi()),
        regionApiClientProvider.overrideWithValue(FakeRegionApi()),
        photoUploaderProvider.overrideWithValue(uploader),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    // 스크롤한 위치가 그려진 뒤에 누른다. 아니면 스크롤 전 위치(하단 버튼 밑)를 누른다.
    await tester.pumpAndSettle();
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
    // 활동 지역은 로그인 전에 시·군·구를 검색해 고른다.
    await tap(tester, find.ancestor(of: find.text('활동 지역을 선택하세요'), matching: find.byType(TextField)));
    await tester.enterText(find.byType(TextField), '아산');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tap(tester, find.text('아산시'));
    expect(find.text('충남 아산시'), findsOneWidget);
    await tap(tester, find.text('6개월+'));
  }

  setUp(() {
    api = FakeMemberApi();
    storage = MemoryTokenStorage();
    permissions = FakeRunPermissions();
    uploader = FakePhotoUploader();
  });

  testWidgets('first login goes through consent, permissions and profile, then home', (tester) async {
    await startApp(tester);
    expect(find.text('카카오 로그인'), findsOneWidget);
    expect(find.text('Google 계정으로 로그인', findRichText: true), findsOneWidget);
    expect(find.text('Apple로 로그인'), findsNothing);

    await tap(tester, find.text('카카오 로그인'));
    expect(find.textContaining('이메일'), findsNothing);

    // 필수 동의 전에는 계속할 수 없다.
    await tap(tester, find.text('동의하고 계속하기'));
    expect(find.text('서비스 이용 동의'), findsOneWidget);
    expect(find.text('필수 항목에 모두 동의해야 계속할 수 있어요.'), findsOneWidget);

    await tap(tester, find.text('전체 동의하기'));
    expect(find.text('필수 항목에 모두 동의해야 계속할 수 있어요.'), findsNothing);
    await tap(tester, find.text('동의하고 계속하기'));

    await tap(tester, find.text('권한 허용하기'));
    expect(permissions.requests, 1);

    await fillProfile(tester, '흐름러너');
    await tap(tester, find.text('시작하기'));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(api.signedUp, {
      'signupToken': 'signup-token',
      'agreements': const Agreements.all(true).toJson(),
      'nickname': '흐름러너',
      'bio': null,
      'regionCode': '4420000000',
      'affiliation': null,
      'runningExperience': 'MONTHS_6',
      'profileImageKey': null,
      'bodyInfo': null,
    });
    expect(storage.tokens?.refreshToken, testTokens.refreshToken);
    expect(uploader.uploaded, isEmpty);
  });

  testWidgets('a picked profile photo is uploaded with the signup token and its key goes into the signup', (tester) async {
    uploader.photo = testPhoto;
    await startApp(tester);
    await reachProfile(tester);

    await tap(tester, find.bySemanticsLabel('프로필 사진 고르기'));
    expect(find.text('사진 빼기'), findsOneWidget);
    await fillProfile(tester, '사진러너');
    await tap(tester, find.text('시작하기'));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(uploader.uploaded, [testPhoto]);
    expect(api.photoFormTokens, ['signup-token']);
    expect(api.signedUp?['profileImageKey'], 'member/photo.jpg');
  });

  testWidgets('a removed profile photo is not uploaded', (tester) async {
    uploader.photo = testPhoto;
    await startApp(tester);
    await reachProfile(tester);

    await tap(tester, find.bySemanticsLabel('프로필 사진 고르기'));
    await tap(tester, find.text('사진 빼기'));
    await fillProfile(tester, '사진없음');
    await tap(tester, find.text('시작하기'));

    expect(uploader.uploaded, isEmpty);
    expect(api.signedUp?['profileImageKey'], isNull);
  });

  testWidgets('body info unlocks after its consent and all four values go into the signup', (tester) async {
    await startApp(tester);
    await reachProfile(tester);
    await fillProfile(tester, '몸러너');

    // 동의 전에는 입력칸을 쓸 수 없다.
    final birthYear = find.ancestor(of: find.text('출생연도를 선택하세요'), matching: find.byType(TextField));
    await tester.ensureVisible(birthYear);
    await tester.pumpAndSettle();
    await tester.tap(birthYear, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('만 14세 이상만 고를 수 있어요'), findsNothing);

    await tap(tester, find.text('[선택] 신체 정보 수집 및 이용'));
    await tap(tester, birthYear);
    // 목록은 연도만으로 만 14세 이상이 확실한 해부터 시작한다.
    final latest = BodyInfo.birthYears(DateTime.now()).first;
    expect(find.text('만 14세 이상만 고를 수 있어요'), findsOneWidget);
    expect(find.text('${latest + 1}년생'), findsNothing);
    await tap(tester, find.text('$latest년생'));
    await tap(tester, find.text('적용'));
    expect(find.text('$latest년생'), findsOneWidget);

    // 네 값을 모두 넣기 전에는 시작할 수 없다.
    await tap(tester, find.text('시작하기'));
    expect(api.signedUp, isNull);

    await tester.enterText(find.ancestor(of: find.text('키 (cm)'), matching: find.byType(TextField)), '175');
    await tester.enterText(find.ancestor(of: find.text('체중 (kg)'), matching: find.byType(TextField)), '68');
    await tap(tester, find.text('남성'));
    await tap(tester, find.text('시작하기'));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(api.signedUp?['bodyInfo'], {'birthYear': latest, 'heightCm': 175, 'weightKg': 68, 'gender': 'MALE'});
  });

  testWidgets('out-of-range body info blocks the start, and turning the consent off clears it', (tester) async {
    await startApp(tester);
    await reachProfile(tester);
    await fillProfile(tester, '범위러너');

    await tap(tester, find.text('[선택] 신체 정보 수집 및 이용'));
    await tap(tester, find.ancestor(of: find.text('출생연도를 선택하세요'), matching: find.byType(TextField)));
    await tap(tester, find.text('${BodyInfo.birthYears(DateTime.now()).first}년생'));
    await tap(tester, find.text('적용'));
    await tester.enterText(find.ancestor(of: find.text('키 (cm)'), matching: find.byType(TextField)), '99');
    await tester.enterText(find.ancestor(of: find.text('체중 (kg)'), matching: find.byType(TextField)), '68');
    await tap(tester, find.text('여성'));

    expect(find.text('키는 100~250cm, 체중은 20~300kg으로 입력해 주세요'), findsOneWidget);
    await tap(tester, find.text('시작하기'));
    expect(api.signedUp, isNull);

    await tap(tester, find.text('[선택] 신체 정보 수집 및 이용'));
    expect(find.text('키 (cm)'), findsOneWidget);
    expect(find.text('출생연도를 선택하세요'), findsOneWidget);
    await tap(tester, find.text('시작하기'));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(api.signedUp?['bodyInfo'], isNull);
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
    expect(find.byType(HomeScreen), findsOneWidget);

    await tap(tester, find.text('MY'));
    await tap(tester, find.text('로그아웃'));

    expect(find.text('카카오 로그인'), findsOneWidget);
    expect(storage.tokens, isNull);
    expect(api.logouts, 1);
  });

  testWidgets('starts at home when tokens are stored', (tester) async {
    storage.tokens = testTokens;
    await startApp(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
