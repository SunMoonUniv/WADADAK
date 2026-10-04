import 'package:flutter/material.dart';

import 'tokens.dart';

/// 앱 전역 테마. `MaterialApp(theme: WdTheme.light())`.
///
/// Wd 컴포넌트는 토큰을 직접 쓰므로 이 테마는 기본 Text·Material 위젯(다이얼로그, 스낵바 등)이
/// 디자인 시스템과 어긋나지 않게 맞추는 역할이다.
abstract final class WdTheme {
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        fontFamily: WdFonts.pretendard,
        package: wdPackage,
        scaffoldBackgroundColor: WdColors.paper,
        colorScheme: const ColorScheme.light(
          primary: WdColors.lime,
          onPrimary: WdColors.ink,
          secondary: WdColors.green,
          onSecondary: WdColors.white,
          surface: WdColors.paper,
          onSurface: WdColors.ink,
          onSurfaceVariant: WdColors.muted,
          outline: WdColors.line,
          outlineVariant: WdColors.map,
          error: WdColors.warningText,
        ),
        dividerTheme: const DividerThemeData(color: WdColors.map, thickness: 1, space: 1),
        textTheme: const TextTheme(
          titleLarge: WdText.ko20Bold,
          titleMedium: WdText.ko16Bold,
          titleSmall: WdText.cardTitle14,
          bodyLarge: WdText.body13Medium,
          bodyMedium: WdText.body13,
          bodySmall: WdText.caption11,
          labelLarge: WdText.button15,
          labelMedium: WdText.label12,
          labelSmall: WdText.micro10,
        ).apply(bodyColor: WdColors.ink, displayColor: WdColors.ink),
      );
}
