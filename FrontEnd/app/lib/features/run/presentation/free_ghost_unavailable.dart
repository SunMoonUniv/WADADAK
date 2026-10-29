/// Explains the server verdict without deciding replay eligibility on the device.
String freeGhostUnavailableMessage(Map<String, dynamic> preparation) {
  final playback = preparation['playback'] as Map? ?? const {};
  final reasons = playback['unavailableReasons'];
  final quality = playback['quality'] as Map?;
  final diagnostics = preparation['diagnostics'] as Map?;
  String? number(Object? value, int decimals) =>
      value is num && value.isFinite ? value.toStringAsFixed(decimals) : null;
  String seconds(Object? value) {
    final text = value is num ? number(value / 1000, 1) : null;
    return text == null ? '' : ' (실제 $text초)';
  }

  String referenceFailure() {
    switch (diagnostics?['reason']) {
      case 'START_NOT_CONFIRMED':
        return '경로 재현 시 출발점 30m 이내에서 시작한 위치를 확인하지 못했어요.';
      case 'FINISH_NOT_REACHED':
        return '경로 재현 시 도착점까지 남은 거리 30m 이내에 도달한 위치를 확인하지 못했어요.';
      case 'DISTANCE_SHORT':
        final percent = number(diagnostics?['recognizedPercent'], 2);
        final recognized = number(diagnostics?['recognizedDistanceM'], 1);
        final reference = number(diagnostics?['referenceDistanceM'], 1);
        final actual = percent == null ? '' : ' 실제 인정률은 $percent%예요.';
        final distance = recognized == null || reference == null
            ? ''
            : ' (경로 ${reference}m 중 ${recognized}m 인정)';
        return '경로 재현 인정률이 필요한 95%에 미달해요.$actual$distance';
      default:
        return '경로 재현 검사에서 출발점 확인·도착점 도달·경로 95% 이상 인정 조건을 통과하지 못했어요. 서버가 세부 항목을 제공하지 않아 어느 조건인지는 확인할 수 없어요.';
    }
  }

  String sourceFailure() => switch (diagnostics?['reason']) {
    'SOURCE_INPUTS_MISSING' => '서버에 GPS·시간 원본이 남아 있지 않아 재생할 수 없어요.',
    'SOURCE_CALCULATION_MISMATCH' =>
      '저장된 기록의 계산 방식 정보가 GPS·시간 원본의 정보와 일치하지 않아요.',
    'SOURCE_CALCULATION_UNSUPPORTED' =>
      '이 기록에 사용된 거리·시간 계산 방식을 현재 고스트 재생에서 지원하지 않아요.',
    'SOURCE_RESULT_MISMATCH' => '원본으로 다시 계산한 거리 또는 시간이 저장된 기록과 일치하지 않아요.',
    'REFERENCE_GEOMETRY_MISSING' =>
      '이동 경로를 만들 수 있는 유효한 위치가 부족해요. 위치가 최소 2개이고 경로 길이가 0m보다 커야 해요.',
    'SOURCE_INPUTS_INVALID' => 'GPS·시간 원본의 순서나 값이 유효하지 않아 재생할 수 없어요.',
    _ => '원본 GPS·시간 확인 또는 거리·시간 재계산에 실패했어요. 서버가 더 자세한 사유를 제공하지 않았어요.',
  };
  final messages = <String>[];
  for (final reason in reasons is List ? reasons : const []) {
    final message = switch (reason) {
      'DISTANCE_BELOW_1000M' =>
        '실제 기록 거리가 1,000m 미만이에요. 고스트에는 1,000m 이상인 기록이 필요해요.',
      'NOT_FREE_RECORD' => '자유 기록이 아니어서 이 화면의 고스트로 사용할 수 없어요.',
      'REFERENCE_NOT_REPRODUCIBLE' => referenceFailure(),
      'MISSING_SOURCE_INPUTS' => sourceFailure(),
      'CONTINUOUS_GAP_EXCEEDED' =>
        '위치를 알 수 없는 구간이 연속 30초를 초과해요${seconds(quality?['maxGapMs'])}.',
      'TOTAL_GAP_EXCEEDED' => () {
        final active = quality?['activeDurationMs'];
        final gap = quality?['gapMs'];
        final percent = active is num && active > 0 && gap is num
            ? number(gap * 100 / active, 2)
            : null;
        return '일시정지를 제외한 재생 시간 중 위치를 알 수 없는 시간이 5%를 초과해요${percent == null ? '' : ' (실제 $percent%)'}.';
      }(),
      'AMBIGUOUS_POSITION' => '경로가 겹치는 구간에서 고스트의 진행 위치를 하나로 정하지 못했어요.',
      'PAUSE_POSITION_UNAVAILABLE' =>
        '일시정지할 때의 경로상 위치를 확인하지 못했어요. 정지 직전 10초 이내의 유효한 위치가 필요해요.',
      'FINISH_POSITION_UNAVAILABLE' => '고스트 재생 종료 시점의 경로상 위치를 확인하지 못했어요.',
      'NO_ACTIVE_DURATION' => '일시정지를 제외한 재생 시간이 0초여서 사용할 수 없어요.',
      _ => '서버가 고스트 사용 불가로 판정했지만 앱에서 해석할 수 있는 자세한 사유를 제공하지 않았어요.',
    };
    if (!messages.contains(message)) messages.add(message);
  }
  if (messages.isEmpty) {
    messages.add('서버가 고스트 사용 불가로 판정했지만 자세한 사유를 제공하지 않았어요.');
  }
  return '이 기록을 고스트로 사용할 수 없어요.\n${messages.map((m) => '• $m').join('\n')}';
}
