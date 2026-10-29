import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';

abstract interface class PublicGhostSource {
  Future<Map<String, dynamic>> prepare(
    String owner,
    String sourceId,
    String courseId,
    String period,
  );
}

class PublicGhostApi implements PublicGhostSource {
  PublicGhostApi(this.client);
  final RunApiClient client;
  @override
  Future<Map<String, dynamic>> prepare(
    String owner,
    String sourceId,
    String courseId,
    String period,
  ) async => ((await callApi(
    () => client.dio.get<Object?>(
      '/api/v1/runs/records/$sourceId/public-ghost-playback',
      queryParameters: {'courseId': courseId, 'period': period},
      options: client.options(owner),
    ),
  )) as Map).cast<String, dynamic>();
}
