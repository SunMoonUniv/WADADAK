import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/presentation/ghost_start_rejected_alert.dart';

void main() {
  testWidgets(
    'refusal shows once at narrow width and confirmation returns to selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final message = ValueNotifier<String?>('refused');
      addTearDown(message.dispose);
      var confirmations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String?>(
            valueListenable: message,
            builder: (context, value, _) => GhostStartRejectedAlert(
              message: value,
              onConfirm: () {
                confirmations++;
                message.value = null;
              },
              child: const Scaffold(body: Text('다른 기록 선택')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('사용할 수 없는 고스트입니다.'), findsOneWidget);
      expect(find.text('다른 기록을 선택해 주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(confirmations, 1);
      expect(find.text('사용할 수 없는 고스트입니다.'), findsNothing);
      expect(find.text('다른 기록 선택'), findsOneWidget);
    },
  );

  testWidgets('account reset removes an old refusal without confirming it', (
    tester,
  ) async {
    final message = ValueNotifier<String?>('refused');
    addTearDown(message.dispose);
    var confirmations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String?>(
          valueListenable: message,
          builder: (context, value, _) => GhostStartRejectedAlert(
            message: value,
            onConfirm: () => confirmations++,
            child: const Scaffold(body: Text('준비')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    message.value = null;
    await tester.pumpAndSettle();
    expect(find.text('확인'), findsNothing);
    expect(confirmations, 0);
    expect(tester.takeException(), isNull);
  });
}
