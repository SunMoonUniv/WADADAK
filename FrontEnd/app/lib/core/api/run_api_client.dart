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

  /// 코스 러닝 준비(C6, 측정 시작 전). 코스 공개 여부를 확인하고 판정용 경로 스냅샷을 받는다(정책 D-08).
  Future<Map<String, dynamic>> prepareCourse(String owner, String id, String courseId) => _map(
    () => dio.put<Object?>(
      '/api/v1/runs/sessions/$id/course',
      data: {'courseId': courseId},
      options: options(owner),
    ),
  );

  /// 코스 러닝 시작 신호(카운트다운 끝). [startedAt]은 기록의 시작 시각과 같아야 업로드 준비가 맞는다.
  Future<void> startCourse(String owner, String id, DateTime startedAt) => callApi(
    () => dio.post<Object?>(
      '/api/v1/runs/sessions/$id/course/start',
      data: {'startedAt': startedAt.toUtc().toIso8601String()},
      options: options(owner),
    ),
  );

  /// ③ 코스 구간 종료 신호(현재 러너 수에서 뺀다). 판정 경계는 기록의 `SEGMENT_END`이고 이 신호는 쓰지 않는다
  Future<void> segmentEnd(String owner, String id) => callApi(
    () => dio.post<Object?>('/api/v1/runs/sessions/$id/course/segment-end', options: options(owner)),
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
  Future<Map<String,dynamic>> ghostResult(String owner,String id)=>_map(
    ()=>dio.get<Object?>('/api/v1/runs/sessions/$id/ghost/result',options:options(owner)));
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
