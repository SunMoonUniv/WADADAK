import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/member_api_client.dart';
import '../../core/api/region_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';
import '../../core/region_search.dart';
import '../../core/upload/photo_uploader.dart';
import 'birth_year_sheet.dart';
import 'consent_screen.dart';

/// 닉네임이 서버 규칙(2~10자, 한글 · 영문 · 숫자)에 어긋나면 안내 문구. 비었으면 null이다. F2 · F6가 같이 쓴다.
String? nicknameProblem(String value) {
  if (value.isEmpty) return null;
  if (!RegExp(r'^[가-힣a-zA-Z0-9]+$').hasMatch(value)) return '한글 · 영문 · 숫자만 쓸 수 있어요';
  if (value.length < 2) return '2자 이상 입력해 주세요';
  return null;
}

/// F2 · 프로필 초기 설정. "시작하기"를 누르면 동의 내용과 함께 가입한다.
/// 프로필 사진은 선택이다. 고른 사진은 가입할 때 올린다.
/// 신체 정보도 선택이다. 동의해야 입력할 수 있고, 동의하면 네 값을 모두 넣어야 시작할 수 있다(정책 공통 9).
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nickname = TextEditingController();
  final _bio = TextEditingController();
  final _region = TextEditingController();
  final _affiliation = TextEditingController();
  final _birthYearText = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  Region? _selectedRegion;
  RunningExperience? _experience;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _bodyAgreed = false;
  int? _birthYear;
  Gender? _gender;

  /// 서버가 알려 준 닉네임 오류(중복).
  String? _nicknameError;
  bool _submitting = false;

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _region.dispose();
    _affiliation.dispose();
    _birthYearText.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  String get _nicknameValue => _nickname.text.trim();

  String? get _nicknameProblem => nicknameProblem(_nicknameValue);

  /// 동의했고 네 값이 모두 범위 안이면 보낼 신체 정보.
  BodyInfo? get _bodyInfo {
    final height = int.tryParse(_height.text.trim());
    final weight = int.tryParse(_weight.text.trim());
    if (!_bodyAgreed || _birthYear == null || _gender == null || height == null || weight == null) return null;
    if (!BodyInfo.isValidHeight(height) || !BodyInfo.isValidWeight(weight)) return null;
    return BodyInfo(birthYear: _birthYear!, heightCm: height, weightKg: weight, gender: _gender!);
  }

  /// 키·체중을 넣었는데 범위 밖이면 안내한다.
  String? get _bodyProblem {
    bool outOfRange(TextEditingController field, bool Function(int) valid) {
      final value = int.tryParse(field.text.trim());
      return field.text.trim().isNotEmpty && (value == null || !valid(value));
    }

    return outOfRange(_height, BodyInfo.isValidHeight) || outOfRange(_weight, BodyInfo.isValidWeight)
        ? '키는 100~250cm, 체중은 20~300kg으로 입력해 주세요'
        : null;
  }

  bool get _ready =>
      _nicknameValue.isNotEmpty &&
      _nicknameProblem == null &&
      _selectedRegion != null &&
      _experience != null &&
      (!_bodyAgreed || _bodyInfo != null);

  /// 동의를 끄면 넣은 신체 정보를 비운다.
  void _setBodyAgreed(bool agreed) => setState(() {
        _bodyAgreed = agreed;
        if (agreed) return;
        _birthYear = null;
        _gender = null;
        _birthYearText.clear();
        _height.clear();
        _weight.clear();
      });

  Future<void> _pickBirthYear() async {
    final year = await showBirthYearSheet(context, selected: _birthYear);
    if (year != null) {
      setState(() {
        _birthYear = year;
        _birthYearText.text = '$year년생';
      });
    }
  }

  Future<void> _pickRegion() async {
    final region = await RegionPickScreen.open(context);
    if (region != null) {
      setState(() {
        _selectedRegion = region;
        _region.text = '${region.province} ${region.name}';
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ref.read(photoUploaderProvider).pick();
      if (picked.isEmpty) return;
      final bytes = await picked.single.readAsBytes();
      if (mounted) {
        setState(() {
          _photo = picked.single;
          _photoBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
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
            photo: _photo,
            bodyInfo: _bodyInfo,
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
    final bodyMessage = _bodyAgreed ? _bodyProblem : null;
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
              // 원을 누르면 고르고(다시 누르면 바꾸고), 고른 뒤에는 아래 글자로 뺀다.
              Center(
                child: Semantics(
                  button: true,
                  label: '프로필 사진 고르기',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: _submitting ? null : _pickPhoto,
                    child: ClipOval(
                      child: SizedBox.square(
                        dimension: 84,
                        child: _photoBytes != null
                            ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                            : ColoredBox(
                                color: WdColors.soft,
                                child: Center(child: Text('＋', style: WdText.raw(28, FontWeight.w300).copyWith(color: WdColors.ink))),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: _photo == null
                    ? Text('프로필 사진 추가', style: helper.copyWith(color: WdColors.green))
                    : GestureDetector(
                        onTap: _submitting ? null : () => setState(() => _photo = _photoBytes = null),
                        child: Text('사진 빼기', style: helper.copyWith(color: WdColors.green)),
                      ),
              ),
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
              Text('신체 정보 (선택)', style: label),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s12,
                children: [
                  WdConsentRow(label: '[선택] 신체 정보 수집 및 이용', checked: _bodyAgreed, onChanged: _setBodyAgreed),
                  // 동의 전에는 흐리게 두고 입력을 받지 않는다(Figma F2).
                  IgnorePointer(
                    ignoring: !_bodyAgreed,
                    child: Opacity(
                      opacity: _bodyAgreed ? 1 : 0.4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: WdSpace.s12,
                        children: [
                          WdTextField(
                              soft: true, controller: _birthYearText, hintText: '출생연도를 선택하세요', onTap: _pickBirthYear),
                          Row(
                            spacing: WdSpace.s8,
                            children: [
                              for (final (field, hint, unit) in [(_height, '키 (cm)', 'cm'), (_weight, '체중 (kg)', 'kg')])
                                Expanded(
                                  child: WdTextField(
                                    soft: true,
                                    controller: field,
                                    hintText: hint,
                                    suffixText: unit,
                                    keyboardType: TextInputType.number,
                                    maxLength: 3,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                            ],
                          ),
                          Row(
                            spacing: WdSpace.s6,
                            children: [
                              for (final gender in Gender.values)
                                WdFilterChip(
                                  gender.label,
                                  height: 36,
                                  selected: _gender == gender,
                                  onTap: () => setState(() => _gender = gender),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    bodyMessage ?? '칼로리 계산에만 쓰고 다른 러너에게 보이지 않아요',
                    style: helper.copyWith(color: bodyMessage == null ? WdColors.muted : WdColors.warningText),
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
                      child: Text('활동 지역은 지역 주간 랭킹에 쓰여요.', style: helper.copyWith(color: WdColors.muted)),
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
