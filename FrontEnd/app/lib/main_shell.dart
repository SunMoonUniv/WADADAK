import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'core/map/map_view.dart';
import 'features/home/home_tab_exits.dart';
import 'features/run/application/free_run_controller.dart';
import 'features/run/domain/run_models.dart';

/// 하단 탭 4개(홈 · 달리기 · 랭킹 · MY). 탭마다 자기 화면 기록을 유지한다.
/// 홈은 다른 탭에 갔다 오면 탐색 상태를 처음으로 되돌린다(FIL-08, [HomeTabExits]).
///
/// 탭 첫 화면의 뒤로가기(탭 안에 연 화면은 그 탭이 먼저 닫는다):
/// - 홈이 아닌 탭: 홈 탭으로 간다. 러닝 측정은 화면 밖에서 계속된다
/// - 홈 탭: [exitWindow] 안에 두 번 눌러야 앱을 닫는다. 측정 중이면 닫지 않고 기기 홈 화면으로만 보낸다(측정은 계속)
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// 홈에서 두 번째 뒤로가기를 기다리는 시간. 안내 스낵바도 이만큼 보인다.
  static const exitWindow = Duration(seconds: 2);

  /// Android MainActivity의 RunScreenAwake 채널(moveToBack).
  static const _runScreen = MethodChannel('com.wadadak.app/run_screen');

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  // 홈에서 처음 뒤로가기를 누른 뒤 [MainShell.exitWindow] 동안 켜져 있다.
  Timer? _exitArmed;

  @override
  void dispose() {
    _exitArmed?.cancel();
    super.dispose();
  }

  void _back(FreeRunController run) {
    final shell = widget.shell;
    if (shell.currentIndex != 0) {
      _exitArmed?.cancel();
      _exitArmed = null;
      shell.goBranch(0, initialLocation: true);
      return;
    }
    if (_exitArmed?.isActive != true) {
      _exitArmed = Timer(MainShell.exitWindow, () {});
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('한 번 더 누르면 종료돼요'),
            duration: MainShell.exitWindow,
          ),
        );
      return;
    }
    _exitArmed?.cancel();
    _exitArmed = null;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final state = run.snapshot.state;
    final measuring =
        run.preparing || state == RunState.running || state == RunState.paused;
    if (defaultTargetPlatform != TargetPlatform.android) {
      SystemNavigator.pop();
    } else {
      // 측정 중이면 닫지 않고 기기 홈 화면으로만 보낸다. 닫기는 Android가 직접 한다(SystemNavigator.pop은
      // 뒤로가기를 가로채는 동안 다시 이 처리로 돌아와 앱이 닫히지 않는다)
      MainShell._runScreen.invokeMethod<void>(
        measuring ? 'moveToBack' : 'finish',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final run = ref.watch(freeRunControllerProvider);
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        // C5만 탭을 표시하고 H4/C4/D1-2는 피그마의 전체 화면을 쓴다.
        final fullScreen = runFullScreen(shell.currentIndex, run);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back(run);
          },
          child: Scaffold(
            body: HomeTabExits(atHome: shell.currentIndex == 0, child: shell),
            bottomNavigationBar: fullScreen
                ? null
                : WdBottomNav(
                    currentIndex: shell.currentIndex,
                    // 홈은 다른 탭에서 돌아와도 처음 자리(A2)다. 홈 탭 안에 연 검색(G1)은 닫힌다(FIL-08).
                    onTap: (index) => shell.goBranch(
                      index,
                      initialLocation:
                          index == shell.currentIndex || index == 0,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// 달리기 탭이 전체 화면(H4/C4/D1-2)인지. 이때는 하단 탭을 숨기고 밀어서 탭 넘기기도 끈다.
bool runFullScreen(int tab, FreeRunController run) =>
    tab == 1 &&
    (run.preparing ||
        run.courseStart != null ||
        run.snapshot.state != RunState.ready);

/// 하단 탭 전환을 옆으로 미끄러지게 보이고, 좌우로 밀어서도 옆 탭으로 넘긴다. 탭 화면은 계속 살아 있고
/// 안 보이는 탭은 멈춘다(go_router 기본 indexedStack과 같다).
///
/// 안쪽에서 먼저 가로 끌기를 받는 곳(러닝 지도 · 홈 지도 · 러닝 화면 좌우 페이지 · 가로 목록)은 그대로 그쪽이 받는다.
class SlidingBranchContainer extends StatefulWidget {
  const SlidingBranchContainer({
    super.key,
    required this.index,
    required this.children,
    required this.onSwipe,
    this.canSwipe = _always,
  });

  final int index;
  final List<Widget> children;

  /// 밀어서 [index] 옆 탭으로 넘기기로 했다.
  final ValueChanged<int> onSwipe;

  /// 밀기를 시작할 때 묻는다(러닝 측정 중 전체 화면이면 false).
  final bool Function() canSwipe;

  static bool _always() => true;

  static const duration = Duration(milliseconds: 250);

  /// 이만큼(화면 너비 비율) 넘게 밀거나 [_flingSpeed]보다 빠르게 밀면 넘긴다.
  static const _commitFraction = 0.3;
  static const _flingSpeed = 600.0;

  @override
  State<SlidingBranchContainer> createState() => _SlidingBranchContainerState();
}

class _SlidingBranchContainerState extends State<SlidingBranchContainer>
    with TickerProviderStateMixin {
  // 탭이 바뀔 때 0(이전 탭) → 1(새 탭). 밀어서 넘기면 민 만큼에서 시작한다.
  late final _slide = AnimationController(
    vsync: this,
    duration: SlidingBranchContainer.duration,
    value: 1,
  );
  // 밀다 만 것을 제자리로 돌린다.
  late final _back = AnimationController(
    vsync: this,
    duration: SlidingBranchContainer.duration,
  );
  late int _from = widget.index;

  // 미는 중 현재 탭이 움직인 비율(왼쪽 −, 오른쪽 +). 밀고 있지 않으면 null.
  double? _drag;
  double _backFrom = 0;
  // 밀어서 넘긴 경우 새 탭 애니메이션을 시작할 자리.
  double? _swipedFrom;

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
      if (_back.isAnimating) {
        setState(
          () => _drag =
              _backFrom * (1 - Curves.easeOutCubic.transform(_back.value)),
        );
      } else if (_back.isCompleted) {
        setState(() => _drag = null);
      }
    });
  }

  @override
  void didUpdateWidget(SlidingBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _from = oldWidget.index;
      _drag = null;
      _back.stop();
      _slide
        ..value = _swipedFrom ?? 0
        ..animateTo(1, curve: Curves.easeOutCubic);
      _swipedFrom = null;
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _back.dispose();
    super.dispose();
  }

  /// [drag] 쪽 옆 탭. 끝이면 null.
  int? _neighbor(double drag) {
    final next = widget.index + (drag < 0 ? 1 : -1);
    return drag == 0 || next < 0 || next >= widget.children.length
        ? null
        : next;
  }

  void _dragStart(DragStartDetails _) {
    if (_slide.isAnimating || !widget.canSwipe()) return;
    _back.stop();
    setState(() => _drag = _drag ?? 0);
  }

  void _dragUpdate(DragUpdateDetails details, double width) {
    final drag = _drag;
    if (drag == null || width <= 0) return;
    final next = (drag + details.delta.dx / width).clamp(-1.0, 1.0);
    // 끝 탭에서 바깥으로는 밀리지 않는다
    setState(() => _drag = _neighbor(next) == null ? 0 : next);
  }

  void _dragEnd(DragEndDetails details) {
    final drag = _drag;
    if (drag == null) return;
    final speed = details.primaryVelocity ?? 0;
    final neighbor = _neighbor(drag);
    final commit =
        neighbor != null &&
        (drag.abs() > SlidingBranchContainer._commitFraction ||
            (speed.abs() > SlidingBranchContainer._flingSpeed &&
                speed.sign == drag.sign));
    if (commit) {
      _swipedFrom = drag.abs();
      widget.onSwipe(neighbor);
    } else {
      _backFrom = drag;
      _back.forward(from: 0);
    }
  }

  // 안쪽 가로 스크롤(랭킹 거리·지역 탭, 가로 목록)이 끝에 닿아 더 밀리는 것을 이어받는 중인지.
  var _fromInner = false;

  /// 안쪽 가로 스크롤이 끝에서 더 밀리면(넘길 것이 없으면) 그만큼 옆 탭으로 민다. 다시 안쪽으로 되돌리면 따라 돌아온다.
  bool _innerScroll(ScrollNotification n, double width) {
    if (n.metrics.axis != Axis.horizontal) return false;
    switch (n) {
      case OverscrollNotification(:final overscroll, dragDetails: _?):
        if (!_fromInner) {
          if (_drag != null) return false; // 바깥에서 이미 미는 중
          _dragStart(DragStartDetails());
          if (_drag == null) return false;
          _fromInner = true;
        }
        _dragUpdate(
          DragUpdateDetails(
            globalPosition: Offset.zero,
            delta: Offset(-overscroll, 0),
          ),
          width,
        );
      case ScrollUpdateNotification(:final scrollDelta?, dragDetails: _?)
          when _fromInner:
        final drag = _drag ?? 0;
        // 반대로 되돌리는 만큼만 탭 밀기를 줄인다(0을 넘어가면 안쪽 스크롤 몫)
        final back = -scrollDelta / width;
        if (drag != 0 && back.sign != drag.sign) {
          final next =
              (drag + back).abs() < drag.abs() &&
                  (drag + back).sign == drag.sign
              ? drag + back
              : 0.0;
          setState(() => _drag = next);
        }
      case ScrollEndNotification(:final dragDetails) when _fromInner:
        _fromInner = false;
        _dragEnd(dragDetails ?? DragEndDetails());
      default:
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => NotificationListener<ScrollNotification>(
      onNotification: (n) => _innerScroll(n, constraints.maxWidth),
      child: RawGestureDetector(
        gestures: {
          _TabSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<_TabSwipeRecognizer>(
                _TabSwipeRecognizer.new,
                (drag) {
                  drag
                    // 기본(18)보다 길게 밀어야 시작한다. 안쪽 지도(확대·이동은 36)와 가로 목록이 먼저 잡고,
                    // 세로 스크롤 중 살짝 옆으로 밀려도 탭이 넘어가지 않는다
                    ..gestureSettings = const DeviceGestureSettings(
                      touchSlop: 48,
                    )
                    // 손가락이 닿은 곳부터 따라온다(넘기기 시작 전 민 만큼도 화면이 따라 움직인다)
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = _dragStart
                    ..onUpdate = ((details) =>
                        _dragUpdate(details, constraints.maxWidth))
                    ..onEnd = _dragEnd
                    ..onCancel = (() => _dragEnd(DragEndDetails()));
                },
              ),
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, _) {
              // 탭마다 가로 위치(화면 너비 비율). 없으면 화면 밖이라 그리지 않는다
              final offsets = <int, double>{};
              final drag = _drag;
              if (drag != null) {
                offsets[widget.index] = drag;
                final neighbor = _neighbor(drag);
                if (neighbor != null) {
                  offsets[neighbor] = drag + (drag < 0 ? 1 : -1);
                }
              } else if (_slide.isAnimating) {
                // 오른쪽 탭으로 가면 새 화면이 오른쪽에서 들어오고 이전 화면은 왼쪽으로 나간다
                final t = _slide.value;
                final direction = widget.index > _from ? 1.0 : -1.0;
                offsets[widget.index] = direction * (1 - t);
                offsets[_from] = -direction * t;
              } else {
                offsets[widget.index] = 0;
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 탭 순서·위젯 종류를 늘 같게 두어 탭 화면 상태가 유지된다
                  for (final (i, child) in widget.children.indexed)
                    Offstage(
                      offstage: !offsets.containsKey(i),
                      child: TickerMode(
                        enabled: i == widget.index,
                        child: FractionalTranslation(
                          translation: Offset(offsets[i] ?? 0, 0),
                          child: child,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// 하단 탭 밀어 넘기기. 끌기를 먼저 가져가는 지도([MapView.grabGestures])에서 시작한 터치는 받지 않아,
/// 지도가 경쟁 없이 처음부터 끌기를 받는다.
class _TabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  @override
  bool isPointerAllowed(PointerEvent event) {
    if (!super.isPointerAllowed(event)) return false;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    return !hit.path.any(
      (entry) =>
          entry.target is RenderMetaData &&
          (entry.target as RenderMetaData).metaData == MapView.gestureGrab,
    );
  }
}
