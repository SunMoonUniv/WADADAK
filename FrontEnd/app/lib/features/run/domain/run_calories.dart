/// User-approved estimate. Only measured horizontal running distance is used.
double? estimateRunCalories(double? weightKg, double distanceM) {
  if (weightKg == null ||
      !weightKg.isFinite ||
      weightKg < 20 ||
      weightKg > 300 ||
      !distanceM.isFinite ||
      distanceM < 0) {
    return null;
  }
  return weightKg * distanceM / 1000;
}

String formatRunCalories(double? calories, {bool unit = true}) =>
    calories == null || !calories.isFinite || calories < 0
    ? '—'
    : '${calories.round()}${unit ? ' kcal' : ''}';
