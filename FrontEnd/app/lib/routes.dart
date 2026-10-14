/// 화면 경로. 탭 화면은 각 담당자가 하위 경로를 붙여 나간다.
abstract final class Routes {
  static const login = '/login';
  static const consent = '/onboarding/consent';
  static const permission = '/onboarding/permission';
  static const profile = '/onboarding/profile';

  static const home = '/home';

  /// B3 코스 만들기(경로 그리기). 하단 탭 위에 쌓는다. extra: 홈 지도 위치(`MapCamera`).
  static const courseCreate = '/course/new';

  /// B4 코스 정보 입력. B3 위에 쌓아 돌아오면 입력점이 그대로다. extra: `GeneratedRoute`.
  static const courseInfo = '/course/new/info';
  static const run = '/run';
  static const ranking = '/ranking';
  static const my = '/my';
  static const runHistory = '/my/runs';
  static const runSettings = '/my/run-settings';
  static String runRecord(String id) =>
      '$runHistory/${Uri.encodeComponent(id)}';

  /// I5 · 지역 주간 전체 순위
  static const rankingRegion = '/ranking/region';

  /// I6 · 지역 선택
  static const rankingRegionSelect = '/ranking/region/select';
}
