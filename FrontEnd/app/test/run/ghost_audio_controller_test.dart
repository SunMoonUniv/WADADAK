import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/audio_guide.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/free_ghost.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/domain/route_guidance.dart';
import 'package:wadadak/features/run/run_voice_settings_events.dart';

import 'free_ghost_flow_test.dart' as free;
import 'ghost_controller_recovery_test.dart' show GhostLocation;
import 'ghost_recovery_support.dart';
import 'recording/course_run_start_test.dart' show CourseApi;
import 'recording/run_controller_test.dart' show FailingStore, until;
import 'run_device_controller_test.dart' show Output;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late RunController runs;
  late FailingStore store;
  late GhostLocation location;
  late Output output;
  late RecoveryApi starts;
  late RunVoiceSettingsEvents events;
  String? member;
  Future<String?> Function()? ownerReader;
  setUp(() {
    member = 'alice';
    ownerReader = null;
    store = FailingStore();
    output = Output();
    location = GhostLocation()..clock = 100000;
    starts = RecoveryApi();
    events = RunVoiceSettingsEvents();
    runs = RunController(
      store,
      location,
      CourseApi(),
      () => ownerReader?.call() ?? Future.value(member),
      audio: AudioGuide(output),
      ghostApi: starts,
      voiceSettingsEvents: events.changes,
      automaticTicks: false,
      nowMs: location.nowMs,
      recoveryClock: () async => RunClockSample(location.clock, 'boot-a'),
      wait: (_) async {},
      utcNow: () => location.utc,
      lifecycleState: () => AppLifecycleState.resumed,
    );
  });
  tearDown(() async {
    await until(() => !runs.syncing && !runs.loadingHistory);
    await events.close();
    await runs.shutdown();
    runs.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });

  Future<void> begin({bool isFree = false}) async {
    await runs.bindOwner();
    await runs.receiveVoiceSettings(
      const RunVoiceSettingsChanged(
        owner: 'alice',
        unit: VoiceUnit.time,
        ghostGapEnabled: true,
      ),
    );
    if (isFree) {
      starts.onStart = (intent) async => free.approval(intent);
      runs.selectFreeGhost(
        PreparedFreeGhost(
          'alice',
          free.preparation(version: 'GHOST_PLAYBACK_FREE_V2'),
        ),
      );
    } else {
      final replay = OwnGhostReplay.fromJson(
        (ghostApproval(ghostIntent())['playback'] as Map)
            .cast<String, dynamic>(),
      );
      runs.selectGhost(
        PreparedOwnGhost(
          'alice',
          const GhostCourseContext(courseId, 0),
          OwnGhostCandidate.fromJson({
            'id': sourceId,
            'courseId': courseId,
            'courseVersion': 0,
            'startedAt': ghostEpoch.toIso8601String(),
            'registeredAt': ghostEpoch.toIso8601String(),
            'courseElapsedSeconds': 230,
            'courseDistanceMeters': 1112,
          }),
          replay,
        ),
      );
    }
    await runs.prepareStart();
    await runs.prepareStart();
    expect(runs.error, isNull);
    expect(runs.onCourse, true);
    await until(() => location.streams.any((s) => s.hasListener));
  }

  Future<void> moveTo(int seconds) async {
    location.clock = 100000 + seconds * 1000;
    final count = runs.run!.inputs.length;
    location.streams.last.add(location.point(36 + .009 * seconds / 300));
    await until(() => runs.run!.inputs.length > count);
    await runs.refreshMeasurement();
  }

  test('future F4 stream receives owner-scoped partial changes and saves without MY changes', () async {
    await runs.bindOwner();
    events.publish(
      const RunVoiceSettingsChanged(
        owner: 'alice',
        unit: VoiceUnit.time,
        timeMinutes: 10,
      ),
    );
    events.publish(
      const RunVoiceSettingsChanged(owner: 'alice', ghostGapEnabled: true),
    );
    await until(() => runs.voiceSettings.ghostGapEnabled);
    expect(runs.voiceSettings.timeMinutes, 10);
    expect(runs.voiceSettings.unit, VoiceUnit.time);
    expect((await store.voiceSettings('alice')).ghostGapEnabled, true);
    expect(ghostGapVoiceSettingLabel, '고스트 격차 음성 안내');
    expect(
      await runs.receiveVoiceSettings(
        const RunVoiceSettingsChanged(owner: 'bob', enabled: false),
      ),
      false,
    );
    expect(runs.voiceSettings.enabled, true);
    member = 'bob';
    await runs.bindOwner();
    expect(runs.voiceSettings.ghostGapEnabled, false);
    expect(
      await runs.receiveVoiceSettings(
        const RunVoiceSettingsChanged(owner: 'alice', ghostGapEnabled: false),
      ),
      false,
    );
    member = 'alice';
    await runs.bindOwner();
    expect(runs.voiceSettings.ghostGapEnabled, true);
    expect(runs.voiceSettings.timeMinutes, 10);
  });

  test(
    'invalid events fail independently and do not poison subsequent updates',
    () async {
      await runs.bindOwner();
      await expectLater(
        runs.receiveVoiceSettings(
          const RunVoiceSettingsChanged(owner: 'alice', distanceKm: 0),
        ),
        throwsFormatException,
      );
      expect(
        await runs.receiveVoiceSettings(
          const RunVoiceSettingsChanged(owner: 'alice', ghostGapEnabled: true),
        ),
        true,
      );
      member = null;
      expect(
        await runs.receiveVoiceSettings(
          const RunVoiceSettingsChanged(owner: 'alice', ghostGapEnabled: false),
        ),
        false,
      );
    },
  );

  test('an owner lookup that finishes after account binding cannot apply Alice settings to Bob', () async {
    await runs.bindOwner();
    final gate = Completer<String?>();
    var requested = false;
    ownerReader = () {
      requested = true;
      return gate.future;
    };
    final pending = runs.receiveVoiceSettings(
      const RunVoiceSettingsChanged(owner: 'alice', ghostGapEnabled: true),
    );
    await until(() => requested);
    member = 'bob';
    ownerReader = null;
    await runs.bindOwner();
    gate.complete('alice');
    expect(await pending, false);
    expect(runs.voiceSettings.ghostGapEnabled, false);
    expect((await store.voiceSettings('bob')).ghostGapEnabled, false);
  });

  for (final isFree in [false, true]) {
    test(
      'real ${isFree ? 'free' : 'course'} ghost flow speaks shared arrival gap once then ends it on free-run transition',
      () async {
        await begin(isFree: isFree);
        for (var s = 0; s <= 300; s += 5) {
          await moveTo(s);
        }
        await until(() => output.speech.isNotEmpty);
        final adapter = FreeRunController.recording(runs);
        final delta = adapter.ghostComparison!.timeDeltaMs!;
        expect(delta, greaterThan(0));
        final rounded = (delta.abs() / 5000).round() * 5;
        expect(output.speech.single, contains('현재 고스트보다 $rounded초 뒤처져 있어요.'));
        await runs.refreshMeasurement();
        expect(output.speech, hasLength(1));
        await runs.endCourse('COURSE_ONLY');
        expect(runs.ghostComparison, isNull);
        expect(adapter.ghostComparison, isNull);
        location.clock = 700000;
        await runs.refreshMeasurement();
        expect(output.speech, hasLength(2));
        expect(output.speech.last, isNot(contains('고스트')));
        adapter.dispose();
      },
    );
  }

  for (final state in [GuidanceState.candidate, GuidanceState.off]) {
    test(
      'muted $state still suppresses ghost gap but preserves regular time announcement',
      () async {
        await begin();
        for (var s = 0; s <= 295; s += 5) {
          await moveTo(s);
        }
        runs.routeGuidance!.state = state;
        runs.routeGuidance!.mute();
        location.clock = 400000;
        await runs.refreshMeasurement();
        expect(output.speech, hasLength(1));
        expect(output.speech.single, isNot(contains('고스트')));
      },
    );
  }

  test('stale GPS omits gap without announcing an error or suppressing the time cue', () async {
    await begin();
    for (var s = 0; s <= 285; s += 5) {
      await moveTo(s);
    }
    location.clock = 400000;
    await runs.refreshMeasurement();
    expect(output.speech, hasLength(1));
    expect(output.speech.single, isNot(contains('고스트')));
    expect(output.speech.single, isNot(contains('계산할 수')));
  });

  test('arrival on a periodic boundary cancels ghost speech and announces only finish metrics', () async {
    await begin();
    for (var s = 0; s <= 295; s += 5) {
      location.clock = 100000 + s * 1000;
      final count = runs.run!.inputs.length;
      location.streams.last.add(location.point(36 + .0097 * s / 295));
      await until(() => runs.run!.inputs.length > count);
      await runs.refreshMeasurement();
    }
    location.clock = 400000;
    location.streams.last.add(location.point(36.0099));
    await until(() => runs.courseEndReason == 'ROUTE_END');
    await runs.refreshMeasurement();
    await until(() => output.speech.isNotEmpty);
    expect(output.speech, hasLength(1));
    expect(output.speech.single, contains('코스 끝에 도착했어요'));
    expect(output.speech.single, isNot(contains('고스트')));
    expect(output.speech.single, isNot(contains('승리')));
  });
}
