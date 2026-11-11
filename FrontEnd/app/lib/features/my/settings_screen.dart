import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/api/notification_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';
import '../../routes.dart';
import '../run/application/run_controller.dart';
import '../run/run_settings_events.dart';
import 'my_screen.dart';
import 'voice_sheet.dart';

/// F4 권한 칸의 세 줄.
enum AppPermission {
  location('위치 (실행 중일 때만)'),
  motion('동작 및 피트니스'),
  notification('알림');

  const AppPermission(this.label);
  final String label;
}

/// 휴대폰 권한 상태를 읽고 휴대폰 설정을 연다. 테스트에서는 가짜로 바꿔 끼운다.
class DevicePermissions {
  const DevicePermissions();

  Future<bool> granted(AppPermission permission) async => (await _of(permission).status).isGranted;

  Future<void> openSettings() => openAppSettings();

  // 걸음 센서 권한은 Android가 activityRecognition, iOS가 sensors다(온보딩 권한 화면과 같다)
  static Permission _of(AppPermission permission) => switch (permission) {
    AppPermission.location => Permission.locationWhenInUse,
    AppPermission.motion => Platform.isIOS ? Permission.sensors : Permission.activityRecognition,
    AppPermission.notification => Permission.notification,
  };
}

final devicePermissionsProvider = Provider<DevicePermissions>((_) => const DevicePermissions());

/// F4 `내 코스 만료 임박`(서버 저장). 못 받으면 스위치를 잠근다.
final courseExpiringSoonProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(notificationApiClientProvider).courseExpiringSoon(),
  retry: (_, _) => null,
);

/// 앱 버전(F4 · F7). 못 읽으면 화면에 `—`로 둔다.
final appVersionProvider = FutureProvider<String>(
  (_) async => (await PackageInfo.fromPlatform()).version,
  retry: (_, _) => null,
);

/// F4 · 설정(Figma `F4 · 설정`). E3 오른쪽 위 설정 아이콘에서 연다.
///
/// - 계정: 닉네임(누르면 F6) · 연결된 소셜 계정. 이메일 줄은 두지 않는다(2026-10-20 결정).
/// - 권한: 휴대폰 권한 상태. 누르면 휴대폰 설정을 열고, 돌아오면 다시 읽는다.
/// - 오디오 안내는 달리기의 음성 안내 설정이다(기기에 저장). 누르면 F5 시트.
/// - 공개 여부 두 스위치는 바꾸는 즉시 서버에 저장한다(`PUT /members/me/settings`). 실패하면 되돌린다.
/// - 고스트 격차 음성 안내는 AUD-07의 계정별 설정 이벤트로 저장한다. 전체 음성 OFF면 선택값을 보존하고 잠근다.
/// - 자동 일시정지는 정상 GPS 정지 10초 뒤 적용한다. 화면 항상 켜기는 진행 중 세션·앱 전면에서만 적용한다.
/// - 기본 고스트는 내 최고 기록(기본) · 내 최근 기록 · 매번 직접 고르기 중 하나다. 다른 러닝 설정처럼 계정별로 기기에 저장하고,
///   코스 고스트 선택(C2)에 들어가면 그 기록을 미리 골라 둔다(2026-11-11 사용자 결정). 거리 단위는 km 고정이라 뺐다.
/// - 약관 및 개인정보 처리방침은 F7 약관 및 정책을 연다.
/// - 회원 탈퇴는 확인 창 하나로 묻고 바로 탈퇴한다(`DELETE /members/me`). 끝나면 로그인 화면으로 간다(2026-11-02 사용자 결정).
/// (2026-10-30 사용자 결정)
/// - 내 코스 만료 임박(F14)은 바꾸는 즉시 서버에 저장한다(`PUT /notifications/settings`). 실패하면 되돌린다.
///   휴대폰 알림 권한이 꺼져 있으면 켜 두어도 받지 못한다고 줄 아래에 알린다.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final AppLifecycleListener _lifecycle;
  Map<AppPermission, bool>? _permissions;

  /// 서버에 저장한(또는 저장 중인) 공개 여부. 없으면 내 정보 값을 쓴다.
  bool? _infoPublic, _searchable;
  bool _savingSettings = false;
  bool _savingRunSettings = false;

  /// 서버에 저장한(또는 저장 중인) 만료 임박 알림. 없으면 서버에서 받은 값을 쓴다.
  bool? _expiringSoon;
  bool _savingNotification = false;

  /// 탈퇴 요청 중. 두 번 누르지 못하게 줄을 잠근다.
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    // 휴대폰 설정에서 권한을 바꾸고 돌아오면 다시 읽는다
    _lifecycle = AppLifecycleListener(onResume: _loadPermissions);
    _loadPermissions();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final permissions = ref.read(devicePermissionsProvider);
    final result = {for (final p in AppPermission.values) p: await permissions.granted(p)};
    if (mounted) setState(() => _permissions = result);
  }

  /// 한 번 묻고 탈퇴한다. 탈퇴하면 라우터가 로그인 화면으로 보낸다. 실패하면 F4에 남아 오류를 보인다.
  Future<void> _withdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 탈퇴할까요?'),
        content: const Text(
          '러닝 기록 · 랭킹 · 리뷰(사진 포함) · 저장한 코스가 바로 지워지고 되돌릴 수 없어요. '
          '등록한 코스는 남고 등록자는 "탈퇴한 사용자"로 보여요.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('탈퇴', style: TextStyle(color: WdColors.negative)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // 탈퇴하면 이 화면이 닫히므로 안내는 앱 전체의 메신저로 띄운다
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _withdrawing = true);
    try {
      await ref.read(authControllerProvider.notifier).withdraw();
      messenger.showSnackBar(const SnackBar(content: Text('탈퇴했어요. 그동안 함께 달려 주셔서 고마워요.')));
    } catch (e) {
      if (mounted) {
        setState(() => _withdrawing = false);
        showError(context, e);
      }
    }
  }

  /// 두 스위치 값을 함께 보낸다. 실패하면 화면 값을 되돌린다.
  Future<void> _saveSettings(MyProfile me, {bool? infoPublic, bool? searchable}) async {
    final (infoBefore, searchBefore) = (_infoPublic, _searchable);
    setState(() {
      _infoPublic = infoPublic ?? _infoPublic ?? me.infoPublic;
      _searchable = searchable ?? _searchable ?? me.profileSearchable;
      _savingSettings = true;
    });
    try {
      await ref.read(memberApiClientProvider).changeSettings(infoPublic: _infoPublic!, profileSearchable: _searchable!);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _infoPublic = infoBefore;
        _searchable = searchBefore;
      });
      showError(context, e);
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _setExpiringSoon(bool on) async {
    final before = _expiringSoon;
    setState(() {
      _expiringSoon = on;
      _savingNotification = true;
    });
    try {
      final saved = await ref.read(notificationApiClientProvider).changeCourseExpiringSoon(on);
      if (mounted) setState(() => _expiringSoon = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _expiringSoon = before);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _savingNotification = false);
    }
  }

  Future<void> _editVoice(RunController runs) async {
    final member = runs.currentOwner;
    if (_savingRunSettings || member == null) return;
    final picked = await showVoiceSheet(context, runs.voiceSettings);
    if (picked == null || !mounted) return;
    await _saveRunSettings(runs, RunSettingsChanged(
      owner: member,
      enabled: picked.enabled,
      unit: picked.unit,
      distanceKm: picked.distanceKm,
      timeMinutes: picked.timeMinutes,
    ));
  }

  /// 기본 고스트도 다른 러닝 설정처럼 계정별로 기기에 저장한다(같은 RunSettingsChanged 경로).
  Future<void> _editDefaultGhost(RunController runs) async {
    final member = runs.currentOwner;
    if (_savingRunSettings || member == null) return;
    final picked = await showDefaultGhostSheet(context, runs.settings.defaultGhost);
    if (picked == null || picked == runs.settings.defaultGhost || !mounted) return;
    await _saveRunSettings(runs, RunSettingsChanged(owner: member, defaultGhost: picked));
  }

  Future<void> _setGhostGapVoice(RunController runs, bool enabled) async {
    final member = runs.currentOwner;
    if (_savingRunSettings || !runs.voiceSettings.enabled || member == null) return;
    await _saveRunSettings(runs, RunSettingsChanged(owner: member, ghostGapEnabled: enabled));
  }

  Future<void> _setRunOption(RunController runs, {bool? autoPauseEnabled, bool? keepScreenOn}) async {
    final member = runs.currentOwner;
    if (_savingRunSettings || member == null) return;
    await _saveRunSettings(runs, RunSettingsChanged(
      owner: member, autoPauseEnabled: autoPauseEnabled, keepScreenOn: keepScreenOn,
    ));
  }

  Future<void> _saveRunSettings(RunController runs, RunSettingsChanged change) async {
    if (_savingRunSettings) return;
    setState(() => _savingRunSettings = true);
    try {
      final saved = await runs.receiveSettings(change);
      if (!saved && mounted) {
        showError(context, StateError('account changed'), message: '계정이 변경되어 설정을 적용하지 못했어요. 다시 시도해 주세요.');
      }
    } catch (error) {
      if (mounted) showError(context, error, message: '러닝 설정을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _savingRunSettings = false);
    }
  }

  static String _voiceLabel(RunVoiceSettings voice) => !voice.enabled
      ? '안내 안 함'
      : voice.unit == VoiceUnit.distance
      ? '${voice.distanceKm}km마다'
      : '${voice.timeMinutes}분마다';

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider).value;
    final runs = ref.watch(runControllerProvider);
    final infoPublic = _infoPublic ?? me?.infoPublic;
    final searchable = _searchable ?? me?.profileSearchable;
    // 내 정보를 받기 전이나 저장하는 동안은 공개 여부를 바꾸지 못한다
    final canSave = me != null && !_savingSettings;
    final expiringSoon = _expiringSoon ?? ref.watch(courseExpiringSoonProvider).value;
    String? granted(AppPermission p) => switch (_permissions?[p]) {
      true => '허용됨',
      false => '허용 안 함',
      null => null,
    };
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '설정', onBack: () => context.pop()),
      body: ListView(
        // 칸 제목마다 위로 16 띄우므로 맨 위는 Figma 20에서 그만큼 뺀다
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s4, WdSpace.s24, WdSpace.s24),
        children: [
          const SettingsHeading('계정'),
          SettingsCard([
            SettingsRow('닉네임', value: me?.nickname ?? '—', onTap: () => context.push(Routes.myProfileEdit)),
            SettingsRow('연결된 소셜 계정', value: me?.socialProvider?.label ?? '—'),
          ]),
          const SettingsHeading('권한'),
          SettingsCard([
            for (final p in AppPermission.values)
              SettingsRow(p.label, value: granted(p), onTap: () => ref.read(devicePermissionsProvider).openSettings()),
          ]),
          const SettingsHeading('러닝'),
          SettingsCard([
            ListenableBuilder(
              listenable: runs,
              builder: (context, _) =>
                  SettingsRow('오디오 안내', value: _voiceLabel(runs.voiceSettings), onTap: _savingRunSettings || runs.currentOwner == null ? null : () => _editVoice(runs)),
            ),
            ListenableBuilder(
              listenable: runs,
              builder: (context, _) => SettingsRow('자동 일시정지',
                toggle: runs.settings.autoPauseEnabled,
                onToggle: !_savingRunSettings && runs.currentOwner != null ? (on) => _setRunOption(runs, autoPauseEnabled: on) : null,
                help: '10초간 멈추면 일시정지해요.\n움직이면 다시 시작해요.',
              ),
            ),
            ListenableBuilder(
              listenable: runs,
              builder: (context, _) => SettingsRow('화면 항상 켜기',
                toggle: runs.settings.keepScreenOn,
                onToggle: !_savingRunSettings && runs.currentOwner != null ? (on) => _setRunOption(runs, keepScreenOn: on) : null,
                help: '러닝 중 앱을 보고 있을 때 화면을 켜 둬요.',
              ),
            ),
          ]),
          const SettingsHeading('고스트 · 대결'),
          SettingsCard([
            ListenableBuilder(
              listenable: runs,
              builder: (context, _) => SettingsRow('기본 고스트',
                value: defaultGhostLabel(runs.settings.defaultGhost),
                onTap: _savingRunSettings || runs.currentOwner == null ? null : () => _editDefaultGhost(runs),
              ),
            ),
            ListenableBuilder(
              listenable: runs,
              builder: (context, _) => SettingsRow(
                ghostGapVoiceSettingLabel,
                toggle: runs.voiceSettings.ghostGapEnabled,
                onToggle: runs.voiceSettings.enabled && runs.currentOwner != null && !_savingRunSettings
                    ? (enabled) => _setGhostGapVoice(runs, enabled)
                    : null,
                help: runs.voiceSettings.enabled ? null : '음성 안내를 켜면 사용할 수 있어요',
              ),
            ),
          ]),
          // 이 스위치는 휴대폰에 띄울지만 정한다. 꺼도 알림함에는 쌓인다(Figma AD7 메모)
          const SettingsHeading('푸시 알림'),
          SettingsCard([
            SettingsRow(
              '내 코스 만료 임박',
              toggle: expiringSoon ?? false,
              onToggle: expiringSoon != null && !_savingNotification ? _setExpiringSoon : null,
              help: _permissions?[AppPermission.notification] == false
                  ? '휴대폰 알림 권한이 꺼져 있어 받을 수 없어요.\n위 권한의 알림을 눌러 켜 주세요.'
                  : '등록한 코스가 만료되기 7일 전 · 1일 전에 알려 드려요.',
            ),
          ]),
          const SettingsHeading('공개 여부'),
          SettingsCard([
            SettingsRow(
              '내 정보 공개',
              toggle: infoPublic ?? false,
              onToggle: canSave ? (on) => _saveSettings(me, infoPublic: on) : null,
              help: '켜면 랭킹에 내 기록이 보이고, 고스트로도 쓰일 수 있어요.\n실시간 위치는 공개되지 않아요.',
            ),
            SettingsRow(
              '프로필 검색 허용',
              toggle: searchable ?? false,
              onToggle: canSave ? (on) => _saveSettings(me, searchable: on) : null,
              help: '끄면 러너 검색 결과에 내 프로필이 나오지 않아요.',
            ),
          ]),
          const SettingsHeading('정보'),
          SettingsCard([
            SettingsRow('버전', value: ref.watch(appVersionProvider).value ?? '—'),
            SettingsRow('약관 및 개인정보 처리방침', onTap: () => context.push(Routes.myTerms)),
            SettingsRow('회원 탈퇴', onTap: _withdrawing ? null : _withdraw),
          ]),
          const SizedBox(height: WdSpace.s16),
          Text(
            '기기를 바꿔도 같은 소셜 계정으로 로그인하면 기록이 그대로 복구돼요',
            textAlign: TextAlign.center,
            style: WdText.label12.copyWith(color: WdColors.muted),
          ),
          const SizedBox(height: WdSpace.s8),
          Center(
            child: TextButton(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              child: Text('로그아웃', style: WdText.ko16Bold.copyWith(color: WdColors.warning)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 칸 제목(16 Bold · muted). 위 칸과 16 띄운다.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WdSpace.s16, bottom: WdSpace.s16),
    child: Text(title, style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
  );
}

/// soft 카드 안의 줄들. 줄 사이에 구분선.
class SettingsCard extends StatelessWidget {
  const SettingsCard(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => WdSurface(
    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 2),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, color: WdColors.map),
          rows[i],
        ],
      ],
    ),
  );
}

/// 설정 한 줄(Figma List row, 높이 58): 이름 + 값 + `›`, 또는 이름 + 스위치.
/// [toggle]이 있는데 [onToggle]이 없으면 흐린 스위치로 잠근다. [help]는 줄 아래 작은 안내.
class SettingsRow extends StatelessWidget {
  const SettingsRow(this.label, {super.key, this.value, this.onTap, this.toggle, this.onToggle, this.help});

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool? toggle;
  final ValueChanged<bool>? onToggle;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final small = WdText.raw(12, FontWeight.w400, 20).copyWith(color: WdColors.muted);
    final row = SizedBox(
      height: 58,
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.ink),
            ),
          ),
          if (value != null) Text(value!, style: small),
          if (toggle != null)
            Opacity(
              opacity: onToggle == null ? 0.4 : 1,
              child: WdSwitch(value: toggle!, onChanged: onToggle),
            )
          else if (onTap != null)
            Text('›', style: small),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        onTap == null ? row : InkWell(onTap: onTap, child: row),
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(bottom: WdSpace.s12),
            child: Text(help!, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
          ),
      ],
    );
  }
}
