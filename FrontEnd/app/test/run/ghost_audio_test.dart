import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/application/audio_guide.dart';
import 'package:wadadak/features/run/data/run_audio_output.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_voice.dart';

class SpeechOutput extends RunAudioOutput {
  final speech = <String>[];
  bool playing = false, supported = true, fail = false;
  Completer<void>? pending;
  int stops = 0;
  @override
  bool get isSpeaking => playing;
  @override
  Future<bool> initialize() async => supported;
  @override
  Future<bool> speak(String text) async {
    if (fail) throw StateError('TTS unavailable');
    speech.add(text);
    playing = true;
    await pending?.future;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
  }

  @override
  Future<void> close() async {}
}

RunMetrics measured(double meters, [int ms = 300000]) =>
    RunMetrics(meters, ms, ms, 0);

void main() {
  late SpeechOutput output;
  late AudioGuide guide;
  setUp(() {
    output = SpeechOutput();
    guide = AudioGuide(output);
  });
  tearDown(() => guide.close());

  test('old persisted settings default OFF and preserve the option when global voice is disabled', () {
    final old = RunVoiceSettings.fromJson({'enabled': true});
    expect(old.ghostGapEnabled, false);
    final saved = old.copyWith(ghostGapEnabled: true).copyWith(enabled: false);
    final restored = RunVoiceSettings.fromJson(saved.toJson());
    expect(restored.enabled, false);
    expect(restored.ghostGapEnabled, true);
    expect(restored.copyWith(enabled: true).ghostGapEnabled, true);
  });

  test('signed arrival gap, 5 second threshold and rounding boundaries', () {
    expect(ghostGapVoice(null), isNull);
    expect(ghostGapVoice(double.nan), isNull);
    expect(ghostGapVoice(double.infinity), isNull);
    for (final gap in [0.0, -4999.0, 4999.0]) {
      expect(ghostGapVoice(gap), '고스트와 거의 나란히 달리고 있어요.');
    }
    expect(ghostGapVoice(-5000), '현재 고스트보다 5초 앞서 있어요.');
    expect(ghostGapVoice(7499), '현재 고스트보다 5초 뒤처져 있어요.');
    expect(ghostGapVoice(-7500), '현재 고스트보다 10초 앞서 있어요.');
    expect(ghostGapVoice(12500), '현재 고스트보다 15초 뒤처져 있어요.');
  });

  test('gap is appended once to a distance announcement and only computed when due', () async {
    await guide.prepare(const RunVoiceSettings(ghostGapEnabled: true));
    var calculations = 0;
    double? gap() {
      calculations++;
      return -10000;
    }

    await guide.update(
      'run',
      RunPhase.running,
      measured(0),
      ghostTimeDeltaMs: gap,
    );
    await guide.update(
      'run',
      RunPhase.running,
      measured(999),
      ghostTimeDeltaMs: gap,
    );
    expect(calculations, 0);
    await guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: gap,
    );
    expect(output.speech.single, endsWith('현재 고스트보다 10초 앞서 있어요.'));
    expect(calculations, 1);
    await guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: gap,
    );
    expect(output.speech, hasLength(1));
  });

  for (final global in [false, true]) {
    test(
      'global=$global and gap OFF never compute or speak a ghost gap',
      () async {
        await guide.prepare(RunVoiceSettings(enabled: global));
        double? gap() => throw StateError('disabled gap must not calculate');
        await guide.update(
          'run',
          RunPhase.running,
          measured(0),
          ghostTimeDeltaMs: gap,
        );
        await guide.update(
          'run',
          RunPhase.running,
          measured(1000),
          ghostTimeDeltaMs: gap,
        );
        expect(output.speech.length, global ? 1 : 0);
        expect(output.speech.join(), isNot(contains('고스트')));
      },
    );
  }
  test('global OFF suppresses even an enabled gap option', () async {
    await guide.prepare(
      const RunVoiceSettings(enabled: false, ghostGapEnabled: true),
    );
    await guide.update('run', RunPhase.running, measured(0));
    await guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: () => 10000,
    );
    await guide.announce('완주');
    expect(output.speech, isEmpty);
  });

  test('time mode uses active time; no separate ghost timer or catch-up after pause', () async {
    await guide.prepare(
      const RunVoiceSettings(unit: VoiceUnit.time, ghostGapEnabled: true),
    );
    await guide.update('run', RunPhase.running, measured(0, 0));
    await guide.update(
      'run',
      RunPhase.running,
      const RunMetrics(500, 600000, 299999, 0),
      ghostTimeDeltaMs: () => 15000,
    );
    expect(output.speech, isEmpty);
    await guide.update(
      'run',
      RunPhase.running,
      const RunMetrics(500, 600001, 300000, 0),
      ghostTimeDeltaMs: () => 15000,
    );
    expect(output.speech.single, endsWith('현재 고스트보다 15초 뒤처져 있어요.'));
    await guide.update('run', RunPhase.paused, measured(1500, 600000));
    await guide.update('run', RunPhase.running, measured(1500, 600000));
    expect(output.speech, hasLength(1));
    await guide.update(
      'run',
      RunPhase.running,
      measured(2000, 900000),
      ghostTimeDeltaMs: () => null,
    );
    expect(output.speech, hasLength(2));
    expect(output.speech.last, isNot(contains('고스트')));
  });

  test('deviation preempts periodic; lower-priority regular speech is discarded, never replayed', () async {
    await guide.prepare(const RunVoiceSettings(ghostGapEnabled: true));
    await guide.update('run', RunPhase.running, measured(0));
    await guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: () => -10000,
    );
    await guide.announce(
      '이탈 후보',
      priority: RunVoicePriority.deviationCandidate,
    );
    await guide.update(
      'run',
      RunPhase.running,
      measured(2000),
      ghostTimeDeltaMs: () => -10000,
    );
    await guide.announce(
      '이탈 확정',
      priority: RunVoicePriority.deviationConfirmed,
    );
    expect(output.speech, hasLength(3));
    expect(output.speech.last, '이탈 확정');
    output.playing = false;
    await guide.update('run', RunPhase.running, measured(2000));
    expect(output.speech, hasLength(3));
    await guide.update('run', RunPhase.running, measured(3000));
    expect(output.speech, hasLength(4));
  });

  test('arrival cancels pending announcements before the same interval, then free-run speech continues', () async {
    await guide.prepare(const RunVoiceSettings(ghostGapEnabled: true));
    await guide.update('run', RunPhase.running, measured(0));
    final candidate = guide.announce(
      'stale',
      priority: RunVoicePriority.deviationCandidate,
    );
    final transition = guide.beginCourseTransition();
    await guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: () => -10000,
    );
    await Future.wait([candidate, transition]);
    await guide.announce('완주 시간·페이스', priority: RunVoicePriority.arrival);
    guide.endCourseTransition();
    expect(output.speech, ['완주 시간·페이스']);
    output.playing = false;
    await guide.update('run', RunPhase.running, measured(2000));
    expect(output.speech, hasLength(2));
    expect(output.speech.last, isNot(contains('고스트')));
  });

  test('pause invalidates queued speech, and voice failure does not escape into recording', () async {
    await guide.prepare(const RunVoiceSettings(ghostGapEnabled: true));
    await guide.update('run', RunPhase.running, measured(0));
    final due = guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: () => -10000,
    );
    await guide.update('run', RunPhase.paused, measured(1000));
    await due;
    expect(output.speech, isEmpty);
    output.fail = true;
    await guide.update('run', RunPhase.running, measured(2000));
    expect(guide.notice, isNotNull);
  });

  for (final priority in [
    RunVoicePriority.deviationConfirmed,
    RunVoicePriority.arrival,
  ]) {
    test(
      'changing ghost option preserves active $priority and cancels a queued old gap',
      () async {
        await guide.prepare(const RunVoiceSettings(ghostGapEnabled: true));
        await guide.update('run', RunPhase.running, measured(0));
        await guide.announce('중요 안내', priority: priority);
        final stops = output.stops;
        final queued = guide.update(
          'run',
          RunPhase.running,
          measured(1000),
          ghostTimeDeltaMs: () => -10000,
        );
        await guide.configure(
          const RunVoiceSettings(),
          id: 'run',
          phase: RunPhase.running,
          metrics: measured(1000),
        );
        await queued;
        expect(output.stops, stops);
        expect(output.playing, true);
        expect(output.speech, ['중요 안내']);
        output.playing = false;
        await guide.update(
          'run',
          RunPhase.running,
          measured(2000),
          ghostTimeDeltaMs: () => -10000,
        );
        expect(output.speech.last, isNot(contains('고스트')));
      },
    );
  }

  test('settings changes suppress current threshold and disabling gap stops its remaining sentence', () async {
    await guide.prepare(const RunVoiceSettings());
    await guide.update('run', RunPhase.running, measured(0));
    await guide.configure(
      const RunVoiceSettings(ghostGapEnabled: true),
      id: 'run',
      phase: RunPhase.running,
      metrics: measured(1000),
    );
    await guide.update(
      'run',
      RunPhase.running,
      measured(1000),
      ghostTimeDeltaMs: () => -10000,
    );
    expect(output.speech, isEmpty);
    await guide.update(
      'run',
      RunPhase.running,
      measured(2000),
      ghostTimeDeltaMs: () => -10000,
    );
    expect(output.speech.single, contains('고스트'));
    await guide.configure(
      const RunVoiceSettings(),
      id: 'run',
      phase: RunPhase.running,
      metrics: measured(2000),
    );
    expect(output.playing, false);
    await guide.update(
      'run',
      RunPhase.running,
      measured(3000),
      ghostTimeDeltaMs: () => -10000,
    );
    expect(output.speech.last, isNot(contains('고스트')));
  });
}
