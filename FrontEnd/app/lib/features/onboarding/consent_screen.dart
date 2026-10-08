import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../routes.dart';

/// 동의 화면에서 고른 값. 가입을 마치거나 그만두면 버린다.
final agreementsProvider = NotifierProvider.autoDispose<AgreementsNotifier, Agreements>(AgreementsNotifier.new);

class AgreementsNotifier extends Notifier<Agreements> {
  @override
  Agreements build() => const Agreements();

  void set(Agreements value) => state = value;
}

/// 소셜 정보 동의. 뒤로 가면 가입을 그만두고 로그인 화면으로 돌아간다.
class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agreements = ref.watch(agreementsProvider);
    final provider = switch (ref.watch(authControllerProvider).value) {
      SignupRequired(:final provider) => provider,
      _ => SocialProvider.kakao,
    };
    void set(Agreements value) => ref.read(agreementsProvider.notifier).set(value);
    void cancel() => ref.read(authControllerProvider.notifier).cancelSignup();

    // 약관 본문(F7)이 준비되면 각 줄의 onView로 "보기 ›"를 연결한다.
    final rows = <(String, bool, Agreements Function(bool))>[
      ('[필수] 만 14세 이상입니다', agreements.over14, (v) => agreements.copyWith(over14: v)),
      ('[필수] 서비스 이용약관', agreements.serviceTerms, (v) => agreements.copyWith(serviceTerms: v)),
      ('[필수] 개인정보 수집 및 이용', agreements.privacyPolicy, (v) => agreements.copyWith(privacyPolicy: v)),
      ('[필수] 위치기반서비스 이용약관', agreements.locationTerms, (v) => agreements.copyWith(locationTerms: v)),
      ('[필수] 프로필 정보 (닉네임 · 프로필 사진)', agreements.profileInfo, (v) => agreements.copyWith(profileInfo: v)),
      (
        '[선택] ${provider == SocialProvider.google ? 'Google' : '카카오'} 계정 이메일 제공',
        agreements.email,
        (v) => agreements.copyWith(email: v),
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel();
      },
      child: Scaffold(
        appBar: WdAppBar(title: '서비스 이용 동의', onBack: cancel),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, 48, WdSpace.s24, WdSpace.s24),
          children: [
            Text('와다닥과 함께\n달릴 준비가 됐나요?', style: WdText.raw(28, FontWeight.w700, 41).copyWith(color: WdColors.ink)),
            const SizedBox(height: WdSpace.s16),
            Text(
              '서비스 이용을 위해 아래 내용을 확인해 주세요.',
              style: WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.muted),
            ),
            const SizedBox(height: WdSpace.s16),
            Column(
              spacing: WdSpace.s8,
              children: [
                WdConsentRow(label: '전체 동의하기', checked: agreements.all, onChanged: (v) => set(Agreements.all(v))),
                for (final (label, checked, toggle) in rows)
                  WdConsentRow(label: label, checked: checked, onChanged: (v) => set(toggle(v))),
              ],
            ),
            const SizedBox(height: WdSpace.s16),
            Text(
              agreements.allRequired ? '선택 항목에 동의하지 않아도 서비스를 이용할 수 있어요.' : '필수 항목에 모두 동의해야 계속할 수 있어요.',
              style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(WdSpace.s24),
          child: WdButton(
            '동의하고 계속하기',
            onPressed: agreements.allRequired ? () => context.push(Routes.permission) : null,
          ),
        ),
      ),
    );
  }
}
