import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/error_message.dart';
import '../../../core/map/map_view.dart';
import '../../../routes.dart';
import '../../run/application/free_run_controller.dart';
import '../../run/domain/run_models.dart';
import '../course_format.dart';
import '../course_public_period_sheet.dart';
import 'auto_course_view.dart';
import 'gps_course_intro.dart';
import 'route_draft.dart';

/// B3 코스 만들기 — 경로 그리기. 지도를 탭해 입력점을 찍으면 서버가 순서대로 직선으로 이어 최종 경로를 만든다.
///
/// 생성 방식 탭의 `내가 달려서 등록`은 B5다. 달리기를 시작하거나(C5) 지난 기록에서 고른다(B6).
/// `자동 생성`(빌드 플래그 `AUTO_COURSE`)은 조건으로 후보를 만들고, 고른 후보의 점으로 입력점을 채운다(A4).
class RouteDrawScreen extends ConsumerStatefulWidget {
  const RouteDrawScreen({super.key, this.camera});

  /// 홈에서 보던 지도 위치(A2-07). 없으면 기본 위치에서 시작한다.
  final MapCamera? camera;

  @override
  ConsumerState<RouteDrawScreen> createState() => _RouteDrawScreenState();
}

enum _Method { draw, run, auto }

class _RouteDrawScreenState extends ConsumerState<RouteDrawScreen> {
  // 범례 + 아래 여백.
  static const _legendHeight = WdRouteLegend.height + WdSpace.s16;

  // 위 안내 · 되돌리기 · 전체 지우기(위 여백 16 + 버튼 2개). 채운 경로를 맞출 때 그 아래로 들어오게 한다.
  static const _controlsHeight = 92.0;

  var _draft = const RouteDraft();
  var _method = _Method.draw;
  var _generating = false;

  /// 자동 생성 후보로 채운 뒤 처음 그리는 지도는 채운 경로가 다 보이게 맞춘다.
  var _fitFilled = false;

  /// 오늘 사용자 지정 코스를 더 등록할 수 없다. 한도를 받아 오지 못하면 막지 않는다(등록할 때 서버가 다시 확인한다).
  var _quotaUsedUp = false;

  /// 오늘 GPS 기록으로 만든 코스를 3개 모두 등록했다. B5의 두 버튼을 막는다(4.1 B5 · 공통 3 GPS 한도 소진).
  var _gpsQuotaUsedUp = false;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await ref.read(courseApiClientProvider).registrationQuota();
      if (!mounted) return;
      setState(() {
        _quotaUsedUp = quota.custom.remaining <= 0;
        _gpsQuotaUsedUp = quota.gps.remaining <= 0;
      });
    } on Object {
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
                  items: ['경로 그리기', '내가 달려서 등록', if (ref.watch(autoCourseProvider)) '자동 생성'],
                  selectedIndex: _method.index,
                  style: WdSegmentStyle.light,
                  onChanged: (index) => _changeMethod(_Method.values[index]),
                ),
              ),
              if (_method == _Method.draw) ...[
                Expanded(child: _map()),
                _summary(),
              ] else if (_method == _Method.run)
                Expanded(child: GpsCourseIntro(quotaUsedUp: _gpsQuotaUsedUp))
              else
                Expanded(child: AutoCourseView(onPick: _fill, onDraw: () => _changeMethod(_Method.draw))),
            ],
          ),
          bottomNavigationBar: _method == _Method.run ? _runBar() : null,
        ),
      );

  /// B5 아래 두 버튼. 위의 1px 선도 Figma(1453:4054) 그대로다. 오늘 GPS 한도를 다 썼으면 둘 다 막는다.
  Widget _runBar() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ColoredBox(color: WdColors.map, child: SizedBox(width: double.infinity, height: WdSpace.s1)),
          WdBottomBar.dual(
            secondary: WdButton(
              '내 기록에서 코스 올리기',
              variant: WdButtonVariant.secondary,
              onPressed: _gpsQuotaUsedUp
                  ? null
                  : () async {
                      await context.push(Routes.courseFromRecords);
                      // 그 사이 다른 기기에서 등록했을 수 있어 다시 받는다(B6에서 등록하면 홈으로 가서 여기 오지 않는다)
                      if (mounted) unawaited(_loadQuota());
                    },
            ),
            primary: WdButton('달리기 시작하기', onPressed: _gpsQuotaUsedUp ? null : _startRun),
          ),
        ],
      );

  /// 달리기 탭의 C5 자유 러닝 준비로 간다(B5-03). 코스 상세에서 골라 둔 코스가 남아 있으면 비워 자유 러닝이 되게 한다.
  /// 자유 러닝 준비 화면이 아닐 때(카운트다운 · 코스 출발 확인 · 달리는 중 · 결과)는 건드리지 않고 그 화면을 보인다(RUN-05).
  void _startRun() {
    final run = ref.read(freeRunControllerProvider);
    if (!run.preparing && run.courseStart == null && run.snapshot.state == RunState.ready) run.clearCourse();
    context.go(Routes.run);
  }

  Widget _map() => Stack(
        children: [
          MapView(
            // 아래 범례만큼 비워 네이버 로고·축척이 범례에 가리지 않게 한다. 위는 안내 · 버튼만큼 비운다.
            padding: const EdgeInsets.only(top: _controlsHeight, bottom: _legendHeight),
            initialCenter: _draft.isEmpty ? widget.camera?.center ?? MapView.seoulCityHall : _draft.points.first,
            initialZoom: widget.camera?.zoom ?? 14,
            lines: [MapLine(id: 'draft', points: _draft.points)],
            markers: _markers(),
            onTap: _addPoint,
            onCreated: (map) {
              if (!_fitFilled) return;
              _fitFilled = false;
              map.fitPoints(_draft.points);
            },
          ),
          Positioned(
            left: WdSpace.s16,
            top: WdSpace.s16,
            right: WdSpace.s14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s8,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: WdMapHint(_draft.filledCount > 0
                        ? '자동 생성 경로 · 탭하면 이어 그려요'
                        : '지도를 탭해 경로 그리기 · 점을 순서대로 연결'),
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
  /// 자동 생성 후보로 채운 점(최대 500개)은 출발 · 도착만 그린다. 그 뒤에 이어 찍은 점은 작성점으로 그린다.
  List<MapMarker> _markers() => [for (var i = 0; i < _draft.points.length; i++) ?_marker(_draft.points, i)];

  MapMarker? _marker(List<GeoPoint> points, int i) {
    if (i == 0) {
      return MapMarker(
        id: 'point-$i',
        position: points[i],
        child: const WdRouteEndpoint.start(),
        imageKey: 'route-start',
        anchor: WdRouteEndpoint.startAnchor,
      );
    }
    if (i == points.length - 1) {
      // 한 바퀴처럼 출발점으로 돌아오면 출발만 보인다(Figma A4).
      if (points[i] == points.first) return null;
      return MapMarker(
        id: 'point-$i',
        position: points[i],
        child: const WdRouteEndpoint.end(),
        imageKey: 'route-end',
        anchor: WdRouteEndpoint.endAnchor,
      );
    }
    return i < _draft.filledCount ? null : MapMarker.icon(id: 'point-$i', position: points[i], icon: WdIcons.routePoint);
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
                (_draft.filledCount > 0 ? '입력점 (자동 생성)' : '찍은 점', '${_draft.points.length}'),
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

  /// 고른 자동 생성 후보의 점으로 입력점을 채우고 경로 그리기(A4)로 간다. 되돌리기 한 번이면 채우기 전으로 돌아간다(정책 B3-A08).
  void _fill(List<GeoPoint> points) => setState(() {
        _draft = _draft.fill(points);
        _method = _Method.draw;
        _fitFilled = true;
      });

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

  /// 점이 있으면 버릴지 묻고 B3를 연 화면(홈 · G4)으로 돌아간다(B3-08, 정책 문서 4.1).
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
