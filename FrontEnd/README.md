
# 와다닥 앱

와다닥 러닝 앱의 Flutter 클라이언트.

- 디자인: [Figma · 몰입형 디자인](https://www.figma.com/design/AHA57jFG1znDzxdmGWHGUm/%EB%AA%B0%EC%9E%85%ED%98%95-%EB%94%94%EC%9E%90%EC%9D%B8?node-id=1453-2946)
  - `디자인 · 전체 화면 (와이어프레임 기준)` 페이지 — **구현 기준 화면** (위 링크)
  - `🧱 와다닥 디자인 시스템` 페이지 — 토큰 · 컴포넌트 (컴포넌트 설명에 대응하는 Flutter 위젯 이름이 적혀 있다)
  - 화면 사이 흐름은 Figma 프로토타입으로 확인한다.

## 현재 상태

| 영역 | 상태 |
|---|---|
| 디자인 토큰 — 색 · 간격 · 반경 · 그림자 · 글자 스타일 52종 | ✅ 완료 |
| 테마 (`WdTheme.light()`) · 아이콘 26개 · 로고 · 글꼴(Pretendard) | ✅ 완료 |
| 공통 컴포넌트 위젯 62개 | ✅ 완료 |
| 컴포넌트 카탈로그 앱 + 스모크 테스트 | ✅ 완료 |
| Figma 디자인 시스템 페이지 (변수 · 스타일 · 컴포넌트 82개 / 29세트) | ✅ 완료 |
| 앱 프로젝트 (`app/`) — Riverpod · go_router · dio, 하단 탭 4개 | ✅ 뼈대 |
| 화면 | 🟡 14 / 72 (온보딩: A1 · 소셜 정보 동의 · 권한 안내 · F2, 코스: B3 경로 그리기 · B5 코스 정보 입력, 랭킹: E1 · I2 · I5 · I6, 리뷰: G2 · B2 · B10 · B10-1) |
| 로그인 · 토큰 저장 · 자동 갱신 | 🟡 서버 연동 · 카카오 SDK 완료, Google · Apple SDK는 아직 |
| 지도 — `core/map` (네이버 지도 SDK 래퍼 · 키 없이 도는 개발용 지도) | 🟡 홈 탭에 연결, 축척에 따라 지도 범위 안 코스 경로 · 이름표 / 지역별 코스 수 배지 |
| API · 위치 추적 연동 | 🟡 코스 API(경로 생성 · 오늘 남은 등록 수 · 이름 확인 · 등록 · 지도 범위 안 코스 · 지역별 코스 수 · 코스 목록) · 랭킹 API(서버 거리 집계는 아직 스텁) · 리뷰 API(요약 · 목록 · 내 리뷰 · 작성 · 수정 · 삭제 · 지도 평점) · 지역 검색 API · 사진 업로드(`core/upload`, 리뷰 업로드 폼), 위치 추적은 시작 전 |

즉 **디자인 시스템과 앱 뼈대, 온보딩, 랭킹 탭까지 준비된 상태**다. 홈 탭은 지도(축척에 따라 범위 안 코스 또는 지역별 코스 수 표시), 아래 코스 목록 시트(최신순 · 가까운순 · 필터 A3), 코스 만들기 · 등록(B3 · B5)만 있고, 달리기 · MY 탭은 자리만 있다.

### 구현된 컴포넌트

| 분류 | 위젯 |
|---|---|
| 기본 | `WdSurface` `WdIcon` `WdLogo` |
| 버튼 | `WdButton` `WdBottomBar` `WdSocialLoginButton` |
| 내비게이션 | `WdAppBar` `WdTabBar` `WdBottomNav` `WdSegmentedControl` |
| 칩 · 태그 | `WdTag` `WdFilterChip` |
| 입력 | `WdTextField` `WdSearchBar` `WdSearchHeader` `WdSwitch` `WdConsentRow` `WdRatingRow` `WdPhotoUpload` `WdStepper` |
| 피드백 | `WdInfoBanner` `WdStateMessage` `WdProgressBar` `WdRemainingDistance` |
| 목록 | `WdListRow` `WdMenuCard` `WdSectionHeading` `WdStepRow` |
| 카드 | `WdSummaryTile(s)` `WdMetric` `WdStatSummary` `WdAvatar` `WdRouteThumbnail` `WdCourseCard` `WdRunRecordCard` `WdReviewCard` |
| 랭킹 | `WdRankRow` `WdRankList` `WdMyRankCard` |
| 러닝 | `WdRunHeader` `WdElapsedTime` `WdRunMetricTile` `WdLapRecords` `WdGhostLeadCard` `WdCourseProgress` `WdPageIndicator` `WdRunPauseButton` `WdRunPausedButtons` `WdSensorStatus` `WdSelectedCourseCard` `WdRecordCard` |
| 지도 위 요소 | `WdMapLocateButton` `WdKmMarker` `WdRoutePoint` `WdRegionCountBubble` `WdSheetPeek` `WdMapHint` `WdMapPillButton` `WdRouteEndpoint` `WdRouteLegend` `WdMapCourseLabel` |
| 분석 | `WdSegmentChart` `WdSegmentTable` |

Figma 컴포넌트와의 1:1 대응표, 토큰 사용법은 [디자인 시스템 README](packages/wadadak_design_system/README.md)에 있다.

## 디렉터리 구조

```
FrontEnd/
├─ README.md
├─ app/                                 # ✅ 실제 앱
│  └─ lib/
│     ├─ main.dart                      # ProviderScope + MaterialApp.router
│     ├─ router.dart · routes.dart      # 로그인 상태로 화면 분기 (A1 · 온보딩 · 탭)
│     ├─ main_shell.dart                # 하단 탭 4개 (각 탭은 담당자가 채운다)
│     ├─ core/                          # API 클라이언트 · 인증 · 위치 · 사진 업로드 · 공통 오류/빈 상태 화면
│     │  ├─ config.dart                 #   서버 주소 (API_BASE_URL) · 로그인 · 지도 방식과 공개 키
│     │  ├─ api/                        #   Dio · ApiResult 해석 · 서버 모듈별 클라이언트
│     │  ├─ auth/                       #   로그인 상태 · 토큰 보안 저장 · 401 자동 갱신 · 소셜 로그인
│     │  └─ map/                        #   MapView · MapController (화면은 이것만 쓴다)
│     └─ features/                      # Figma 디자인 페이지 섹션 단위
│        ├─ onboarding/                 #   🚪 온보딩 (A1 · 동의 · 권한 · 프로필)
│        ├─ home/                       #   🏠 홈 · 코스 탐색
│        ├─ course/                     #   📍 코스 상세 · 만들기
│        ├─ run/                        #   🏃 달리기 준비 · ⏱ 러닝 중 · 📊 러닝 결과 · 분석
│        ├─ ranking/                    #   🏆 랭킹 (E1 · I2 · I5 · I6)
│        ├─ review/                     #   💬 리뷰 · 커뮤니티
│        └─ my/                         #   👤 MY · 설정
└─ packages/
   └─ wadadak_design_system/            # ✅ 디자인 시스템
      ├─ lib/
      │  ├─ wadadak_design_system.dart  #   앱은 이것 하나만 import
      │  └─ src/
      │     ├─ tokens.dart              #   색 · 간격 · 반경 · 그림자 · 글자 스타일
      │     ├─ theme.dart               #   MaterialApp 테마
      │     ├─ icons.dart               #   WdIcon · WdLogo
      │     └─ components/              #   위젯 (분류별 13개 파일)
      ├─ assets/
      │  ├─ icons/                      #   SVG 26개
      │  └─ fonts/                      #   Pretendard 400 · 500 · 700 · 800 + 라이선스
      └─ example/                       #   컴포넌트 카탈로그 앱 + 스모크 테스트
```

`features/` 아래 온보딩 · 랭킹 외 폴더는 각 담당자가 화면을 만들 때 생긴다.

## 앱 실행

앱은 기본으로 로컬 백엔드(`BackEnd/`)에 붙는다. [백엔드 README](../BackEnd/README.md)의 로컬 실행을 먼저 한다.

```bash
cd app
flutter pub get
flutter run                                                        # Android 에뮬레이터 → http://10.0.2.2:8080
flutter run --dart-define=API_BASE_URL=http://localhost:8080       # iOS 시뮬레이터
flutter run --dart-define=API_BASE_URL=http://<PC의 IP>:8080        # 실기기 (같은 와이파이)
flutter run --dart-define=API_BASE_URL=https://api.leedohyunn8n.shop # 팀 공용 서버 (실기기, 어디서나)
flutter test
```

- **팀 공용 서버** `https://api.leedohyunn8n.shop`: main의 서버가 자동 배포돼 있어 로컬 서버 없이 실기기로 시험한다. 팀이 회원 · 데이터를 함께 쓴다. 실제 소셜 검증이라 가짜 로그인(`REAL_SOCIAL_LOGIN=false`)으로는 붙지 않는다. 운영 · 상태는 [`deploy/README.md`](../deploy/README.md).

- PR마다 GitHub Actions(`.github/workflows/frontend.yml`, Flutter 3.47.6)가 디자인 시스템과 앱의 `dart analyze` · `flutter test`를 돌린다.
- 로그인 버튼은 카카오 SDK로 실제 로그인한다. 서버도 기본이 실제 검증이라 따로 설정하지 않는다. 에뮬레이터에는 카카오톡이 없어 카카오계정(웹) 로그인 창이 뜬다.
  - **공용 디버그 키 필요**: 팀 공용 `debug.keystore`를 팀 내부 공유처에서 받아 `app/android/app/debug.keystore`에 둔다. 저장소가 공개라 커밋하지 않는다(`.gitignore`). 없으면 각자 PC의 기본 디버그 키로 서명돼 키 해시가 달라 카카오 로그인이 실패한다.
  - 카카오 콘솔에는 공용 디버그 키의 해시만 등록돼 있다. 출시 전에 디버그 키 해시는 빼고 출시용 키 해시만 남긴다.
  - Google · Apple 로그인은 아직 연결하지 않았다.
- **가짜 로그인**(카카오 계정 없이)으로 시험하려면 앱과 서버를 둘 다 가짜 모드로 띄운다(한쪽만 바꾸면 로그인이 실패하거나 매번 새 회원이 생긴다). 설치마다 같은 ID를 써서, 같은 기기는 같은 회원으로 로그인한다. 새 회원으로 시험하려면 앱 데이터를 지운다.
  ```bash
  # BackEnd/
  ./gradlew bootRun --args='--app.member.social.fake=true'
  # FrontEnd/app/
  flutter run --dart-define=REAL_SOCIAL_LOGIN=false
  ```
- 지도는 네이버 지도 SDK다. Client ID는 `core/config.dart`의 공개 값이다(NCP 콘솔 Application에 앱 ID `com.wadadak.app`으로 등록, Client Secret은 쓰지 않는다).
  - 화면은 `core/map`의 `MapView`만 쓴다. 선 · 표지는 값으로 넘기고, 카메라는 `onCreated`로 받은 `MapController`로 움직인다.
  - 현재 위치: 홈은 지도 SDK가 기기 위치를 받는다(`MyLocationSource.map`, 기본). 러닝은 측정한 좌표를 넘긴다(`MyLocationSource.app` + `myLocation`). 둘 다 `showMyLocation()`으로 따라가고, 지도를 움직이면 따라가기가 꺼진다(`onFollowingChanged`). `showMyLocation(follow: false)`는 현재 위치 점만 보이고 카메라는 그대로 둔다(홈 현재 위치 버튼). `hideMyLocation()`으로 끝낸다.
  - 선 모양은 쓰는 곳마다 나눈다: 홈 · 코스 만들기 코스선 `course`(라임), 러닝 화면 코스선 `runCourse`(흰색), 러닝 주행선 `track`(라임, 코스선 위).
  - 러닝 화면은 `MapView(dark: true)` — 네이버 지도 야간 모드(내비 지도 유형).
  - 지도 위에 버튼 · 범례를 올리면 그 높이만큼 `padding`을 준다. 네이버 로고 · 축척이 그 위로 올라가 가리지 않는다(네이버 지도는 로고를 가리면 안 된다).
  - 거리는 `GeoPoint.distanceTo` · `GeoPoint.pathLength` — 서버(PostGIS `ST_Length(geography)`)와 같은 WGS84 타원체 기준이다.
  - 키 없이 시험하려면 `flutter run --dart-define=REAL_MAP=false` — 개발용 지도(배경색 위에 선 · 표지만)가 뜬다. 위젯 테스트는 `mapEngineProvider`를 `MapEngine.dev`로 바꾼다.
- 저장소 경로에 한글(예: `바탕화면\와다닥`)이 있으면:
  - Android 빌드: `app/android/gradle.properties`의 `android.overridePathCheck=true`로 이미 막아 두었다.
  - `flutter analyze`가 분석 서버 오류로 멈춘다. 대신 `dart analyze`를 쓴다.
- 앱 ID `com.wadadak.app`으로 확정했고 카카오 콘솔에 등록했다(스토어 출시 후에는 바꿀 수 없다).

## 남은 단계

### 1. 개발 환경
- [ ] Flutter SDK 최신 stable 설치 (3.47.6에서 확인 · 3.32 미만은 `flutter_lints 6` 설치 실패) — `flutter doctor`로 확인
- [ ] 카탈로그 앱 실행 확인: `cd packages/wadadak_design_system/example && flutter run -d chrome`
- Android 빌드가 `Android sdkmanager did not install NDK ...`로 실패하면: 새 Command-line Tools는 패키지 이름이 `ndk/버전` 형식이라 Gradle의 NDK 자동 설치가 실패한다. 오류에 나온 버전을 직접 설치한다 — `<Android SDK>/cmdline-tools/latest/bin/android sdk install ndk/28.2.13676358` 또는 Android Studio SDK Manager → SDK Tools → NDK (Side by side) → Show Package Details
- 아마 알겠지만 git clone 하면 pubspec.lock과 .dart_tool/ 이게 없어서 빌드 하다 오류 날 수도 있으니, 안드로이드 스튜디오면 packages/wadadak_design_system/pubspec.yaml 이거 열어서 Pub get 하거나, 터미널에 명령어 입력하셈 : `cd packages/wadadak_design_system && flutter pub get && cd example && flutter pub get` 

### 2. 팀 결정
- [x] 상태 관리 Riverpod 3 · 화면 이동 go_router · HTTP 클라이언트 dio
- [x] 지도 SDK — 네이버 지도 API
- [ ] 위치 추적 방식 — 러닝 중 백그라운드 위치 권한 포함
- [ ] 소셜 로그인 SDK — 카카오 · Google 먼저. Apple은 보류(iOS 심사 전 필요: App Store 심사 지침 4.8)
- [ ] 백엔드와 API 명세 · 기능별 인터페이스 정의

### 3. 앱 뼈대
- [x] `flutter create app` 후 디자인 시스템 연결
- [x] `MaterialApp.router(theme: WdTheme.light())`, 라우팅, 하단 탭 4개 (홈 · 달리기 · 랭킹 · MY — `WdBottomNav` 기본값)

### 4. 화면 구현 (14 / 72)

Figma `디자인 · 전체 화면 (와이어프레임 기준)` 페이지의 섹션 순서 그대로다.
처음에는 가짜 데이터로 화면만 만들고, API는 나중에 붙인다. 화면 코드에는 색 · 간격 · 글꼴 값을 직접 쓰지 않고 디자인 시스템 토큰과 위젯만 쓴다.

<details>
<summary>🚪 온보딩 (4 / 6)</summary>

- [ ] A0-1 · 소개 — 코스 공유
- [ ] 소개 — 고스트 대결 (Figma 프레임 이름이 `Frame`)
- [x] A1 · 스플래시 / 로그인 — Apple 버튼은 보류로 숨김
- [x] 소셜 정보 동의 (선택 전 · 선택 후) — "보기 ›"는 약관 본문(F7)이 생기면 연결
- [x] 권한 안내 (위치 · 동작 및 피트니스)
- [x] F2 · 프로필 초기 설정 — 프로필 사진(선택)은 시작하기를 누를 때 가입 토큰으로 받은 업로드 폼으로 올리고 그 키로 가입한다(`core/upload`). 활동 지역은 시·군·구 검색(로그인 전이라 공용 지역 검색 API를 쓴다)

카카오 로그인 화면(Figma `카카로 로그인`)은 참고 이미지다. 카카오 SDK가 띄우는 화면이라 직접 만들지 않는다.
</details>

<details>
<summary>🏠 홈 · 코스 탐색 (0 / 9)</summary>

- [ ] A2 · 홈 (공통 지도 + 코스 리스트)
- [ ] A3 · 코스 필터
- [ ] A4 · 홈 — 지도 축소 (지역별 개수)
- [ ] A5 · 홈 — 지도 전체 보기 (코스 표시)
- [ ] A6 · 홈 — 코스 목록 전체 보기
- [ ] G1 · 검색 결과
- [ ] G6 · 검색 결과 (지역)
- [ ] G7 · 검색 결과 (러너)
- [ ] G8 · 검색 결과 없음
</details>

<details>
<summary>📍 코스 상세 · 만들기 (2 / 9)</summary>

- [ ] B1 · 코스 상세 — 정보
- [ ] B8 · 코스 상세 — 리뷰
- [ ] B9 · 코스 상세 — 랭킹
- [ ] G3 · 코스 전체 순위
- [x] B3 · 코스 만들기 (경로 그리기) — 생성 방식 탭의 `내가 달려서 등록`은 자리만(F7)
- [ ] B4 · 코스 만들기 — 내가 달려서 등록
- [x] B5 · 코스 정보 입력 & 등록 — 정책 문서 ID는 B4. 등록하면 홈 지도가 새 코스 출발점으로 옮겨 간다(지도에 코스를 그리는 건 홈 · 코스 탐색에서)
- [ ] B6 · 내 기록에서 코스 등록
- [ ] B11 · 코스 공개 기간 안내 (시트)
</details>

<details>
<summary>🏃 달리기 준비 (기본 연결 1 / 7 · 검증 범위는 아래 표)</summary>

- [x] C5 · 달리기 준비 — 자유 러닝 기본 시작 연결. 최근 카드의 서버 기록 통합은 후속
- [ ] C6 · 달리기 준비 — 코스 러닝
- [ ] C1 · 달리기 준비 — 고스트 대결
- [ ] C2 · 고스트 러너 선택
- [ ] C8 · 코스 선택 (달리기 준비)
- [ ] C9 · 고스트 선택 — 내 기록 전체
- [ ] C10 · 고스트 선택 — 다른 러너 전체
</details>

<details>
<summary>⏱ 러닝 중 — 카운트다운 · 실시간 (기본 연결 2 / 8 · 자유 러닝 지표는 부분 구현)</summary>

- [ ] H1 · 시작 카운트다운 (코스 러닝)
- [x] H4 · 시작 카운트다운 (자유 러닝) — 1초 누르기·3초 카운트다운·취소
- [ ] H5 · 시작 카운트다운 (고스트 대결)
- [ ] C4 · 러닝 중 — 고스트 대결 (기본 · 왼쪽 슬라이드 지도 C4-1 · 오른쪽 슬라이드 상세 지표 C4-2)
- [ ] C4 · 러닝 중 — 코스 러닝 (기본 · 지도 C4-1 · 상세 지표 C4-2)
- [ ] C4 · 러닝 중 — 자유 러닝: 측정·지도·좌우 슬라이드·페이스·랩·케이던스 구현. 최고 페이스 등 결과 지표는 후속
- [ ] C4-3 · 러닝 중 — 경로 이탈 (지도)
- [x] 러닝 일시정지 — 자유 러닝 정지·재개·종료 확인 연결
</details>

<details>
<summary>📊 러닝 결과 · 분석 (0 / 8)</summary>

- [ ] D1 · 러닝 결과 (종합 기록)
- [ ] D1-1 · 러닝 결과 — 코스 완주 미인정
- [ ] D1-2 · 러닝 결과 — 자유 러닝: 저장 상태·시간·거리·랩·경로·케이던스 구현. 코스 등록·공유·분석·최고 지표는 후속
- [ ] D2 · 고스트 대결 결과
- [ ] D3 · 구간별 상세 분석
- [ ] D5 · 구간별 케이던스 분석
- [ ] D6 · 구간별 고도 분석
- [ ] D4 · 달린 경로를 코스로 등록 (GPS)
</details>

<details>
<summary>👤 MY · 설정 (0 / 10)</summary>

- [ ] E3 · 마이페이지 (뱃지 · 업적)
- [ ] I1 · 내 러닝 기록 (히스토리): 기본 목록·상세·삭제·재전송 구현. 유형/월 필터·통계·주간 차트는 MY 협업 후속
- [ ] G4 · 내가 등록한 코스 관리
- [ ] G5 · 내 코스 — 저장한 코스
- [ ] B7 · 코스 수정
- [ ] I3 · 다른 러너 프로필
- [ ] F4 · 설정
- [ ] F5 · 설정 선택 시트 (공통)
- [ ] F6 · 프로필 편집
- [ ] F7 · 약관 및 정책
</details>

<details>
<summary>🏆 랭킹 (4 / 4)</summary>

- [x] E1 · 랭킹 — 전체 러너 / 지역 주간 — 러너를 누르면 I3로 가는 연결은 I3가 생기면 추가. 내 순위 카드 이름은 `나`(내 프로필 조회 API가 생기면 `나 (닉네임)`)
- [x] I2 · 지역 주간 랭킹
- [x] I5 · 지역 주간 전체 순위
- [x] I6 · 지역 선택 — 최근 선택은 로그인한 동안만 기억
</details>

<details>
<summary>💬 리뷰 · 커뮤니티 (4 / 4)</summary>

- [x] B2 · 코스 리뷰 작성 — 진입은 G2 "리뷰 작성하기"(리뷰 자격이 있는 가장 최근 기록이 근거)
- [x] G2 · 코스 리뷰 전체 — B8 "모두 보기"에서 `Routes.courseReviews(courseId)`, extra로 코스 이름. B8(코스 담당)이 생기면 연결
- [x] B10 · 리뷰 수정
- [x] B10-1 · 리뷰 수정 — 근거 기록 삭제됨
</details>

<details>
<summary>⚠️ 오류 · 빈 상태 (0 / 7)</summary>

- [ ] 위치 권한 꺼짐
- [ ] GPS 신호 약함
- [ ] 러닝 중 GPS 신호 끊김
- [ ] 러닝 중 경로 이탈 (기본 화면)
- [ ] 네트워크 오류
- [ ] 주변 코스 없음
- [ ] 러닝 기록 없음
</details>

### 5. 연동
- [x] 소셜 로그인 — 카카오 SDK (`core/auth/social_login.dart`의 `SdkSocialLogin`, 에뮬레이터에서 가입·로그인 확인)
- [ ] 소셜 로그인 — Google · Apple SDK
- [x] 토큰 보안 저장 · 401 자동 갱신(갱신은 한 번에 하나) · 로그아웃
- [x] 위치 · 동작 및 피트니스 권한 요청 (권한 안내 화면 순서대로)
- [ ] API 연결 (가짜 데이터 → 실제 데이터)
  - [x] 코스: 경로 생성 · 오늘 남은 등록 수 · 이름 확인 · 등록 · 지도 범위 안 코스 · 지역별 코스 수 · 코스 목록 (`core/api/course_api_client.dart`)
  - [x] 랭킹: 누적 거리 · 지역 주간 랭킹 (`core/api/ranking_api_client.dart`)
  - [x] 지역: 시·군·구 검색, 로그인 없이 (`core/api/region_api_client.dart`) — 가입 활동 지역 · I6가 같은 검색 화면(`core/region_search.dart`)을 쓴다
- [x] 지도 SDK 연결 — `core/map` `MapView`(선 · 표지 · 누른 위치 · 카메라 범위 · 축척 · 현재 위치 · 러닝 좌표 따라가기), 홈 탭에 표시
- [ ] 지도 위 코스 경로 · km 표지 · 지역별 개수 표시 (각 화면에서)
  - [x] 홈: 지도 범위 안 코스 경로 · 이름표 — 지도가 멈출 때마다 다시 받는다
  - [x] 홈: 지역별 코스 수 배지(A4) — 축척 500m보다 넓으면 구 단위, 2km보다 넓으면 시 단위(MAP-02). 배지를 누르면 그 지역을 시트 위로 보이는 지도의 한가운데로 옮기며 한 단계 확대(시 → 축척 2km, 구 → 500m, A4-06)
  - [x] 홈: 현재 위치 버튼(A4-05 · A5-05) — 현재 위치를 시트 위로 보이는 지도의 한가운데로 옮기며 축척 100m로 확대하고, 현재 위치 점만 보인다(지도는 따라가지 않음). 권한이 없으면 묻고, 거부 · 위치 실패면 안내(가까운순과 같은 `LocationService`)
- [ ] 홈 상단 배너 — A2는 인사말, A4 · A5 · A6는 제목 `코스`, 아래 검색창(누르면 G1, G1이 생기면 연결)
- [ ] 홈 코스 목록 시트 — 제목 줄을 끌어 피크(A4 · A5) · 반(A2) · 전체(A6, 배너 밑까지)에 멈춘다. 목록은 반에서도 따로 스크롤된다. 시트에 가리지 않고 보이는 지도 범위를 지도 · 시트가 멈출 때마다 다시 받고, 끝까지 내리면 다음 쪽(20개씩). 제목 뒤 숫자는 그 범위 안 코스 수
  - [x] 최신순, 카드(경로 썸네일 · 거리 · 난이도 · 첫 특징 · 유형 · 만료 D-N, 7일 이하면 주황), 코스 없음 · 처음 실패 다시 시도
  - [x] 가까운순 · 카드의 `0.8km 거리` — 칩 줄 `최신순 · 가까운순` + 슬라이더 아이콘 칩(A3 열기, 조건이 걸리면 검정). 현재 위치는 `features/home/my_location.dart`가 공통 `LocationService`로 한 번 받는다. 가까운순을 고를 때 권한을 묻고, 못 받으면 정렬은 그대로 두고 안내. 카드 거리는 위치 권한이 있으면 항상 보인다
  - [x] 필터(A3) — 정렬 · 거리 · 난이도 · 코스 태그 · 코스 유형. 바꾸면 약 300ms 뒤 예상 코스 수, `코스 N개 보기`로 지도 · 지역별 코스 수 · 목록에 같이 적용(A2-04). 0건이면 `조건에 맞는 코스가 없어요` + `필터 초기화`(STA-04)
  - [ ] 최소 평점 · 기간 슬라이더 — 코스 통계(F11)가 생기면
  - [ ] 다른 하단 탭에 갔다 오면 탐색 상태(필터 · 지도 위치) 초기화(FIL-08) — 검색(G1)과 함께
  - [ ] 인기순 · 평점순 · 실시간순 · 카드의 평점 · 리뷰 수 · 현재 러너 — 코스 통계(F11)가 생기면
  - [ ] 카드를 누르면 코스 상세(B1) — B1이 생기면
- [x] 자유 러닝 — Android GPS·백그라운드 추적, 이동시간 평균/현재 페이스, 자동 랩, 기기 저장·복구·서버 동기화, 개인 기록 조회·삭제
- [x] 홈 지도 코스 선택(A5, MAP-03) — 이름표를 누르면 그 코스만 지도 · 목록에 남고 이름표 배경이 파랑(`WdMapCourseLabel.selected`). 지도를 움직이거나 축소해도 유지, 지도의 다른 곳을 누르면 풀린다
- [ ] 코스 경로 이탈 판정·코스/고스트 러닝 (별도 범위)
- [ ] GPS 러닝 기록 — 백그라운드 추적, 페이스 · 거리 · 구간 계산, 경로 이탈 판정
- [x] 케이던스 측정 (Android 실제 걸음 센서, 현재·평균·누락 상태). 실외 정확도·장시간 화면 꺼짐 검증은 남아 있음
- [x] AudioGuide — Android 한국어 음성, 계정별 기기 설정, 거리/달린시간 간격·정지 중단·중복 억제
- [ ] 고스트 대결 — 기록 재생과 앞섬/뒤처짐 비교

### 6. 출시 준비
- [ ] Android · iOS 플랫폼 설정 (권한 문구, 앱 아이콘, 스플래시)
- [ ] 스토어 배포

### 디자인 시스템 남은 일
- [ ] Apple 로그인 로고를 Apple 공식 아트워크로 교체
- [ ] Figma 텍스트 스타일을 Pretendard로 전환 (디자이너 PC에 Pretendard 설치 후. 지금 Figma는 Noto Sans KR · Inter)
- [ ] 화면을 만들며 부족한 컴포넌트는 Figma와 패키지에 함께 추가

### 자유 러닝 공통 구성 (2026-10-14 정책 정렬)

- `core/location/LocationService`: 권한·현재 위치 1회 조회·설정 이동·추적 스트림. 러닝 정확도/수집 설정은 run에서 지정한다.
- `core/time/MonotonicClock`: OS 단조 시계. 위치 수집과 분리한다.
- `core/api/RunApiClient`·`RunUpload`: run HTTP 계약. 기능 내부 SQLite 모델을 import하지 않는다. 기록 목록은 공통 `content`·`nextCursor` 응답을 사용한다.
- `features/run/application/AudioGuide`: 음성 설정·임계값·중복 억제·상태 전이·오류를 관리한다. TTS는 RunAudioOutput, 걸음 센서는 RunDevice로 분리한다.
- 서버 확정 후에는 원격 결과를 목록·상세·종료 결과에 반영하며, 기기 원본은 보존한다. 측정/준비 중 기록 동기화는 유예한다.
- 정책 미정 사항을 임의 구현하지 않고 사용자에게 알린다. 구현 전후 정책 조항·호출 경로·예외 상황을 대조한다.


### 자유 러닝 구현·검증 구분 (2026-10-15)

| 영역 | 현재 구현 | 완료로 보지 않는 범위 |
| --- | --- | --- |
| 측정·복구 | Android GPS, PACE_V2, 랩·케이던스·음성, SQLite 저장·복구·계정 분리 | 삼성 기기 30분 이상 실외/잠금·절전·배터리·정확도 인수 |
| 서버 기록 | 업로드·재계산·서버 확정 결과 반영·목록/상세·삭제/탈퇴·재시도 | 최신 배포 환경에서 실제 기록의 저장→재조회→삭제까지 통합 확인 |
| 고도 | GPS `altitudeM`·`altitudeAccuracyM`를 원본 JSON으로 저장·전송 | 누적 상승·고도 차트·course-source. 이전 기록의 고도 복원 불가 |
| 지도 | 실제 경로·현재 위치 따라가기, 출발·종료 표지, GPS 공백 분리 | 새 km 표지 추가는 이번 범위에서 하지 않음 |
| 결과 | 거리/시간/페이스·평균 케이던스·랩 목록·경로 | 최고 구간/최고 페이스·구간 차트/상세 분석·코스 등록·공유 |

2026-10-15 사용자 승인으로 기본 화면의 큰 지표와 아래 세 지표를 각각 터치해 다른 측정 항목으로 순환한다. 정책 문서 RUN-09를 따른다. 기존 Figma의 좌우 드래그(지도/기본/전체 지표)도 유지한다. 새 세션은 기본 배치로 시작하고 같은 세션의 화면 갱신·정지/재개·좌우 슬라이드에서는 선택을 유지한다. 지표 선택은 표시 상태이며 측정 원본·타이머·서버 결과를 수정하지 않는다. 미수집 값을 Figma의 예시 숫자로 채우지 않는다.

정책 문서의 ‘자유 러닝 기본 기능 1~4 구현 세부’와 현재 구현에 따라 거리 0 기록은 개인 목록/서버 등록에서 제외하고 종료 원본은 기기에 보존한다. 이번 변경에서 그 저장 범위를 바꾸지 않는다. 양수 거리의 짧은 기록은 코스 등록 1km 조건 때문에 제외하지 않는다.

자세한 변경 범위와 회귀 검증: [고도 원본과 지도 보완](../run/고도%20원본과%20지도%20보완%20-%202026-10-15.md). iOS는 개발 정책 1.2의 Android 우선 출시와 구분한다.
