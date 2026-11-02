import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'terms_docs.dart';

/// 약관 본문 하나. F7 약관 및 정책과 가입 동의 화면의 `보기 ›`에서 연다.
/// Figma에는 본문 화면이 없어 F4 · F7처럼 흰 바탕에 조 제목과 본문을 차례로 둔다.
class TermsDocScreen extends StatelessWidget {
  const TermsDocScreen({super.key, required this.doc});

  final TermsDoc doc;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.paper,
    appBar: WdAppBar(title: doc.title, onBack: () => context.pop()),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
      children: [
        Text(
          '시행일 ${TermsDoc.effectiveOn} · 버전 ${TermsDoc.version}',
          style: WdText.label12.copyWith(color: WdColors.muted),
        ),
        for (final (title, body) in doc.sections) ...[
          const SizedBox(height: WdSpace.s24),
          Text(title, style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
          const SizedBox(height: WdSpace.s8),
          Text(body, style: WdText.raw(14, FontWeight.w400, 22).copyWith(color: WdColors.ink)),
        ],
      ],
    ),
  );
}
