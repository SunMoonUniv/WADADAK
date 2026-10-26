// Offline inspection of the owner-only API response; no network, tokens, or UI state.
import 'dart:convert';
import 'dart:io';

import 'package:wadadak/features/run/domain/ghost_playback.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/verify_ghost_playback.dart RESPONSE.json [elapsedMs ...]',
    );
    exitCode = 64;
    return;
  }
  final envelope = jsonDecode(File(args.first).readAsStringSync()) as Map;
  final data = ((envelope['data'] ?? envelope) as Map).cast<String, dynamic>();
  final playback = GhostPlayback.fromJson(data);
  final times = args.length > 1
      ? args.skip(1).map(int.parse).toList()
      : [
          0,
          45000,
          120000,
          if (playback.durationMs != null) playback.durationMs!,
        ];
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'sourceRecordId': data['sourceRecordId'],
      'version': playback.version,
      'eligible': playback.eligible,
      'durationMs': playback.durationMs,
      'unavailableReasons': playback.reasons,
      'probes': [
        for (final ms in times)
          {
            'elapsedMs': ms,
            'state': playback.at(ms).state.name,
            'coursePositionM': playback.at(ms).coursePositionM,
          },
      ],
    }),
  );
}
