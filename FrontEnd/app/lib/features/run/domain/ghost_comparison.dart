/// Owner-only, immutable comparison made by the server at duel finalization.
class GhostComparison {
  GhostComparison.fromJson(Map<String, dynamic> j)
    : sessionId = j['sessionId'] as String,
      sourceId = j['sourceRecordId'] as String,
      result = Map.unmodifiable((j['result'] as Map).cast<String, dynamic>()),
      status = j['status'] as String,
      courseId = j['courseId'] as String?,
      courseName = j['courseName'] as String?,
      distanceM = (j['distanceMeters'] as num).toInt(),
      kind = j['sourceKind'] as String,
      publicPeriod = j['publicPeriod'] as String?,
      sourceState = j['sourceState'] as String,
      reachedM = (j['reachedMeters'] as num).toDouble(),
      personalBest = j['personalBest'] as String,
      previousBestSeconds = (j['previousBestSeconds'] as num?)?.toInt(),
      ours = j['ours'] == null
          ? null
          : GhostComparisonMetrics.fromJson(j['ours'] as Map),
      ghost = j['ghost'] == null
          ? null
          : GhostComparisonMetrics.fromJson(j['ghost'] as Map),
      segments = List.unmodifiable([
        for (final s in j['segments'] as List)
          GhostComparisonSegment.fromJson(s as Map),
      ]) {
    if (j['version'] != 'GHOST_COMPARISON_V1' ||
        sessionId.isEmpty ||
        sourceId.isEmpty ||
        result['sessionId'] != sessionId ||
        result['sourceRecordId'] != sourceId ||
        !['WIN', 'LOSE', 'DRAW', 'INVALID'].contains(result['outcome']) ||
        result['completed'] is! bool ||
        (result['courseElapsedSeconds'] as num).isNegative ||
        (result['sourceElapsedSeconds'] as num).isNegative ||
        !reachedM.isFinite ||
        reachedM < 0 ||
        status == 'AVAILABLE' &&
            (distanceM <= 0 ||
                ours == null ||
                ghost == null ||
                !['OWN_FREE', 'OWN_COURSE', 'PUBLIC_COURSE'].contains(kind) ||
                kind == 'PUBLIC_COURSE' &&
                    !['ALL', 'MONTH', 'WEEK'].contains(publicPeriod))) {
      throw const FormatException('Invalid ghost comparison');
    }
    double previous = 0;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.number != i + 1 ||
          s.fromM != previous ||
          s.toM > distanceM ||
          s.fromM != i * 1000 ||
          s.toM != (s.fromM + 1000).clamp(0, distanceM)) {
        throw const FormatException('Invalid reference boundaries');
      }
      previous = s.toM;
    }
    if (status == 'AVAILABLE' && previous != distanceM) {
      throw const FormatException('Incomplete reference boundaries');
    }
    if (kind == 'PUBLIC_COURSE' &&
        (ghost?.activeMs != null || ghost?.cadence != null)) {
      throw const FormatException('Public sensor metrics are not permitted');
    }
  }
  final String sessionId, sourceId, status, kind, sourceState, personalBest;
  final String? courseId, courseName, publicPeriod;
  final int distanceM;
  final double reachedM;
  final int? previousBestSeconds;
  final Map<String, dynamic> result;
  final GhostComparisonMetrics? ours, ghost;
  final List<GhostComparisonSegment> segments;
  bool get available => status == 'AVAILABLE';
}

class GhostComparisonMetrics {
  GhostComparisonMetrics.fromJson(Map j)
    : elapsedSeconds = (j['elapsedSeconds'] as num?)?.toInt(),
      activeMs = (j['activeMs'] as num?)?.toInt(),
      pace = (j['paceSecondsPerKm'] as num?)?.toDouble(),
      cadence = (j['averageCadence'] as num?)?.toDouble(),
      bestSegment = (j['bestSegment'] as num?)?.toInt() {
    if (elapsedSeconds != null && elapsedSeconds! < 0 ||
        activeMs != null && activeMs! < 0 ||
        pace != null && (!pace!.isFinite || pace! < 0) ||
        cadence != null && (!cadence!.isFinite || cadence! < 0) ||
        bestSegment != null && bestSegment! < 1) {
      throw const FormatException('Invalid comparison metric');
    }
  }
  final int? elapsedSeconds, activeMs, bestSegment;
  final double? pace, cadence;
}

class GhostComparisonSegment {
  GhostComparisonSegment.fromJson(Map j)
    : number = (j['number'] as num).toInt(),
      fromM = (j['fromMeters'] as num).toDouble(),
      toM = (j['toMeters'] as num).toDouble(),
      full = j['fullKilometer'] == true,
      ours = (j['ourSeconds'] as num?)?.toInt(),
      ghost = (j['ghostSeconds'] as num?)?.toInt(),
      delta = (j['deltaSeconds'] as num?)?.toInt(),
      cumulative = (j['cumulativeDeltaSeconds'] as num?)?.toInt(),
      reason = j['unavailableReason'] as String? {
    if (!fromM.isFinite ||
        !toM.isFinite ||
        fromM < 0 ||
        toM <= fromM ||
        toM - fromM > 1000 ||
        full != (toM - fromM == 1000) ||
        ours != null && ours! < 0 ||
        ghost != null && ghost! < 0 ||
        reason != null && (delta != null || cumulative != null) ||
        reason == null &&
            (ours == null ||
                ghost == null ||
                delta != ghost! - ours! ||
                cumulative == null)) {
      throw const FormatException('Invalid comparison segment');
    }
  }
  final int number;
  final double fromM, toM;
  final bool full;
  final int? ours, ghost, delta, cumulative;
  final String? reason;
  String get label => '${_km(fromM)}–${_km(toM)}km';
  String get explanation => reason == 'GPS_GAP'
      ? 'GPS 공백으로 구간 시간을 확인할 수 없어요.'
      : '이 경계의 도착 위치·시각을 확인할 수 없어요.';
  double? pace(bool own) {
    final seconds = own ? ours : ghost;
    return seconds == null ? null : seconds * 1000 / (toM - fromM);
  }

  static String _km(double m) => m % 1000 == 0
      ? (m / 1000).toInt().toString()
      : (m / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

String ghostComparisonUnavailable(String status) => switch (status) {
  'LEGACY_NO_DETAIL' => '이전 기록에는 대결 당시의 상세 비교 자료가 저장되지 않았어요. 최종 승패는 그대로 보존돼요.',
  'SOURCE_RESULT_MISMATCH' =>
    '저장된 결과와 상세 계산 기준이 달라 상세 비교를 제공할 수 없어요. 최종 승패는 그대로 보존돼요.',
  _ => '상세 비교 자료를 확인할 수 없어요. 최종 승패는 그대로 보존돼요.',
};

String ghostVerdictReason(String? reason) => switch (reason) {
  'VOLUNTARY_AFTER_GHOST_FINISH' => '고스트 도착 후 완주 전에 대결을 종료했어요.',
  'VOLUNTARY_BEFORE_GHOST_FINISH' => '고스트 도착 전에 대결을 종료했어요.',
  'INVOLUNTARY_INCOMPLETE' => '기록이 중단되어 완주를 확인할 수 없어요.',
  'FINISH_NOT_CONFIRMED' => '서버가 완주를 확인하지 못했어요.',
  _ => '완주 조건을 충족하지 못했어요.',
};

String ghostDelta(int? value) =>
    value == null ? '—' : '${value > 0 ? '+' : ''}$value초';
