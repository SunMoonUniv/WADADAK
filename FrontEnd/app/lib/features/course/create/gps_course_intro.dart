import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../course_format.dart';

/// B5 코스 만들기 — 내가 달려서 등록의 본문(Figma 1453:4004).
/// 달린 경로가 코스가 되는 순서(B5-01)와 등록 조건(B5-02)을 안내한다. 아래 두 버튼은 B3 화면이 그린다.
class GpsCourseIntro extends StatelessWidget {
  const GpsCourseIntro({super.key, required this.quotaUsedUp});

  /// 오늘 GPS 기록으로 만든 코스를 다 등록했다(하루 3개, 정책 공통 3).
  final bool quotaUsedUp;

  /// 등록 조건. Figma의 `1 km 이상 · 하루 3개`에 정책 B5-02의 GPS 정확도 · 거리 상한 없음을 더했다(4.1 B5-02).
  static const conditions = '1 km 이상 달려야 하고 GPS 신호가 좋아야 등록할 수 있어요. 거리 상한은 없고, 하루 3개까지 등록할 수 있어요.';

  // Figma 코스 지도 카드(A / Course map) 크기. 그림은 이 크기로 그려져 있다.
  static const _mapSize = Size(354, 150);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WdSpace.s16,
          children: [
            Text('직접 달린 경로가 그대로 코스가 돼요', style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
            Text(
              '지도에 점을 찍지 않아도 돼요. 달리기가 끝나면 달린 경로가 그대로 코스로 만들어져요.',
              style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
            ),
            _map(),
            Text('진행 순서', style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
            Column(
              spacing: WdSpace.s10,
              children: [
                _step(1, Text('달리기 시작', style: WdText.ko16Bold.copyWith(color: WdColors.ink))),
                _step(2, Text('자동 변환', style: WdText.ko16Bold.copyWith(color: WdColors.ink))),
                _step(
                  3,
                  const WdStepRow(title: '정보 입력 후 등록', description: '이름 · 난이도 · 특징을 입력하면 모든 러너에게 공개돼요.'),
                ),
              ],
            ),
            const WdInfoBanner(conditions, plain: true),
            if (quotaUsedUp) const WdInfoBanner(gpsQuotaUsedUpMessage, tone: WdBannerTone.warning, plain: true),
          ],
        ),
      );

  /// 예시 경로 그림(Figma Map / Base illustration). 실제 경로가 없는 안내 화면이라 지도 대신 그림을 쓴다(4.1 B5-01).
  /// 화면 너비가 달라도 그림과 지명이 함께 늘고 줄도록 Figma 크기 그대로 그린 뒤 카드에 맞춘다.
  Widget _map() => ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WdRadius.r12),
          child: SizedBox(
            width: double.infinity,
            height: _mapSize.height,
            child: ColoredBox(
              color: WdColors.soft,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox.fromSize(
                  size: _mapSize,
                  child: Stack(
                    children: [
                      SvgPicture.asset('assets/course/gps_course_intro_map.svg', width: 354, height: 150),
                      Positioned(
                        left: 158,
                        top: 121,
                        child: Text('한강', style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.muted)),
                      ),
                      Positioned(
                        left: 174,
                        top: 8,
                        child: Text('반포한강공원', style: WdText.raw(11, FontWeight.w500, 15).copyWith(color: WdColors.muted)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // Figma 간격은 11인데 맞는 간격 토큰이 없어 가장 가까운 12를 쓴다(개발 정책 9장 토큰만 쓰기).
  Widget _step(int number, Widget label) => Row(
        spacing: WdSpace.s12,
        children: [
          Container(
            width: WdSpace.s28,
            height: WdSpace.s28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: WdColors.dark, shape: BoxShape.circle),
            child: Text('$number', style: WdText.ko16Bold.copyWith(color: WdColors.white)),
          ),
          Expanded(child: label),
        ],
      );
}
