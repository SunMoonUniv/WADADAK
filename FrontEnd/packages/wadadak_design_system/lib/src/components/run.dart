import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'cards.dart';
import 'surface.dart';

// 러닝 중 화면은 어두운 배경(WdColors.dark 계열) 위에 놓인다.

/// Run header — 코스명 · 모드 · 상태 배지 (h64). 상단 안전 영역은 화면에서 처리한다.
class WdRunHeader extends StatelessWidget {
  const WdRunHeader({super.key, required this.title, required this.subtitle, this.badge = 'LIVE'});

  final String title;

  /// 예: "코스 러닝"
  final String subtitle;

  /// 예: "LIVE", "기록 중"
  final String badge;

  // Figma는 py12 안에 42px 글자 묶음을 가운데 정렬해 위아래로 1px씩 넘친다(클립). 같은 위치가 되도록 세로 패딩 없이 가운데 정렬.
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24),
          child: Row(
            spacing: WdSpace.s8,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.ko17Bold.copyWith(color: WdColors.white)),
                    Text(subtitle, style: WdText.raw(12, FontWeight.w400, 15).copyWith(color: WdColors.runTextSub)),
                  ],
                ),
              ),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: WdColors.runSurface, borderRadius: BorderRadius.circular(WdRadius.full)),
                child: Text(badge, style: WdText.raw(12, FontWeight.w500, 15).copyWith(color: WdColors.lime)),
              ),
            ],
          ),
        ),
      );
}

/// Run / Elapsed time — 큰 경과 시간.
class WdElapsedTime extends StatelessWidget {
  const WdElapsedTime({super.key, required this.time, this.label = '달린 시간', this.caption});

  /// 예: "12:34"
  final String time;
  final String label;

  /// 예: "총 소요 13:02"
  final String? caption;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 154,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: WdSpace.s6,
          children: [
            Text(label, style: WdText.raw(14, FontWeight.w500, 17).copyWith(color: WdColors.runTextSub)),
            Text(
              time,
              style: WdText.numeric88.copyWith(
                color: WdColors.white,
                // 초가 바뀔 때 글자 폭이 흔들리지 않도록 고정폭 숫자.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (caption != null)
              Text(caption!, style: WdText.raw(13, FontWeight.w400, 17).copyWith(color: WdColors.runTextSub)),
          ],
        ),
      );
}

/// Run / Metric tile — 러닝 중 지표 카드 (h88).
class WdRunMetricTile extends StatelessWidget {
  const WdRunMetricTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => WdSurface(
        color: WdColors.runSurface,
        height: 88,
        padding: const EdgeInsets.all(WdSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WdSpace.s10,
          children: [
            Text(label, style: WdText.raw(13, FontWeight.w400, 17).copyWith(color: WdColors.runTextSub)),
            Text(value, maxLines: 1, style: WdText.numeric24.copyWith(color: WdColors.white)),
          ],
        ),
      );
}

class WdLap {
  const WdLap({required this.label, required this.pace, required this.delta, this.faster = false, this.current = false});

  /// 예: "1 km", "현재 0.41 km"
  final String label;

  /// 예: "5′18″"
  final String pace;

  /// 예: "6초 느림"
  final String delta;

  /// 고스트보다 빠르면 라임.
  final bool faster;

  /// 진행 중인 랩이면 라벨이 라임.
  final bool current;
}

/// Run / Lap records — 1 km 자동 랩.
class WdLapRecords extends StatelessWidget {
  const WdLapRecords({super.key, required this.laps, this.title = '랩 기록', this.meta = '1 km 자동'});

  final List<WdLap> laps;
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final cell = WdText.raw(16, FontWeight.w500, 17);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: WdSpace.s8,
      children: [
        SizedBox(
          height: 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: WdText.raw(14, FontWeight.w700, 19).copyWith(color: WdColors.white)),
              Text(meta, style: WdText.raw(13, FontWeight.w400, 15).copyWith(color: WdColors.runTextSub)),
            ],
          ),
        ),
        for (final lap in laps)
          SizedBox(
            height: 30,
            child: Row(
              spacing: WdSpace.s12,
              children: [
                SizedBox(
                  width: 124,
                  child: Text(lap.label, style: cell.copyWith(color: lap.current ? WdColors.lime : WdColors.runTextSub)),
                ),
                Expanded(
                  child: Text(lap.pace,
                      textAlign: TextAlign.center,
                      style: WdText.raw(16, FontWeight.w500, 17).copyWith(color: WdColors.white)),
                ),
                SizedBox(
                  width: 124,
                  child: Text(lap.delta,
                      textAlign: TextAlign.right,
                      style: cell.copyWith(color: lap.faster ? WdColors.lime : WdColors.runTextSub)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Run / Ghost lead card — 라임 카드: 고스트 대비 상황.
class WdGhostLeadCard extends StatelessWidget {
  const WdGhostLeadCard({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
    required this.message,
  });

  /// 예: "고스트보다 앞서고 있어요"
  final String title;

  /// 예: "+12 m"
  final String value;

  /// 예: "약 4초 앞서는 중"
  final String caption;

  /// 예: "지금 페이스를 이어가세요."
  final String message;

  @override
  Widget build(BuildContext context) => WdSurface(
        color: WdColors.lime,
        radius: WdRadius.r20,
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WdSpace.s4,
          children: [
            SizedBox(
              height: 20,
              child: Row(
                spacing: 7,
                children: [
                  const WdIcon(WdIcons.ghost),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.raw(14, FontWeight.w700, 17).copyWith(color: WdColors.nearBlack)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 32,
              child: Row(
                spacing: WdSpace.s10,
                children: [
                  Text(value, style: WdText.numeric28.copyWith(color: WdColors.nearBlack)),
                  Flexible(
                    child: Text(caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.raw(16, FontWeight.w500, 17).copyWith(color: WdColors.green)),
                  ),
                ],
              ),
            ),
            Text(message, style: WdText.raw(13, FontWeight.w400, 15).copyWith(color: WdColors.green)),
          ],
        ),
      );
}

/// Run / Course progress — 코스 진행률 + 고스트 위치.
class WdCourseProgress extends StatelessWidget {
  const WdCourseProgress({
    super.key,
    required this.progress,
    this.ghostProgress,
    required this.leading,
    required this.trailing,
    this.label = '코스 진행',
  });

  /// 0–1
  final double progress;

  /// 0–1, 고스트 대결이 아니면 null.
  final double? ghostProgress;

  /// 아래 줄 왼쪽, 예: "3 km 지점까지 590 m"
  final String leading;

  /// 아래 줄 오른쪽, 예: "총 5.2 km"
  final String trailing;
  final String label;

  @override
  Widget build(BuildContext context) {
    final sub = WdText.raw(14, FontWeight.w400, 16).copyWith(color: WdColors.runTextSub);
    final percent = '${(progress.clamp(0, 1) * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: WdSpace.s8,
      children: [
        SizedBox(
          height: 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: sub),
              Text(percent, style: WdText.raw(16, FontWeight.w700, 14).copyWith(color: WdColors.lime)),
            ],
          ),
        ),
        Semantics(
          label: label,
          value: percent,
          child: SizedBox(
            height: 7,
            child: CustomPaint(painter: _CourseTrackPainter(progress.clamp(0, 1).toDouble(), ghostProgress?.clamp(0, 1).toDouble())),
          ),
        ),
        SizedBox(
          height: 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(leading, style: sub), Text(trailing, style: sub)],
          ),
        ),
      ],
    );
  }
}

/// Figma Track: #363636 트랙 · 라임 완료 구간 · 고스트(회색 r5) · 나(라임 r7), 트랙 모양으로 잘림.
class _CourseTrackPainter extends CustomPainter {
  _CourseTrackPainter(this.progress, this.ghost);

  final double progress;
  final double? ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    final x = size.width * progress;
    canvas
      ..save()
      ..clipRRect(track)
      ..drawRRect(track, Paint()..color = WdColors.courseTrack)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, x, size.height), Radius.circular(r)),
          Paint()..color = WdColors.lime);
    if (ghost != null) canvas.drawCircle(Offset(size.width * ghost!, r), 5, Paint()..color = WdColors.ghostMarker);
    canvas
      ..drawCircle(Offset(x + 1, r), 7, Paint()..color = WdColors.lime)
      ..restore();
  }

  @override
  bool shouldRepaint(_CourseTrackPainter old) => old.progress != progress || old.ghost != ghost;
}

/// 러닝 화면 좌우 슬라이드 위치 표시 점 (6px · 간격 6).
class WdPageIndicator extends StatelessWidget {
  const WdPageIndicator({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s6,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? WdColors.lime : WdColors.runDotInactive,
                shape: BoxShape.circle,
              ),
            ),
        ],
      );
}

/// Run controls / Pause의 흰 일시정지 버튼 (h64 · radius 20).
///
/// Figma 조합: `WdPageIndicator` → 12 → 이 버튼. 홈 인디케이터는 OS가 그린다.
class WdRunPauseButton extends StatelessWidget {
  const WdRunPauseButton({super.key, required this.onPressed, this.label = '일시정지'});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: WdSurface(
          color: WdColors.paper,
          radius: WdRadius.r20,
          width: double.infinity,
          height: 64,
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: WdSpace.s10,
            children: [
              const WdIcon(WdIcons.pause),
              Text(label, style: WdText.ko17Bold.copyWith(color: WdColors.nearBlack)),
            ],
          ),
        ),
      );
}

/// Run controls / Paused buttons — 러닝 종료(보조) + 계속 달리기(주), 133:209 비율.
class WdRunPausedButtons extends StatelessWidget {
  const WdRunPausedButtons({
    super.key,
    required this.onStop,
    required this.onResume,
    this.stopLabel = '러닝 종료',
    this.resumeLabel = '계속 달리기',
  });

  final VoidCallback? onStop;
  final VoidCallback? onResume;
  final String stopLabel;
  final String resumeLabel;

  @override
  Widget build(BuildContext context) => Row(
        spacing: WdSpace.s12,
        children: [
          Expanded(flex: 133, child: WdButton(stopLabel, onPressed: onStop, variant: WdButtonVariant.secondary)),
          Expanded(flex: 209, child: WdButton(resumeLabel, onPressed: onResume)),
        ],
      );
}

/// Run controls / Countdown의 센서 상태 줄 (GPS 신호 · 케이던스 센서).
///
/// Figma 조합: 이 위젯 → 12 → `WdButton('시작 취소', variant: secondary)`.
class WdSensorStatus extends StatelessWidget {
  const WdSensorStatus(this.items, {super.key});

  /// (항목, 상태) 예: ('GPS 신호', '좋음 (±4m)')
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: WdSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: WdSpace.s8,
          children: [
            for (final (label, status) in items)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: WdText.raw(12, FontWeight.w400).copyWith(color: WdColors.runTextSub)),
                  Text(status, style: WdText.raw(12, FontWeight.w700).copyWith(color: WdColors.lime)),
                ],
              ),
          ],
        ),
      );
}

/// Run prep / Selected course — 달리기 준비의 선택된 코스 (h96).
class WdSelectedCourseCard extends StatelessWidget {
  const WdSelectedCourseCard({
    super.key,
    required this.title,
    required this.meta,
    required this.status,
    this.thumbnail,
    this.onChange,
    this.changeLabel = '변경',
  });

  final String title;

  /// 예: "5.2 km · 난이도 중 · 평지"
  final String meta;

  /// 예: "★ 4.6  ·  지금 3명 달리는 중"
  final String status;
  final Widget? thumbnail;
  final VoidCallback? onChange;
  final String changeLabel;

  @override
  Widget build(BuildContext context) => WdSurface(
        height: 96,
        padding: const EdgeInsets.all(WdSpace.s12),
        child: Row(
          spacing: WdSpace.s12,
          children: [
            WdRouteThumbnail(width: 84, height: 76, child: thumbnail),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 5,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
                  SizedBox(
                    height: 22,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: WdSpace.s10,
                      children: [
                        Expanded(
                          child: Text(meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WdText.ko12.copyWith(color: WdColors.muted)),
                        ),
                        GestureDetector(
                          onTap: onChange,
                          child: Text(changeLabel, style: WdText.ko12Bold.copyWith(color: WdColors.ink)),
                        ),
                      ],
                    ),
                  ),
                  Text(status, style: WdText.raw(12, FontWeight.w500, 15).copyWith(color: WdColors.green)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Run prep / Record card — 어두운 카드: 대결 상대 기록 (고스트 대결 준비).
class WdRecordCard extends StatelessWidget {
  const WdRecordCard({
    super.key,
    required this.overline,
    required this.title,
    required this.time,
    required this.caption,
    required this.footer,
    this.onTap,
  });

  /// 예: "코스 최고 기록"
  final String overline;

  /// 예: "이 코스의 내 최고 기록"
  final String title;

  /// 예: "27:14"
  final String time;

  /// 예: "평균 페이스 5′14″"
  final String caption;

  /// 예: "코스 순위 24위 / 312명  ·  목표 26:40 (−34초)"
  final String footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = WdColors.grayLight;
    return WdSurface(
      color: WdColors.dark,
      radius: WdRadius.r20,
      padding: const EdgeInsets.all(WdSpace.s20),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s14,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s10,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: WdColors.darkCard, borderRadius: BorderRadius.circular(WdRadius.r12)),
                  child: const WdIcon(WdIcons.brandGhost),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(overline, style: WdText.raw(11, FontWeight.w700, 10).copyWith(color: sub)),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WdText.ko15Bold.copyWith(color: WdColors.white)),
                    ],
                  ),
                ),
                const WdIcon(WdIcons.chevronRight),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: WdSpace.s10,
              children: [
                Text(time, style: WdText.numeric40.copyWith(color: WdColors.white)),
                Flexible(child: Text(caption, style: WdText.ko12.copyWith(color: sub))),
              ],
            ),
          ),
          const ColoredBox(color: WdColors.darkLine, child: SizedBox(height: 1)),
          Text(footer, style: WdText.raw(12, FontWeight.w400, 16).copyWith(color: sub)),
        ],
      ),
    );
  }
}
