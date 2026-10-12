import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/run_models.dart';

void main() {
  late Duration tick;
  late FreeRunSession session;
  setUp(() {
    tick = Duration.zero;
    session = FreeRunSession(
      monotonicNow: () => tick,
      utcNow: () => DateTime.utc(2026, 10, 12),
    );
  });

  test('120 seconds with a 20 second pause excludes pause movement', () {
    session.start('sample-v1');
    session.addLocation(const RunPoint(36, 127), accuracyM: 5);
    tick = const Duration(seconds: 10);
    session.addLocation(const RunPoint(36.0001, 127), accuracyM: 5);
    tick = const Duration(seconds: 40);
    session.pause();
    tick = const Duration(seconds: 50);
    session.addLocation(const RunPoint(36.1, 127), accuracyM: 5);
    tick = const Duration(seconds: 60);
    session.resume();
    session.addLocation(const RunPoint(36.1, 127), accuracyM: 5);
    tick = const Duration(seconds: 70);
    session.addLocation(const RunPoint(36.1001, 127), accuracyM: 5);
    tick = const Duration(seconds: 120);
    session.pause();
    session.finish();
    final run = session.snapshot;
    expect(run.elapsed, const Duration(seconds: 120));
    expect(run.active, const Duration(seconds: 100));
    expect(run.distanceMeters, closeTo(22.239016, .001));
    expect(run.inputs.map((p) => p.seq), List.generate(10, (i) => i));
    expect(run.inputs.first.elapsedMs, 0);
    expect(run.inputs.last.toJson()['kind'], 'END');
  });

  test(
    'multiple pauses keep total time running and freeze the ended result',
    () {
      session.start('time');
      tick = const Duration(seconds: 10);
      session.pause();
      tick = const Duration(seconds: 20);
      expect(session.snapshot.elapsed.inSeconds, 20);
      expect(session.snapshot.active.inSeconds, 10);
      session.resume();
      tick = const Duration(seconds: 30);
      session.pause();
      tick = const Duration(seconds: 40);
      session.finish();
      tick = const Duration(seconds: 100);
      expect(session.snapshot.elapsed.inSeconds, 40);
      expect(session.snapshot.active.inSeconds, 20);
    },
  );

  test('gap and poor accuracy break distance continuity', () {
    session.start('gap');
    session.addLocation(const RunPoint(36, 127), accuracyM: 5);
    tick = const Duration(seconds: 1);
    session.addGap();
    tick = const Duration(seconds: 2);
    session.addLocation(const RunPoint(36.1, 127), accuracyM: 5);
    tick = const Duration(seconds: 3);
    session.addLocation(const RunPoint(36.2, 127), accuracyM: 100);
    tick = const Duration(seconds: 4);
    session.addLocation(const RunPoint(36.2001, 127), accuracyM: 5);
    expect(session.snapshot.distanceMeters, 0);
    expect(session.snapshot.paceSecondsPerKm, isNull);
  });

  test('invalid transitions and location do not add inputs', () {
    expect(session.pause, throwsStateError);
    session.start('state');
    expect(session.finish, throwsStateError);
    expect(() => session.start('duplicate'), throwsStateError);
    expect(
      () => session.addLocation(const RunPoint(91, 127), accuracyM: 5),
      throwsArgumentError,
    );
    expect(session.snapshot.inputs, hasLength(1));
    expect(() => session.snapshot.inputs.clear(), throwsUnsupportedError);
  });
}
