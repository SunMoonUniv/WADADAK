import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';
import '../../routes.dart';
import '../run/application/run_controller.dart';
import '../run/domain/run_voice.dart';
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

/// F4 · 설정(Figma `F4 · 설정`). E3 오른쪽 위 설정 아이콘에서 연다.
///
/// - 계정: 닉네임(누르면 F6) · 연결된 소셜 계정. 이메일 줄은 두지 않는다(2026-10-20 결정).
/// - 권한: 휴대폰 권한 상태. 누르면 휴대폰 설정을 열고, 돌아오면 다시 읽는다.
/// - 오디오 안내는 달리기의 음성 안내 설정이다(기기에 저장). 누르면 F5 시트.
/// - 공개 여부 두 스위치는 바꾸는 즉시 서버에 저장한다(`PUT /members/me/settings`). 실패하면 되돌린다.
/// - 정책이 없는 자동 일시정지 · 화면 항상 켜기 · 기본 고스트 · 구간 격차 음성 안내와
///   약관(F7) · 회원 탈퇴는 보이기만 하고 누르면 준비 중 안내. 거리 단위는 km 고정이라 뺐다.
/// - 내 코스 만료 임박은 알림 기능(F14)이 없어 꺼진 채 잠근다.
/// (2026-10-30 사용자 결정)
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final AppLifecycleListener _lifecycle;
  Map<AppPermission, bool>? _permissions;
  String? _version;

  /// 서버에 저장한(또는 저장 중인) 공개 여부. 없으면 내 정보 값을 쓴다.
  bool? _infoPublic, _searchable;
  bool _savingSettings = false;

  @override
  void initState() {
    super.initState();
    // 휴대폰 설정에서 권한을 바꾸고 돌아오면 다시 읽는다
    _lifecycle = AppLifecycleListener(onResume: _loadPermissions);
    _loadPermissions();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // 못 읽으면 `—`로 둔다
    }
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

  void _soon() => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('준비 중인 기능이에요.')));

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

  Future<void> _editVoice(RunController runs) async {
    final picked = await showVoiceSheet(context, runs.voiceSettings);
    if (picked != null) await runs.saveVoiceSettings(picked);
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
          const _Heading('계정'),
          _Card([
            _Row('닉네임', value: me?.nickname ?? '—', onTap: () => context.push(Routes.myProfileEdit)),
            _Row('연결된 소셜 계정', value: me?.socialProvider?.label ?? '—'),
          ]),
          const _Heading('권한'),
          _Card([
            for (final p in AppPermission.values)
              _Row(p.label, value: granted(p), onTap: () => ref.read(devicePermissionsProvider).openSettings()),
          ]),
          const _Heading('러닝'),
          _Card([
            ListenableBuilder(
              listenable: runs,
              builder: (context, _) =>
                  _Row('오디오 안내', value: _voiceLabel(runs.voiceSettings), onTap: () => _editVoice(runs)),
            ),
            _Row('자동 일시정지', toggle: false, onToggle: (_) => _soon()),
            _Row('화면 항상 켜기', toggle: false, onToggle: (_) => _soon()),
          ]),
          const _Heading('고스트 · 대결'),
          _Card([
            _Row('기본 고스트', onTap: _soon),
            _Row('구간 격차 음성 안내', toggle: false, onToggle: (_) => _soon()),
          ]),
          const _Heading('알림'),
          const _Card([_Row('내 코스 만료 임박', toggle: false, help: '알림 기능이 준비되면 켤 수 있어요.')]),
          const _Heading('공개 여부'),
          _Card([
            _Row(
              '내 정보 공개',
              toggle: infoPublic ?? false,
              onToggle: canSave ? (on) => _saveSettings(me, infoPublic: on) : null,
              help: '켜면 랭킹에 내 기록이 보이고, 고스트로도 쓰일 수 있어요.\n실시간 위치는 공개되지 않아요.',
            ),
            _Row(
              '프로필 검색 허용',
              toggle: searchable ?? false,
              onToggle: canSave ? (on) => _saveSettings(me, searchable: on) : null,
              help: '끄면 러너 검색 결과에 내 프로필이 나오지 않아요.',
            ),
          ]),
          const _Heading('정보'),
          _Card([
            _Row('버전', value: _version ?? '—'),
            _Row('약관 및 개인정보 처리방침', onTap: _soon),
            _Row('회원 탈퇴', onTap: _soon),
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
class _Heading extends StatelessWidget {
  const _Heading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WdSpace.s16, bottom: WdSpace.s16),
    child: Text(title, style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
  );
}

/// soft 카드 안의 줄들. 줄 사이에 구분선.
class _Card extends StatelessWidget {
  const _Card(this.rows);

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
class _Row extends StatelessWidget {
  const _Row(this.label, {this.value, this.onTap, this.toggle, this.onToggle, this.help});

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
