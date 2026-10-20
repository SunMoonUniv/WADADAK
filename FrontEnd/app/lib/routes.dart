/// 화면 경로. 탭 화면은 각 담당자가 하위 경로를 붙여 나간다.
abstract final class Routes {
  static const login = '/login';
  static const consent = '/onboarding/consent';
  static const permission = '/onboarding/permission';
  static const profile = '/onboarding/profile';

  static const home = '/home';

  /// G1 검색 결과(코스 · 지역 · 러너 탭). 홈 탭 안에 쌓아 하단 탭이 보인다(Figma G1). 빈 입력으로 연다(SEA-01).
  /// 다른 하단 탭에 갔다가 홈으로 돌아오면 닫힌다(FIL-08).
  static const courseSearch = '/home/search';

  /// B3 코스 만들기(경로 그리기). 하단 탭 위에 쌓는다. extra: 홈 지도 위치(`MapCamera`).
  static const courseCreate = '/course/new';

  /// B4 코스 정보 입력. B3 위에 쌓아 돌아오면 입력점이 그대로다. extra: `GeneratedRoute`.
  static const courseInfo = '/course/new/info';

  /// A3 코스 필터. 하단 탭 위에 쌓고, 확정하면 `CourseFilterChoice`를 돌려준다. extra: `CourseFilterRequest`.
  static const courseFilter = '/course/filter';

  /// B1 코스 상세. 하단 탭 위에 쌓아 돌아오면 홈의 탐색 상태(필터 · 지도 위치 · 목록 스크롤)가 그대로다(FIL-08).
  static String courseDetail(String courseId) => '/course/${Uri.encodeComponent(courseId)}';

  /// G2 코스 리뷰 전체. B8 "모두 보기"에서 연다. extra: 코스 이름(String).
  static String courseReviews(String courseId) => '/course/${Uri.encodeComponent(courseId)}/reviews';

  /// G3 코스 전체 순위. B9 "전체 순위 N명 보기"에서 연다. extra: `CourseRankingsArgs`.
  static String courseRankings(String courseId) => '/course/${Uri.encodeComponent(courseId)}/rankings';

  /// B2 리뷰 쓰기 · B10 리뷰 수정. G2 위에 쌓는다. extra: `ReviewFormArgs`.
  static const reviewForm = '/review/form';
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
