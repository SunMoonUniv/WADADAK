# wadadak_design_system

Figma **몰입형 디자인 › 🧩 공통 컴포넌트**를 Flutter로 옮긴 디자인 시스템 패키지.
앱은 이 패키지만 보고 화면을 조립한다 — 색·간격·글꼴 값을 화면 코드에 직접 쓰지 않는다.

```
lib/
  wadadak_design_system.dart   # 이것 하나만 import
  src/tokens.dart              # 색 · 간격 · 반경 · 그림자 · 글꼴
  src/theme.dart               # MaterialApp 테마
  src/icons.dart               # WdIcon · WdLogo (assets/icons/*.svg)
  src/components/*.dart        # 컴포넌트
example/                       # 컴포넌트 카탈로그 앱 (Figma와 나란히 비교용)
```

## 앱에 붙이기

```yaml
# app/pubspec.yaml
dependencies:
  wadadak_design_system:
    path: ../wadadak_design_system
```

```dart
import 'package:wadadak_design_system/wadadak_design_system.dart';

MaterialApp(theme: WdTheme.light(), home: ...);

Scaffold(
  appBar: WdAppBar(title: '코스 만들기', onBack: () => Navigator.pop(context)),
  body: ...,
  bottomNavigationBar: WdBottomBar.pinned(primary: WdButton('시작하기', onPressed: start)),
);
```

카탈로그 앱(`example/`)은 Figma와 나란히 놓고 비교하는 용도다. 웹은 바로 실행되고, 모바일은 플랫폼 폴더를 한 번 만든 뒤 실행한다.

```bash
cd example && flutter run -d chrome
```

```bash
cd example && flutter create . --platforms=android,ios && flutter run
```

`example/test/widget_test.dart`는 카탈로그 전체를 그려 레이아웃 예외(오버플로·무한 제약·에셋 누락)를 잡는 스모크 테스트다. 컴포넌트를 고친 뒤 `cd example && flutter test`.

## 글꼴

글꼴은 **Pretendard** 하나다 (`assets/fonts/`, v1.3.9 · 400/500/700/800 · SIL OFL 1.1 — `OFL-Pretendard.txt`를 함께 배포).
Pretendard의 영문·숫자는 Inter 기반이라 Figma의 Inter 숫자 스타일(`A DS / Numeric/*`)도 같은 글꼴로 그린다.

Figma는 아직 Noto Sans KR · Inter다. 디자이너 PC에 Pretendard를 설치한 뒤 텍스트 스타일을 Pretendard로 바꾸면 코드와 같아진다.

## 토큰 ↔ Figma

| Dart | Figma |
|---|---|
| `WdColors.ink` … `green` | `--a-color-*` |
| `WdColors.textPrimary` 등 | `--a-text-*`, `--a-surface-*`, `--a-action-primary` |
| `WdColors.recordSelf*` | `--record-self-*` |
| `WdColors.info/warning/success(+Bg)` | `accent/*`, `tone/*` |
| `WdColors.neutral*` | `text/*`, `surface/*`, `border/*` (와이어프레임 이관 컴포넌트) |
| `WdColors.runTextSub` 등 (raw 구역) | 변수로 등록 안 된 값 — 디자인에서 변수로 만들면 이름만 옮기면 된다 |
| `WdSpace.s4` … `s24` | `--a-space-*` |
| `WdRadius.r8` … `full` | `--a-radius-*` |
| `WdText.display26` … `micro9` | `01 Display / 26 Bold` … `20 Micro / 9 Regular` |
| `WdText.ko{크기}{굵기}` (예: `ko20Bold`) | `A DS / Korean/{크기} {굵기}` |
| `WdText.numeric{크기}` (예: `numeric88`) | `A DS / Numeric/{크기} {굵기}` |
| `WdText.raw(size, weight, lineHeight)` | 스타일로 등록 안 된 텍스트 (Auto 줄 높이 = 120%) |

## 컴포넌트 ↔ Figma

| Figma | Flutter |
|---|---|
| App bar / * (9종) | `WdAppBar` + `WdAppBarAction` (클래스 주석에 변형별 사용법) |
| Tab item | `WdTabBar` (Material `TabBar` 기반) |
| A DS / Bottom navigation | `WdBottomNav` |
| Run / Mode segment · Builder segment | `WdSegmentedControl(style: dark / light)` |
| A DS / Button | `WdButton` (`onPressed: null` → 비활성) |
| Bottom bar / Pinned CTA · Dual CTA | `WdBottomBar.pinned` · `.dual` |
| Social login button | `WdSocialLoginButton` |
| Course filters (홈) | `WdFilterChip`, `WdFilterChip.icon` |
| Tag | `WdTag` (`filled: false` = 카드 안 글자 태그) |
| Input · Search / Bar · Search / Header | `WdTextField` · `WdSearchBar` · `WdSearchHeader` |
| Consent row · List row · Stepper | `WdConsentRow` · `WdListRow` (+`WdSwitch`) · `WdStepper` |
| Review / Rating form · Photo upload | `WdRatingRow` · `WdPhotoUpload` |
| Info banner · State / Message | `WdInfoBanner` · `WdStateMessage` |
| Progress bar · Progress / Remaining distance | `WdProgressBar` · `WdRemainingDistance(dark:)` |
| Course / Summary tile · Info grid · Build summary | `WdSummaryTile` · `WdSummaryTiles` |
| A DS / Metric · Card / Stat summary | `WdMetric(dark:)` · `WdStatSummary` |
| Course card (Saved · Search · List) | `WdCourseCard` |
| Run record card (+ Selectable) | `WdRunRecordCard` · `.selectable` |
| Review card (With photos · Text only) | `WdReviewCard` |
| List card / Menu · Section heading · Step row | `WdMenuCard` · `WdSectionHeading` · `WdStepRow` |
| Rank row · Rank / List · My rank card | `WdRankRow` · `WdRankList` · `WdMyRankCard` |
| Run header · Elapsed time · Metric tile | `WdRunHeader` · `WdElapsedTime` · `WdRunMetricTile` |
| Run / Lap records · Ghost lead card · Course progress | `WdLapRecords` · `WdGhostLeadCard` · `WdCourseProgress` |
| Run controls / Pause · Paused buttons · Countdown | `WdPageIndicator` + `WdRunPauseButton` · `WdRunPausedButtons` · `WdSensorStatus` + `WdButton` |
| Run prep / Selected course · Record card | `WdSelectedCourseCard` · `WdRecordCard` |
| Map button / Locate · Zoom · Km marker · Route point | `WdMapLocateButton` · `WdMapZoomControl` · `WdKmMarker` · `WdRoutePoint` |
| Map / Region count bubble · Sheet peek · Thumbnail | `WdRegionCountBubble` · `WdSheetPeek` · `WdRouteThumbnail` |
| Analysis / Segment chart · Segment table | `WdSegmentChart` · `WdSegmentTable` |
| A 확장 / Avatar | `WdAvatar` |
| Information · Notice / Speed ghost, 브랜드 로고 | `WdIcon(WdIcons.ghostInfo …)`, `WdLogo` |

옮기지 않은 것: Status bar·홈 인디케이터(OS가 그림), Map / Base illustration(시안용 지도 그림 — 실제는 지도 SDK),
Backdrop 사각형(전시용 배경).

## 아이콘

`assets/icons/*.svg`는 Figma 벡터 원본을 아이콘 프레임 크기(viewBox)에 맞춰 저장한 것이다. 선 두께가 크기에 비례하므로
`WdIcon(icon, size: n)`으로 아무 크기나 써도 Figma 스케일과 같다. `color:`를 주면 단색으로 칠한다.
Apple 로고는 Figma 메모대로 Apple Design Resources 공식 아트워크로 교체해야 한다.
