import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';
import '../domain/ghost_comparison.dart';

abstract interface class GhostComparisonSource {
  Future<GhostComparison> get(String owner, String id);
}

class GhostComparisonApi implements GhostComparisonSource {
  GhostComparisonApi(this.client);
  final RunApiClient client;
  @override
  Future<GhostComparison> get(String owner, String id) {
    final token = CancelToken();
    return _get(owner, id, token).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        token.cancel();
        throw const ApiException(
          'GHOST_COMPARISON_TIMEOUT',
          '비교 기록 확인이 15초 안에 끝나지 않았어요. 다시 시도해 주세요.',
        );
      },
    );
  }

  Future<GhostComparison> _get(
    String owner,
    String id,
    CancelToken token,
  ) async {
    final j = (await callApi(
      () => client.dio.get<Object?>(
        '/api/v1/runs/sessions/$id/ghost/result/comparison',
        cancelToken: token,
        options: client
            .options(owner)
            .copyWith(transformTimeout: const Duration(seconds: 15)),
      ),
    )) as Map;
    final detail = GhostComparison.fromJson(j.cast<String, dynamic>());
    if (detail.sessionId != id) {
      throw const FormatException('Mismatched ghost comparison');
    }
    return detail;
  }
}
