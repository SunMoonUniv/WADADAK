import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

/// Shown only after a definitive refusal and durable cancellation, never for an uncertain start.
class GhostStartRejectedAlert extends StatefulWidget {
  const GhostStartRejectedAlert({
    super.key,
    required this.message,
    required this.onConfirm,
    required this.child,
  });
  final String? message;
  final VoidCallback onConfirm;
  final Widget child;
  @override
  State<GhostStartRejectedAlert> createState() =>
      _GhostStartRejectedAlertState();
}

class _GhostStartRejectedAlertState extends State<GhostStartRejectedAlert> {
  DialogRoute<void>? route;
  @override
  void initState() {
    super.initState();
    sync();
  }

  @override
  void didUpdateWidget(GhostStartRejectedAlert oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  void sync() {
    if (widget.message != null && route == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else if (widget.message == null) {
      close();
    }
  }

  void close() {
    final previous = route;
    route = null;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous.isActive) previous.navigator?.removeRoute(previous);
      });
    }
  }

  Future<void> show() async {
    if (!mounted || widget.message == null || route != null) return;
    final next = route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: WdColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WdRadius.r20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WdSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('사용할 수 없는 고스트입니다.', style: WdText.ko20Bold),
              const SizedBox(height: WdSpace.s12),
              Text('다른 기록을 선택해 주세요.', style: WdText.ko13),
              const SizedBox(height: WdSpace.s24),
              WdButton('확인', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(next);
    if (!mounted || route != next) return;
    route = null;
    widget.onConfirm();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
