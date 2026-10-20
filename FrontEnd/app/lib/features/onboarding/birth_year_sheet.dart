import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';

/// F5 · 설정 선택 시트 — 출생연도. `적용`을 누르면 고른 해, 취소 · X · 바깥 · 뒤로는 null이다.
Future<int?> showBirthYearSheet(BuildContext context, {int? selected}) => showModalBottomSheet<int>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      builder: (_) => BirthYearSheet(selected: selected),
    );

class BirthYearSheet extends StatefulWidget {
  const BirthYearSheet({super.key, this.selected});

  final int? selected;

  @override
  State<BirthYearSheet> createState() => _BirthYearSheetState();
}

class _BirthYearSheetState extends State<BirthYearSheet> {
  static const _rowHeight = 44.0;

  final _years = BodyInfo.birthYears(DateTime.now());
  late int? _year = widget.selected;
  // 고른 해가 있으면 그 줄이 보이게 연다. 줄마다 구분선 1px이 붙는다.
  late final _scroll = ScrollController(
      initialScrollOffset: _year == null ? 0 : _years.indexOf(_year!).clamp(0, _years.length) * (_rowHeight + 1));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
                  Expanded(child: Text('출생연도', style: WdText.ko20Bold.copyWith(color: WdColors.ink))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: WdColors.muted),
                    tooltip: '닫기',
                  ),
                ],
              ),
              Text('만 14세 이상만 고를 수 있어요', style: WdText.label12.copyWith(color: WdColors.muted)),
              WdSurface(
                color: WdColors.paper,
                border: const BorderSide(color: WdColors.line),
                padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14),
                child: SizedBox(
                  height: _rowHeight * 5 + 4,
                  child: ListView.separated(
                    controller: _scroll,
                    itemCount: _years.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1, color: WdColors.line),
                    itemBuilder: (_, i) => _row(_years[i]),
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
                    child: WdButton('적용', onPressed: _year == null ? null : () => Navigator.of(context).pop(_year)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _row(int year) {
    final selected = year == _year;
    return Semantics(
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _year = year),
        child: SizedBox(
          height: _rowHeight,
          child: Row(
            spacing: 11,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? WdColors.ink : null,
                  border: selected ? null : Border.all(color: WdColors.checkOff, width: 1.5),
                ),
              ),
              Text('$year년생',
                  style: WdText.raw(12, selected ? FontWeight.w700 : FontWeight.w400, 18).copyWith(color: WdColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
