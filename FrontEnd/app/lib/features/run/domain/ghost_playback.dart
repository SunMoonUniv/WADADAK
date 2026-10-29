/// F9 pure replay of the server's GHOST_PLAYBACK_V1 contract.
/// Time is total elapsed milliseconds; the runner's pause state is not an input.
library;

enum GhostPlaybackState {
  beforeStart,
  tracked,
  paused,
  unknown,
  finished,
  unavailable,
}

class GhostMoment {
  const GhostMoment(this.state, this.coursePositionM);
  final GhostPlaybackState state;
  final double? coursePositionM;
}

class GhostSpan {
  const GhostSpan(this.fromMs, this.toMs, this.fromM, this.toM, this.state);
  factory GhostSpan.fromJson(Map<String, dynamic> j) => GhostSpan(
    (j['fromMs'] as num).toInt(),
    (j['toMs'] as num).toInt(),
    (j['fromPositionM'] as num?)?.toDouble(),
    (j['toPositionM'] as num?)?.toDouble(),
    switch (j['state']) {
      'TRACKED' => GhostPlaybackState.tracked,
      'PAUSED' => GhostPlaybackState.paused,
      'UNKNOWN' => GhostPlaybackState.unknown,
      _ => throw const FormatException('Unknown ghost span state'),
    },
  );
  final int fromMs, toMs;
  final double? fromM, toM;
  final GhostPlaybackState state;
  double? positionAt(int ms) => fromM == null || toM == null
      ? null
      : fromM! + (toM! - fromM!) * (ms - fromMs) / (toMs - fromMs);
}

class GhostPlayback {
  GhostPlayback.fromJson(Map<String, dynamic> j)
    : version = j['version'] as String?,
      eligible = j['eligible'] == true,
      durationMs = (j['durationMs'] as num?)?.toInt(),
      reasons = List<String>.unmodifiable(
        (j['unavailableReasons'] as List? ?? const []).cast<String>(),
      ),
      spans = List<GhostSpan>.unmodifiable([
        for (final s in j['spans'] as List? ?? const [])
          GhostSpan.fromJson((s as Map).cast<String, dynamic>()),
      ]),
      samples = List<({int ms, double? position})>.unmodifiable([
        for (final s in j['samples'] as List? ?? const [])
          (
            ms: (s['elapsedMs'] as num).toInt(),
            position: (s['coursePositionM'] as num?)?.toDouble(),
          ),
      ]) {
    if (eligible && supported) {
      var edge = 0;
      for (final s in spans) {
        if (s.fromMs != edge ||
            s.toMs <= s.fromMs ||
            s.state != GhostPlaybackState.unknown &&
                (s.fromM == null ||
                    s.toM == null ||
                    !s.fromM!.isFinite ||
                    !s.toM!.isFinite)) {
          throw const FormatException('Invalid ghost span continuity');
        }
        edge = s.toMs;
      }
      if (durationMs == null || durationMs! <= 0 || edge != durationMs) {
        throw const FormatException('Invalid ghost duration');
      }
      var previous = -1;
      for (final s in samples) {
        if (s.ms <= previous ||
            s.ms < 0 ||
            s.ms > durationMs! ||
            s.position != null && !s.position!.isFinite) {
          throw const FormatException('Invalid ghost sample');
        }
        previous = s.ms;
      }
    }
  }

  final String? version;
  bool get supported =>
      version == 'GHOST_PLAYBACK_V1' ||
      version == 'GHOST_PLAYBACK_FREE_V1' ||
      version == 'GHOST_PLAYBACK_FREE_V2';
  final bool eligible;
  final int? durationMs;
  final List<String> reasons;
  final List<GhostSpan> spans;
  final List<({int ms, double? position})> samples;

  GhostMoment at(int elapsedMs) {
    final end = durationMs;
    if (!eligible || !supported || end == null || spans.isEmpty) {
      return const GhostMoment(GhostPlaybackState.unavailable, null);
    }
    if (elapsedMs < 0) {
      return const GhostMoment(GhostPlaybackState.beforeStart, null);
    }
    if (elapsedMs >= end) {
      return GhostMoment(GhostPlaybackState.finished, spans.last.toM);
    }
    final span = _spanAt(elapsedMs);
    if (span == null) {
      return const GhostMoment(GhostPlaybackState.unknown, null);
    }
    if (span.state == GhostPlaybackState.paused) {
      return GhostMoment(span.state, span.fromM);
    }
    // Exact valid fixes remain usable at the edge of an unknown interval.
    var low = 0, high = samples.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2, sample = samples[mid];
      if (sample.ms == elapsedMs) {
        if (sample.position != null) {
          return GhostMoment(GhostPlaybackState.tracked, sample.position);
        }
        break;
      }
      if (sample.ms < elapsedMs) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return GhostMoment(span.state, span.positionAt(elapsedMs));
  }

  GhostSpan? _spanAt(int ms) {
    var low = 0, high = spans.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2, span = spans[mid];
      if (ms < span.fromMs) {
        high = mid - 1;
      } else if (ms >= span.toMs) {
        low = mid + 1;
      } else {
        return span;
      }
    }
    return null;
  }

  /// Earliest confirmed forward arrival, in ms. Never extrapolates across gaps.
  double? firstArrivalMs(double positionM) {
    if (!eligible || !supported || !positionM.isFinite) {
      return null;
    }
    for (final span in spans) {
      final from = span.fromM, to = span.toM;
      if (span.state != GhostPlaybackState.tracked ||
          from == null ||
          to == null ||
          to <= from) {
        continue;
      }
      if (positionM >= from && positionM <= to) {
        return span.fromMs +
            (span.toMs - span.fromMs) * (positionM - from) / (to - from);
      }
    }
    return null;
  }
}
