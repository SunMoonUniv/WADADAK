import 'package:flutter/widgets.dart';

/// 홈 탭에서 다른 하단 탭으로 떠난 횟수와 다시 돌아온 횟수를 홈에 알린다. 하단 탭 틀이 탭 화면들을 감싼다.
/// 홈은 떠날 때마다 탐색 상태를 처음으로 되돌려 두고, 돌아오면 지도를 지금 위치로 다시 맞춰(그 사이 달렸을 수 있다)
/// 앱을 처음 켰을 때처럼 보인다(FIL-08).
class HomeTabExits extends StatefulWidget {
  const HomeTabExits({super.key, required this.atHome, required this.child});

  /// 지금 홈 탭에 있다.
  final bool atHome;

  final Widget child;

  /// 떠난 횟수 · 돌아온 횟수. 감싸는 [HomeTabExits]가 없으면 둘 다 0이다.
  static ({int exits, int returns}) of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ExitCount>()?.counts ?? (exits: 0, returns: 0);

  @override
  State<HomeTabExits> createState() => _HomeTabExitsState();
}

class _HomeTabExitsState extends State<HomeTabExits> {
  var _exits = 0;
  var _returns = 0;

  @override
  void didUpdateWidget(HomeTabExits oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.atHome && !widget.atHome) _exits++;
    if (!oldWidget.atHome && widget.atHome) _returns++;
  }

  @override
  Widget build(BuildContext context) => _ExitCount(counts: (exits: _exits, returns: _returns), child: widget.child);
}

class _ExitCount extends InheritedWidget {
  const _ExitCount({required this.counts, required super.child});

  final ({int exits, int returns}) counts;

  @override
  bool updateShouldNotify(_ExitCount oldWidget) => counts != oldWidget.counts;
}
