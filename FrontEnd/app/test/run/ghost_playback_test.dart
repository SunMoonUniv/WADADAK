import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/ghost_playback.dart';

void main() {
  final fixture = jsonDecode(
    File('../../run/fixtures/ghost_playback_v1.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('shared server/app ghost playback: ${c['name']}', () {
      final data = <String, dynamic>{
        ...(c['expected'] as Map).cast<String, dynamic>(),
        'version': fixture['version'],
      };
      final playback = GhostPlayback.fromJson(data);
      for (final probe in c['probes'] as List) {
        final actual = playback.at(probe['elapsedMs'] as int);
        expect(
          actual.state.name.toUpperCase().replaceAll(
            'BEFORESTART',
            'BEFORE_START',
          ),
          probe['state'],
        );
        if (probe['coursePositionM'] == null) {
          expect(actual.coursePositionM, isNull);
        } else {
          expect(
            actual.coursePositionM,
            closeTo((probe['coursePositionM'] as num).toDouble(), 1e-6),
          );
        }
      }
      for (final arrival in c['arrivals'] as List) {
        final actual = playback.firstArrivalMs(
          (arrival['positionM'] as num).toDouble(),
        );
        if (arrival['elapsedMs'] == null) {
          expect(actual, isNull);
        } else {
          expect(
            actual,
            closeTo((arrival['elapsedMs'] as num).toDouble(), 1e-6),
          );
        }
      }
      // Pure lookup: moving the UI or replaying old queries never changes the timeline.
      final before = jsonEncode(data);
      playback.at(99999999);
      playback.at(0);
      playback.at(1000);
      expect(jsonEncode(data), before);
    });
  }

  Map<String, dynamic> basic() => {
    'version': 'GHOST_PLAYBACK_V1',
    'eligible': true,
    'durationMs': 10000,
    'spans': [
      {
        'fromMs': 0,
        'toMs': 10000,
        'fromPositionM': 0,
        'toPositionM': 50,
        'state': 'TRACKED',
      },
    ],
    'samples': [
      {'elapsedMs': 0, 'coursePositionM': 0},
      {'elapsedMs': 10000, 'coursePositionM': 50},
    ],
  };

  test(
    'unavailable and unsupported playback cannot supply a ghost position',
    () {
      for (final data in [
        basic()..['eligible'] = false,
        basic()..['version'] = 'future',
      ]) {
        final actual = GhostPlayback.fromJson(data).at(5000);
        expect(actual.state, GhostPlaybackState.unavailable);
        expect(actual.coursePositionM, isNull);
      }
    },
  );

  test('reverse movement does not invent a forward arrival time', () {
    final data = basic();
    data['spans'] = [
      {
        'fromMs': 0,
        'toMs': 10000,
        'fromPositionM': 50,
        'toPositionM': 0,
        'state': 'TRACKED',
      },
    ];
    final playback = GhostPlayback.fromJson(data);
    expect(playback.at(5000).coursePositionM, 25);
    expect(playback.firstArrivalMs(25), isNull);
  });

  test('malformed or discontinuous server intervals fail closed', () {
    final data = basic();
    (data['spans'] as List).first['fromMs'] = 1;
    expect(() => GhostPlayback.fromJson(data), throwsFormatException);
  });
}
