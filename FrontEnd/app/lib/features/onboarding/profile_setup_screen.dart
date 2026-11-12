import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';
import '../../core/upload/photo_uploader.dart';
import 'consent_screen.dart';
import 'profile_form.dart';

/// F2 · 프로필 초기 설정. "시작하기"를 누르면 동의 내용과 함께 가입한다.
/// 프로필 사진은 선택이다. 고른 사진은 가입할 때 올린다.
/// 신체 정보도 선택이다. 동의해야 입력할 수 있고, 동의하면 네 값을 모두 넣어야 시작할 수 있다(정책 공통 9).
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> with ProfileForm<ProfileSetupScreen> {
  XFile? _photo;
  Uint8List? _photoBytes;

  /// 서버가 알려 준 닉네임 오류(중복).
  String? _nicknameError;
  bool _submitting = false;

  Future<void> _changePhoto() async {
    final action = await showPhotoActionSheet(context, hasPhoto: _photo != null);
    switch (action) {
      case PhotoAction.pick:
        await _pickPhoto();
      case PhotoAction.remove:
        setState(() => _photo = _photoBytes = null);
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
            nickname: nicknameValue,
            bio: ProfileForm.blankToNull(bio.text),
            regionCode: selectedRegion!.code,
            affiliation: ProfileForm.blankToNull(affiliation.text),
            runningExperience: experience!,
            photo: _photo,
            bodyInfo: bodyInfo,
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

  @override
  Widget build(BuildContext context) {
    ref.watch(agreementsProvider); // 동의 값을 가입할 때까지 유지한다.
    final nicknameMessage = _nicknameError ?? nicknameProblem(nicknameValue);
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final helper = WdText.raw(12, FontWeight.w400, 18);
    final photoLabel = _photo == null ? '프로필 사진 추가' : '사진 변경';

    return Scaffold(
      appBar: const WdAppBar(title: '프로필 설정'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WdSpace.s16,
            children: [
              // 원이나 아래 글자를 누르면 앨범에서 고르기 · 사진 삭제를 고른다(F6와 같다).
              Semantics(
                button: true,
                label: photoLabel,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _submitting ? null : _changePhoto,
                  child: Column(
                    spacing: WdSpace.s16,
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: 84,
                          child: _photoBytes != null
                              ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                              : ColoredBox(
                                  color: WdColors.soft,
                                  child: Center(
                                      child: Text('＋', style: WdText.raw(28, FontWeight.w300).copyWith(color: WdColors.ink))),
                                ),
                        ),
                      ),
                      Text(photoLabel, style: helper.copyWith(color: WdColors.green)),
                    ],
                  ),
                ),
              ),
              Text('닉네임', style: label),
              WdTextField(
                soft: true,
                controller: nickname,
                hintText: '러너 닉네임을 입력하세요',
                maxLength: 10,
                onChanged: (_) => setState(() => _nicknameError = null),
              ),
              Text(
                nicknameMessage ?? '랭킹과 코스 리뷰에 표시돼요',
                style: helper.copyWith(color: nicknameMessage == null ? WdColors.muted : WdColors.warningText),
              ),
              Text('한 줄 소개 (선택)', style: label),
              WdTextField(soft: true, controller: bio, hintText: '러닝 스타일이나 목표를 짧게 적어주세요', maxLength: 50),
              Text('활동 지역', style: label),
              WdTextField(soft: true, controller: region, hintText: '활동 지역을 선택하세요', onTap: pickRegion),
              Text('소속 (선택)', style: label),
              WdTextField(soft: true, controller: affiliation, hintText: '학교 · 회사 · 크루 이름', maxLength: 30),
              Text('러닝 경력', style: label),
              experienceChips(),
              Text('신체 정보 (선택)', style: label),
              bodyInfoFields(helper: helper, note: '칼로리 계산에만 쓰고 다른 러너에게 보이지 않아요'),
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
        primary: WdButton('시작하기', onPressed: profileValid && !_submitting ? _submit : null),
      ),
    );
  }
}
