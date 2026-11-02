import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/api/run_api_client.dart';

/// 러닝 기록의 코스 등록용 경로(달리기 서버 `GET /api/v1/runs/records/{id}/course-source`). D4 · B6가 쓴다.
///
/// 달리기 서버 API는 core의 [RunApiClient] 하나로 부른다. 그 연결을 빌려 코스 등록에 쓰는 호출만 여기 둔다
/// (`features/run/data/own_ghost_api.dart`와 같은 방식). 달리기 담당 파일은 고치지 않는다.
class RunCourseSourceApi {
  RunCourseSourceApi(this._client);

  final RunApiClient _client;

  /// Registration already succeeded. A separate status failure must never trigger registration again.
  Future<String> completionMessage(String recordId) async {
    const pending = '원본 기록을 이 코스의 완주 기록으로 연결하고 있어요. 반영에는 잠시 시간이 걸릴 수 있어요.';
    const unknown = '원본의 완주 기록 연결 상태는 잠시 후 코스 기록에서 확인해 주세요.';
    try {
      final data = await callApi(
        () => _client.dio.get<Object?>(
          '/api/v1/runs/records/${Uri.encodeComponent(recordId)}/gps-course-link',
        ),
      ).timeout(const Duration(seconds: 3));
      if (data is! Map) return unknown;
      return switch (data['status']) {
        'LINKED' => '원본 기록이 이 코스의 완주 기록으로 연결됐어요.',
        'PENDING' || 'NOT_RECEIVED' => pending,
        'REJECTED' => '코스는 등록됐지만 원본 기록을 확인하지 못해 완주 기록으로 연결하지 못했어요.',
        'REMOVED' => '코스는 등록됐어요. 원본 기록이 삭제되어 완주 기록 연결은 해제됐어요.',
        _ => unknown,
      };
    } on ApiException {
      return unknown;
    } on TimeoutException {
      return unknown;
    }
  }

  /// 결과 화면 지도와 같은 인정 경로를 끊긴 곳(일시정지 · GPS 공백 · 튐)마다 나눈 조각. 달린 순서이고 조각 사이는 잇지 않았다.
  /// 없는 기록 · 다른 회원의 기록은 달리기 서버 오류(`RUN-002`)다.
  Future<List<List<GpsSourcePoint>>> segments(String recordId) async {
    final data = await callApi(
      () => _client.dio.get<Object?>('/api/v1/runs/records/${Uri.encodeComponent(recordId)}/course-source'),
    );
    return [
      for (final segment in (data! as Map)['segments']! as List)
        [for (final point in segment as List) GpsSourcePoint.fromJson(point as Map)],
    ];
  }
}

final runCourseSourceApiProvider =
    Provider<RunCourseSourceApi>((ref) => RunCourseSourceApi(RunApiClient(ref.watch(dioProvider))));
