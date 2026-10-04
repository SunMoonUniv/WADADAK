# WADADAK-FrontEnd

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
| 공통 컴포넌트 위젯 58개 | ✅ 완료 |
| 컴포넌트 카탈로그 앱 + 스모크 테스트 | ✅ 완료 |
| Figma 디자인 시스템 페이지 (변수 · 스타일 · 컴포넌트 82개 / 29세트) | ✅ 완료 |
| 앱 프로젝트 (`app/`) | ⬜ 시작 전 |
| 화면 | ⬜ 0 / 72 |
| 로그인 · API · 지도 · 위치 추적 연동 | ⬜ 시작 전 |

즉 **화면을 조립할 부품(디자인 시스템)까지 준비된 상태**이고, 앱과 화면은 아직 없다.

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
| 지도 위 요소 | `WdMapLocateButton` `WdMapZoomControl` `WdKmMarker` `WdRoutePoint` `WdRegionCountBubble` `WdSheetPeek` |
| 분석 | `WdSegmentChart` `WdSegmentTable` |

Figma 컴포넌트와의 1:1 대응표, 토큰 사용법은 [디자인 시스템 README](packages/wadadak_design_system/README.md)에 있다.

## 디렉터리 구조

```
WADADAK-FrontEnd/
├─ README.md
├─ app/                                 # ⬜ 실제 앱 (flutter create app 으로 만들 예정)
│  └─ lib/
│     ├─ main.dart
│     ├─ core/                          # API 클라이언트 · 인증 · 위치 · 공통 오류/빈 상태 화면
│     └─ features/                      # Figma 디자인 페이지 섹션 단위
│        ├─ onboarding/                 #   🚪 온보딩
│        ├─ home/                       #   🏠 홈 · 코스 탐색
│        ├─ course/                     #   📍 코스 상세 · 만들기
│        ├─ run/                        #   🏃 달리기 준비 · ⏱ 러닝 중 · 📊 러닝 결과 · 분석
│        ├─ ranking/                    #   🏆 랭킹
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

`app/` 아래 구조는 제안이다. 앱 뼈대를 만들 때 확정한다.

## 남은 단계

### 1. 개발 환경
- [ ] Flutter SDK 최신 stable 설치 (3.47.6에서 확인 · 3.32 미만은 `flutter_lints 6` 설치 실패) — `flutter doctor`로 확인
- [ ] 카탈로그 앱 실행 확인: `cd packages/wadadak_design_system/example && flutter run -d chrome`
- 아마 알겠지만 git clone 하면 pubspec.lock과 .dart_tool/ 이게 없어서 빌드 하다 오류 날 수도 있으니, 안드로이드 스튜디오면 packages/wadadak_design_system/pubspec.yaml 이거 열어서 Pub get 하거나, 터미널에 명령어 입력하셈 : `cd packages/wadadak_design_system && flutter pub get && cd example && flutter pub get` 

### 2. 팀 결정
- [ ] 상태 관리 (예: Riverpod) · 화면 이동 (예: go_router) · HTTP 클라이언트 (예: dio)
- [ ] 지도 SDK (네이버 · 카카오 · 구글 중 하나)
- [ ] 위치 추적 방식 — 러닝 중 백그라운드 위치 권한 포함
- [ ] 소셜 로그인 SDK (카카오 · Apple · Google)
- [ ] 백엔드와 API 명세 · 기능별 인터페이스 정의

### 3. 앱 뼈대
- [ ] `flutter create app` 후 디자인 시스템 연결

  ```yaml
  # app/pubspec.yaml
  dependencies:
    wadadak_design_system:
      path: ../packages/wadadak_design_system
  ```
- [ ] `MaterialApp(theme: WdTheme.light())`, 라우팅, 하단 탭 4개 (홈 · 달리기 · 랭킹 · MY — `WdBottomNav` 기본값)

### 4. 화면 구현 (0 / 72)

Figma `디자인 · 전체 화면 (와이어프레임 기준)` 페이지의 섹션 순서 그대로다.
처음에는 가짜 데이터로 화면만 만들고, API는 나중에 붙인다. 화면 코드에는 색 · 간격 · 글꼴 값을 직접 쓰지 않고 디자인 시스템 토큰과 위젯만 쓴다.

<details>
<summary>🚪 온보딩 (0 / 6)</summary>

- [ ] A0-1 · 소개 — 코스 공유
- [ ] 소개 — 고스트 대결 (Figma 프레임 이름이 `Frame`)
- [ ] A1 · 스플래시 / 로그인
- [ ] 소셜 정보 동의 (선택 전 · 선택 후)
- [ ] 권한 안내 (위치 · 동작 및 피트니스)
- [ ] F2 · 프로필 초기 설정

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
<summary>📍 코스 상세 · 만들기 (0 / 9)</summary>

- [ ] B1 · 코스 상세 — 정보
- [ ] B8 · 코스 상세 — 리뷰
- [ ] B9 · 코스 상세 — 랭킹
- [ ] G3 · 코스 전체 순위
- [ ] B3 · 코스 만들기 (경로 그리기)
- [ ] B4 · 코스 만들기 — 내가 달려서 등록
- [ ] B5 · 코스 정보 입력 & 등록
- [ ] B6 · 내 기록에서 코스 등록
- [ ] B11 · 코스 공개 기간 안내 (시트)
</details>

<details>
<summary>🏃 달리기 준비 (0 / 7)</summary>

- [ ] C5 · 달리기 준비 — 자유 러닝
- [ ] C6 · 달리기 준비 — 코스 러닝
- [ ] C1 · 달리기 준비 — 고스트 대결
- [ ] C2 · 고스트 러너 선택
- [ ] C8 · 코스 선택 (달리기 준비)
- [ ] C9 · 고스트 선택 — 내 기록 전체
- [ ] C10 · 고스트 선택 — 다른 러너 전체
</details>

<details>
<summary>⏱ 러닝 중 — 카운트다운 · 실시간 (0 / 8)</summary>

- [ ] H1 · 시작 카운트다운 (코스 러닝)
- [ ] H4 · 시작 카운트다운 (자유 러닝)
- [ ] H5 · 시작 카운트다운 (고스트 대결)
- [ ] C4 · 러닝 중 — 고스트 대결 (기본 · 왼쪽 슬라이드 지도 C4-1 · 오른쪽 슬라이드 상세 지표 C4-2)
- [ ] C4 · 러닝 중 — 코스 러닝 (기본 · 지도 C4-1 · 상세 지표 C4-2)
- [ ] C4 · 러닝 중 — 자유 러닝 (기본 · 지도 H4-1 · 상세 지표 C4-2)
- [ ] C4-3 · 러닝 중 — 경로 이탈 (지도)
- [ ] 러닝 일시정지
</details>

<details>
<summary>📊 러닝 결과 · 분석 (0 / 8)</summary>

- [ ] D1 · 러닝 결과 (종합 기록)
- [ ] D1-1 · 러닝 결과 — 코스 완주 미인정
- [ ] D1-2 · 러닝 결과 — 자유 러닝
- [ ] D2 · 고스트 대결 결과
- [ ] D3 · 구간별 상세 분석
- [ ] D5 · 구간별 케이던스 분석
- [ ] D6 · 구간별 고도 분석
- [ ] D4 · 달린 경로를 코스로 등록 (GPS)
</details>

<details>
<summary>👤 MY · 설정 (0 / 10)</summary>

- [ ] E3 · 마이페이지 (뱃지 · 업적)
- [ ] I1 · 내 러닝 기록 (히스토리)
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
<summary>🏆 랭킹 (0 / 4)</summary>

- [ ] E1 · 랭킹 — 전체 러너 / 지역 주간
- [ ] I2 · 지역 주간 랭킹
- [ ] I5 · 지역 주간 전체 순위
- [ ] I6 · 지역 선택
</details>

<details>
<summary>💬 리뷰 · 커뮤니티 (0 / 4)</summary>

- [ ] B2 · 코스 리뷰 작성
- [ ] G2 · 코스 리뷰 전체
- [ ] B10 · 리뷰 수정
- [ ] B10-1 · 리뷰 수정 — 근거 기록 삭제됨
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
- [ ] 소셜 로그인 · 토큰 저장
- [ ] 위치 · 동작 및 피트니스 권한 요청 (권한 안내 화면 순서대로)
- [ ] API 연결 (가짜 데이터 → 실제 데이터)
- [ ] 지도 SDK — 코스 경로 · km 표지 · 지역별 개수 표시
- [ ] GPS 러닝 기록 — 백그라운드 추적, 페이스 · 거리 · 구간 계산, 경로 이탈 판정
- [ ] 케이던스 측정 (걸음 센서)
- [ ] 고스트 대결 — 기록 재생과 앞섬/뒤처짐 비교

### 6. 출시 준비
- [ ] Android · iOS 플랫폼 설정 (권한 문구, 앱 아이콘, 스플래시)
- [ ] 스토어 배포

### 디자인 시스템 남은 일
- [ ] Apple 로그인 로고를 Apple 공식 아트워크로 교체
- [ ] Figma 텍스트 스타일을 Pretendard로 전환 (디자이너 PC에 Pretendard 설치 후. 지금 Figma는 Noto Sans KR · Inter)
- [ ] 화면을 만들며 부족한 컴포넌트는 Figma와 패키지에 함께 추가
