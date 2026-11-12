import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/api/region_api_client.dart';
import '../../core/region_search.dart';
import 'birth_year_sheet.dart';

/// 닉네임이 서버 규칙(2~10자, 한글 · 영문 · 숫자)에 어긋나면 안내 문구. 비었으면 null이다. F2 · F6가 같이 쓴다.
String? nicknameProblem(String value) {
  if (value.isEmpty) return null;
  if (!RegExp(r'^[가-힣a-zA-Z0-9]+$').hasMatch(value)) return '한글 · 영문 · 숫자만 쓸 수 있어요';
  if (value.length < 2) return '2자 이상 입력해 주세요';
  return null;
}

enum PhotoAction { pick, remove }

/// 사진 변경 시트. 앨범에서 고르기, 지금 사진이 있으면 사진 삭제도 고른다. F2 · F6가 같이 쓴다.
Future<PhotoAction?> showPhotoActionSheet(BuildContext context, {required bool hasPhoto}) =>
    showModalBottomSheet<PhotoAction>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('앨범에서 고르기', style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
              onTap: () => Navigator.pop(context, PhotoAction.pick),
            ),
            if (hasPhoto)
              ListTile(
                title: Text('사진 삭제', style: WdText.ko16Bold.copyWith(color: WdColors.warningText)),
                onTap: () => Navigator.pop(context, PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

/// F2 프로필 초기 설정과 F6 프로필 편집이 같이 쓰는 칸(닉네임 · 소개 · 활동 지역 · 소속 · 러닝 경력 · 신체 정보)의
/// 값과 규칙. 칸 규칙은 두 화면이 같다(정책 공통 9).
mixin ProfileForm<T extends StatefulWidget> on State<T> {
  final nickname = TextEditingController();
  final bio = TextEditingController();
  final region = TextEditingController();
  final affiliation = TextEditingController();
  final birthYearText = TextEditingController();
  final height = TextEditingController();
  final weight = TextEditingController();
  Region? selectedRegion;
  RunningExperience? experience;
  bool bodyAgreed = false;
  int? birthYear;
  Gender? gender;

  @override
  void dispose() {
    for (final field in [nickname, bio, region, affiliation, birthYearText, height, weight]) {
      field.dispose();
    }
    super.dispose();
  }

  static String regionText(Region? region) => region == null ? '' : '${region.province} ${region.name}';

  static String? blankToNull(String value) => value.trim().isEmpty ? null : value.trim();

  String get nicknameValue => nickname.text.trim();

  /// 동의했고 네 값이 모두 범위 안이면 보낼 신체 정보.
  BodyInfo? get bodyInfo {
    final heightCm = int.tryParse(height.text.trim());
    final weightKg = int.tryParse(weight.text.trim());
    if (!bodyAgreed || birthYear == null || gender == null || heightCm == null || weightKg == null) return null;
    if (!BodyInfo.isValidHeight(heightCm) || !BodyInfo.isValidWeight(weightKg)) return null;
    return BodyInfo(birthYear: birthYear!, heightCm: heightCm, weightKg: weightKg, gender: gender!);
  }

  /// 키·체중을 넣었는데 범위 밖이면 안내한다.
  String? get bodyProblem {
    bool outOfRange(TextEditingController field, bool Function(int) valid) {
      final value = int.tryParse(field.text.trim());
      return field.text.trim().isNotEmpty && (value == null || !valid(value));
    }

    return outOfRange(height, BodyInfo.isValidHeight) || outOfRange(weight, BodyInfo.isValidWeight)
        ? '키는 100~250cm, 체중은 20~300kg으로 입력해 주세요'
        : null;
  }

  /// 필수 칸(닉네임 · 활동 지역 · 러닝 경력)을 채웠고, 신체 정보에 동의했으면 네 값을 모두 넣었다.
  bool get profileValid =>
      nicknameValue.isNotEmpty &&
      nicknameProblem(nicknameValue) == null &&
      selectedRegion != null &&
      experience != null &&
      (!bodyAgreed || bodyInfo != null);

  /// 동의를 끄면 넣은 신체 정보를 비운다.
  void setBodyAgreed(bool agreed) => setState(() {
        bodyAgreed = agreed;
        if (agreed) return;
        birthYear = null;
        gender = null;
        birthYearText.clear();
        height.clear();
        weight.clear();
      });

  Future<void> pickBirthYear() async {
    final year = await showBirthYearSheet(context, selected: birthYear);
    if (year != null) {
      setState(() {
        birthYear = year;
        birthYearText.text = '$year년생';
      });
    }
  }

  Future<void> pickRegion() async {
    final picked = await RegionPickScreen.open(context);
    if (picked != null) {
      setState(() {
        selectedRegion = picked;
        region.text = regionText(picked);
      });
    }
  }

  Widget experienceChips() => Row(
        spacing: WdSpace.s6,
        children: [
          for (final value in RunningExperience.values)
            WdFilterChip(
              value.label,
              height: 36,
              selected: experience == value,
              onTap: () => setState(() => experience = value),
            ),
        ],
      );

  /// 신체 정보 칸(동의 · 출생연도 · 키 · 체중 · 성별 · 안내). [note]는 값에 문제가 없을 때 아래에 보이는 안내다.
  Widget bodyInfoFields({required TextStyle helper, required String note}) {
    final problem = bodyAgreed ? bodyProblem : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s12,
      children: [
        WdConsentRow(label: '[선택] 신체 정보 수집 및 이용', checked: bodyAgreed, onChanged: setBodyAgreed),
        // 동의 전에는 흐리게 두고 입력을 받지 않는다(Figma F2).
        IgnorePointer(
          ignoring: !bodyAgreed,
          child: Opacity(
            opacity: bodyAgreed ? 1 : 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s12,
              children: [
                WdTextField(soft: true, controller: birthYearText, hintText: '출생연도를 선택하세요', onTap: pickBirthYear),
                Row(
                  spacing: WdSpace.s8,
                  children: [
                    for (final (field, hint, unit) in [(height, '키 (cm)', 'cm'), (weight, '체중 (kg)', 'kg')])
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
                    for (final value in Gender.values)
                      WdFilterChip(
                        value.label,
                        height: 36,
                        selected: gender == value,
                        onTap: () => setState(() => gender = value),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Text(problem ?? note, style: helper.copyWith(color: problem == null ? WdColors.muted : WdColors.warningText)),
      ],
    );
  }
}
