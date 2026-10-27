import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';
import '../domain/ghost_run.dart';

abstract interface class GhostStartSource {
  Future<Map<String, dynamic>> start(GhostStartIntent intent);
  Future<Map<String, dynamic>> receipt(String owner, String id);
}

class GhostStartApi implements GhostStartSource {
  GhostStartApi(this.client);
  final RunApiClient client;
  @override
  Future<Map<String, dynamic>> start(GhostStartIntent intent) async =>
      ((await callApi(
        () => client.dio.post<Object?>(
          '/api/v1/runs/sessions/${intent.id}/ghost/start',
          data: intent.request,
          options: client.options(intent.owner),
        ),
      )) as Map).cast<String, dynamic>();
  @override
  Future<Map<String, dynamic>> receipt(String owner, String id) async =>
      ((await callApi(
        () => client.dio.get<Object?>(
          '/api/v1/runs/sessions/$id/ghost/start',
          options: client.options(owner),
        ),
      )) as Map).cast<String, dynamic>();
}
