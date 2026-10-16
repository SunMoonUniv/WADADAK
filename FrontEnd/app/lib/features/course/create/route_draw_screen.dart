import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/error_message.dart';
import '../../../core/map/map_view.dart';
import '../../../routes.dart';
import '../course_format.dart';
import '../course_public_period_sheet.dart';
import 'route_draft.dart';

/// B3 코스 만들기 — 경로 그리기. 지도를 탭해 입력점을 찍으면 서버가 순서대로 직선으로 이어 최종 경로를 만든다.
///
/// 생성 방식 탭의 `내가 달려서 등록`(B5, Figma 프레임 이름은 B4)은 F7에서 만든다. 지금은 자리만 있다.
class RouteDrawScreen extends ConsumerStatefulWidget {
  const RouteDrawScreen({super.key, this.camera});

  /// 홈에서 보던 지도 위치(A2-07). 없으면 기본 위치에서 시작한다.
  final MapCamera? camera;

  @override
  ConsumerState<RouteDrawScreen> createState() => _RouteDrawScreenState();
}

enum _Method { draw, run }

class _RouteDrawScreenState extends ConsumerState<RouteDrawScreen> {
  // 범례 + 아래 여백.
  static const _legendHeight = WdRouteLegend.height + WdSpace.s16;

  var _draft = const RouteDraft();
  var _method = _Method.draw;
  var _generating = false;

  /// 오늘 사용자 지정 코스를 더 등록할 수 없다. 한도를 받아 오지 못하면 막지 않는다(등록할 때 서버가 다시 확인한다).
  var _quotaUsedUp = false;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await ref.read(courseApiClientProvider).registrationQuota();
      if (mounted) setState(() => _quotaUsedUp = quota.custom.remaining <= 0);
    } on ApiException {
      // 막지 않고 둔다.
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // 휴대폰 뒤로 가기도 앱바 뒤로 가기와 같이 확인한다(B3-08).
        canPop: _draft.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: WdAppBar(title: '코스 만들기', onBack: _leave),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16, vertical: WdSpace.s10),
                child: WdSegmentedControl(
                  items: const ['경로 그리기', '내가 달려서 등록'],
                  selectedIndex: _method.index,
                  style: WdSegmentStyle.light,
                  onChanged: (index) => _changeMethod(_Method.values[index]),
                ),
              ),
              if (_method == _Method.draw) ...[
                Expanded(child: _map()),
                _summary(),
              ] else
                Expanded(
                  child: Center(child: Text('준비 중인 화면이에요', style: WdText.body13.copyWith(color: WdColors.muted))),
                ),
            ],
          ),
        ),
      );

  Widget _map() => Stack(
        children: [
          MapView(
            // 아래 범례만큼 비워 네이버 로고·축척이 범례에 가리지 않게 한다.
            padding: const EdgeInsets.only(bottom: _legendHeight),
            initialCenter: widget.camera?.center ?? MapView.seoulCityHall,
            initialZoom: widget.camera?.zoom ?? 14,
            lines: [MapLine(id: 'draft', points: _draft.points)],
            markers: _markers(),
            onTap: _addPoint,
          ),
          Positioned(
            left: WdSpace.s16,
            top: WdSpace.s16,
            right: WdSpace.s14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s8,
              children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: WdMapHint('지도를 탭해 경로 그리기 · 점을 순서대로 연결'),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: WdSpace.s8,
                  children: [
                    WdMapPillButton('↺  되돌리기', bold: true, onPressed: _draft.canUndo && !_generating ? _undo : null),
                    // 점이 없으면 확인 팝업 없이 아무 일도 하지 않는다(B3-04).
                    WdMapPillButton('✕  전체 지우기', onPressed: !_draft.isEmpty && !_generating ? _clearAll : null),
                  ],
                ),
              ],
            ),
          ),
          const Positioned(left: WdSpace.s16, bottom: WdSpace.s16, child: WdRouteLegend()),
        ],
      );

  /// 첫 점 출발, 마지막 점 도착, 나머지는 경로 작성점(B3-05). 표지를 눌러도 지도 누름으로 간다.
  List<MapMarker> _markers() {
    final points = _draft.points;
    return [
      for (var i = 0; i < points.length; i++)
        if (i == 0)
          MapMarker(
            id: 'point-$i',
            position: points[i],
            child: const WdRouteEndpoint.start(),
            imageKey: 'route-start',
            anchor: WdRouteEndpoint.startAnchor,
          )
        else if (i == points.length - 1)
          MapMarker(
            id: 'point-$i',
            position: points[i],
            child: const WdRouteEndpoint.end(),
            imageKey: 'route-end',
            anchor: WdRouteEndpoint.endAnchor,
          )
        else
          MapMarker.icon(id: 'point-$i', position: points[i], icon: WdIcons.routePoint),
    ];
  }

  Widget _summary() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          child: Column(
            spacing: WdSpace.s16,
            children: [
              WdSummaryTiles([
                ('총 거리', formatKm(_draft.distanceMeters.round())),
                ('찍은 점', '${_draft.points.length}'),
              ]),
              if (_quotaUsedUp)
                const WdInfoBanner(customQuotaUsedUpMessage, tone: WdBannerTone.warning)
              else
                const WdInfoBanner('그려서 만드는 코스는 하루 1개까지 등록할 수 있어요.', tone: WdBannerTone.warning, plain: true),
              // 입력점 2개 이상, 1km 이상 100km 이하가 아니면 비활성(B3-06).
              WdButton('다음 · 코스 정보 입력', onPressed: _draft.canProceed && !_quotaUsedUp && !_generating ? _next : null),
            ],
          ),
        ),
      );

  void _addPoint(GeoPoint point) {
    // 보낸 점과 화면의 점이 달라지지 않게 경로를 만드는 동안은 찍지 않는다.
    if (_generating) return;
    if (_quotaUsedUp) return _notify(customQuotaUsedUpMessage);
    if (_draft.isFull) return _notify(_fullMessage);
    setState(() => _draft = _draft.add(point));
    if (_draft.isFull) _notify(_fullMessage);
  }

  static const _fullMessage = '점은 ${RouteDraft.maxPoints}개까지 찍을 수 있어요.';

  void _undo() => setState(() => _draft = _draft.undo());

  Future<void> _clearAll() async {
    final confirmed = await _confirm(
      title: '찍은 점을 모두 지울까요?',
      message: '지운 점은 되돌리기로 다시 살릴 수 있어요.',
      cancel: '취소',
      ok: '지우기',
    );
    if (confirmed) setState(() => _draft = _draft.clear());
  }

  /// 서버에 최종 경로를 만들어 B4로 간다. 실패하면 B3에 머물러 점을 그대로 두고 다시 시도할 수 있게 한다(B3-06).
  /// 경로를 만들면 B4로 가기 전에 공개 기간(B11)을 매번 알린다. `확인`을 눌러야 넘어가고 닫으면 B3에 머문다(4.1 B11).
  Future<void> _next() async {
    setState(() => _generating = true);
    final GeneratedRoute route;
    try {
      route = await ref.read(courseApiClientProvider).generateRoute(_draft.points);
    } on ApiException catch (e) {
      if (mounted) showError(context, e, onRetry: _next);
      return;
    } finally {
      if (mounted) setState(() => _generating = false);
    }
    if (!mounted) return;
    final confirmed = await showCoursePublicPeriodSheet(context);
    if (!confirmed || !mounted) return;
    // B4를 이 화면 위에 쌓는다. 돌아오면 입력점이 그대로 있어 고칠 수 있다(정책 공통 3).
    final course = await context.push<RegisteredCourse>(Routes.courseInfo, extra: route);
    // 등록했으면 홈으로 돌아가 새 코스 위치를 보여 준다(B4-07).
    if (course != null && mounted) context.pop(course);
  }

  Future<void> _changeMethod(_Method method) async {
    if (method == _method) return;
    if (method == _Method.run && !_draft.isEmpty) {
      final confirmed = await _confirm(
        title: '생성 방식을 바꿀까요?',
        message: '작성 중인 경로가 삭제돼요.',
        cancel: '계속 작성',
        ok: '방식 변경',
      );
      if (!confirmed) return;
    }
    setState(() {
      _method = method;
      if (method == _Method.run) _draft = const RouteDraft();
    });
  }

  /// 점이 있으면 버릴지 묻고 홈으로 돌아간다(B3-08).
  Future<void> _leave() async {
    if (!_draft.isEmpty) {
      final confirmed = await _confirm(
        title: '코스 만들기를 그만둘까요?',
        message: '찍은 점이 모두 삭제돼요.',
        cancel: '계속 작성',
        ok: '나가기',
      );
      if (!confirmed) return;
    }
    if (mounted) context.pop();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String cancel,
    required String ok,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ok)),
          ],
        ),
      ) ??
      false;

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
