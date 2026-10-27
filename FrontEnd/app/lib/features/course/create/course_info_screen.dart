import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/error_message.dart';
import '../course_format.dart';
import 'course_info_inputs.dart';

/// B4 코스 정보 입력 & 등록.
///
/// 위 지도에는 서버가 만든 최종 경로와 1km 거리 표지만 보인다(B4-01). 입력점은 보이지 않는다.
/// 등록 성공 팝업을 닫으면 등록한 코스를 결과로 돌려주며 닫힌다. B3가 그 결과로 홈에 돌아간다(B4-07).
class CourseInfoScreen extends ConsumerStatefulWidget {
  const CourseInfoScreen({super.key, required this.route});

  final GeneratedRoute route;

  @override
  ConsumerState<CourseInfoScreen> createState() => _CourseInfoScreenState();
}

class _CourseInfoScreenState extends ConsumerState<CourseInfoScreen> with CourseInfoInputs {
  // Figma 코스 지도 카드(A / Course map) 높이.
  static const _mapHeight = 110.0;

  /// 오늘 사용자 지정 코스를 더 등록할 수 없다(등록 응답 COURSE-008).
  var _quotaUsedUp = false;
  var _submitting = false;

  /// 이 화면에서 하는 등록 하나의 멱등 키. 실패 뒤 다시 보낼 때도 같은 값을 쓴다(STA-05).
  final _idempotencyKey = const Uuid().v4();

  bool get _canRegister => inputsReady && !_quotaUsedUp && !_submitting;

  /// 실패하면 입력을 그대로 두고 알린다(STA-05).
  Future<void> _register() async {
    stopNameCheck();
    setState(() => _submitting = true);
    try {
      final course = await ref.read(courseApiClientProvider).registerCustom(
            idempotencyKey: _idempotencyKey,
            anchorPoints: widget.route.anchorPoints,
            name: nameValue,
            difficulty: difficulty!,
            tags: tags,
          );
      if (!mounted) return;
      await showCourseRegistered(context);
      if (mounted) context.pop(course);
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'COURSE-006':
          markNameTaken();
        case 'COURSE-008':
          setState(() => _quotaUsedUp = true);
          showError(context, e);
        // 경로 때문에 막혔다. 다시 보내도 같아서 이유만 알린다. 경로는 B3로 돌아가 고친다.
        case 'COURSE-003' || 'COURSE-004' || 'COURSE-005' || 'COURSE-007' || 'COURSE-009':
          showError(context, e);
        default:
          showError(context, e, onRetry: _register);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    return PopScope(
      // 등록하는 동안은 나가지 않는다. 결과를 놓치면 다시 등록하다 오늘 한도에 걸린다.
      canPop: !_submitting,
      child: Scaffold(
        // 경로를 고치려면 B3로 돌아간다. B3에는 입력점이 그대로 있다.
        appBar: WdAppBar(
          title: '코스 정보',
          onBack: () {
            if (!_submitting) context.pop();
          },
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s16,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WdRadius.r12),
                  child: SizedBox(
                    height: _mapHeight,
                    child: CourseRouteMap(route: widget.route.route, distanceMarkers: widget.route.distanceMarkers),
                  ),
                ),
                Text('코스 이름', style: label),
                ...nameInputs(),
                Text('난이도', style: label),
                difficultyChips(),
                Text('코스 특징 (중복 선택)', style: label),
                ...tagChipRows(),
                Text('코스 유형', style: label),
                // 실제 완주 판정(달리기 정책 5.3)은 서버가 한다. 이탈 안내 수치는 완주 기준이 아니라 적지 않는다.
                const WdSurface(
                  padding: EdgeInsets.all(WdSpace.s14),
                  child: WdStepRow(title: '그려서 만든 코스', description: '경로를 따라 끝까지 달려야 완주로 기록돼요.'),
                ),
                const WdInfoBanner(coursePublicPeriodNotice, plain: true),
                if (_quotaUsedUp) const WdInfoBanner(customQuotaUsedUpMessage, tone: WdBannerTone.warning),
              ],
            ),
          ],
        ),
        bottomNavigationBar: WdBottomBar.pinned(
          primary: WdButton('코스 등록하기', onPressed: _canRegister ? _register : null),
        ),
      ),
    );
  }
}
