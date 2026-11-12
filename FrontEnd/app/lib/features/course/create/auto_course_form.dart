import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/course_api_client.dart';

/// 목표 거리(m) 또는 시간(분). 하나만 있다.
typedef PlanTarget = ({int? distanceM, int? durationMin});

/// B3 `자동 생성` 조건 폼(Figma A7 · A7-1 · A7-2).
///
/// 문장으로 채운 조건([request]가 있음, A7-1)이면 위에 그 문장을 두고, 비어 있는 필수 칸 옆에 `골라 주세요`를 단다.
/// 필수 칸을 다 채우기 전에는 `코스 찾기`를 누를 수 없다. 편도 · 경유는 거리 · 시간 대신 도착지 · 경유지 칸이 열린다.
class AutoCourseForm extends StatefulWidget {
  const AutoCourseForm({super.key, required this.initial, required this.onSubmit, this.request, this.notice});

  final PlanForm initial;
  final ValueChanged<PlanForm> onSubmit;

  /// 조건을 채운 문장(A7-1). 직접 고르면 null.
  final String? request;

  /// 장소를 못 찾았거나 너무 멀 때의 서버 안내(정책 B3-A04).
  final String? notice;

  /// `거리 · 시간` 칩(Figma A7). `직접 입력`은 km를 받는다.
  static const targets = <(String, PlanTarget)>[
    ('3km', (distanceM: 3000, durationMin: null)),
    ('5km', (distanceM: 5000, durationMin: null)),
    ('7km', (distanceM: 7000, durationMin: null)),
    ('10km', (distanceM: 10000, durationMin: null)),
    ('30분', (distanceM: null, durationMin: 30)),
    ('1시간', (distanceM: null, durationMin: 60)),
  ];

  /// 한 바퀴는 22km까지, 그 밖은 100km까지(정책 B3-A02).
  static int maxKm(PlanShape shape) => shape == PlanShape.loop ? 22 : 100;

  @override
  State<AutoCourseForm> createState() => _AutoCourseFormState();
}

class _AutoCourseFormState extends State<AutoCourseForm> {
  late PlanStart _start = widget.initial.start ?? PlanStart.current;
  late PlanShape _shape = widget.initial.shape ?? PlanShape.loop;
  late final _place = TextEditingController(text: widget.initial.startQuery);
  late final _end = TextEditingController(text: widget.initial.endQuery);
  late final _via = TextEditingController(text: widget.initial.viaQuery);
  late final Set<PlanPref> _prefer = {...widget.initial.prefer};

  /// 문장에서 읽은 시간이 칩에 없으면(예: 45분) 그 시간 칩을 하나 더 둔다.
  late final List<(String, PlanTarget)> _targets = [
    ...AutoCourseForm.targets,
    if (widget.initial.durationMin case final minutes? when !AutoCourseForm.targets.any((t) => t.$2.durationMin == minutes))
      (formatMinutes(minutes), (distanceM: null, durationMin: minutes)),
  ];
  late PlanTarget? _target = _initialTarget();
  late final _customKm = TextEditingController(
      text: _custom ? kmText(widget.initial.distanceM!) : '');
  late bool _custom = widget.initial.distanceM != null && !_targets.any((t) => t.$2 == _target);

  PlanTarget? _initialTarget() {
    final initial = (distanceM: widget.initial.distanceM, durationMin: widget.initial.durationMin);
    if (initial.distanceM == null && initial.durationMin == null) return null;
    return initial;
  }

  @override
  void dispose() {
    _place.dispose();
    _end.dispose();
    _via.dispose();
    _customKm.dispose();
    super.dispose();
  }

  bool get _prefilled => widget.request != null;

  bool get _startMissing => _start == PlanStart.place && _place.text.trim().isEmpty;

  bool get _placeMissing => switch (_shape) {
        PlanShape.pointToPoint => _end.text.trim().isEmpty,
        PlanShape.via => _via.text.trim().isEmpty,
        _ => false,
      };

  /// 직접 입력이면 칸의 km를 m로 바꾼다. 범위 밖이면 null.
  PlanTarget? get _chosenTarget {
    if (!_custom) return _target;
    final km = double.tryParse(_customKm.text.trim());
    if (km == null || km < 1 || km > AutoCourseForm.maxKm(_shape)) return null;
    return (distanceM: (km * 1000).round(), durationMin: null);
  }

  bool get _targetMissing => _shape.needsTarget && _chosenTarget == null;

  bool get _complete => !_startMissing && !_placeMissing && !_targetMissing;

  /// 평지와 오르막은 하나만 고른다.
  void _toggle(PlanPref pref) {
    if (_prefer.remove(pref)) return;
    _prefer
      ..add(pref)
      ..remove(switch (pref) { PlanPref.flat => PlanPref.hilly, PlanPref.hilly => PlanPref.flat, _ => null });
  }

  void _submit() {
    final target = _chosenTarget;
    widget.onSubmit(PlanForm(
      start: _start,
      startQuery: _start == PlanStart.place ? _place.text.trim() : null,
      shape: _shape,
      endQuery: _end.text.trim(),
      viaQuery: _via.text.trim(),
      distanceM: target?.distanceM,
      durationMin: target?.durationMin,
      prefer: _prefer,
    ));
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
                  if (widget.request case final request?) ...[
                    PlanRequestBubble(request),
                    const WdInfoBanner('문장에서 읽은 조건이에요. 빈 칸은 골라 주세요.'),
                  ],
                  if (widget.notice case final notice?) WdInfoBanner(notice, tone: WdBannerTone.warning),
                  _group(
                    '출발',
                    missing: _startMissing,
                    children: [
                      _chips([
                        for (final start in PlanStart.values)
                          WdFilterChip(start.label,
                              selected: _start == start, onTap: () => setState(() => _start = start)),
                      ]),
                      WdTextField(
                        controller: _place,
                        hintText: '장소 이름 검색',
                        maxLength: 100,
                        textInputAction: TextInputAction.done,
                        // 장소 이름을 쓰면 장소에서 출발한다.
                        onChanged: (_) => setState(() => _start = PlanStart.place),
                      ),
                    ],
                  ),
                  _group('모양', children: [
                    _chips([
                      for (final shape in PlanShape.values)
                        WdFilterChip(shape.label, selected: _shape == shape, onTap: () => setState(() => _shape = shape)),
                    ]),
                  ]),
                  if (_shape == PlanShape.pointToPoint)
                    _group('도착', missing: _placeMissing, children: [_placeField(_end, '도착지 이름 검색')])
                  else if (_shape == PlanShape.via)
                    _group('경유지', missing: _placeMissing, children: [_placeField(_via, '경유지 이름 검색')])
                  else
                    _group('거리 · 시간', missing: _targetMissing, children: [
                      _chips([
                        for (final (label, target) in _targets)
                          WdFilterChip(label,
                              selected: !_custom && _target == target,
                              onTap: () => setState(() {
                                    _custom = false;
                                    _target = target;
                                  })),
                        WdFilterChip('직접 입력', selected: _custom, onTap: () => setState(() => _custom = true)),
                      ]),
                      if (_custom)
                        WdTextField(
                          controller: _customKm,
                          hintText: '1~${AutoCourseForm.maxKm(_shape)}km',
                          suffixText: 'km',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          maxLength: 5,
                          onChanged: (_) => setState(() {}),
                        ),
                    ]),
                  _group('원하는 길', children: [
                    _chips([
                      for (final pref in PlanPref.supported)
                        WdFilterChip(pref.label, selected: _prefer.contains(pref), onTap: () => setState(() => _toggle(pref))),
                    ]),
                  ]),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, 0, WdSpace.s24, WdSpace.s24),
              child: WdButton('코스 찾기', onPressed: _complete ? _submit : null),
            ),
          ),
        ],
      );

  Widget _placeField(TextEditingController controller, String hint) => WdTextField(
        controller: controller,
        hintText: hint,
        maxLength: 100,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
      );

  /// 칸 이름과 내용. 문장으로 채웠는데 비어 있는 필수 칸이면 이름 옆에 `골라 주세요`(Figma A7-1).
  Widget _group(String label, {bool missing = false, required List<Widget> children}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s8,
        children: [
          Row(
            spacing: WdSpace.s8,
            children: [
              Text(label, style: WdText.section12.copyWith(color: WdColors.muted)),
              if (_prefilled && missing) const WdTag('골라 주세요', tone: WdTone.warning),
            ],
          ),
          ...children,
        ],
      );

  Widget _chips(List<Widget> chips) => Wrap(spacing: WdSpace.s8, runSpacing: WdSpace.s8, children: chips);

}

/// 사용자가 보낸 문장(Figma AI / Request bubble). 오른쪽에 둔다.
class PlanRequestBubble extends StatelessWidget {
  const PlanRequestBubble(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: WdSpace.s10),
          decoration: const BoxDecoration(
            color: WdColors.limeSoft,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Text(text, style: WdText.run14W400H20.copyWith(color: WdColors.ink)),
        ),
      );
}

/// km 숫자. `5` · `7.5`.
String kmText(int meters) => meters % 1000 == 0 ? '${meters ~/ 1000}' : (meters / 1000).toStringAsFixed(1);

/// `30분` · `1시간` · `1시간 30분`.
String formatMinutes(int minutes) {
  final (hours, rest) = (minutes ~/ 60, minutes % 60);
  if (hours == 0) return '$rest분';
  return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
}
