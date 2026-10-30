import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../run/domain/run_voice.dart';

/// F5 · 오디오 안내 시트(Figma `F5 · 설정 선택 시트`). F4 `오디오 안내`를 누르면 연다.
///
/// 안내 안 함 · 거리마다 · 시간마다 중 하나를 고르고 −/+로 간격을 정한다.
/// 간격은 달리기의 음성 안내 정책대로 1 · 2 · 5km, 5 · 10 · 15분만 된다(Figma의 0.5km · 1분 단위 대신, 2026-10-30 결정).
/// `적용`을 누르면 고른 설정, 취소 · X · 바깥 · 뒤로는 null이다.
Future<RunVoiceSettings?> showVoiceSheet(BuildContext context, RunVoiceSettings current) =>
    showModalBottomSheet<RunVoiceSettings>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => VoiceSheet(current: current),
    );

class VoiceSheet extends StatefulWidget {
  const VoiceSheet({super.key, required this.current});

  final RunVoiceSettings current;

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  static const _distances = [1, 2, 5];
  static const _minutes = [5, 10, 15];

  late var _voice = widget.current;

  /// [unit]이 null이면 안내 안 함.
  void _choose(VoiceUnit? unit) => setState(
    () => _voice = unit == null ? _voice.copyWith(enabled: false) : _voice.copyWith(enabled: true, unit: unit),
  );

  @override
  Widget build(BuildContext context) {
    final off = !_voice.enabled;
    final byDistance = _voice.enabled && _voice.unit == VoiceUnit.distance;
    final byTime = _voice.enabled && _voice.unit == VoiceUnit.time;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(WdSpace.s16, 0, WdSpace.s16, WdSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WdSpace.s12,
          children: [
            Row(
              children: [
                Expanded(child: Text('오디오 안내', style: WdText.ko20Bold.copyWith(color: WdColors.ink))),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: WdColors.muted),
                  tooltip: '닫기',
                ),
              ],
            ),
            Text('안내 기준을 고르고 간격을 직접 정하세요', style: WdText.label12.copyWith(color: WdColors.muted)),
            WdSurface(
              color: WdColors.paper,
              border: const BorderSide(color: WdColors.line),
              padding: const EdgeInsets.fromLTRB(WdSpace.s14, WdSpace.s4, WdSpace.s14, WdSpace.s12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Option(title: '안내 안 함', selected: off, onTap: () => _choose(null)),
                  const Divider(height: 1, thickness: 1, color: WdColors.map),
                  _Option(
                    title: '거리마다',
                    subtitle: '정한 거리마다 거리 · 시간 · 페이스',
                    selected: byDistance,
                    onTap: () => _choose(VoiceUnit.distance),
                    stepper: _Stepper(
                      label: '${_voice.distanceKm} km',
                      semantic: '안내 거리',
                      values: _distances,
                      value: _voice.distanceKm,
                      onChanged: (km) =>
                          setState(() => _voice = _voice.copyWith(enabled: true, unit: VoiceUnit.distance, distanceKm: km)),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, color: WdColors.map),
                  _Option(
                    title: '시간마다',
                    subtitle: '정한 시간마다 거리 · 시간 · 페이스 안내',
                    selected: byTime,
                    onTap: () => _choose(VoiceUnit.time),
                    stepper: _Stepper(
                      label: '${_voice.timeMinutes}분',
                      semantic: '안내 시간',
                      values: _minutes,
                      value: _voice.timeMinutes,
                      onChanged: (min) =>
                          setState(() => _voice = _voice.copyWith(enabled: true, unit: VoiceUnit.time, timeMinutes: min)),
                    ),
                  ),
                  const SizedBox(height: WdSpace.s4),
                  Text(
                    '거리는 1 · 2 · 5 km, 시간은 5 · 10 · 15분 중에서 골라요',
                    style: WdText.label12.copyWith(color: WdColors.muted),
                  ),
                ],
              ),
            ),
            Row(
              spacing: WdSpace.s12,
              children: [
                Expanded(
                  child: WdButton('취소', variant: WdButtonVariant.secondary, onPressed: () => Navigator.of(context).pop()),
                ),
                Expanded(
                  flex: 2,
                  child: WdButton('적용', onPressed: () => Navigator.of(context).pop(_voice)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 동그라미 + 제목(+ 설명) + 오른쪽 −/+. 고른 줄은 제목이 굵고 크다.
class _Option extends StatelessWidget {
  const _Option({required this.title, this.subtitle, required this.selected, required this.onTap, this.stepper});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? stepper;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WdSpace.s12),
        child: Row(
          spacing: WdSpace.s12,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? WdColors.ink : null,
                border: selected ? null : Border.all(color: WdColors.line, width: 1.5),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: selected
                        ? WdText.ko16Bold.copyWith(color: WdColors.ink)
                        : WdText.body13.copyWith(color: WdColors.ink),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: WdText.raw(11, FontWeight.w400, 16).copyWith(color: WdColors.muted)),
                ],
              ),
            ),
            ?stepper,
          ],
        ),
      ),
    ),
  );
}

/// soft 알약 안의 − 값 +. [values] 안에서 한 칸씩 움직이고 끝에서는 그 쪽 버튼이 흐려진다.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.semantic,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String semantic;
  final List<int> values;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final i = values.indexOf(value);
    Widget button(String text, String name, int? next) => Semantics(
      button: true,
      enabled: next != null,
      label: '$semantic $name',
      excludeSemantics: true,
      child: InkWell(
        onTap: next == null ? null : () => onChanged(next),
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 28,
          child: Center(
            child: Text(
              text,
              style: WdText.ko16Bold.copyWith(color: next == null ? WdColors.grayLight : WdColors.ink),
            ),
          ),
        ),
      ),
    );
    return WdSurface(
      radius: WdRadius.full,
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('−', '줄이기', i > 0 ? values[i - 1] : null),
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8, vertical: 2),
            decoration: const BoxDecoration(color: WdColors.paper, borderRadius: BorderRadius.all(Radius.circular(99))),
            child: Text(label, textAlign: TextAlign.center, style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
          ),
          button('+', '늘리기', i < values.length - 1 ? values[i + 1] : null),
        ],
      ),
    );
  }
}
