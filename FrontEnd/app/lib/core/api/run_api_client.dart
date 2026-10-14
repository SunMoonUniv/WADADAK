import 'package:dio/dio.dart';

import 'api_client.dart';
import 'run_upload.dart';
export 'run_upload.dart';

class RunApiClient {
  RunApiClient(this.dio);
  final Dio dio;
  Options options(String owner) => Options(extra: {'runOwner': owner});
  Future<Map<String, dynamic>> _map(
    Future<Response<Object?>> Function() request,
  ) async => ((await callApi(request)) as Map).cast<String, dynamic>();
  Future<Map<String, dynamic>> prepare(RunUpload run) => _map(
    () => dio.put<Object?>(
      '/api/v1/runs/sessions/${run.id}',
      data: {
        'mode': 'FREE',
        'startedAt': run.startedAt.toUtc().toIso8601String(),
      },
      options: options(run.owner),
    ),
  );
  Future<Map<String, dynamic>> upload(
    RunUpload run,
    List<Map<String, dynamic>> inputs,
  ) => _map(
    () => dio.post<Object?>(
      '/api/v1/runs/sessions/${run.id}/record',
      data: {'finalSeq': run.finalSeq, 'inputs': inputs},
      options: options(run.owner),
    ),
  );
  Future<Map<String, dynamic>> status(RunUpload run) => _map(
    () => dio.get<Object?>(
      '/api/v1/runs/sessions/${run.id}/status',
      options: options(run.owner),
    ),
  );
  Future<Map<String, dynamic>> result(String owner, String id) => _map(
    () => dio.get<Object?>('/api/v1/runs/records/$id', options: options(owner)),
  );
  Future<void> delete(String owner, String id) async {
    final result = await _map(
      () => dio.delete<Object?>(
        '/api/v1/runs/records/$id',
        options: options(owner),
      ),
    );
    if (result['deleted'] != true || result['id'] != id) {
      throw const ApiException(ApiException.network, '서버의 삭제 확인을 기다리고 있어요.');
    }
  }

  Future<Map<String, dynamic>> history(String owner, {String? cursor}) => _map(
    () => dio.get<Object?>(
      '/api/v1/runs/records',
      queryParameters: {'cursor': ?cursor},
      options: options(owner),
    ),
  );
}
