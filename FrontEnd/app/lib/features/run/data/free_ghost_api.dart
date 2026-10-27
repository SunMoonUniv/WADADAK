import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';
import '../domain/free_ghost.dart';

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
  Future<Map<String, dynamic>> prepare(String owner, String id) async =>
      ((await callApi(
        () => client.dio.get<Object?>(
          '/api/v1/runs/records/$id/free-ghost-playback',
          options: client.options(owner),
        ),
      )) as Map).cast<String, dynamic>();
}
