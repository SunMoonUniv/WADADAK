import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';

/// 1 km 랩 하나의 케이던스·고도(달리기 서버 `GET /api/v1/runs/records/{id}/splits`, D3·D5·D6). 측정하지 못했으면 null
class RunSplit {
  const RunSplit({required this.number, this.cadence, this.elevationChangeM, this.cumulativeGainM});

  factory RunSplit.fromJson(Map<Object?, Object?> json) => RunSplit(
    number: (json['number']! as num).toInt(),
    cadence: (json['cadence'] as num?)?.toDouble(),
    elevationChangeM: (json['elevationChangeM'] as num?)?.toDouble(),
    cumulativeGainM: (json['cumulativeGainM'] as num?)?.toDouble(),
  );

  /// 결과 랩과 같은 번호
  final int number;

  /// spm
  final double? cadence;

  /// 랩 끝 높이 − 시작 높이(내리막은 음수). 고도 자료가 끊긴 랩은 null
  final double? elevationChangeM;

  /// 기록 시작부터 이 랩 끝까지의 상승 고도. 마지막 랩은 결과 상승 고도와 같다
  final double? cumulativeGainM;
}

/// 서버가 저장된 원본으로 계산한다. 서버에 올리기 전 기록은 `RUN-002`
final runSplitsProvider = FutureProvider.autoDispose.family<List<RunSplit>, String>((ref, recordId) async {
  final client = RunApiClient(ref.watch(dioProvider));
  final data = await callApi(
    () => client.dio.get<Object?>('/api/v1/runs/records/${Uri.encodeComponent(recordId)}/splits'),
  );
  return [for (final lap in (data! as Map)['laps']! as List) RunSplit.fromJson(lap as Map)];
}, retry: (_, _) => null);
