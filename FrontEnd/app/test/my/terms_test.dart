import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wadadak/features/my/terms_screen.dart';
import 'package:wadadak/features/terms/terms_doc_screen.dart';
import 'package:wadadak/features/terms/terms_docs.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  /// E3(글자만) 위에 F7을 연다. 본문은 앱 라우터처럼 `/terms/:doc`로 연다.
  Future<void> openTerms(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: Routes.my,
      routes: [
        GoRoute(path: Routes.my, builder: (_, _) => const Scaffold(body: Text('E3'))),
        GoRoute(path: Routes.myTerms, builder: (_, _) => const TermsScreen()),
        GoRoute(
          path: '/terms/:doc',
          builder: (_, state) => TermsDocScreen(doc: TermsDoc.values.byName(state.pathParameters['doc']!)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router)),
    );
    await tester.pumpAndSettle();
    router.push(Routes.myTerms);
    await tester.pumpAndSettle();
  }

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '와다닥',
      packageName: 'com.wadadak.app',
      version: '1.0.3',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  testWidgets('F7 lists the three terms, open source licenses and the app version', (tester) async {
    await openTerms(tester);

    expect(find.text('약관 및 정책'), findsOneWidget);
    for (final label in ['서비스 이용약관', '개인정보 처리방침', '위치기반서비스 이용약관', '오픈소스 라이선스']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('1.0.3'), findsOneWidget);
  });

  testWidgets('a terms row opens its text with the version and goes back', (tester) async {
    await openTerms(tester);

    await tester.tap(find.text('개인정보 처리방침'));
    await tester.pumpAndSettle();

    expect(find.text('시행일 ${TermsDoc.effectiveOn} · 버전 ${TermsDoc.version}'), findsOneWidget);
    expect(find.text('1. 수집하는 개인정보'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('뒤로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('오픈소스 라이선스'), findsOneWidget);
  });

  testWidgets('open source licenses open the Flutter license page', (tester) async {
    await openTerms(tester);

    await tester.tap(find.text('오픈소스 라이선스'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('every terms text has sections and the version matches the server agreements', () {
    // 서버 AgreementType의 약관 버전이 "1"이다. 본문을 바꾸면 둘 다 올린다.
    expect(TermsDoc.version, '1');
    for (final doc in TermsDoc.values) {
      expect(doc.sections, isNotEmpty, reason: doc.name);
    }
  });
}
