import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

/// 코스 이탈 팝업(정책 7.1·7.2). [open]이 켜지면 진동과 함께 띄우고, 복귀·일시정지로 꺼지면 닫는다.
/// 추가 설명 문구는 두지 않는다. 안내 중에도 측정은 계속된다.
class CourseDeviationAlert extends StatefulWidget {
  const CourseDeviationAlert({
    super.key,
    required this.open,
    required this.onConfirm,
    required this.onMute,
    required this.child,
  });

  final bool open;
  final VoidCallback onConfirm, onMute;
  final Widget child;

  @override
  State<CourseDeviationAlert> createState() => _CourseDeviationAlertState();
}

class _CourseDeviationAlertState extends State<CourseDeviationAlert> {
  DialogRoute<bool>? _route;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CourseDeviationAlert oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.open && _route == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    } else if (!widget.open && _route != null) {
      final route = _route!;
      _route = null; // 코드로 닫으면 버튼을 누른 것으로 치지 않는다
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  Future<void> _show() async {
    if (!mounted || !widget.open || _route != null) return;
    unawaited(HapticFeedback.heavyImpact());
    final route = _route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: WdColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WdRadius.r20)),
        child: Padding(
          padding: const EdgeInsets.all(WdSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('코스를 벗어났어요', style: WdText.ko20Bold),
              const SizedBox(height: WdSpace.s24),
              Row(
                spacing: WdSpace.s8,
                children: [
                  Expanded(
                    child: WdButton(
                      '다시 표시하지 않음',
                      variant: WdButtonVariant.secondary,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  Expanded(child: WdButton('확인', onPressed: () => Navigator.pop(context, true))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final confirmed = await Navigator.of(context).push(route);
    if (_route != route) return; // 복귀·일시정지로 닫혔다
    _route = null;
    // 뒤로 가기로 닫으면 확인과 같다
    if (confirmed == false) {
      widget.onMute();
    } else {
      widget.onConfirm();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
