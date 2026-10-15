import 'package:flutter/widgets.dart';

/// 홈 탭에서 다른 하단 탭으로 떠난 횟수를 홈에 알린다. 하단 탭 틀이 탭 화면들을 감싼다.
/// 홈은 떠날 때마다 탐색 상태를 처음으로 되돌려 두어, 돌아오면 앱을 처음 켰을 때처럼 보인다(FIL-08).
class HomeTabExits extends StatefulWidget {
  const HomeTabExits({super.key, required this.atHome, required this.child});

  /// 지금 홈 탭에 있다.
  final bool atHome;

  final Widget child;

  /// 떠난 횟수. 감싸는 [HomeTabExits]가 없으면 0이다.
  static int of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ExitCount>()?.count ?? 0;

  @override
  State<HomeTabExits> createState() => _HomeTabExitsState();
}

class _HomeTabExitsState extends State<HomeTabExits> {
  var _count = 0;

  @override
  void didUpdateWidget(HomeTabExits oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.atHome && !widget.atHome) _count++;
  }

  @override
  Widget build(BuildContext context) => _ExitCount(count: _count, child: widget.child);
}

class _ExitCount extends InheritedWidget {
  const _ExitCount({required this.count, required super.child});

  final int count;

  @override
  bool updateShouldNotify(_ExitCount oldWidget) => count != oldWidget.count;
}
