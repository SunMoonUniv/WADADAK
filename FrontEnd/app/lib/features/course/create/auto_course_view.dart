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

part 'auto_course_candidates.dart';
part 'auto_course_searching.dart';

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
      (final meters?, _) => '${kmText(meters)}km',
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
  const _Form(this.form, {this.notice});
  final PlanForm form;
  final String? notice;
}

/// A2 찾는 중.
final class _Searching extends _Stage {
  const _Searching(this.form);
  final PlanForm form;
}

/// A3 후보.
final class _Candidates extends _Stage {
  const _Candidates(this.form, this.result);
  final PlanForm form;
  final PlanResult result;
}

/// A6 후보 없음 · 비슷한 코스가 이미 있음.
final class _Empty extends _Stage {
  const _Empty(this.form, this.result);
  final PlanForm form;
  final PlanResult result;
}

/// A8 오늘 생성 한도.
final class _Limit extends _Stage {
  const _Limit();
}

class _AutoCourseViewState extends ConsumerState<AutoCourseView> {
  _Stage _stage = const _Input();
  final _text = TextEditingController();
  var _parsing = false;

  /// 조건을 채운 문장(A7-1). `직접 조건 고르기`로 시작했으면 null이다. 폼 · 찾는 중 화면 위에 보인다.
  String? _request;

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
      setState(() {
        if (form.message != null) {
          _stage = _Input(notice: form.message);
        } else {
          _request = text;
          _stage = _Form(form);
        }
      });
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
  Future<void> _plan(PlanForm form) async {
    setState(() => _stage = _Searching(form));
    final location = await requestMyLocation(context, ref.read(myLocationProvider));
    if (!mounted) return;
    if (location == null) return setState(() => _stage = _Form(form));
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
            null => _Candidates(form, result),
            PlanReason.placeNotFound || PlanReason.placeTooFar => _Form(form, notice: result.message),
            PlanReason.noCandidates || PlanReason.similarExists => _Empty(form, result),
          });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'COURSE-012') return setState(() => _stage = const _Limit());
      setState(() => _stage = _Form(form));
      showError(context, e, onRetry: () => _plan(form));
    }
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
        _Input(:final notice) => _input(notice),
        _Form(:final form, :final notice) => AutoCourseForm(
            // 같은 단계로 돌아와도 넘긴 조건으로 다시 채운다.
            key: ObjectKey(_stage),
            initial: form,
            request: _request,
            notice: notice,
            onSubmit: _plan,
          ),
        _Searching(:final form) => _SearchingView(form: form, request: _request),
        _Candidates(:final form, :final result) => _CandidatesView(
            form: form,
            result: result,
            onRetry: () => setState(() => _stage = _Form(form)),
            onPick: widget.onPick,
          ),
        _Empty(:final form, :final result) => _empty(form, result),
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
  Widget _empty(PlanForm form, PlanResult result) {
    final loopFailed = result.reason == PlanReason.noCandidates && form.shape == PlanShape.loop;
    final retry = WdButton('다시 입력',
        variant: WdButtonVariant.secondary,
        onPressed: () => setState(() => _stage = _Form(form)));
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
            primary: WdButton('왕복으로 만들기', onPressed: () => _plan(form.withShape(PlanShape.outAndBack))),
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
