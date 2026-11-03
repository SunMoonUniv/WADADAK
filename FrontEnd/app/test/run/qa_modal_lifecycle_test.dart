import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/presentation/course_deviation_alert.dart';

void main() {
  testWidgets('QA removing deviation host preserves another dialog above it', (
    tester,
  ) async {
    final result = ValueNotifier(false);
    addTearDown(result.dispose);
    var callbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: result,
          builder: (context, ended, _) => ended
              ? const Scaffold(body: Text('러닝 결과'))
              : CourseDeviationAlert(
                  open: true,
                  onConfirm: () => callbacks++,
                  onMute: () => callbacks++,
                  child: const Scaffold(body: Text('기록 중')),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('확인'));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('별도 안내'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    result.value = true;
    await tester.pumpAndSettle();
    expect(find.text('별도 안내'), findsOneWidget);
    expect(callbacks, 0);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('코스를 벗어났어요'), findsNothing);
    expect(find.text('러닝 결과'), findsOneWidget);
    expect(callbacks, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'QA replacing running view with result removes the deviation modal and its callbacks',
    (tester) async {
      var confirmed = 0, muted = 0;
      final showingResult = ValueNotifier(false);
      addTearDown(showingResult.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showingResult,
            builder: (context, result, _) => result
                ? const Scaffold(body: Text('러닝 결과'))
                : CourseDeviationAlert(
                    open: true,
                    onConfirm: () => confirmed++,
                    onMute: () => muted++,
                    child: const Scaffold(body: Text('기록 중')),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('코스를 벗어났어요'), findsOneWidget);
      // E.g. required permission is revoked while the popup is displayed.
      showingResult.value = true;
      await tester.pumpAndSettle();
      expect(find.text('러닝 결과'), findsOneWidget);
      expect(
        find.text('코스를 벗어났어요'),
        findsNothing,
        reason:
            'A course alert must close when its recording screen is removed.',
      );
      expect((confirmed, muted), (0, 0));
    },
  );
}
