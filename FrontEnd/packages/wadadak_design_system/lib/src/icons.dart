import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';

/// Figma 아이콘 원본(SVG). 각 파일은 Figma 아이콘 프레임 크기 그대로이고,
/// 선 두께는 크기에 비례하므로 어떤 [WdIcon.size]로 그려도 Figma와 같다.
enum WdIcons {
  back('back'), // Icon / back · 22
  share('share'), // Icon / share · 22
  sliders('sliders'), // Icon / settings(슬라이더) · 20
  settings('settings'), // Icon / settings(톱니) · 20
  pause('pause'), // Icon / pause · 23
  locate('locate'), // Icon / target · 22
  arrowRight('arrow_right'), // A DS / Icon / arrow · 20
  check('check'), // Icon / check · 20 (green)
  chevronRight('chevron_right'), // Icon / chevron · 18 (grayLight)
  ghost('ghost'), // Icon / ghost · 18
  user('user'), // Icon / user · 20 (muted)
  home('home'), // Icon / home · 21
  run('run'), // Icon / run · 21
  trophy('trophy'), // Icon / trophy · 21
  search('search'), // Icon / search · 19
  routePoint('route_point'), // Route point · 14
  brandGhost('brand_ghost'), // Logo / Symbol / Speed ghost (lime) · 24
  ghostInfo('ghost_info'), // Information / Speed ghost · Neutral
  ghostInfoBrand('ghost_info_brand'), // Information / Speed ghost · Brand (어두운 배경)
  ghostWarning('ghost_warning'), // Notice / Speed ghost · Warning
  ghostSuccess('ghost_success'), // Notice / Speed ghost · Success
  kakao('kakao'),
  apple('apple'), // Figma 메모: Apple 공식 아트워크로 교체 필요
  google('google');

  const WdIcons(this.file);
  final String file;
}

class WdIcon extends StatelessWidget {
  const WdIcon(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final WdIcons icon;

  /// null이면 Figma 원본 크기.
  final double? size;

  /// null이면 원본 색.
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/${icon.file}.svg',
        package: wdPackage,
        width: size,
        height: size,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
      );
}

/// 와다닥 로고 (Logo / Primary): 스피드 고스트 심볼 + 워드마크.
///
/// 밝은 배경은 기본값(ink), 어두운 배경은 `color: WdColors.lime`.
class WdLogo extends StatelessWidget {
  const WdLogo({super.key, this.height = 32, this.color = WdColors.ink, this.symbolOnly = false});

  final double height;
  final Color color;
  final bool symbolOnly;

  @override
  Widget build(BuildContext context) {
    final filter = ColorFilter.mode(color, BlendMode.srcIn);
    final symbol = SvgPicture.asset('assets/icons/logo_symbol.svg',
        package: wdPackage, width: height, height: height, colorFilter: filter, semanticsLabel: '와다닥');
    if (symbolOnly) return symbol;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      symbol,
      SizedBox(width: height * 0.2), // Figma: 심볼 240 · 간격 48
      SvgPicture.asset('assets/icons/logo_wordmark.svg',
          package: wdPackage, height: height, colorFilter: filter, excludeFromSemantics: true),
    ]);
  }
}
