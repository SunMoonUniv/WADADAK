import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/config.dart';
import '../../../core/error_message.dart';
import '../../../core/map/map_view.dart';
import '../../home/my_location.dart';
import '../../run/application/run_controller.dart';
import 'auto_course_form.dart';

/// `자동 생성` 탭을 그릴지(빌드 플래그 `AUTO_COURSE`). 시험은 이 값으로 켜고 끈다.
final autoCourseProvider = Provider<bool>((ref) => autoCourse);

/// 평소 페이스(초/km)를 구한다. MY 기록 목록과 같은 서버 기록 요약에서 최근 기록의 평균이다. 기록이 없으면 null.
/// 시험은 기기 기록 없이 돌도록 이 함수를 바꾼다.
final usualPaceProvider = Provider<Future<int?> Function()>((ref) => () async {
      final runs = ref.read(runControllerProvider);
      if (runs.remoteRecords.isEmpty) await runs.loadHistory();
      return usualPace(runs.remoteRecords);
    });

/// 최근 [count]개 기록(페이스가 있는 것)의 평균 페이스(초/km, 반올림). 서버가 받는 180~900초 밖이면 그 끝으로 맞춘다.
int? usualPace(List<Map<String, dynamic>> records, {int count = 5}) {
  final paces = records
      .map((record) => (record['metrics'] as Map?)?['paceSecondsPerKm'])
      .whereType<num>()
      .where((pace) => pace > 0)
      .take(count)
      .toList();
  if (paces.isEmpty) return null;
  return (paces.reduce((a, b) => a + b) / paces.length).round().clamp(180, 900);
}

/// 목표 거리 · 시간 표시. `5km` · `7.5km` · `30분` · `1시간`.
String planTargetLabel(PlanForm form) => switch ((form.distanceM, form.durationMin)) {
      (final meters?, _) => meters % 1000 == 0 ? '${meters ~/ 1000}km' : '${(meters / 1000).toStringAsFixed(1)}km',
      (_, final minutes?) => formatMinutes(minutes),
      _ => '',
    };

/// 조건 한 줄(A2 문장 대신 · A3 위). 예: `선문대학교 아산캠퍼스 출발 · 5km · 한 바퀴`.
String planSummary(PlanForm form, {String? startName}) {
  final shape = form.shape!;
  final from = startName ?? (form.start == PlanStart.place ? form.startQuery! : PlanStart.current.label);
  return [
    '$from 출발',
    if (shape.needsTarget) planTargetLabel(form),
    shape.label,
    if (shape == PlanShape.pointToPoint) '${form.endQuery} 도착',
    if (shape == PlanShape.via) '${form.viaQuery} 경유',
  ].join(' · ');
}

/// B3 코스 만들기의 `자동 생성` 탭(Figma A1 · A7 · A2 · A3 · A6 · A8, 정책 B3-A01~A08).
///
/// 문장(A1)이나 폼(A7)으로 조건을 정하면 서버가 길을 따라 후보를 최대 3개 만든다(A2 → A3).
/// 후보를 고르면 [onPick]으로 그 입력점을 넘기고, 화면은 경로 그리기(A4)로 바뀐다.
class AutoCourseView extends ConsumerStatefulWidget {
  const AutoCourseView({super.key, required this.onPick, required this.onDraw});

  /// `이 코스로 만들기`(A3). 고른 후보의 입력점.
  final ValueChanged<List<GeoPoint>> onPick;

  /// `직접 그리기`(A8). 경로 그리기 탭으로 간다.
  final VoidCallback onDraw;

  /// A1 `이렇게 말해 보세요`. 누르면 입력란을 채운다.
  static const examples = ['천안역 근처 10km, 편의점 들르게', '여의도 한강공원 3km 가볍게', '30분 조깅 코스', '해운대에서 광안리까지 편도'];

  /// 문장 최대 길이(정책 B3-A01).
  static const maxTextLength = 200;

  @override
  ConsumerState<AutoCourseView> createState() => _AutoCourseViewState();
}

/// 화면 단계. 폼 · 결과 단계는 조건을 들고 있어 `다시 찾기` · `다시 입력`으로 같은 조건의 폼에 돌아온다.
sealed class _Stage {
  const _Stage();
}

/// A1 문장 입력. [notice]는 무관 요청 · 조건 자동 채우기 한도 안내.
final class _Input extends _Stage {
  const _Input({this.notice});
  final String? notice;
}

/// A7 · A7-1 · A7-2 조건 폼.
final class _Form extends _Stage {
  const _Form(this.form, {this.request, this.notice});
  final PlanForm form;
  final String? request;
  final String? notice;
}

/// A2 찾는 중.
final class _Searching extends _Stage {
  const _Searching(this.form, {this.request});
  final PlanForm form;
  final String? request;
}

/// A3 후보.
final class _Candidates extends _Stage {
  const _Candidates(this.form, this.result, {this.request});
  final PlanForm form;
  final PlanResult result;
  final String? request;
}

/// A6 후보 없음 · 비슷한 코스가 이미 있음.
final class _Empty extends _Stage {
  const _Empty(this.form, this.result, {this.request});
  final PlanForm form;
  final PlanResult result;
  final String? request;
}

/// A8 오늘 생성 한도.
final class _Limit extends _Stage {
  const _Limit();
}

class _AutoCourseViewState extends ConsumerState<AutoCourseView> {
  _Stage _stage = const _Input();
  final _text = TextEditingController();
  var _parsing = false;

  /// 오늘 남은 생성 횟수. 받지 못하면 보이지 않는다.
  int? _remaining;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _loadQuota();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await ref.read(courseApiClientProvider).planQuota();
      if (!mounted) return;
      setState(() {
        _remaining = quota.remaining;
        // 이미 다 썼으면 문장부터 쓰게 하지 않는다(A8).
        if (quota.remaining <= 0 && _stage is _Input) _stage = const _Limit();
      });
    } on Object {
      // 남은 횟수만 보이지 않는다. 생성할 때 서버가 다시 센다.
    }
  }

  /// `조건 자동 채우기`(A1 → A7-1). 무관 요청이면 A1에 안내만 보인다.
  Future<void> _parse() async {
    final text = _text.text.trim();
    setState(() => _parsing = true);
    try {
      final form = await ref.read(courseApiClientProvider).parsePlan(text);
      if (!mounted) return;
      setState(() => _stage = form.message != null ? _Input(notice: form.message) : _Form(form, request: text));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'COURSE-013') {
        setState(() => _stage = _Input(notice: e.message));
      } else {
        showError(context, e, onRetry: _parse);
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  /// `코스 찾기`(A7 → A2 → A3 · A6 · A8). 장소를 못 찾거나 너무 멀면 폼에 서버 안내를 보인다.
  /// 그 밖의 오류(서버 오류 · 시간 초과)는 폼으로 돌아가 `다시 시도`를 보인다.
  Future<void> _plan(PlanForm form, {String? request}) async {
    setState(() => _stage = _Searching(form, request: request));
    final location = await requestMyLocation(context, ref.read(myLocationProvider));
    if (!mounted) return;
    if (location == null) return setState(() => _stage = _Form(form, request: request));
    int? pace;
    try {
      pace = await ref.read(usualPaceProvider)();
    } on Object {
      // 평소 페이스 없이 보낸다(서버가 6분 30초로 본다).
    }
    try {
      final result =
          await ref.read(courseApiClientProvider).planCourse(form, currentLocation: location, paceSecPerKm: pace);
      if (!mounted) return;
      setState(() => _stage = switch (result.reason) {
            null => _Candidates(form, result, request: request),
            PlanReason.placeNotFound || PlanReason.placeTooFar => _Form(form, request: request, notice: result.message),
            PlanReason.noCandidates || PlanReason.similarExists => _Empty(form, result, request: request),
          });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'COURSE-012') return setState(() => _stage = const _Limit());
      setState(() => _stage = _Form(form, request: request));
      showError(context, e, onRetry: () => _plan(form, request: request));
    }
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
        _Input(:final notice) => _input(notice),
        _Form(:final form, :final request, :final notice) => AutoCourseForm(
            // 같은 단계로 돌아와도 넘긴 조건으로 다시 채운다.
            key: ObjectKey(_stage),
            initial: form,
            request: request,
            notice: notice,
            onSubmit: (submitted) => _plan(submitted, request: request),
          ),
        _Searching(:final form, :final request) => _SearchingView(form: form, request: request),
        _Candidates(:final form, :final result, :final request) => _CandidatesView(
            form: form,
            result: result,
            onRetry: () => setState(() => _stage = _Form(form, request: request)),
            onPick: widget.onPick,
          ),
        _Empty(:final form, :final result, :final request) => _empty(form, result, request),
        _Limit() => _limit(),
      };

  /// A1 문장 입력.
  Widget _input(String? notice) => Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: WdSpace.s8,
                    children: [
                      Text('어떤 코스를 달리고 싶나요?', style: WdText.heading19.copyWith(color: WdColors.ink)),
                      Text('장소 · 거리 · 원하는 길을 한 문장으로 말해 주세요.',
                          style: WdText.body13.copyWith(color: WdColors.muted)),
                    ],
                  ),
                  _PromptField(controller: _text),
                  WdButton(_parsing ? '조건 읽는 중…' : '조건 자동 채우기',
                      onPressed: _text.text.trim().isEmpty || _parsing ? null : _parse),
                  if (notice != null) WdInfoBanner(notice, tone: WdBannerTone.warning),
                  // 문장 국외 전송 고지(정책 B3-A06).
                  const WdInfoBanner('입력한 문장은 조건을 읽기 위해 외부 AI로 보내요.\n위치는 보내지 않아요.'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: WdSpace.s8,
                    children: [
                      Text('이렇게 말해 보세요', style: WdText.section12.copyWith(color: WdColors.muted)),
                      Wrap(
                        spacing: WdSpace.s8,
                        runSpacing: WdSpace.s8,
                        children: [
                          for (final example in AutoCourseView.examples)
                            WdFilterChip(example, onTap: () => _text.text = example),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, 0, WdSpace.s24, WdSpace.s24),
              child: Column(
                spacing: WdSpace.s16,
                children: [
                  if (_remaining case final remaining?)
                    Text('오늘 남은 코스 추천 $remaining회', style: WdText.label12.copyWith(color: WdColors.muted)),
                  WdButton('직접 조건 고르기',
                      variant: WdButtonVariant.secondary,
                      onPressed: () => setState(
                          () => _stage = const _Form(PlanForm(start: PlanStart.current, shape: PlanShape.loop)))),
                ],
              ),
            ),
          ),
        ],
      );

  /// A6. 한 바퀴를 만들 길이 없으면 왕복을 권한다(정책 B3-A04).
  Widget _empty(PlanForm form, PlanResult result, String? request) {
    final loopFailed = result.reason == PlanReason.noCandidates && form.shape == PlanShape.loop;
    final retry = WdButton('다시 입력',
        variant: WdButtonVariant.secondary,
        onPressed: () => setState(() => _stage = _Form(form, request: request)));
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: WdStateMessage(
                title: switch (result.reason) {
                  PlanReason.similarExists => '이미 있는 코스와 겹쳐요',
                  _ when loopFailed => '한 바퀴로 돌 길이 부족해요',
                  _ => '코스를 만들 길이 부족해요',
                },
                message: result.message ?? '',
              ),
            ),
          ),
        ),
        if (loopFailed)
          WdBottomBar.dual(
            secondary: retry,
            primary: WdButton('왕복으로 만들기', onPressed: () => _plan(form.withShape(PlanShape.outAndBack), request: request)),
          )
        else
          WdBottomBar.pinned(primary: retry),
      ],
    );
  }

  /// A8. 하루 20회(정책 B3-A05).
  Widget _limit() => Column(
        children: [
          const Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: WdStateMessage(
                  title: '오늘 코스 추천을 모두 썼어요',
                  message: '코스 추천은 하루 20번까지 쓸 수 있어요.\n내일 00:00부터 다시 쓸 수 있어요.',
                  icon: WdIcons.pause,
                ),
              ),
            ),
          ),
          WdBottomBar.pinned(primary: WdButton('직접 그리기', onPressed: widget.onDraw)),
        ],
      );
}

/// 문장 입력란(Figma AI / Prompt field). soft 바탕 · ink 테두리 · 높이 112.
class _PromptField extends StatelessWidget {
  const _PromptField({required this.controller});

  final TextEditingController controller;

  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(WdRadius.r16),
    borderSide: const BorderSide(color: WdColors.ink, width: 1.5),
  );

  @override
  Widget build(BuildContext context) {
    final style = WdText.raw(15, FontWeight.w400, 22);
    return SizedBox(
      height: 112,
      child: TextField(
        controller: controller,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        inputFormatters: [LengthLimitingTextInputFormatter(AutoCourseView.maxTextLength)],
        style: style.copyWith(color: WdColors.ink),
        cursorColor: WdColors.ink,
        decoration: InputDecoration(
          hintText: '예: 선문대에서 5km 평지로 한 바퀴',
          hintStyle: style.copyWith(color: WdColors.muted),
          filled: true,
          fillColor: WdColors.soft,
          contentPadding: const EdgeInsets.fromLTRB(WdSpace.s16, WdSpace.s16, WdSpace.s16, WdSpace.s12),
          enabledBorder: _border,
          focusedBorder: _border,
        ),
      ),
    );
  }
}

/// A2 찾는 중. 서버가 단계를 알려 주지 않아 시간에 따라 단계를 넘긴다(출발지 찾기 → 후보 만들기 → 고르기).
class _SearchingView extends StatefulWidget {
  const _SearchingView({required this.form, this.request});

  final PlanForm form;
  final String? request;

  static const steps = ['출발지 찾기', '길 따라 후보 만들기', '서로 다른 3개 고르기'];

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

class _SearchingViewState extends State<_SearchingView> {
  var _step = 0;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _timers.addAll([
      Timer(const Duration(milliseconds: 800), () => setState(() => _step = 1)),
      Timer(const Duration(seconds: 4), () => setState(() => _step = 2)),
    ]);
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s16,
                children: [
                  PlanRequestBubble(widget.request ?? planSummary(widget.form)),
                  Container(
                    padding: const EdgeInsets.all(WdSpace.s20),
                    decoration: BoxDecoration(color: WdColors.soft, borderRadius: BorderRadius.circular(WdRadius.r16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: WdSpace.s12,
                      children: [
                        Text('코스를 찾고 있어요', style: WdText.title17.copyWith(color: WdColors.ink)),
                        Text(
                          widget.form.shape == PlanShape.loop
                              ? '길을 따라 12개 방향으로 후보를 만들고, 서로 겹치지 않는 3개를 고르는 중이에요.'
                              : '길을 따라 후보를 만들고, 서로 겹치지 않는 코스를 고르는 중이에요.',
                          style: WdText.body13.copyWith(color: WdColors.muted),
                        ),
                        WdProgressBar(value: const [0.2, 0.58, 0.85][_step]),
                        for (final (i, label) in _SearchingView.steps.indexed)
                          _ProgressStep(label, done: i < _step, active: i == _step),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, 0, WdSpace.s24, WdSpace.s24),
              child: Column(
                spacing: WdSpace.s16,
                children: [
                  Text('보통 몇 초 안에 끝나요.', style: WdText.label12.copyWith(color: WdColors.muted)),
                  const WdButton('코스 찾는 중…', onPressed: null),
                ],
              ),
            ),
          ),
        ],
      );
}

/// 찾는 단계 한 줄(Figma AI / Progress step: Done · Active · Pending).
class _ProgressStep extends StatelessWidget {
  const _ProgressStep(this.label, {required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: Row(
          spacing: WdSpace.s10,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? WdColors.lime : (active ? WdColors.limeSoft : WdColors.paper),
                border: Border.all(
                  color: done || active ? WdColors.ink : WdColors.line,
                  width: active ? 2 : 1,
                ),
              ),
              child: done ? const WdIcon(WdIcons.check, size: 12, color: WdColors.ink) : null,
            ),
            Expanded(
              child: Text(
                label,
                style: (done || active ? WdText.raw(14, FontWeight.w500, 20) : WdText.run14W400H20)
                    .copyWith(color: done || active ? WdColors.ink : WdColors.muted),
              ),
            ),
          ],
        ),
      );
}

/// A3 후보. 지도에 후보를 모두 그리고 고른 후보를 라임 선으로 강조한다. 카드 · 지도 번호를 누르면 고른다.
class _CandidatesView extends StatefulWidget {
  const _CandidatesView({required this.form, required this.result, required this.onRetry, required this.onPick});

  final PlanForm form;
  final PlanResult result;
  final VoidCallback onRetry;
  final ValueChanged<List<GeoPoint>> onPick;

  @override
  State<_CandidatesView> createState() => _CandidatesViewState();
}

class _CandidatesViewState extends State<_CandidatesView> {
  var _selected = 0;

  List<PlanCandidate> get _candidates => widget.result.candidates;

  @override
  Widget build(BuildContext context) {
    final notApplied = _candidates.first.notApplied;
    return Column(
      children: [
        SizedBox(height: 268, child: _map()),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s16, WdSpace.s24, WdSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s10,
              children: [
                Text(planSummary(widget.form, startName: widget.result.startName),
                    style: WdText.body13Medium.copyWith(color: WdColors.ink)),
                for (final (i, candidate) in _candidates.indexed)
                  _CandidateCard(
                    number: i + 1,
                    candidate: candidate,
                    shape: widget.form.shape!,
                    showToilets: widget.form.prefer.contains(PlanPref.toiletOnRoute),
                    selected: i == _selected,
                    onTap: () => setState(() => _selected = i),
                  ),
                if (notApplied.isNotEmpty)
                  WdInfoBanner('${[for (final pref in notApplied) pref.label].join(' · ')} 조건은 아직 반영하지 않았어요.',
                      tone: WdBannerTone.warning),
              ],
            ),
          ),
        ),
        WdBottomBar.dual(
          secondary: WdButton('다시 찾기', variant: WdButtonVariant.secondary, onPressed: widget.onRetry),
          primary: WdButton('이 코스로 만들기', onPressed: () => widget.onPick(_candidates[_selected].anchorPoints)),
        ),
      ],
    );
  }

  Widget _map() {
    final start = _candidates.first.anchorPoints.first;
    return Stack(
      children: [
        MapView(
          initialCenter: start,
          initialZoom: 14,
          onCreated: (map) => map.fitPoints([for (final candidate in _candidates) ...candidate.anchorPoints]),
          lines: [
            for (final (i, candidate) in _candidates.indexed)
              MapLine(
                id: 'plan-$i',
                points: candidate.anchorPoints,
                style: i == _selected ? MapLineStyle.course : MapLineStyle.candidate,
              ),
          ],
          markers: [
            MapMarker(
              id: 'plan-start',
              position: start,
              child: const WdRouteEndpoint.start(),
              imageKey: 'route-start',
              anchor: WdRouteEndpoint.startAnchor,
              priority: 1,
            ),
            for (final (i, candidate) in _candidates.indexed)
              MapMarker(
                id: 'plan-number-$i',
                position: _farthest(candidate.anchorPoints),
                child: _NumberBadge(i + 1, selected: i == _selected),
                imageKey: 'plan-number-${i + 1}-${i == _selected}',
                priority: i == _selected ? 3 : 2,
                onTap: () => setState(() => _selected = i),
              ),
          ],
        ),
        // OSM 데이터로 만든 경로라 출처를 보인다(정책 B3-A07).
        Positioned(
          right: WdSpace.s8,
          bottom: WdSpace.s8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: WdSpace.s6, vertical: WdSpace.s2),
            decoration: BoxDecoration(color: WdColors.paper, borderRadius: BorderRadius.circular(4)),
            child: Text('© OpenStreetMap contributors', style: WdText.micro10.copyWith(color: WdColors.muted)),
          ),
        ),
      ],
    );
  }

  /// 번호표 자리: 출발점에서 가장 먼 점. 후보마다 다른 방향이라 번호가 잘 겹치지 않는다.
  static GeoPoint _farthest(List<GeoPoint> points) =>
      points.reduce((a, b) => points.first.distanceTo(b) > points.first.distanceTo(a) ? b : a);
}

/// 지도 위 후보 번호(Figma A3 `후보 N · 번호`). 고른 후보는 라임 바탕.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number, {required this.selected});

  final int number;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? WdColors.lime : WdColors.paper,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? WdColors.ink : WdColors.ghost, width: 1.5),
        ),
        child: Text('$number', style: WdText.body13Bold.copyWith(color: selected ? WdColors.ink : WdColors.muted)),
      );
}

/// 후보 카드(Figma AI / Candidate card). 예: `5.14km · 한 바퀴 · 오르막 32m` / `큰길 24% · 편의점 3곳 · 같은 길 2%`.
/// 오르막은 서버가 알 때만, 화장실 수는 `화장실 들르기`를 골랐을 때만 보인다(둘째 줄이 한 줄을 넘지 않게).
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.number,
    required this.candidate,
    required this.shape,
    required this.showToilets,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final PlanCandidate candidate;
  final PlanShape shape;
  final bool showToilets;
  final bool selected;
  final VoidCallback onTap;

  static String _percent(double ratio) => '${(ratio * 100).round()}%';

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 72,
            padding: const EdgeInsets.fromLTRB(WdSpace.s14, WdSpace.s14, WdSpace.s16, WdSpace.s14),
            decoration: BoxDecoration(
              color: selected ? WdColors.limeSoft : WdColors.paper,
              borderRadius: BorderRadius.circular(WdRadius.r16),
              border: Border.all(color: selected ? WdColors.ink : WdColors.line, width: selected ? 1.5 : 1),
            ),
            child: Row(
              spacing: WdSpace.s12,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: selected ? WdColors.lime : WdColors.soft, shape: BoxShape.circle),
                  child: Text('$number',
                      style: WdText.body13Bold.copyWith(color: selected ? WdColors.ink : WdColors.muted)),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                          [
                            '${(candidate.distanceMeters / 1000).toStringAsFixed(2)}km',
                            shape.label,
                            if (candidate.ascentMeters case final ascent?) '오르막 ${ascent}m',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WdText.cardTitle14.copyWith(color: WdColors.ink)),
                      Text(
                        [
                          '큰길 ${_percent(candidate.arterialRatio)}',
                          '편의점 ${candidate.storeCount}곳',
                          if (showToilets) '화장실 ${candidate.toiletCount}곳',
                          '같은 길 ${_percent(candidate.retraceRatio)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.label12.copyWith(color: WdColors.muted),
                      ),
                    ],
                  ),
                ),
                if (selected) const WdIcon(WdIcons.check, size: 24, color: WdColors.ink),
              ],
            ),
          ),
        ),
      );
}
