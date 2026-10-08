import 'package:flutter/material.dart';

import '../tokens.dart';

/// 카드·타일·버튼이 공유하는 바탕: 배경색 + 반경 + (선택) 테두리 + (선택) 탭.
///
/// 화면 전용 카드를 만들 때도 이걸 쓰면 토큰이 유지된다.
class WdSurface extends StatelessWidget {
  const WdSurface({
    super.key,
    this.color = WdColors.soft,
    this.radius = WdRadius.r16,
    this.padding = EdgeInsets.zero,
    this.border,
    this.width,
    this.height,
    this.onTap,
    required this.child,
  });

  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final BorderSide? border;
  final double? width, height;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) content = InkWell(onTap: onTap, child: content);
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: border ?? BorderSide.none,
        ),
        child: content,
      ),
    );
  }
}
