import 'dart:convert';
import 'dart:io';

import 'package:wadadak/features/run/domain/ghost_playback.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';

/// Checks responses exported by the isolated DB integration test, without opening the live run screen.
void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError(
      'Expected candidate-response.json selected-replay-response.json',
    );
  }
  Map<String, dynamic> data(String file) =>
      ((jsonDecode(File(file).readAsStringSync()) as Map)['data'] as Map)
          .cast<String, dynamic>();
  final page = OwnGhostPage.fromJson(data(args[0]));
  final replay = OwnGhostReplay.fromJson(data(args[1]));
  final selected = page.content.firstWhere((c) => c.id == replay.sourceId);
  if (!replay.playback.eligible ||
      replay.courseId != selected.course.id ||
      replay.courseVersion != selected.course.version ||
      replay.seconds != selected.seconds ||
      replay.playback.at(0).state == GhostPlaybackState.unavailable) {
    throw StateError('Candidate and replay contract do not match');
  }
  stdout.writeln(
    jsonEncode({
      'candidateCount': page.summary.count,
      'selectedRecordId': selected.id,
      'courseId': selected.course.id,
      'courseVersion': selected.course.version,
      'courseElapsedSeconds': selected.seconds,
      'ready': true,
      'at45000': {
        'state': replay.playback.at(45000).state.name,
        'positionM': replay.playback.at(45000).coursePositionM,
      },
      'at230000': replay.playback.at(230000).state.name,
    }),
  );
}
