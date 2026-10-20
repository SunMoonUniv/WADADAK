import '../domain/run_models.dart';

/// Display selection only. Changing a metric never updates the recorder.
enum RunMetric {
  active('시간'),
  distance('거리'),
  averagePace('평균 페이스'),
  currentPace('현재 페이스'),
  cadence('케이던스');

  const RunMetric(this.label);
  final String label;
  RunMetric get next => values[(index + 1) % values.length];

  String value(RunSnapshot run) => switch (this) {
    active => formatRunTime(run.active),
    distance =>
      run.hasLocation
          ? '${(run.distanceMeters / 1000).toStringAsFixed(2)} km'
          : '—',
    averagePace => _pace(run.paceSecondsPerKm),
    currentPace => _pace(run.currentPaceDisplay),
    cadence =>
      run.currentCadence == null ? '—' : '${run.currentCadence!.round()} spm',
  };

  static String _pace(double? value) =>
      value == null ? '—' : '${formatRunPace(value)} /km';
}
