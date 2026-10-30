import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';
import '../domain/free_ghost.dart';

const freeGhostPreparationTimeout = Duration(seconds: 15);
const freeGhostPreparationTimeoutError = ApiException(
  'FREE_GHOST_PREPARATION_TIMEOUT',
  '기록 확인이 15초 안에 끝나지 않았어요. 기록을 다시 선택해 주세요.',
);

abstract interface class FreeGhostSource {
  Future<({List<FreeGhostCandidate> content, String? nextCursor})> candidates(
    String owner, {
    String period = 'ALL',
    String? cursor,
  });
  Future<Map<String, dynamic>> prepare(String owner, String id);
}

class FreeGhostApi implements FreeGhostSource {
  FreeGhostApi(this.client);
  final RunApiClient client;
  @override
  Future<({List<FreeGhostCandidate> content, String? nextCursor})> candidates(
    String owner, {
    String period = 'ALL',
    String? cursor,
  }) async {
    final j = (await callApi(
      () => client.dio.get<Object?>(
        '/api/v1/runs/ghost-candidates/own/free',
        queryParameters: {'period': period, 'cursor': ?cursor},
        options: client.options(owner),
      ),
    )) as Map;
    return (
      content: [
        for (final c in j['content'] as List)
          FreeGhostCandidate.fromJson((c as Map).cast<String, dynamic>()),
      ],
      nextCursor: j['nextCursor'] as String?,
    );
  }

  @override
  Future<Map<String, dynamic>> prepare(String owner, String id) {
    final cancellation = CancelToken();
    // Include authentication, download and JSON decoding in one deadline.
    return _prepare(owner, id, cancellation).timeout(
      freeGhostPreparationTimeout,
      onTimeout: () {
        cancellation.cancel(freeGhostPreparationTimeoutError);
        throw freeGhostPreparationTimeoutError;
      },
    );
  }

  Future<Map<String, dynamic>> _prepare(
    String owner,
    String id,
    CancelToken cancellation,
  ) async {
    final response = ((await callApi(
      () => client.dio.get<Object?>(
        '/api/v1/runs/records/$id/free-ghost-playback',
        queryParameters: {'playbackVersion': 'GHOST_PLAYBACK_FREE_V2'},
        cancelToken: cancellation,
        options: client
            .options(owner)
            .copyWith(
              // Also release a decoder isolate that never starts in debug mode.
              transformTimeout: freeGhostPreparationTimeout,
            ),
      ),
    )) as Map).cast<String, dynamic>();
    if ((response['playback'] as Map?)?['version'] !=
        'GHOST_PLAYBACK_FREE_V2') {
      throw const FormatException(
        'Free ghost playback version was not negotiated',
      );
    }
    return response;
  }
}
