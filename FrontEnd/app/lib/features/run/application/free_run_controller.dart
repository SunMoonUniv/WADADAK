import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../domain/free_run_session.dart';
import '../domain/run_models.dart';

// A regular Provider keeps the session alive when the running tab is hidden.
final freeRunControllerProvider = Provider<FreeRunController>((ref) {
  final clock = Stopwatch()..start();
  final controller = FreeRunController(
    createSession: () =>
        FreeRunSession(monotonicNow: () => clock.elapsed, utcNow: DateTime.now),
    createId: () => const Uuid().v4(),
  );
  ref.listen(authControllerProvider, (_, next) {
    if (next.value is SignedOut) controller.discard();
  });
  ref.onDispose(() {
    controller.dispose();
    clock.stop();
  });
  return controller;
});

class FreeRunController extends ChangeNotifier {
  FreeRunController({required this.createSession, required this.createId}) {
    _session = createSession();
  }
  final FreeRunSession Function() createSession;
  final String Function() createId;
  late FreeRunSession _session;
  Timer? _countdownTimer, _refreshTimer;
  int? countdown;
  RunSnapshot get snapshot => _session.snapshot;

  void prepareStart() {
    if (snapshot.state != RunState.ready || countdown != null) return;
    countdown = 3;
    notifyListeners();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown == 1) {
        timer.cancel();
        countdown = null;
        _session.start(createId());
        // The timer only redraws. Elapsed time comes from the monotonic clock.
        _refreshTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => notifyListeners(),
        );
      } else {
        countdown = countdown! - 1;
      }
      notifyListeners();
    });
  }

  void cancelStart() {
    _countdownTimer?.cancel();
    countdown = null;
    notifyListeners();
  }

  void pause() {
    if (snapshot.state != RunState.running) return;
    _session.pause();
    notifyListeners();
  }

  void resume() {
    if (snapshot.state != RunState.paused) return;
    _session.resume();
    notifyListeners();
  }

  void finish() {
    if (snapshot.state != RunState.paused) return;
    _session.finish();
    _refreshTimer?.cancel();
    notifyListeners();
  }

  void newRun() {
    if (snapshot.state != RunState.finished) return;
    discard();
  }

  void discard() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    countdown = null;
    _session = createSession();
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
