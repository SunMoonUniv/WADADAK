import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/member_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';
import 'consent_screen.dart';
import 'regions.dart';

/// F2 · 프로필 초기 설정. "시작하기"를 누르면 동의 내용과 함께 가입한다.
///
/// 프로필 사진은 서버에 사진 업로드(ObjectStorage)가 생기면 추가한다.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  /// 서버 규칙과 같다: 2~10자, 한글 · 영문 · 숫자.
  static final _nicknamePattern = RegExp(r'^[가-힣a-zA-Z0-9]+$');

  final _nickname = TextEditingController();
  final _bio = TextEditingController();
  final _region = TextEditingController();
  final _affiliation = TextEditingController();
  Region? _selectedRegion;
  RunningExperience? _experience;

  /// 서버가 알려 준 닉네임 오류(중복).
  String? _nicknameError;
  bool _submitting = false;

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _region.dispose();
    _affiliation.dispose();
    super.dispose();
  }

  String get _nicknameValue => _nickname.text.trim();

  String? get _nicknameProblem {
    final value = _nicknameValue;
    if (value.isEmpty) return null;
    if (!_nicknamePattern.hasMatch(value)) return '한글 · 영문 · 숫자만 쓸 수 있어요';
    if (value.length < 2) return '2자 이상 입력해 주세요';
    return null;
  }

  bool get _ready =>
      _nicknameValue.isNotEmpty && _nicknameProblem == null && _selectedRegion != null && _experience != null;

  Future<void> _pickRegion() async {
    final region = await showModalBottomSheet<Region>(
      context: context,
      backgroundColor: WdColors.paper,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s12),
          children: [
            Text('활동 지역', style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
            const SizedBox(height: WdSpace.s8),
            for (final region in kRegions)
              WdListRow(label: region.name, onTap: () => Navigator.pop(context, region)),
          ],
        ),
      ),
    );
    if (region != null) {
      setState(() {
        _selectedRegion = region;
        _region.text = region.name;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _nicknameError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signup(
            agreements: ref.read(agreementsProvider),
            nickname: _nicknameValue,
            bio: _blankToNull(_bio.text),
            regionCode: _selectedRegion!.code,
            affiliation: _blankToNull(_affiliation.text),
            runningExperience: _experience!,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'MEMBER-006':
          setState(() => _nicknameError = e.message);
        case 'MEMBER-003' || 'MEMBER-005':
          // 가입 토큰이 만료됐거나 이미 가입된 계정이다. 소셜 로그인부터 다시 한다.
          showError(context, e);
          ref.read(authControllerProvider.notifier).cancelSignup();
        default:
          showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static String? _blankToNull(String value) => value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    ref.watch(agreementsProvider); // 동의 값을 가입할 때까지 유지한다.
    final nicknameMessage = _nicknameError ?? _nicknameProblem;
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final helper = WdText.raw(12, FontWeight.w400, 18);

    return Scaffold(
      appBar: const WdAppBar(title: '프로필 설정'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WdSpace.s16,
            children: [
              Text('닉네임', style: label),
              WdTextField(
                soft: true,
                controller: _nickname,
                hintText: '러너 닉네임을 입력하세요',
                maxLength: 10,
                onChanged: (_) => setState(() => _nicknameError = null),
              ),
              Text(
                nicknameMessage ?? '랭킹과 코스 리뷰에 표시돼요',
                style: helper.copyWith(color: nicknameMessage == null ? WdColors.muted : WdColors.warningText),
              ),
              Text('한 줄 소개 (선택)', style: label),
              WdTextField(soft: true, controller: _bio, hintText: '러닝 스타일이나 목표를 짧게 적어주세요', maxLength: 50),
              Text('활동 지역', style: label),
              WdTextField(soft: true, controller: _region, hintText: '활동 지역을 선택하세요', onTap: _pickRegion),
              Text('소속 (선택)', style: label),
              WdTextField(soft: true, controller: _affiliation, hintText: '학교 · 회사 · 크루 이름', maxLength: 30),
              Text('러닝 경력', style: label),
              Row(
                spacing: WdSpace.s6,
                children: [
                  for (final experience in RunningExperience.values)
                    WdFilterChip(
                      experience.label,
                      height: 36,
                      selected: _experience == experience,
                      onTap: () => setState(() => _experience = experience),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: WdSpace.s8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: WdSpace.s8,
                  children: [
                    const WdIcon(WdIcons.ghostInfo, size: 16),
                    Expanded(
                      child: Text('지역과 소속은 주간 랭킹 그룹을 정하는 데 쓰여요.', style: helper.copyWith(color: WdColors.muted)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: WdBottomBar.pinned(
        primary: WdButton('시작하기', onPressed: _ready && !_submitting ? _submit : null),
      ),
    );
  }
}
