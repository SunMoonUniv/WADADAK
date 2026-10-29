import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/member_api_client.dart';
import '../../core/api/region_api_client.dart';
import '../../core/error_message.dart';
import '../../core/region_search.dart';
import '../../core/upload/photo_uploader.dart';
import '../onboarding/birth_year_sheet.dart';
import '../onboarding/profile_setup_screen.dart';
import 'my_screen.dart';

/// F6 · 프로필 편집(Figma `F6 · 프로필 편집`). E3 [편집]에서 연다.
///
/// 칸 규칙은 가입(F2)과 같고, 저장하면 화면 값을 통째로 보낸다(`PUT /members/me`).
/// - 활동 지역은 Figma의 시/도 · 시·군·구 드롭다운 대신 F2처럼 검색으로 고른다. 서버에 지역 목록 API가 없다.
/// - 사진 변경을 누르면 앨범에서 고르기 · 사진 삭제를 고른다.
/// - 닉네임은 30일에 한 번 바꿀 수 있어서, 아직 못 바꾸면 칸을 잠그고 다음 변경 가능 날짜를 보인다.
/// - 바꾼 게 있는데 저장하지 않고 나가면 한 번 묻는다.
/// (2026-10-29 사용자 결정)
class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    // 저장 뒤 다시 받는 동안에도 이전 값으로 폼을 그대로 둔다
    if (profile.value case final me?) return _ProfileEditForm(me: me);
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '프로필 편집', onBack: () => context.pop()),
      body: Center(
        child: profile.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('내 정보를 불러오지 못했어요.', style: WdText.body13.copyWith(color: WdColors.muted)),
                  TextButton(
                    onPressed: () => ref.invalidate(myProfileProvider),
                    child: Text('다시 불러오기', style: WdText.body13Bold.copyWith(color: WdColors.green)),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

enum _PhotoAction { pick, remove }

class _ProfileEditForm extends ConsumerStatefulWidget {
  const _ProfileEditForm({required this.me});

  /// 화면을 열 때의 내 정보. 칸의 처음 값이고, 바뀐 게 있는지 이것과 비교한다.
  final MyProfile me;

  @override
  ConsumerState<_ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends ConsumerState<_ProfileEditForm> {
  late final MyProfile _me = widget.me;
  late final _nickname = TextEditingController(text: _me.nickname);
  late final _bio = TextEditingController(text: _me.bio ?? '');
  late final _region = TextEditingController(text: _regionText(_me.region));
  late final _affiliation = TextEditingController(text: _me.affiliation ?? '');
  late final _birthYearText =
      TextEditingController(text: _me.bodyInfo == null ? '' : '${_me.bodyInfo!.birthYear}년생');
  late final _height = TextEditingController(text: _me.bodyInfo?.heightCm.toString() ?? '');
  late final _weight = TextEditingController(text: _me.bodyInfo?.weightKg.toString() ?? '');
  late Region? _selectedRegion = _me.region;
  late RunningExperience? _experience = _me.runningExperience;
  late bool _bodyAgreed = _me.bodyInfo != null;
  late int? _birthYear = _me.bodyInfo?.birthYear;
  late Gender? _gender = _me.bodyInfo?.gender;

  /// 새로 고른 사진. 저장할 때 올린다.
  XFile? _photo;
  Uint8List? _photoBytes;

  /// 지금 사진을 지웠다. 저장하면 사진 키를 null로 보낸다.
  bool _photoRemoved = false;

  /// 이미 올린 새 사진의 키. 저장이 실패해 다시 누르면 다시 올리지 않는다(올린 파일은 1시간 동안 남는다).
  String? _uploadedKey;

  /// 서버가 알려 준 닉네임 오류(중복 · 30일 규칙).
  String? _nicknameError;
  bool _saving = false;

  /// 화면을 열 때의 값. [_dirty]가 이것과 비교한다.
  late final Object _initial;

  @override
  void initState() {
    super.initState();
    _initial = _values;
  }

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

  static String _regionText(Region? region) => region == null ? '' : '${region.province} ${region.name}';

  static String? _blankToNull(String value) => value.trim().isEmpty ? null : value.trim();

  String get _nicknameValue => _nickname.text.trim();

  /// 닉네임을 다시 바꿀 수 있는 날이 아직 오지 않았으면 그 시각.
  DateTime? get _nicknameLockedUntil {
    final at = _me.nicknameChangeableAt;
    return at != null && at.isAfter(DateTime.now()) ? at : null;
  }

  /// 칸의 값을 모은 것. 레코드라 값이 같으면 같다.
  Object get _values => (
        _nicknameValue,
        _blankToNull(_bio.text),
        _selectedRegion?.code,
        _blankToNull(_affiliation.text),
        _experience,
        _photo != null || _photoRemoved,
        _bodyAgreed,
        _birthYear,
        _height.text.trim(),
        _weight.text.trim(),
        _gender,
      );

  bool get _dirty => _values != _initial;

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

  bool get _canSave =>
      !_saving &&
      _dirty &&
      _nicknameValue.isNotEmpty &&
      nicknameProblem(_nicknameValue) == null &&
      _selectedRegion != null &&
      _experience != null &&
      (!_bodyAgreed || _bodyInfo != null);

  /// 동의를 끄면 넣은 신체 정보를 비운다. 이대로 저장하면 서버에서도 지워진다.
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
        _region.text = _regionText(region);
      });
    }
  }

  bool get _hasPhoto => _photoBytes != null || (!_photoRemoved && _me.profileImageUrl != null);

  Future<void> _changePhoto() async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('앨범에서 고르기', style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
              onTap: () => Navigator.pop(context, _PhotoAction.pick),
            ),
            if (_hasPhoto)
              ListTile(
                title: Text('사진 삭제', style: WdText.ko16Bold.copyWith(color: WdColors.warningText)),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case _PhotoAction.pick:
        await _pickPhoto();
      case _PhotoAction.remove:
        setState(() {
          _photo = _photoBytes = _uploadedKey = null;
          _photoRemoved = true;
        });
      case null:
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
          _photoRemoved = false;
          _uploadedKey = null;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _nicknameError = null;
    });
    try {
      final api = ref.read(memberApiClientProvider);
      if (_photo != null) _uploadedKey ??= await ref.read(photoUploaderProvider).upload(_photo!, api.photoUploadForm);
      await api.editProfile(
        nickname: _nicknameValue,
        bio: _blankToNull(_bio.text),
        regionCode: _selectedRegion!.code,
        affiliation: _blankToNull(_affiliation.text),
        runningExperience: _experience!,
        profileImageKey: _photo != null ? _uploadedKey : (_photoRemoved ? null : _me.profileImageKey),
        bodyInfo: _bodyInfo,
      );
      if (!mounted) return;
      // E3가 새 값을 다시 받는다
      ref.invalidate(myProfileProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('프로필을 저장했어요.')));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'MEMBER-006' || 'MEMBER-010':
          setState(() => _nicknameError = e.message);
        default:
          showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 앱 바 뒤로 가기 · 휴대폰 뒤로 가기. 바꾼 게 있으면 묻고 나간다. 저장하는 동안은 나가지 않는다.
  Future<void> _leave() async {
    if (_saving) return;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('저장하지 않고 나갈까요?'),
          content: const Text('바꾼 내용은 저장되지 않아요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 편집')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('나가기')),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final lockedUntil = _nicknameLockedUntil;
    final nicknameMessage = _nicknameError ?? nicknameProblem(_nicknameValue);
    final bodyMessage = _bodyAgreed ? _bodyProblem : null;
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final helper = WdText.raw(12, FontWeight.w400, 17);
    final ImageProvider? photo = _photoBytes != null
        ? MemoryImage(_photoBytes!)
        : (!_photoRemoved && _me.profileImageUrl != null ? NetworkImage(_me.profileImageUrl!) : null);

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: WdColors.paper,
        appBar: WdAppBar(
          title: '프로필 편집',
          onBack: _leave,
          action: WdAppBarAction.button('저장', primary: true, onTap: _canSave ? _save : null),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s16,
              children: [
                Semantics(
                  button: true,
                  label: '사진 변경',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving ? null : _changePhoto,
                    child: Padding(
                      padding: const EdgeInsets.only(top: WdSpace.s6, bottom: 2),
                      child: Column(
                        spacing: WdSpace.s8,
                        children: [
                          WdAvatar(size: 84, image: photo),
                          Text('사진 변경', style: helper.copyWith(color: WdColors.green)),
                        ],
                      ),
                    ),
                  ),
                ),
                Text('닉네임', style: label),
                WdTextField(
                  soft: true,
                  controller: _nickname,
                  hintText: '러너 닉네임을 입력하세요',
                  maxLength: 10,
                  enabled: lockedUntil == null,
                  onChanged: (_) => setState(() => _nicknameError = null),
                ),
                Text(
                  nicknameMessage ??
                      (lockedUntil == null
                          ? '30일에 한 번 바꿀 수 있어요'
                          : '30일에 한 번 바꿀 수 있어요 · 다음 변경 가능 ${_date(lockedUntil)}'),
                  style: helper.copyWith(color: nicknameMessage == null ? WdColors.muted : WdColors.warningText),
                ),
                Text('한 줄 소개', style: label),
                WdTextField(
                  soft: true,
                  controller: _bio,
                  hintText: '러닝 스타일이나 목표를 짧게 적어주세요',
                  maxLength: 50,
                  onChanged: (_) => setState(() {}),
                ),
                Text('활동 지역', style: label),
                WdTextField(soft: true, controller: _region, hintText: '활동 지역을 선택하세요', onTap: _pickRegion),
                Text(
                  '활동 지역은 지역 주간 랭킹 기준이에요. 바꾸면 다음 주부터 반영돼요.',
                  style: helper.copyWith(color: WdColors.muted),
                ),
                Text('소속', style: label),
                WdTextField(
                  soft: true,
                  controller: _affiliation,
                  hintText: '학교 · 회사 · 크루 이름',
                  maxLength: 30,
                  onChanged: (_) => setState(() {}),
                ),
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
                Text('신체 정보', style: label),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: WdSpace.s12,
                  children: [
                    WdConsentRow(label: '[선택] 신체 정보 수집 및 이용', checked: _bodyAgreed, onChanged: _setBodyAgreed),
                    // 동의 전에는 흐리게 두고 입력을 받지 않는다(F2와 같다).
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
                      bodyMessage ?? '칼로리 계산에만 쓰고 다른 러너에게 보이지 않아요.\n동의를 끄고 저장하면 지워져요.',
                      style: helper.copyWith(color: bodyMessage == null ? WdColors.muted : WdColors.warningText),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 서버가 주는 시각은 한국 날짜 00:00이라 한국 시간으로 날짜를 적는다. 예: 2026.11.28
  static String _date(DateTime at) {
    final kst = at.toUtc().add(const Duration(hours: 9));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${kst.year}.${two(kst.month)}.${two(kst.day)}';
  }
}
