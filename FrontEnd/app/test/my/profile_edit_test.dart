import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/region_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/upload/photo_uploader.dart';
import 'package:wadadak/features/my/profile_edit_screen.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMemberApi members;
  late FakePhotoUploader uploader;

  /// E3(글자만) 위에 F6을 연다. 나가면 E3이 보인다.
  Future<void> openEdit(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: Routes.my,
      routes: [
        GoRoute(path: Routes.my, builder: (_, _) => const Scaffold(body: Text('E3'))),
        GoRoute(path: Routes.myProfileEdit, builder: (_, _) => const ProfileEditScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberApiClientProvider.overrideWithValue(members),
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
          photoUploaderProvider.overrideWithValue(uploader),
          regionApiClientProvider.overrideWithValue(FakeRegionApi()),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push(Routes.myProfileEdit);
    await tester.pumpAndSettle();
  }

  setUp(() {
    members = FakeMemberApi()
      ..profile = {
        ...FakeMemberApi().profile,
        'nicknameChangeableAt': null,
        'bio': '야간 러닝 좋아합니다',
        'profileImageKey': 'member/old.jpg',
        'bodyInfo': {'birthYear': 1998, 'heightCm': 175, 'weightKg': 68, 'gender': 'MALE'},
      };
    uploader = FakePhotoUploader();
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String value) => find.widgetWithText(TextField, value);

  testWidgets('F6 starts with my profile and saves only after a change', (tester) async {
    await openEdit(tester);

    expect(field('wonehgus'), findsOneWidget);
    expect(field('야간 러닝 좋아합니다'), findsOneWidget);
    expect(field('서울 성북구'), findsOneWidget);
    expect(field('선문대학교'), findsOneWidget);
    expect(field('1998년생'), findsOneWidget);
    expect(field('175'), findsOneWidget);
    expect(field('68'), findsOneWidget);
    expect(find.text('30일에 한 번 바꿀 수 있어요'), findsOneWidget);

    // 바꾼 게 없으면 저장되지 않는다
    await tap(tester, find.text('저장'));
    expect(members.edited, isNull);

    await tester.enterText(field('야간 러닝 좋아합니다'), '새벽 러닝');
    await tap(tester, field('서울 성북구'));
    await tester.enterText(find.byType(TextField), '아산');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tap(tester, find.text('아산시'));
    await tap(tester, find.text('1년+'));
    await tap(tester, find.text('저장'));

    expect(members.edited, {
      'nickname': 'wonehgus',
      'bio': '새벽 러닝',
      'regionCode': '4420000000',
      'affiliation': '선문대학교',
      'runningExperience': 'YEAR_1',
      'profileImageKey': 'member/old.jpg',
      'bodyInfo': {'birthYear': 1998, 'heightCm': 175, 'weightKg': 68, 'gender': 'MALE'},
    });
    expect(find.text('E3'), findsOneWidget);
    expect(find.text('프로필을 저장했어요.'), findsOneWidget);
  });

  testWidgets('save button is gray until something changes, then green', (tester) async {
    await openEdit(tester);
    Color? saveColor() => tester
        .widget<WdSurface>(find.ancestor(of: find.text('저장'), matching: find.byType(WdSurface)).first)
        .color;

    expect(saveColor(), WdColors.disabledBg);

    await tester.enterText(field('선문대학교'), '와다닥 크루');
    await tester.pump();
    expect(saveColor(), WdColors.lime);

    // 원래대로 되돌리면 다시 회색
    await tester.enterText(field('와다닥 크루'), '선문대학교');
    await tester.pump();
    expect(saveColor(), WdColors.disabledBg);
  });

  testWidgets('nickname stays locked until the date the server gives', (tester) async {
    members.profile = {...members.profile, 'nicknameChangeableAt': '2099-11-27T15:00:00Z'};
    await openEdit(tester);

    expect(find.text('30일에 한 번 바꿀 수 있어요 · 다음 변경 가능 2099.11.28'), findsOneWidget);
    expect(tester.widget<TextField>(field('wonehgus')).enabled, isFalse);
  });

  testWidgets('server nickname errors show under the field', (tester) async {
    members.editError = const ApiException('MEMBER-006', '이미 사용 중인 닉네임입니다.', status: 409);
    await openEdit(tester);

    await tester.enterText(field('wonehgus'), 'runner');
    await tester.pump();
    await tap(tester, find.text('저장'));

    expect(members.edited?['nickname'], 'runner');
    expect(find.text('이미 사용 중인 닉네임입니다.'), findsOneWidget);
    expect(find.text('E3'), findsNothing);
  });

  testWidgets('a new photo is uploaded and its key is saved', (tester) async {
    uploader.photo = testPhoto;
    await openEdit(tester);

    await tap(tester, find.text('사진 변경'));
    expect(find.text('사진 삭제'), findsNothing); // 지금 사진이 없다
    await tap(tester, find.text('앨범에서 고르기'));
    await tap(tester, find.text('저장'));

    expect(uploader.uploaded, [testPhoto]);
    expect(members.myPhotoForms, 1);
    expect(members.edited?['profileImageKey'], 'member/new.jpg');
  });

  testWidgets('a removed photo is saved as no photo', (tester) async {
    uploader.photo = testPhoto;
    await openEdit(tester);

    await tap(tester, find.text('사진 변경'));
    await tap(tester, find.text('앨범에서 고르기'));
    await tap(tester, find.text('사진 변경'));
    await tap(tester, find.text('사진 삭제'));
    await tap(tester, find.text('저장'));

    expect(uploader.uploaded, isEmpty);
    expect(members.edited?.containsKey('profileImageKey'), isTrue);
    expect(members.edited?['profileImageKey'], isNull);
  });

  testWidgets('turning body consent off saves no body info', (tester) async {
    await openEdit(tester);

    await tap(tester, find.text('[선택] 신체 정보 수집 및 이용'));
    expect(field('175'), findsNothing);
    await tap(tester, find.text('저장'));

    expect(members.edited?['bodyInfo'], isNull);
    expect(find.text('E3'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await openEdit(tester);

    await tester.enterText(field('선문대학교'), '와다닥 크루');
    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.text('저장하지 않고 나갈까요?'), findsOneWidget);

    await tap(tester, find.text('계속 편집'));
    expect(field('와다닥 크루'), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    await tap(tester, find.text('나가기'));
    expect(find.text('E3'), findsOneWidget);
    expect(members.edited, isNull);
  });

  testWidgets('leaving without changes does not ask', (tester) async {
    await openEdit(tester);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.text('저장하지 않고 나갈까요?'), findsNothing);
    expect(find.text('E3'), findsOneWidget);
  });
}
