import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/course_api_client.dart';
import '../domain/run_models.dart';

/// 오늘 등록 한도와 GPS 코스 등록에 쓴 기록(`이미 등록됨`). 실패하면 막지 않고 D4 등록 때 서버가 다시 본다
final _quotaProvider = FutureProvider.autoDispose<RegistrationQuota>(
  (ref) => ref.watch(courseApiClientProvider).registrationQuota(),
  retry: (_, _) => null,
);

/// 기록을 코스로 등록할 수 없는 사유(B6-04와 같다). 없으면 null
String? registerBlocker(RunSnapshot run, RegistrationQuota? quota) {
  if (run.distanceMeters < 1000) return '1km 이상 달린 기록만 등록할 수 있어요';
  final passed = run.gpsGapPassed;
  if (passed == null) return '기록을 서버에 올린 뒤 등록할 수 있어요'; // 동기화 대기(판단 전 포함)
  if (!passed) return 'GPS가 끊긴 구간이 있어 등록할 수 없어요';
  if (quota?.usedRunRecordIds.contains(run.sessionId) ?? false) return '이미 코스로 등록한 기록이에요';
  return null;
}

/// Figma D1-2 "Register as course card" — 결과 화면의 `달린 경로로 코스 만들기`(정책 공통 3).
/// 1km 미만 · 동기화 대기 · GPS 정확도 부족 · 이미 등록됨이면 비활성과 사유. 누르면 오늘 한도를 확인하고 D4로 간다
class CourseRegisterCard extends ConsumerWidget {
  const CourseRegisterCard({super.key, required this.run});
  final RunSnapshot run;

  Future<void> _register(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    RegistrationQuota? quota;
    try {
      quota = await ref.refresh(_quotaProvider.future);
    } on Object {
      quota = null; // 확인하지 못하면 D4 등록 때 서버가 다시 본다
    }
    if (quota != null && quota.gps.remaining <= 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('오늘은 달린 기록으로 코스를 ${quota.gps.limit}개까지 등록할 수 있어요. 내일 다시 등록해 주세요.')),
      );
      return;
    }
    // ponytail: D4(GPS 코스 정보 입력)는 F7이 만들면 그 경로로 연결한다
    messenger.showSnackBar(const SnackBar(content: Text('코스 정보 입력 화면은 준비 중이에요.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 한도·이미 등록됨은 다른 사유가 없을 때만 받는다(결과 화면마다 코스 API를 부르지 않게)
    final blocker = registerBlocker(run, null) ?? registerBlocker(run, ref.watch(_quotaProvider).value);
    return WdSurface(
      radius: WdRadius.r12,
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: WdSpace.s12),
      onTap: blocker == null ? () => _register(context, ref) : null,
      child: Row(
        spacing: WdSpace.s10,
        children: [
          const WdIcon(WdIcons.ghostInfo, size: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s2,
              children: [
                Text(blocker == null ? '코스로 등록할 수 있어요' : '코스로 등록할 수 없어요', style: WdText.run13W700H16),
                Text(blocker ?? '달린 경로가 그대로 코스가 돼요', style: WdText.ko12.copyWith(color: WdColors.muted)),
              ],
            ),
          ),
          Text(
            '코스로 등록',
            style: WdText.ko13.copyWith(color: blocker == null ? WdColors.ink : WdColors.disabledText),
          ),
        ],
      ),
    );
  }
}
