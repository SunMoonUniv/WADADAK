import '../../../core/api/api_client.dart';
import '../../../core/api/run_api_client.dart';
import '../domain/own_ghost.dart';

abstract interface class OwnGhostSource {
  Future<OwnGhostPage> candidates(
    String owner,
    GhostCourseContext course, {
    required OwnGhostSort sort,
    required OwnGhostPeriod period,
    String? cursor,
  });
  Future<OwnGhostReplay> playback(String owner, String recordId);
}

/// Reuses the authenticated RunApiClient transport and its account-bound request options.
class OwnGhostApi implements OwnGhostSource {
  OwnGhostApi(this.client);
  final RunApiClient client;

  @override
  Future<OwnGhostPage> candidates(
    String owner,
    GhostCourseContext course, {
    required OwnGhostSort sort,
    required OwnGhostPeriod period,
    String? cursor,
  }) async {
    final body = await callApi(
      () => client.dio.get<Object?>(
        '/api/v1/runs/ghost-candidates/own',
        queryParameters: {
          'courseId': course.id,
          'courseVersion': course.version,
          'sort': sort.name.toUpperCase(),
          'period': period.name.toUpperCase(),
          'cursor': ?cursor,
        },
        options: client.options(owner),
      ),
    );
    return OwnGhostPage.fromJson((body as Map).cast<String, dynamic>());
  }

  @override
  Future<OwnGhostReplay> playback(String owner, String recordId) async {
    final body = await callApi(
      () => client.dio.get<Object?>(
        '/api/v1/runs/records/$recordId/ghost-playback',
        options: client.options(owner),
      ),
    );
    return OwnGhostReplay.fromJson((body as Map).cast<String, dynamic>());
  }
}
