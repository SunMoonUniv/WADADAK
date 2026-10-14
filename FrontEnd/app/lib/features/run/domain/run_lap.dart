class RunLap {
  const RunLap({
    required this.number,
    required this.distanceM,
    required this.movingMs,
    required this.elapsedMs,
    required this.complete,
  });
  final int number, movingMs, elapsedMs;
  final double distanceM;
  final bool complete;
  double? get paceSecondsPerKm => distanceM > 0 ? movingMs / distanceM : null;
  Map<String, dynamic> toJson() => {
    'number': number,
    'distanceM': distanceM,
    'movingMs': movingMs,
    'elapsedMs': elapsedMs,
    'complete': complete,
    'paceSecondsPerKm': paceSecondsPerKm,
  };
  factory RunLap.fromJson(Map<String, dynamic> j) => RunLap(
    number: j['number'] as int,
    distanceM: (j['distanceM'] as num).toDouble(),
    movingMs: (j['movingMs'] as num).toInt(),
    elapsedMs: (j['elapsedMs'] as num).toInt(),
    complete: j['complete'] as bool,
  );
}

class RunTravel {
  const RunTravel(this.startMs, this.endMs, this.distanceM);
  final int startMs, endMs;
  final double distanceM;
}

class RunTimeSpan {
  const RunTimeSpan(this.start, this.end);
  final int start, end;
  int before(int ms) => (ms - start).clamp(0, end - start);
}
