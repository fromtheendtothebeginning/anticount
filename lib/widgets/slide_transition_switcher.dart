import 'package:flutter/material.dart';

/// 可复用的左右滑动切换动画组件
///
/// 当 [child] 的 key 发生变化时，会以水平滑动 + 淡入淡出的方式切换内容。
/// [slideRight] 控制视觉滑动方向：
/// - `true`：内容整体向右移动，旧内容从右侧退出，新内容从左侧进入
/// - `false`：内容整体向左移动，旧内容从左侧退出，新内容从右侧进入
class SlideTransitionSwitcher extends StatelessWidget {
  const SlideTransitionSwitcher({
    super.key,
    required this.child,
    required this.slideRight,
    this.duration = const Duration(milliseconds: 250),
  });

  /// 当前需要显示的子组件，必须带有 key 才能触发动画
  final Widget child;

  /// 视觉滑动方向：true=向右滑动，false=向左滑动
  final bool slideRight;

  /// 动画时长
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (animatedChild, animation) {
        final isEntering = animatedChild.key == child.key;
        // slideRight=true：新内容从左侧进入，旧内容向右侧退出
        // slideRight=false：新内容从右侧进入，旧内容向左侧退出
        final begin = isEntering
            ? (slideRight ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0))
            : (slideRight ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0));
        final end = isEntering
            ? Offset.zero
            : (slideRight ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0));
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: begin, end: end).animate(animation),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}
