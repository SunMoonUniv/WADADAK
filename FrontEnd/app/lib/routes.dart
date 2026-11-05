/// 화면 경로. 탭 화면은 각 담당자가 하위 경로를 붙여 나간다.
abstract final class Routes {
  static const login = '/login';
  static const consent = '/onboarding/consent';
  static const permission = '/onboarding/permission';
  static const profile = '/onboarding/profile';

  static const home = '/home';

  /// G1 · G6 검색 결과(코스 · 지역 · 러너 탭). 홈 탭 안에 쌓아 하단 탭이 보인다(Figma G1). 빈 입력으로 연다(SEA-01).
  /// extra: 처음 검색어(`String`, 없어도 된다). 주면 지역 탭에서 그 검색어의 결과로 연다(홈 검색창의 G6 조건).
  /// G6에서 지역을 고르면 `CourseSearchPick`을 돌려주며 닫힌다. 다른 하단 탭에 갔다가 홈으로 돌아오면 닫힌다(FIL-08).
  static const courseSearch = '/home/search';

  /// F3 알림함. A2 오른쪽 위 종 아이콘에서 연다. 홈 탭 안에 쌓아 하단 탭이 보인다(Figma F3).
  static const notifications = '/home/notifications';

  /// B3 코스 만들기(경로 그리기). 하단 탭 위에 쌓는다. extra: 홈 지도 위치(`MapCamera`).
  static const courseCreate = '/course/new';

  /// B4 코스 정보 입력. B3 위에 쌓아 돌아오면 입력점이 그대로다. extra: `GeneratedRoute`.
  static const courseInfo = '/course/new/info';

  /// B6 내 기록에서 코스 등록. B5 `내 기록에서 코스 올리기`가 B3 위에 쌓는다. 하단 탭을 덮는다.
  static const courseFromRecords = '/course/new/records';

  /// D4 달린 경로를 코스로 등록. 달리기 결과 · B6이 러닝 기록 ID로 연다. 하단 탭을 덮는다.
  /// 등록하면 홈 탭으로 가서 지도를 새 코스 출발점으로 옮긴다. 하단 탭을 덮은 화면(B3 · B6 · 기록 보기)은 닫히고,
  /// 달리기 탭의 결과 화면은 그 탭에 남는다.
  static String gpsCourseInfo(String recordId) => '/course/new/gps/${Uri.encodeComponent(recordId)}';

  /// A3 코스 필터. 하단 탭 위에 쌓고, 확정하면 `CourseFilterChoice`를 돌려준다. extra: `CourseFilterRequest`.
  static const courseFilter = '/course/filter';

  /// B1 코스 상세. 하단 탭 위에 쌓아 돌아오면 홈의 탐색 상태(필터 · 지도 위치 · 목록 스크롤)가 그대로다(FIL-08).
  static String courseDetail(String courseId) =>
      '/course/${Uri.encodeComponent(courseId)}';

  /// G2 코스 리뷰 전체. B8 "모두 보기"에서 연다. extra: 코스 이름(String).
  static String courseReviews(String courseId) =>
      '/course/${Uri.encodeComponent(courseId)}/reviews';

  /// G3 코스 전체 순위. B9 "전체 순위 N명 보기"에서 연다. extra: `CourseRankingsArgs`.
  static String courseRankings(String courseId) =>
      '/course/${Uri.encodeComponent(courseId)}/rankings';

  /// B2 리뷰 쓰기 · B10 리뷰 수정. G2 위에 쌓는다. extra: `ReviewFormArgs`.
  static const reviewForm = '/review/form';
  static const run = '/run';

  /// C8 코스 선택(달리기 준비). 하단 탭을 덮는다.
  static const runCourseSelect = '/run/course-select';

  /// C9 내 완주 기록 선택. 현재 계정과 고른 코스의 서버 준비 버전으로 조회한다.
  static const runOwnGhostSelect = '/run/own-ghost-select';
  static const runFreeGhostSelect = '/run/free-ghost-select';
  static const runPublicGhost = '/run/public-ghost';
  static const ranking = '/ranking';
  static const my = '/my';

  /// I1 내 러닝 기록. MY 탭 안에 쌓아 하단 탭이 보인다(Figma I1).
  static const myRecords = '/my/records';

  /// I1에서 고른 기록 하나(달리기 결과 화면을 기록 보기로). 하단 탭을 덮는다.
  static String myRecord(String id) => '/my/record/${Uri.encodeComponent(id)}';

  /// G4 내 코스(등록한 코스 · 저장한 코스). E3 `내가 등록한 코스`에서 연다. MY 탭 안에 쌓아 하단 탭이 보인다(Figma G4).
  static const myCourses = '/my/courses';

  /// G4 화면을 저장한 코스 탭(G5)으로 연다. E3 `저장한 코스`에서 연다.
  static const mySavedCourses = '/my/courses?tab=saved';

  /// B7 코스 수정. G4 카드 [수정]에서 연다. 하단 탭을 덮는다. extra: `MyCourseItem`.
  /// 저장하거나 지우면 바뀐 `MyCourseItem`을 돌려주며 닫힌다.
  static const myCourseEdit = '/my/course-edit';

  /// F6 프로필 편집. E3 [편집]에서 연다. 하단 탭을 덮는다.
  static const myProfileEdit = '/my/profile-edit';

  /// F4 설정. E3 오른쪽 위 설정 아이콘에서 연다. 하단 탭을 덮는다.
  static const mySettings = '/my/settings';
  static const runSettings = '/my/run-settings';

  /// F7 약관 및 정책. F4 `약관 및 개인정보 처리방침`에서 연다. 하단 탭을 덮는다.
  static const myTerms = '/my/terms';

  /// 약관 본문 하나(`TermsDoc.name`). F7과 가입 동의 화면의 `보기 ›`가 연다. 로그인 전에도 열린다.
  static String terms(String doc) => '/terms/$doc';

  /// I5 · 지역 주간 전체 순위
  static const rankingRegion = '/ranking/region';

  /// I6 · 지역 선택
  static const rankingRegionSelect = '/ranking/region/select';

  /// I3 다른 러너 프로필. 하단 탭을 덮는다. extra: 코스 화면(B9 · G3)에서 열면 `RunnerProfileCourse`, 아니면 없다(E1 · I2 · I5).
  static String runnerProfile(String memberId) => '/runner/${Uri.encodeComponent(memberId)}';
}
