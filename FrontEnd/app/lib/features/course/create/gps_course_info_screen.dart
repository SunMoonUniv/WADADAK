import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/error_message.dart';
import '../../../routes.dart';
import '../../home/registered_course_focus.dart';
import '../course_format.dart';
import 'course_info_inputs.dart';
import 'run_course_source_api.dart';

/// D4 달린 경로를 코스로 등록(GPS 코스 정보 입력). 달리기 결과의 `달린 경로로 코스 만들기`와 B6이 러닝 기록 ID로 연다.
///
/// 열면 기록의 경로 조각을 받아 서버가 최종 경로와 1 km 지점을 먼저 만든다(미리보기, 저장하지 않는다).
/// 이미 등록됨 → 1 km 미만 → GPS 정확도 부족으로 막히면 이름을 쓰기 전에 사유와 `돌아가기`만 보인다.
/// 이름 · 난이도 · 특징은 B4와 같다. 뒤로는 묻지 않고 닫는다.
/// 등록 성공 팝업을 닫으면 홈 탭으로 가서 지도를 새 코스 출발점으로 옮긴다(B4-07과 같다).
class GpsCourseInfoScreen extends ConsumerStatefulWidget {
  const GpsCourseInfoScreen({super.key, required this.recordId});

  /// 코스로 만들 러닝 기록(달리기 서버의 기록 ID).
  final String recordId;

  static const blockedTitle = '코스로 등록할 수 없는 기록이에요';

  /// 코스로 만들 수 없는 기록의 사유(B6-04와 같은 세 가지). 미리보기 · 등록 응답 코드로 고른다.
  /// 문구는 결과 화면 카드의 사유와 같은 표현이다. 점 2개 미만(COURSE-003)은 거의 달리지 않은 기록이라 1km 미만으로 본다.
  static const blockedReasons = {
    'COURSE-010': '이미 코스로 등록한 기록이에요. 같은 기록은 한 번만 코스로 등록할 수 있어요.',
    'COURSE-003': '1km 이상 달린 기록만 코스로 등록할 수 있어요.',
    'COURSE-004': '1km 이상 달린 기록만 코스로 등록할 수 있어요.',
    'COURSE-011': 'GPS가 끊긴 구간이 있어 코스로 등록할 수 없어요.',
  };

  static const loadFailedTitle = '경로를 불러오지 못했어요';

  /// 서버에 닿지 못했을 때 안내(B1과 같다). 그 밖의 실패는 서버 문구를 보인다(예: 없는 기록).
  static const offlineMessage = '네트워크를 확인하고 다시 시도해 주세요.';

  /// Figma D4 위 안내 문구 그대로다.
  static const routeNotice = '달린 경로가 그대로 코스가 되고 1 km마다 지점이 표시돼요. 다른 러너의 완주 기준이 돼요.';

  @override
  ConsumerState<GpsCourseInfoScreen> createState() => _GpsCourseInfoScreenState();
}

class _GpsCourseInfoScreenState extends ConsumerState<GpsCourseInfoScreen> with CourseInfoInputs {
  // Figma D4 지도 높이.
  static const _mapHeight = 268.0;

  /// 서버가 만든 최종 경로와 1 km 지점. 받는 중 · 막힘 · 실패면 null이다.
  GpsCourseRoute? _route;

  /// 코스로 만들 수 없는 기록의 사유. 있으면 사유와 `돌아가기`만 보인다.
  String? _blocked;

  /// 경로를 받지 못했다. `다시 시도`로 다시 받는다.
  ApiException? _loadError;

  /// 오늘 GPS 코스를 더 등록할 수 없다(등록 응답 COURSE-008).
  var _quotaUsedUp = false;
  var _submitting = false;

  /// 이 화면에서 하는 등록 하나의 멱등 키. 실패 뒤 다시 보낼 때도 같은 값을 쓴다(STA-05).
  final _idempotencyKey = const Uuid().v4();

  bool get _canRegister => inputsReady && !_quotaUsedUp && !_submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 기록의 경로 조각을 받아 서버에 최종 경로와 1 km 지점을 만들게 한다.
  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final segments = await ref.read(runCourseSourceApiProvider).segments(widget.recordId);
      final route =
          await ref.read(courseApiClientProvider).previewGpsRoute(recordId: widget.recordId, segments: segments);
      if (mounted) setState(() => _route = route);
    } on ApiException catch (e) {
      if (!mounted) return;
      final reason = GpsCourseInfoScreen.blockedReasons[e.code];
      setState(() => reason == null ? _loadError = e : _blocked = reason);
    }
  }

  /// 실패하면 입력을 그대로 두고 알린다(STA-05).
  Future<void> _register() async {
    final route = _route!;
    stopNameCheck();
    setState(() => _submitting = true);
    try {
      final course = await ref.read(courseApiClientProvider).registerGps(
            idempotencyKey: _idempotencyKey,
            recordId: route.recordId,
            segments: route.segments,
            name: nameValue,
            difficulty: difficulty!,
            tags: tags,
          );
      if (!mounted) return;
      await showCourseRegistered(context);
      if (!mounted) return;
      // 이 화면을 연 결과 화면은 그 탭에 그대로 남는다.
      ref.read(registeredCourseFocusProvider.notifier).show(course.startPoint);
      context.go(Routes.home);
    } on ApiException catch (e) {
      if (!mounted) return;
      final reason = GpsCourseInfoScreen.blockedReasons[e.code];
      switch (e.code) {
        // 그 사이 다른 기기에서 이 기록을 등록했다 등. 다시 보내도 같아서 사유 화면으로 바꾼다.
        case _ when reason != null:
          setState(() => _blocked = reason);
        case 'COURSE-006':
          markNameTaken();
        case 'COURSE-008':
          setState(() => _quotaUsedUp = true);
          showError(context, e);
        // 경로 때문에 막혔다(85% 겹침 · 출발점 지역). 다시 보내도 같아서 이유만 알린다.
        case 'COURSE-007' || 'COURSE-009':
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
    final route = _route;
    final ready = _blocked == null && route != null;
    return PopScope(
      // 등록하는 동안은 나가지 않는다. 결과를 놓치면 다시 등록하다 오늘 한도에 걸린다.
      canPop: !_submitting,
      child: Scaffold(
        appBar: WdAppBar(
          title: '코스로 등록',
          onBack: () {
            if (!_submitting) context.pop();
          },
        ),
        body: switch ((_blocked, route, _loadError)) {
          (final reason?, _, _) => _state(
              WdStateMessage(title: GpsCourseInfoScreen.blockedTitle, message: reason, icon: WdIcons.ghostInfo),
              WdButton('돌아가기', variant: WdButtonVariant.secondary, onPressed: () => context.pop()),
            ),
          (null, final route?, _) => _form(route),
          (null, null, final error?) => _state(
              WdStateMessage(
                title: GpsCourseInfoScreen.loadFailedTitle,
                message: error.code == ApiException.network ? GpsCourseInfoScreen.offlineMessage : errorMessage(error),
                icon: WdIcons.ghostWarning,
              ),
              WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: _load),
            ),
          _ => const Center(child: CircularProgressIndicator(color: WdColors.ink)),
        },
        bottomNavigationBar: ready
            ? WdBottomBar.pinned(primary: WdButton('코스 등록하기', onPressed: _canRegister ? _register : null))
            : null,
      ),
    );
  }

  /// 막힘 · 실패 안내와 그 아래 버튼(B1과 같은 모양).
  static Widget _state(WdStateMessage message, Widget action) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message,
            Padding(padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24), child: action),
          ],
        ),
      );

  Widget _form(GpsCourseRoute route) {
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final summaryLabel = WdText.ko12.copyWith(color: WdColors.muted);
    return ListView(
      padding: const EdgeInsets.only(bottom: WdSpace.s24),
      children: [
        SizedBox(
          height: _mapHeight,
          child: CourseRouteMap(route: route.route, distanceMarkers: route.distanceMarkers),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WdSpace.s16,
            children: [
              const WdInfoBanner(GpsCourseInfoScreen.routeNotice, plain: true),
              Text('코스 이름', style: label),
              ...nameInputs(),
              Text('난이도 · 특징', style: label),
              difficultyChips(),
              ...tagChipRows(),
              WdSurface(
                padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: WdSpace.s12),
                child: Column(
                  spacing: WdSpace.s6,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('코스 유형', style: summaryLabel)),
                        WdTag(CourseType.gps.label, filled: false),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: Text('공개 범위', style: summaryLabel)),
                        Text('모든 러너에게 공개', style: WdText.ko12Medium.copyWith(color: WdColors.ink)),
                      ],
                    ),
                  ],
                ),
              ),
              const WdInfoBanner(coursePublicPeriodNotice, tone: WdBannerTone.warning, plain: true),
              if (_quotaUsedUp) const WdInfoBanner(gpsQuotaUsedUpMessage, tone: WdBannerTone.warning),
            ],
          ),
        ),
      ],
    );
  }
}
