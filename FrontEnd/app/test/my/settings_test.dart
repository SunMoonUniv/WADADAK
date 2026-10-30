import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/features/my/settings_screen.dart';
import 'package:wadadak/features/run/application/audio_guide.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_audio_output.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/domain/run_voice.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import '../run/recording/run_controller_test.dart' as fake;

/// 기기 저장소. 기록은 없고 음성 안내 설정만 메모리에 둔다.
class _LocalStore extends fake.FailingStore {
  RunVoiceSettings voice = const RunVoiceSettings();

  @override
  Future<RunVoiceSettings> voiceSettings(String owner) async => voice;

  @override
  Future<void> saveVoiceSettings(String owner, RunVoiceSettings settings) async => voice = settings;

  @override
  Future<Set<String>> deletedIds(String owner) async => {};

  @override
  Future<List<String>> pendingDeletions(String owner) async => [];

  @override
  Future<List<PendingGhostStart>> pendingGhostStarts(String owner) async => [];

  @override
  Future<List<String>> pendingGhostClosures(String owner) async => [];

  @override
  Future<List<recording.LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  }) async => [];
}

/// 말하지 않는 음성 출력.
class _SilentOutput extends RunAudioOutput {
  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> speak(String text) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMemberApi members;
  late MemoryTokenStorage tokens;
  late _LocalStore store;
  late FakeDevicePermissions permissions;

  /// E3(글자만) 위에 F4를 연다. 닉네임을 누르면 F6(글자만)으로 간다.
  Future<void> openSettings(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gps = fake.TestLocation();
    final runs = RunController(
      store,
      gps,
      fake.TestApi(),
      () async => 'alice',
      audio: AudioGuide(_SilentOutput()),
      automaticTicks: false,
      nowMs: gps.nowMs,
    );
    addTearDown(runs.dispose);
    // 앱에서는 E3가 먼저 계정을 붙여 둔다. 기다리는 타이머가 있어 아래 pumpAndSettle에서 끝난다
    unawaited(runs.bindOwner());
    final router = GoRouter(
      initialLocation: Routes.my,
      routes: [
        GoRoute(path: Routes.my, builder: (_, _) => const Scaffold(body: Text('E3'))),
        GoRoute(path: Routes.mySettings, builder: (_, _) => const SettingsScreen()),
        GoRoute(path: Routes.myProfileEdit, builder: (_, _) => const Text('F6')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(runs),
          memberApiClientProvider.overrideWithValue(members),
          tokenStorageProvider.overrideWithValue(tokens),
          devicePermissionsProvider.overrideWithValue(permissions),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push(Routes.mySettings);
    await tester.pumpAndSettle();
  }

  setUp(() {
    members = FakeMemberApi();
    tokens = MemoryTokenStorage(testTokens);
    store = _LocalStore();
    permissions = FakeDevicePermissions();
    PackageInfo.setMockInitialValues(
      appName: '와다닥',
      packageName: 'com.wadadak.app',
      version: '1.0.3',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  /// [label] 줄에 보이는 [value].
  Finder row(String label, String value) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.text(value),
  );

  /// [label] 줄의 스위치.
  WdSwitch toggle(WidgetTester tester, String label) => tester.widget<WdSwitch>(
    find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byType(WdSwitch),
    ),
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('F4 shows my account, permissions, audio guide and version', (tester) async {
    await openSettings(tester);

    expect(row('닉네임', 'wonehgus'), findsOneWidget);
    expect(row('연결된 소셜 계정', '카카오'), findsOneWidget);
    expect(row('위치 (실행 중일 때만)', '허용됨'), findsOneWidget);
    expect(row('동작 및 피트니스', '허용 안 함'), findsOneWidget);
    expect(find.text('허용 안 함'), findsNWidgets(2)); // 동작 및 피트니스 · 알림
    expect(row('오디오 안내', '1km마다'), findsOneWidget);
    expect(row('버전', '1.0.3'), findsOneWidget);
    expect(find.text('거리 단위'), findsNothing);
    expect(toggle(tester, '내 정보 공개').value, isTrue);
    expect(toggle(tester, '프로필 검색 허용').value, isTrue);
  });

  testWidgets('nickname opens F6, a permission opens the phone settings', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('동작 및 피트니스'));
    expect(permissions.settingsOpened, 1);

    // 휴대폰 설정에서 허용하고 돌아오면 다시 읽는다
    permissions.allowed = AppPermission.values.toSet();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(row('동작 및 피트니스', '허용됨'), findsOneWidget);

    await tap(tester, find.text('닉네임'));
    expect(find.text('F6'), findsOneWidget);
  });

  testWidgets('audio guide sheet saves the chosen interval', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('오디오 안내'));
    expect(find.text('1 km'), findsOneWidget);
    expect(find.text('5분'), findsOneWidget);

    // 시간마다 5분 → 10분 → 15분, 끝에서는 더 늘지 않는다
    await tap(tester, find.bySemanticsLabel('안내 시간 늘리기'));
    await tap(tester, find.bySemanticsLabel('안내 시간 늘리기'));
    await tap(tester, find.bySemanticsLabel('안내 시간 늘리기'));
    expect(find.text('15분'), findsOneWidget);
    await tap(tester, find.text('적용'));

    expect(store.voice.enabled, isTrue);
    expect(store.voice.unit, VoiceUnit.time);
    expect(store.voice.timeMinutes, 15);
    expect(row('오디오 안내', '15분마다'), findsOneWidget);

    await tap(tester, find.text('오디오 안내'));
    await tap(tester, find.text('안내 안 함'));
    await tap(tester, find.text('적용'));
    expect(store.voice.enabled, isFalse);
    expect(row('오디오 안내', '안내 안 함'), findsOneWidget);
  });

  testWidgets('cancelling the audio sheet keeps the setting', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('오디오 안내'));
    await tap(tester, find.bySemanticsLabel('안내 거리 늘리기'));
    expect(find.text('2 km'), findsOneWidget);
    await tap(tester, find.text('취소'));

    expect(store.voice.distanceKm, 1);
    expect(row('오디오 안내', '1km마다'), findsOneWidget);
  });

  testWidgets('public switches save both values right away', (tester) async {
    await openSettings(tester);

    toggle(tester, '내 정보 공개').onChanged!(false);
    await tester.pumpAndSettle();
    expect(members.savedSettings, [
      {'infoPublic': false, 'profileSearchable': true},
    ]);
    expect(toggle(tester, '내 정보 공개').value, isFalse);

    toggle(tester, '프로필 검색 허용').onChanged!(false);
    await tester.pumpAndSettle();
    expect(members.savedSettings.last, {'infoPublic': false, 'profileSearchable': false});
  });

  testWidgets('a failed public switch goes back', (tester) async {
    members.settingsError = const ApiException(ApiException.network, '오프라인');
    await openSettings(tester);

    toggle(tester, '내 정보 공개').onChanged!(false);
    await tester.pumpAndSettle();

    expect(members.savedSettings, hasLength(1));
    expect(toggle(tester, '내 정보 공개').value, isTrue);
  });

  testWidgets('features without a policy or server say they are coming', (tester) async {
    await openSettings(tester);

    for (final label in ['기본 고스트', '약관 및 개인정보 처리방침', '회원 탈퇴']) {
      await tap(tester, find.text(label));
      expect(find.text('준비 중인 기능이에요.'), findsOneWidget, reason: label);
      ScaffoldMessenger.of(tester.element(find.text(label))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    toggle(tester, '자동 일시정지').onChanged!(true);
    await tester.pump();
    expect(find.text('준비 중인 기능이에요.'), findsOneWidget);
    expect(toggle(tester, '자동 일시정지').value, isFalse);

    // 알림 기능이 없어 만료 임박 스위치는 잠겨 있다
    expect(toggle(tester, '내 코스 만료 임박').onChanged, isNull);
  });

  testWidgets('logout is at the bottom of F4', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('로그아웃'));

    expect(members.logouts, 1);
    expect(tokens.tokens, isNull);
  });
}
