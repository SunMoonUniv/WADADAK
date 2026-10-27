import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/data/ghost_start_api.dart';

import 'own_ghost_api_test.dart' show Server;
import 'ghost_recovery_support.dart';

void main() {
  test('start and receipt reuse authenticated transport, exact request and account guard', () async {
    final server = Server()..data = ghostApproval(ghostIntent());
    final api = GhostStartApi(
      RunApiClient(
        Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
      ),
    );
    final intent = ghostIntent();
    expect(await api.start(intent), ghostApproval(intent));
    expect(server.requests.single.method, 'POST');
    expect(server.requests.single.data, intent.request);
    expect(server.requests.single.extra['runOwner'], 'alice');
    await api.receipt('alice', ghostId);
    expect(server.requests.last.method, 'GET');
    expect(
      server.requests.last.path,
      '/api/v1/runs/sessions/$ghostId/ghost/start',
    );
    expect(server.requests.last.extra['runOwner'], 'alice');
  });
}
