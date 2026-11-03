import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/core/auth/account_data_cleanup.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:wadadak/features/run/run_settings_events.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import '../run/recording/run_controller_test.dart' as fake;

/// 기기 저장소. 기록은 없고 음성 안내 설정만 메모리에 둔다.
class _LocalStore extends fake.FailingStore {
  @override
  Future<List<CourseStartIntent>> pendingCourseStarts(String owner) async => [];
  @override
  Future<void> purgeWithdrawnOwner(String owner) async {
    voice = const RunVoiceSettings();
  }

  RunVoiceSettings voice = const RunVoiceSettings();
  Object? voiceError;
  Completer<void>? voiceGate;

  @override
  Future<RunVoiceSettings> voiceSettings(String owner) async => voice;

  @override
  Future<void> saveVoiceSettings(
    String owner,
    RunVoiceSettings settings,
  ) async {
    await voiceGate?.future;
    if (voiceError != null) throw voiceError!;
    voice = settings;
  }

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
  setUpAll(() async {
    final font = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      font.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await font.load();
  });

  late FakeMemberApi members;
  late MemoryTokenStorage tokens;
  late _LocalStore store;
  late FakeDevicePermissions permissions;
  final capture = GlobalKey();

  /// E3(글자만) 위에 F4를 연다. 닉네임을 누르면 F6(글자만)으로 간다.
  Future<RunController> openSettings(
    WidgetTester tester, {
    double width = 402,
    double height = 2400,
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
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
        GoRoute(
          path: Routes.my,
          builder: (_, _) => const Scaffold(body: Text('E3')),
        ),
        GoRoute(
          path: Routes.mySettings,
          builder: (_, _) => const SettingsScreen(),
        ),
        GoRoute(
          path: Routes.myProfileEdit,
          builder: (_, _) => const Text('F6'),
        ),
        GoRoute(path: Routes.myTerms, builder: (_, _) => const Text('F7')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(runs),
          accountDataCleanupProvider.overrideWithValue(
            runs.purgeWithdrawnOwner,
          ),
          memberApiClientProvider.overrideWithValue(members),
          tokenStorageProvider.overrideWithValue(tokens),
          devicePermissionsProvider.overrideWithValue(permissions),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: WdTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push(Routes.mySettings);
    await tester.pumpAndSettle();
    return runs;
  }

  setUp(() {
    members = FakeMemberApi();
    tokens = MemoryTokenStorage(
      const AuthTokens(
        accessToken: 'x.eyJzdWIiOiJhbGljZSJ9.x',
        refreshToken: 'refresh',
      ),
    );
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

  testWidgets('F4 shows my account, permissions, audio guide and version', (
    tester,
  ) async {
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

  testWidgets('nickname opens F6, a permission opens the phone settings', (
    tester,
  ) async {
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
    expect(members.savedSettings.last, {
      'infoPublic': false,
      'profileSearchable': false,
    });
  });

  testWidgets('a failed public switch goes back', (tester) async {
    members.settingsError = const ApiException(ApiException.network, '오프라인');
    await openSettings(tester);

    toggle(tester, '내 정보 공개').onChanged!(false);
    await tester.pumpAndSettle();

    expect(members.savedSettings, hasLength(1));
    expect(toggle(tester, '내 정보 공개').value, isTrue);
  });

  testWidgets('features without a policy or server say they are coming', (
    tester,
  ) async {
    await openSettings(tester);

    for (final label in ['기본 고스트']) {
      await tap(tester, find.text(label));
      expect(find.text('준비 중인 기능이에요.'), findsOneWidget, reason: label);
      ScaffoldMessenger.of(tester.element(find.text(label)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    // 알림 기능이 없어 만료 임박 스위치는 잠겨 있다
    expect(toggle(tester, '내 코스 만료 임박').onChanged, isNull);
  });

  testWidgets('the terms row opens F7', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('약관 및 개인정보 처리방침'));

    expect(find.text('F7'), findsOneWidget);
  });

  testWidgets(
    'ghost switch saves through the public receiver and updates running audio settings',
    (tester) async {
      final runs = await openSettings(tester);
      expect(find.text('구간 격차 음성 안내'), findsNothing);
      expect(toggle(tester, ghostGapVoiceSettingLabel).value, false);
      toggle(tester, ghostGapVoiceSettingLabel).onChanged!(true);
      await tester.pumpAndSettle();
      expect(store.voice.ghostGapEnabled, true);
      expect(runs.audioGuide.settings.ghostGapEnabled, true);
      expect(toggle(tester, ghostGapVoiceSettingLabel).value, true);
      toggle(tester, ghostGapVoiceSettingLabel).onChanged!(false);
      await tester.pumpAndSettle();
      expect(store.voice.ghostGapEnabled, false);
      expect(runs.audioGuide.settings.ghostGapEnabled, false);
      expect(members.savedSettings, isEmpty);
      expect(find.text('준비 중인 기능이에요.'), findsNothing);
    },
  );

  testWidgets(
    'global audio OFF locks ghost switch but keeps its selection; enabling restores it',
    (tester) async {
      store.voice = const RunVoiceSettings(ghostGapEnabled: true);
      final runs = await openSettings(tester);
      await tap(tester, find.text('오디오 안내'));
      await tap(tester, find.text('안내 안 함'));
      await tap(tester, find.text('적용'));
      expect(toggle(tester, ghostGapVoiceSettingLabel).value, true);
      expect(toggle(tester, ghostGapVoiceSettingLabel).onChanged, isNull);
      expect(find.text('음성 안내를 켜면 사용할 수 있어요'), findsOneWidget);
      expect(store.voice.ghostGapEnabled, true);
      expect(runs.audioGuide.settings.enabled, false);
      await tap(tester, find.text('오디오 안내'));
      await tap(tester, find.text('거리마다'));
      await tap(tester, find.text('적용'));
      expect(toggle(tester, ghostGapVoiceSettingLabel).value, true);
      expect(toggle(tester, ghostGapVoiceSettingLabel).onChanged, isNotNull);
      expect(find.text('음성 안내를 켜면 사용할 수 있어요'), findsNothing);
    },
  );

  testWidgets(
    'auto pause and screen options save independently even when global audio is OFF',
    (tester) async {
      store.voice = const RunVoiceSettings(
        enabled: false,
        ghostGapEnabled: true,
      );
      final runs = await openSettings(tester);
      toggle(tester, '자동 일시정지').onChanged!(true);
      await tester.pumpAndSettle();
      toggle(tester, '화면 항상 켜기').onChanged!(true);
      await tester.pumpAndSettle();
      expect(store.voice.autoPauseEnabled, true);
      expect(store.voice.keepScreenOn, true);
      expect(runs.settings.autoPauseEnabled, true);
      expect(runs.settings.keepScreenOn, true);
      expect(store.voice.enabled, false);
      expect(store.voice.ghostGapEnabled, true);
      toggle(tester, '자동 일시정지').onChanged!(false);
      await tester.pumpAndSettle();
      toggle(tester, '화면 항상 켜기').onChanged!(false);
      await tester.pumpAndSettle();
      expect(store.voice.autoPauseEnabled, false);
      expect(store.voice.keepScreenOn, false);
    },
  );

  testWidgets('persisted options are restored at 320px without overflow', (
    tester,
  ) async {
    store.voice = const RunVoiceSettings(
      ghostGapEnabled: true,
      autoPauseEnabled: true,
      keepScreenOn: true,
      unit: VoiceUnit.time,
      timeMinutes: 10,
    );
    await openSettings(tester, width: 320, height: 874);
    await Scrollable.ensureVisible(
      tester.element(
        find
            .ancestor(
              of: find.text(ghostGapVoiceSettingLabel),
              matching: find.byType(SettingsRow),
            )
            .first,
      ),
      alignment: 1,
    );
    await tester.pumpAndSettle();
    expect(toggle(tester, ghostGapVoiceSettingLabel).value, true);
    expect(toggle(tester, '자동 일시정지').value, true);
    expect(toggle(tester, '화면 항상 켜기').value, true);
    expect(row('오디오 안내', '10분마다'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final screenshot = Platform.environment['RUN_SETTINGS_SCREENSHOT'];
    if (screenshot != null) {
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('failed save keeps old option and allows retry', (tester) async {
    store.voiceError = StateError('disk full');
    await openSettings(tester);
    toggle(tester, ghostGapVoiceSettingLabel).onChanged!(true);
    await tester.pumpAndSettle();
    expect(toggle(tester, ghostGapVoiceSettingLabel).value, false);
    expect(store.voice.ghostGapEnabled, false);
    expect(find.text('러닝 설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(toggle(tester, ghostGapVoiceSettingLabel).onChanged, isNotNull);
    store.voiceError = null;
    toggle(tester, ghostGapVoiceSettingLabel).onChanged!(true);
    await tester.pumpAndSettle();
    expect(toggle(tester, ghostGapVoiceSettingLabel).value, true);
  });

  testWidgets(
    'pending settings save locks all related controls and partial audio changes preserve other options',
    (tester) async {
      store.voiceGate = Completer<void>();
      await openSettings(tester);
      final change = toggle(tester, '자동 일시정지').onChanged!;
      change(true);
      change(false);
      await tester.pump();
      expect(toggle(tester, '자동 일시정지').onChanged, isNull);
      expect(toggle(tester, '화면 항상 켜기').onChanged, isNull);
      expect(toggle(tester, ghostGapVoiceSettingLabel).onChanged, isNull);
      store.voiceGate!.complete();
      await tester.pumpAndSettle();
      expect(store.voice.autoPauseEnabled, true);
      await tap(tester, find.text('오디오 안내'));
      await tap(tester, find.bySemanticsLabel('안내 시간 늘리기'));
      await tap(tester, find.text('적용'));
      expect(store.voice.unit, VoiceUnit.time);
      expect(store.voice.timeMinutes, 10);
      expect(store.voice.autoPauseEnabled, true);
    },
  );

  testWidgets('withdrawal asks once, then clears the tokens', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('회원 탈퇴'));
    expect(find.text('회원 탈퇴할까요?'), findsOneWidget);
    await tap(tester, find.text('취소'));
    expect(members.withdrawals, 0);
    expect(tokens.tokens, isNotNull);

    await tap(tester, find.text('회원 탈퇴'));
    await tap(tester, find.text('탈퇴'));

    expect(members.withdrawals, 1);
    expect(tokens.tokens, isNull);
    expect(find.text('탈퇴했어요. 그동안 함께 달려 주셔서 고마워요.'), findsOneWidget);
  });

  testWidgets('a failed withdrawal keeps me signed in on F4', (tester) async {
    members.withdrawError = const ApiException(ApiException.network, '오프라인');
    await openSettings(tester);

    await tap(tester, find.text('회원 탈퇴'));
    await tap(tester, find.text('탈퇴'));

    expect(members.withdrawals, 0);
    expect(tokens.tokens, isNotNull);
    expect(find.text('설정'), findsOneWidget);
    expect(find.text('오프라인'), findsOneWidget);
  });

  testWidgets('logout is at the bottom of F4', (tester) async {
    await openSettings(tester);

    await tap(tester, find.text('로그아웃'));

    expect(members.logouts, 1);
    expect(tokens.tokens, isNull);
  });
}
