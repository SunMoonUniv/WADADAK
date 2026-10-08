import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';
import 'package:wadadak_design_system_example/main.dart';

// 카탈로그 전체를 한 번씩 그려 레이아웃 예외(무한 제약, 오버플로, 에셋 누락)를 잡는다.
// 테스트 폰트는 실제 글꼴보다 글자 폭이 넓어서 화면 폭을 넉넉히 둔다.
void main() {
  testWidgets('카탈로그의 모든 컴포넌트가 예외 없이 그려진다', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const CatalogApp());
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 30; i++) {
      await tester.drag(list, const Offset(0, -800));
      await tester.pumpAndSettle();
    }
    // 레이아웃 예외는 프레임워크가 위젯 위치와 함께 보고하며 테스트를 실패시킨다.
    expect(find.byType(WdSegmentTable), findsOneWidget);
  });
}
