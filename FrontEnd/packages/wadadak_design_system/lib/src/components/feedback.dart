import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';

enum WdBannerTone { info, warning, success }

/// Info banner — 규칙·상태 안내. 스피드 고스트 아이콘 + 11px 문구.
class WdInfoBanner extends StatelessWidget {
  const WdInfoBanner(this.text, {super.key, this.tone = WdBannerTone.info});

  final String text;
  final WdBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tone) {
      WdBannerTone.info => (WdColors.infoBg, WdColors.info, WdIcons.ghostInfo),
      WdBannerTone.warning => (WdColors.warningBg, WdColors.warning, WdIcons.ghostWarning),
      WdBannerTone.success => (WdColors.successBg, WdColors.success, WdIcons.ghostSuccess),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12, vertical: WdSpace.s10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WdSpace.s8,
        children: [
          WdIcon(icon, size: 16),
          Expanded(child: Text(text, style: WdText.caption11.copyWith(color: fg))),
        ],
      ),
    );
  }
}

/// State / Message — 오류·빈 상태 (GPS 약함, 네트워크 오류, 기록 없음 등).
class WdStateMessage extends StatelessWidget {
  const WdStateMessage({super.key, required this.title, required this.message, this.icon = WdIcons.locate});

  final String title;

  /// 여러 줄이면 `\n`.
  final String message;

  /// limeSoft 원 안에 green으로 그린다.
  final WdIcons icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(WdSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: WdSpace.s24,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: WdColors.limeSoft, shape: BoxShape.circle),
              child: WdIcon(icon, size: 36, color: WdColors.green),
            ),
            Text(title,
                textAlign: TextAlign.center, style: WdText.ko23Bold.copyWith(color: WdColors.ink)),
            Text(message,
                textAlign: TextAlign.center, style: WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.muted)),
          ],
        ),
      );
}

/// Progress bar — 둥근 진행 막대. 기본 색은 와이어프레임 Progress bar.
class WdProgressBar extends StatelessWidget {
  const WdProgressBar({
    super.key,
    required this.value,
    this.trackColor = WdColors.neutralSurface,
    this.fillColor = WdColors.neutralDark,
    this.height = 6,
  });

  /// 0–1
  final double value;
  final Color trackColor;
  final Color fillColor;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
        value: '${(value.clamp(0, 1) * 100).round()}%',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: height,
            child: ColoredBox(
              color: trackColor,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0, 1).toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Progress / Remaining distance — Light(라임 카드 안) · Dark(어두운 배경).
class WdRemainingDistance extends StatelessWidget {
  const WdRemainingDistance({
    super.key,
    required this.leading,
    required this.trailing,
    required this.progress,
    this.dark = false,
  });

  /// 예: "남은 거리 2.79 km"
  final String leading;

  /// 예: "3 km 지점까지 590 m" / "코스 진행 46%"
  final String trailing;
  final double progress;
  final bool dark;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s8,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leading,
                  style: WdText.raw(14, FontWeight.w500).copyWith(color: dark ? WdColors.runTextSub : WdColors.green)),
              Text(trailing,
                  style: WdText.raw(14, FontWeight.w700).copyWith(color: dark ? WdColors.white : WdColors.nearBlack)),
            ],
          ),
          WdProgressBar(
            value: progress,
            trackColor: dark ? WdColors.runTrack : const Color(0x26191919), // rgba(25,25,25,.15)
            fillColor: dark ? WdColors.lime : WdColors.nearBlack,
          ),
        ],
      );
}
