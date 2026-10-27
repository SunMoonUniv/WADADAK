import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

/// I1 연 · 월 선택 시트(Figma `I1 · 연 · 월 선택 시트 (10/27 회의)`). 달 이름을 누르면 연다.
///
/// 연도 | 월 두 줄 휠이다. [first](첫 기록이 있는 달)보다 앞이나 [last](이번 달)보다 뒤는 흐리게 보이고 고를 수 없다.
/// `적용`을 누르면 고른 달(1일), 취소 · X · 바깥 · 뒤로는 null이다.
Future<DateTime?> showRunMonthSheet(
  BuildContext context, {
  required DateTime selected,
  required DateTime first,
  required DateTime last,
}) => showModalBottomSheet<DateTime>(
  context: context,
  backgroundColor: WdColors.paper,
  showDragHandle: true,
  builder: (_) => RunMonthSheet(selected: selected, first: first, last: last),
);

class RunMonthSheet extends StatefulWidget {
  const RunMonthSheet({super.key, required this.selected, required this.first, required this.last});

  final DateTime selected, first, last;

  @override
  State<RunMonthSheet> createState() => _RunMonthSheetState();
}

class _RunMonthSheetState extends State<RunMonthSheet> {
  static const _rowHeight = 48.0;

  late final _years = [for (var y = widget.first.year; y <= widget.last.year; y++) y];
  late int _year = widget.selected.year;
  late int _month = widget.selected.month;
  late final _yearWheel = FixedExtentScrollController(initialItem: _years.indexOf(_year));
  late final _monthWheel = FixedExtentScrollController(initialItem: _month - 1);

  @override
  void dispose() {
    _yearWheel.dispose();
    _monthWheel.dispose();
    super.dispose();
  }

  /// 첫 기록이 있는 달 ~ 이번 달만 고를 수 있다.
  bool _allowed(int year, int month) {
    final m = DateTime(year, month);
    return !m.isBefore(DateTime(widget.first.year, widget.first.month)) && !m.isAfter(widget.last);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(WdSpace.s16, 0, WdSpace.s16, WdSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s12,
        children: [
          Row(
            children: [
              Expanded(child: Text('연 · 월 선택', style: WdText.ko20Bold.copyWith(color: WdColors.ink))),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: WdColors.muted),
                tooltip: '닫기',
              ),
            ],
          ),
          Text('이번 달보다 뒤는 고를 수 없어요', style: WdText.label12.copyWith(color: WdColors.muted)),
          WdSurface(
            color: WdColors.paper,
            border: const BorderSide(color: WdColors.line),
            padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24, vertical: WdSpace.s12),
            child: SizedBox(
              height: _rowHeight * 3,
              child: Row(
                spacing: WdSpace.s12,
                children: [
                  Expanded(
                    child: _wheel(
                      label: '연도',
                      controller: _yearWheel,
                      count: _years.length,
                      text: (i) => '${_years[i]}',
                      selected: (i) => _years[i] == _year,
                      enabled: (i) => _allowed(_years[i], _years[i] == widget.first.year ? widget.first.month : 1),
                      onChanged: (i) => setState(() => _year = _years[i]),
                    ),
                  ),
                  Expanded(
                    child: _wheel(
                      label: '월',
                      controller: _monthWheel,
                      count: 12,
                      text: (i) => '${i + 1}월',
                      selected: (i) => i + 1 == _month,
                      enabled: (i) => _allowed(_year, i + 1),
                      onChanged: (i) => setState(() => _month = i + 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            spacing: WdSpace.s12,
            children: [
              Expanded(
                child: WdButton('취소', variant: WdButtonVariant.secondary, onPressed: () => Navigator.of(context).pop()),
              ),
              Expanded(
                child: WdButton(
                  '적용',
                  // 이번 달보다 뒤(또는 첫 기록보다 앞)에 멈춰 있으면 누를 수 없다
                  onPressed: _allowed(_year, _month) ? () => Navigator.of(context).pop(DateTime(_year, _month)) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// 가운데 줄이 고른 값인 휠. 고른 줄 뒤에 회색 띠를 깐다(Figma).
  Widget _wheel({
    required String label,
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) text,
    required bool Function(int) selected,
    required bool Function(int) enabled,
    required ValueChanged<int> onChanged,
  }) => Semantics(
    label: label,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: _rowHeight,
          decoration: BoxDecoration(color: WdColors.soft, borderRadius: BorderRadius.circular(WdRadius.r12)),
        ),
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _rowHeight,
          diameterRatio: 3,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count,
            builder: (_, i) => Center(
              child: Text(
                text(i),
                style: selected(i)
                    ? WdText.raw(22, FontWeight.w700, 28).copyWith(color: enabled(i) ? WdColors.ink : WdColors.grayLight)
                    : WdText.raw(18, FontWeight.w500, 24).copyWith(color: enabled(i) ? WdColors.muted : WdColors.grayLight),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
