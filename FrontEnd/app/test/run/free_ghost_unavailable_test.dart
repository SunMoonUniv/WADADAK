import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/presentation/free_ghost_unavailable.dart';

void main() {
  Map<String, dynamic> failure(
    List<String> reasons, {
    Map? diagnostics,
    Map? quality,
  }) => {
    'playback': {
      'eligible': false,
      'unavailableReasons': reasons,
      'quality': quality,
    },
    'diagnostics': diagnostics,
  };
  test(
    'explains the distance-short verdict using actual recognized values',
    () {
      final message = freeGhostUnavailableMessage(
        failure(
          ['REFERENCE_NOT_REPRODUCIBLE'],
          diagnostics: {
            'reason': 'DISTANCE_SHORT',
            'recognizedPercent': 78.690075,
            'recognizedDistanceM': 1390.8532,
            'referenceDistanceM': 1767.5078,
          },
        ),
      );
      expect(message, contains('95%'));
      expect(message, contains('78.69%'));
      expect(message, contains('1767.5m 중'));
      expect(message, contains('1390.9m 인정'));
      expect(message, isNot(contains('GPS 공백')));
    },
  );
  test('reports all simultaneous reasons and measured gap limits', () {
    final message = freeGhostUnavailableMessage(
      failure(
        [
          'CONTINUOUS_GAP_EXCEEDED',
          'TOTAL_GAP_EXCEEDED',
          'PAUSE_POSITION_UNAVAILABLE',
        ],
        quality: {
          'activeDurationMs': 600000,
          'gapMs': 45000,
          'maxGapMs': 32000,
        },
      ),
    );
    expect(message, contains('연속 30초'));
    expect(message, contains('실제 32.0초'));
    expect(message, contains('5%'));
    expect(message, contains('실제 7.50%'));
    expect(message, contains('정지 직전 10초'));
  });
  for (final entry in {
    'START_NOT_CONFIRMED': '출발점 30m',
    'FINISH_NOT_REACHED': '도착점까지 남은 거리 30m',
  }.entries) {
    test('explains reference ${entry.key}', () {
      expect(
        freeGhostUnavailableMessage(
          failure(
            ['REFERENCE_NOT_REPRODUCIBLE'],
            diagnostics: {'reason': entry.key},
          ),
        ),
        contains(entry.value),
      );
    });
  }
  for (final entry in {
    'SOURCE_INPUTS_MISSING': '원본이 남아 있지',
    'SOURCE_CALCULATION_MISMATCH': '계산 방식 정보가',
    'SOURCE_CALCULATION_UNSUPPORTED': '계산 방식을',
    'SOURCE_RESULT_MISMATCH': '저장된 기록과 일치하지',
    'REFERENCE_GEOMETRY_MISSING': '최소 2개',
    'SOURCE_INPUTS_INVALID': '순서나 값이 유효하지',
  }.entries) {
    test('explains source ${entry.key}', () {
      expect(
        freeGhostUnavailableMessage(
          failure(
            ['MISSING_SOURCE_INPUTS'],
            diagnostics: {'reason': entry.key},
          ),
        ),
        contains(entry.value),
      );
    });
  }
  for (final entry in {
    'DISTANCE_BELOW_1000M': '1,000m 미만',
    'NOT_FREE_RECORD': '자유 기록이 아니어서',
    'AMBIGUOUS_POSITION': '진행 위치를 하나로',
    'PAUSE_POSITION_UNAVAILABLE': '일시정지할 때',
    'FINISH_POSITION_UNAVAILABLE': '재생 종료 시점',
    'NO_ACTIVE_DURATION': '재생 시간이 0초',
  }.entries) {
    test('explains ${entry.key}', () {
      expect(
        freeGhostUnavailableMessage(failure([entry.key])),
        contains(entry.value),
      );
    });
  }
  test('older servers and unknown reasons do not invent missing details', () {
    expect(
      freeGhostUnavailableMessage(failure(['REFERENCE_NOT_REPRODUCIBLE'])),
      contains('어느 조건인지는 확인할 수 없어요'),
    );
    expect(
      freeGhostUnavailableMessage(failure(['MISSING_SOURCE_INPUTS'])),
      contains('더 자세한 사유를 제공하지'),
    );
    expect(
      freeGhostUnavailableMessage(failure(['FUTURE_REASON'])),
      contains('해석할 수 있는'),
    );
    expect(freeGhostUnavailableMessage(failure([])), contains('자세한 사유를 제공하지'));
  });
}
