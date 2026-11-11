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

// 고른 점을 두르는 고리(4.1 B3-09). 지도에서 고른 코스 이름표(MAP-03)와 같은 파랑이다. Figma에는 아직 이 모양이 없다.
const _selectedRing = SizedBox.square(
  dimension: 36,
  child: DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.fromBorderSide(BorderSide(color: WdColors.info, width: 3)),
    ),
  ),
);

class _RouteDrawScreenState extends ConsumerState<RouteDrawScreen> {
  // 범례 + 아래 여백.
  static const _legendHeight = WdRouteLegend.height + WdSpace.s16;

  // 위 안내 · 되돌리기 · 전체 지우기(위 여백 16 + 버튼 2개). 채운 경로를 맞출 때 그 아래로 들어오게 한다.
  static const _controlsHeight = 92.0;

  /// 누른 곳에서 화면 거리로 이 안(dp)에 표지가 보이는 점이 있으면 그 점을 고른다(4.1 B3-09). 지름 44dp 누름 영역이다.
  static const _pickRadius = 22.0;

  /// 고른 점에서 화면 거리로 이 안(dp)을 다시 누르면 옮기지 않고 고르기만 푼다(4.1 B3-09). 점 표지 위를 누른 정도다.
  static const _cancelRadius = 10.0;

  /// 자동 생성 후보로 채운 가운데 점은 축척 막대가 이 거리(m) 이하일 때만 그린다(4.1 B3-09).
  static const _filledPointScaleMeters = 50;

  var _draft = const RouteDraft();
  var _method = _Method.draw;
  var _generating = false;

  /// 옮기려고 고른 점의 순서(B3-09). 고른 채로 지도를 누르면 그 자리로 옮긴다.
  int? _selected;

  /// 멈춘 지도의 범위 · 축척. 채운 점 중 무엇을 그릴지, 누른 곳 근처에 점이 있는지를 여기서 본다.
  MapCamera? _camera;

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
            onTap: _tapMap,
            onCameraIdle: (camera) => setState(() => _camera = camera),
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
                    child: WdMapHint(_selected != null
                        ? '옮길 곳을 탭하세요 · 점을 다시 탭하면 취소'
                        : _draft.filledCount > 0
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

  /// 첫 점 출발, 마지막 점 도착, 나머지는 경로 작성점(B3-05). 표지를 눌러도 지도 누름으로 가고, 거기서 가까운 점을 찾는다([_tapMap]).
  /// 고른 점에는 고리를 두른다(B3-09).
  List<MapMarker> _markers() {
    final points = _draft.points;
    final selected = _selected;
    return [
      for (var i = 0; i < points.length; i++)
        if (_shows(i)) _marker(points, i),
      if (selected != null)
        MapMarker(
          id: 'selected-point',
          position: points[selected],
          child: _selectedRing,
          imageKey: 'route-selected',
          priority: 1,
        ),
    ];
  }

  /// [i]번째 점에 표지를 그리는가. 자동 생성 후보로 채운 가운데 점(최대 500개)은 축척 [_filledPointScaleMeters]m 이하로
  /// 확대했을 때 화면 안의 것만 그린다(4.1 B3-09). 그 뒤에 이어 찍은 점은 늘 그린다.
  bool _shows(int i) {
    final points = _draft.points;
    if (i == 0) return true;
    // 한 바퀴처럼 출발점으로 돌아오면 출발만 보인다(Figma A4).
    if (i == points.length - 1) return points[i] != points.first;
    if (i >= _draft.filledCount) return true;
    final camera = _camera;
    return camera != null &&
        camera.scaleMeters <= _filledPointScaleMeters &&
        points[i].lat >= camera.southWest.lat &&
        points[i].lat <= camera.northEast.lat &&
        points[i].lng >= camera.southWest.lng &&
        points[i].lng <= camera.northEast.lng;
  }

  MapMarker _marker(List<GeoPoint> points, int i) {
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
      return MapMarker(
        id: 'point-$i',
        position: points[i],
        child: const WdRouteEndpoint.end(),
        imageKey: 'route-end',
        anchor: WdRouteEndpoint.endAnchor,
      );
    }
    return MapMarker.icon(id: 'point-$i', position: points[i], icon: WdIcons.routePoint);
  }

  /// [tap]에서 화면 거리 [_pickRadius] 안에 있는, 표지가 보이는 가장 가까운 점의 순서. 없으면 null.
  int? _nearestShown(GeoPoint tap) {
    final camera = _camera;
    if (camera == null) return null;
    final radiusMeters = _metersOf(_pickRadius, camera);
    int? nearest;
    var best = double.infinity;
    for (var i = 0; i < _draft.points.length; i++) {
      if (!_shows(i)) continue;
      final distance = _draft.points[i].distanceTo(tap);
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    }
    return best <= radiusMeters ? nearest : null;
  }

  /// 화면 거리 [dp]가 [camera]에서 몇 m인지. 지도 너비에 보이는 거리로 바꾼다. 지도를 돌리면 범위가 넓게 잡혀 조금 커진다.
  double _metersOf(double dp, MapCamera camera) =>
      camera.southWest.distanceTo(GeoPoint(camera.southWest.lat, camera.northEast.lng)) *
      dp /
      MediaQuery.sizeOf(context).width;

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

  /// 지도를 눌렀다. 고른 점이 있으면 누른 곳으로 옮기고(그 점을 다시 누르면 고르기만 푼다), 표지가 보이는 점 근처면
  /// 그 점을 고르고(B3-09), 아니면 끝에 새 점을 찍는다(B3-01).
  void _tapMap(GeoPoint point) {
    // 보낸 점과 화면의 점이 달라지지 않게 경로를 만드는 동안은 고치지 않는다.
    if (_generating) return;
    if (_quotaUsedUp) return _notify(customQuotaUsedUpMessage);
    final selected = _selected;
    final camera = _camera;
    if (selected != null && camera != null) {
      // 점 표지 위를 다시 눌렀을 때만 취소다. 그 밖은 바로 옆이어도 옮긴다.
      final onPoint = _draft.points[selected].distanceTo(point) <= _metersOf(_cancelRadius, camera);
      return setState(() {
        if (!onPoint) _draft = _draft.move(selected, point);
        _selected = null;
      });
    }
    final near = _nearestShown(point);
    if (near != null) return setState(() => _selected = near);
    if (_draft.isFull) return _notify(_fullMessage);
    setState(() => _draft = _draft.add(point));
    if (_draft.isFull) _notify(_fullMessage);
  }

  static const _fullMessage = '점은 ${RouteDraft.maxPoints}개까지 찍을 수 있어요.';

  // 점의 순서가 바뀌는 편집(되돌리기 · 채우기 · 전체 지우기 · 방식 바꾸기)은 고른 점을 푼다.
  void _undo() => setState(() {
        _draft = _draft.undo();
        _selected = null;
      });

  /// 고른 자동 생성 후보의 점으로 입력점을 채우고 경로 그리기(A4)로 간다. 되돌리기 한 번이면 채우기 전으로 돌아간다(정책 B3-A08).
  void _fill(List<GeoPoint> points) => setState(() {
        _draft = _draft.fill(points);
        _selected = null;
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
    if (!confirmed) return;
    setState(() {
      _draft = _draft.clear();
      _selected = null;
    });
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
      _selected = null;
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
