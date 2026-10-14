import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../domain/recording_models.dart';

class RunApiClient {
  RunApiClient(this.dio);
  final Dio dio;
  Options options(String owner) => Options(extra: {'runOwner': owner});
  Future<Map<String, dynamic>> _map(
    Future<Response<Object?>> Function() request,
  ) async => ((await callApi(request)) as Map).cast<String, dynamic>();
  Future<Map<String, dynamic>> prepare(LocalRun run) => _map(
    () => dio.put<Object?>(
      '/api/v1/runs/sessions/${run.id}',
      data: {
        'mode': 'FREE',
        'startedAt': run.startedAt.toUtc().toIso8601String(),
      },
      options: options(run.owner),
    ),
  );
  Future<Map<String, dynamic>> upload(LocalRun run, List<RunInput> inputs) =>
      _map(
        () => dio.post<Object?>(
          '/api/v1/runs/sessions/${run.id}/record',
          data: {
            'finalSeq': run.inputs.last.seq,
            'inputs': inputs.map((p) => p.toJson()).toList(),
          },
          options: options(run.owner),
        ),
      );
  Future<Map<String, dynamic>> status(LocalRun run) => _map(
    () => dio.get<Object?>(
      '/api/v1/runs/sessions/${run.id}/status',
      options: options(run.owner),
    ),
  );
  Future<Map<String, dynamic>> result(String owner, String id) => _map(
    () => dio.get<Object?>('/api/v1/runs/records/$id', options: options(owner)),
  );
  Future<Map<String, dynamic>> history(String owner, {String? cursor}) => _map(
    () => dio.get<Object?>(
      '/api/v1/runs/records',
      queryParameters: {'cursor': ?cursor},
      options: options(owner),
    ),
  );
}
