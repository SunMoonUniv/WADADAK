import 'package:flutter/painting.dart';

/// 이 패키지 이름 — 패키지 안의 폰트·에셋을 앱에서 불러올 때 쓴다.
const wdPackage = 'wadadak_design_system';

/// 색상 토큰. 주석은 Figma 변수 이름.
abstract final class WdColors {
  // ── 팔레트 (--a-color-*) ──
  static const ink = Color(0xFF171B19); // --a-color-ink
  static const dark = Color(0xFF111713); // --a-color-dark
  static const darkCard = Color(0xFF1E2720); // --a-color-darkCard
  static const darkLine = Color(0xFF344036); // --a-color-darkLine
  static const muted = Color(0xFF677064); // --a-color-muted
  static const grayLight = Color(0xFFB5C1B3); // --a-color-grayLight
  static const line = Color(0xFFE0E5DC); // --a-color-line
  static const map = Color(0xFFE7ECE2); // --a-color-map (목록 구분선에도 쓰임)
  static const soft = Color(0xFFF3F5F1); // --a-color-soft
  static const paper = Color(0xFFFFFFFF); // --a-color-paper
  static const white = Color(0xFFFFFFFF); // --a-color-white
  static const lime = Color(0xFFC3F25C); // --a-color-lime
  static const limeSoft = Color(0xFFEDF8D9); // --a-color-limeSoft
  static const green = Color(0xFF3B601C); // --a-color-green

  // ── 시맨틱 (--a-text-* / --a-surface-* / --a-action-*) ──
  static const textPrimary = ink;
  static const textSecondary = muted;
  static const textInverse = white;
  static const textInverseSecondary = grayLight;
  static const surfaceDefault = paper;
  static const surfaceSubtle = soft;
  static const actionPrimary = lime;

  // ── 내 기록 강조 (--record-self-*) ──
  static const recordSelfSurface = Color(0xFFD7FD93);
  static const recordSelfBorder = lime;
  static const recordSelfTextPrimary = dark;
  static const recordSelfTextSecondary = Color(0xFF17171C);
  static const recordSelfValue = Color(0xFF171717);
  static const recordSelfAvatar = Color(0xFFF1F2F5);

  // ── 안내 톤 (accent/*, tone/*) ──
  static const info = Color(0xFF296BF5); // accent/파랑
  static const infoBg = Color(0xFFEDF2FF); // tone/정보배경
  static const warning = Color(0xFFED7321); // accent/경고
  static const warningBg = Color(0xFFFCF2E5); // tone/경고배경
  static const warningText = Color(0xFFC2410C); // --color-notice-warning
  static const success = Color(0xFF1C9E6B); // accent/성공
  static const successBg = Color(0xFFE5F6ED); // tone/성공배경

  // ── 와이어프레임 이관 컴포넌트용 뉴트럴 (surface/*, text/*, border/*) ──
  static const neutralText = Color(0xFF17171C); // text/기본
  static const neutralTextSecondary = Color(0xFF787882); // text/보조
  static const neutralTextWeak = Color(0xFFA8A8B2); // text/약함
  static const neutralBorder = Color(0xFFDEDEE3); // border/기본
  static const neutralSurface = Color(0xFFF2F2F5); // surface/연회색
  static const neutralDark = Color(0xFF14141A); // surface/다크

  // ── Figma 변수로 등록되지 않은 원시 색상 (디자인에 직접 입력된 값) ──
  static const nearBlack = Color(0xFF191919);
  static const runTextSub = Color(0xFFBDBDBD); // 러닝 화면 보조 텍스트
  static const runSurface = Color(0xFF1C1C1C); // 러닝 화면 카드·LIVE 배지
  static const runTrack = Color(0xFF2C322E); // 어두운 남은 거리 진행바 트랙
  static const courseTrack = Color(0xFF363636); // 코스 진행 트랙
  static const ghostMarker = Color(0xFFABABAB); // 코스 진행 위 고스트 위치
  static const runDotInactive = Color(0xFF4A504C); // 페이지 인디케이터
  static const divider = Color(0xFFE3E6DF); // 지도 줌 버튼 구분선
  static const disabledBg = Color(0xFFE3E6DF); // 비활성 버튼 배경
  static const disabledText = Color(0xFF8B9388); // 비활성 버튼 글자
  static const checkOff = Color(0xFFC9CEC6); // 동의 전 체크
  static const negative = Color(0xFFDB3D3D); // 구간 표 "느림"
  static const chartBar = Color(0xFFC7D1BF); // 구간 차트 기본 막대
  static const photoPlaceholder = Color(0xFFDFE5D8); // 리뷰 사진 자리
  static const switchOff = Color(0xFFD9D9DE);
}

/// 간격 토큰 (--a-space-*).
abstract final class WdSpace {
  static const double s0 = 0, s4 = 4, s6 = 6, s8 = 8, s10 = 10, s12 = 12;
  static const double s14 = 14, s16 = 16, s18 = 18, s20 = 20, s24 = 24;
}

/// 모서리 반경 토큰 (--a-radius-*).
abstract final class WdRadius {
  static const double r8 = 8, r12 = 12, r16 = 16, r20 = 20, r28 = 28;
  static const double full = 99; // --a-radius-99
}

abstract final class WdShadows {
  /// 지도 위 떠 있는 버튼 (0 2 8 rgba(0,0,0,.08))
  static const floating = [BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 8)];
}

abstract final class WdFonts {
  /// 한글·영문·숫자 모두. 영문·숫자 글리프가 Inter 기반이라 Figma의 Inter 숫자 스타일과 모양이 같다.
  static const pretendard = 'Pretendard';
}

/// 텍스트 스타일 토큰 — Figma 텍스트 스타일과 1:1. 색은 포함하지 않는다(사용처에서 `copyWith(color:)`).
///
/// Figma line-height는 `height`로, CSS와 같은 반-행간 분배는 `leadingDistribution.even`으로 맞춘다.
/// letterSpacing을 0으로 고정해 Material 기본 자간이 섞이지 않게 한다.
abstract final class WdText {
  static const _f = WdFonts.pretendard;
  static const _p = wdPackage;
  static const _e = TextLeadingDistribution.even;
  static const _b = FontWeight.w700, _m = FontWeight.w500, _r = FontWeight.w400, _x = FontWeight.w800;

  // ── 번호 체계 (line-height 140%) ──
  /// 01 Display / 26 Bold
  static const display26 = TextStyle(package: _p, fontFamily: _f, fontSize: 26, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 02 Heading / 19 Bold
  static const heading19 = TextStyle(package: _p, fontFamily: _f, fontSize: 19, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 03 Title / 17 Bold
  static const title17 = TextStyle(package: _p, fontFamily: _f, fontSize: 17, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 04 Metric/20 Bold
  static const metric20 = TextStyle(package: _p, fontFamily: _f, fontSize: 20, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 05 Metric / 18 Bold
  static const metric18 = TextStyle(package: _p, fontFamily: _f, fontSize: 18, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 06 Metric / 16 Bold
  static const metric16 = TextStyle(package: _p, fontFamily: _f, fontSize: 16, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 07 Card title / 14 Bold
  static const cardTitle14 = TextStyle(package: _p, fontFamily: _f, fontSize: 14, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 08 Button / 15 Bold
  static const button15 = TextStyle(package: _p, fontFamily: _f, fontSize: 15, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 09 Body / 13 Regular
  static const body13 = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _r, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 10 Body / 13 Medium
  static const body13Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _m, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 11 Body / 13 Bold
  static const body13Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 12 Label / 12 Regular
  static const label12 = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _r, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 13 Label / 12 Medium
  static const label12Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _m, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 14 Section / 12 Bold
  static const section12 = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 15 Caption / 11 Regular
  static const caption11 = TextStyle(package: _p, fontFamily: _f, fontSize: 11, fontWeight: _r, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 16 Caption / 11 Medium
  static const caption11Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 11, fontWeight: _m, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 17 Caption / 11 Bold
  static const caption11Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 11, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 18 Micro / 10 Regular
  static const micro10 = TextStyle(package: _p, fontFamily: _f, fontSize: 10, fontWeight: _r, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 19 Micro / 10 Bold
  static const micro10Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 10, fontWeight: _b, height: 1.4, letterSpacing: 0, leadingDistribution: _e);
  /// 20 Micro / 9 Regular
  static const micro9 = TextStyle(package: _p, fontFamily: _f, fontSize: 9, fontWeight: _r, height: 1.4, letterSpacing: 0, leadingDistribution: _e);

  // ── A DS / Korean (고정 line-height) ──
  /// A DS / Korean/9 Regular (9/13)
  static const ko9 = TextStyle(package: _p, fontFamily: _f, fontSize: 9, fontWeight: _r, height: 13 / 9, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/10 Regular (10/15)
  static const ko10 = TextStyle(package: _p, fontFamily: _f, fontSize: 10, fontWeight: _r, height: 15 / 10, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/10 Medium (10/15)
  static const ko10Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 10, fontWeight: _m, height: 15 / 10, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/10 Bold (10/15)
  static const ko10Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 10, fontWeight: _b, height: 15 / 10, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/11 Regular (11/16)
  static const ko11 = TextStyle(package: _p, fontFamily: _f, fontSize: 11, fontWeight: _r, height: 16 / 11, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/11 Medium (11/16)
  static const ko11Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 11, fontWeight: _m, height: 16 / 11, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/12 Regular (12/17)
  static const ko12 = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _r, height: 17 / 12, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/12 Medium (12/17)
  static const ko12Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _m, height: 17 / 12, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/12 Bold (12/17)
  static const ko12Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _b, height: 17 / 12, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/13 Regular (13/19)
  static const ko13 = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _r, height: 19 / 13, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/13 Medium (13/19)
  static const ko13Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _m, height: 19 / 13, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/13 Bold (13/19)
  static const ko13Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _b, height: 19 / 13, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/14 Bold (14/20)
  static const ko14Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 14, fontWeight: _b, height: 20 / 14, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/15 Bold (15/22)
  static const ko15Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 15, fontWeight: _b, height: 22 / 15, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/16 Bold (16/23)
  static const ko16Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 16, fontWeight: _b, height: 23 / 16, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/17 Bold (17/25)
  static const ko17Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 17, fontWeight: _b, height: 25 / 17, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/20 Bold (20/29)
  static const ko20Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 20, fontWeight: _b, height: 29 / 20, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/22 Bold (22/32)
  static const ko22Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 22, fontWeight: _b, height: 32 / 22, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/23 Bold (23/33)
  static const ko23Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 23, fontWeight: _b, height: 33 / 23, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Korean/24 Bold (24/35)
  static const ko24Bold = TextStyle(package: _p, fontFamily: _f, fontSize: 24, fontWeight: _b, height: 35 / 24, letterSpacing: 0, leadingDistribution: _e);

  // ── A DS / Numeric — 숫자 (Figma는 Inter, 코드는 같은 모양의 Pretendard 숫자) ──
  /// A DS / Numeric/9 Bold (9/10)
  static const numeric9 = TextStyle(package: _p, fontFamily: _f, fontSize: 9, fontWeight: _b, height: 10 / 9, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/11 Bold (11/13)
  static const numeric11 = TextStyle(package: _p, fontFamily: _f, fontSize: 11, fontWeight: _b, height: 13 / 11, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/12 Bold (12/14)
  static const numeric12 = TextStyle(package: _p, fontFamily: _f, fontSize: 12, fontWeight: _b, height: 14 / 12, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/13 Bold (13/15)
  static const numeric13 = TextStyle(package: _p, fontFamily: _f, fontSize: 13, fontWeight: _b, height: 15 / 13, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/15 Medium (15/17)
  static const numeric15Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 15, fontWeight: _m, height: 17 / 15, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/24 Bold (24/28)
  static const numeric24 = TextStyle(package: _p, fontFamily: _f, fontSize: 24, fontWeight: _b, height: 28 / 24, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/28 Bold (28/32)
  static const numeric28 = TextStyle(package: _p, fontFamily: _f, fontSize: 28, fontWeight: _b, height: 32 / 28, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/33 Bold (33/38)
  static const numeric33 = TextStyle(package: _p, fontFamily: _f, fontSize: 33, fontWeight: _b, height: 38 / 33, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/33 Medium (33/38)
  static const numeric33Medium = TextStyle(package: _p, fontFamily: _f, fontSize: 33, fontWeight: _m, height: 38 / 33, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/40 Bold (40/46)
  static const numeric40 = TextStyle(package: _p, fontFamily: _f, fontSize: 40, fontWeight: _b, height: 46 / 40, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/62 Extra Bold (62/71)
  static const numeric62ExtraBold = TextStyle(package: _p, fontFamily: _f, fontSize: 62, fontWeight: _x, height: 71 / 62, letterSpacing: 0, leadingDistribution: _e);
  /// A DS / Numeric/88 Bold (88/101, 자간 -4)
  static const numeric88 = TextStyle(package: _p, fontFamily: _f, fontSize: 88, fontWeight: _b, height: 101 / 88, letterSpacing: -4, leadingDistribution: _e);

  /// 스타일로 등록되지 않은 값 (디자인에 직접 입력된 크기·굵기·줄 높이). [lineHeight]는 px.
  /// null이면 Figma의 Auto(normal) — 실측상 글자 크기의 약 120%.
  static TextStyle raw(double size, FontWeight weight, [double? lineHeight]) => TextStyle(
      package: _p, fontFamily: _f, fontSize: size, fontWeight: weight,
      height: lineHeight == null ? 1.2 : lineHeight / size, letterSpacing: 0, leadingDistribution: _e);
}
