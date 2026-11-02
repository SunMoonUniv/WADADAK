import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../routes.dart';
import '../terms/terms_docs.dart';
import 'settings_screen.dart';

/// F7 · 약관 및 정책(Figma `F7 · 약관 및 정책`). F4 `약관 및 개인정보 처리방침`에서 연다.
///
/// - 세 약관은 앱에 넣은 본문을 연다([TermsDoc]).
/// - 오픈소스 라이선스는 Flutter 기본 라이선스 화면이다. 쓰는 패키지의 라이선스를 알아서 모은다.
/// (2026-11-02 사용자 결정)
class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '약관 및 정책', onBack: () => context.pop()),
      body: ListView(
        // 칸 제목 위로 16 띄우므로 맨 위는 Figma 20에서 그만큼 뺀다(F4와 같다)
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s4, WdSpace.s24, WdSpace.s24),
        children: [
          const SettingsHeading('약관 · 정책'),
          SettingsCard([
            for (final doc in TermsDoc.values)
              SettingsRow(doc.title, onTap: () => context.push(Routes.terms(doc.name))),
            SettingsRow(
              '오픈소스 라이선스',
              onTap: () => showLicensePage(context: context, applicationName: '와다닥', applicationVersion: version),
            ),
            SettingsRow('앱 버전', value: version ?? '—'),
          ]),
        ],
      ),
    );
  }
}
