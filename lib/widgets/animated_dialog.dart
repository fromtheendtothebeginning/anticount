import 'package:flutter/material.dart';

/// 带动画效果的通用对话框
///
/// 所有弹窗统一使用此函数，呈现从下方向上滑入 + 淡入的动画效果。
/// 替代 showDialog，让对话框风格一致。
///
/// 用法（与 showDialog 一致）：
/// ```dart
/// final ok = await showAnimatedDialog<bool>(
///   context: context,
///   builder: (ctx) => AlertDialog(...),
/// );
/// ```
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color barrierColor = Colors.black54,
  Duration transitionDuration = const Duration(milliseconds: 250),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ?? 'Dialog',
    barrierColor: barrierColor,
    transitionDuration: transitionDuration,
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      // 从下方向上滑入（偏移 20% 高度）+ 淡入
      final tween = Tween<Offset>(
        begin: const Offset(0, 0.2),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(
        position: animation.drive(tween),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
  );
}

/// 信息提示弹窗（带"确认"按钮）
///
/// 用于替换重要信息/错误提示的 SnackBar，确保用户看到并确认。
/// 统一使用动画效果，与其它弹窗风格一致。
///
/// [title] 标题，[content] 内容，[confirmText] 确认按钮文案（默认"确认"）。
Future<void> showInfoDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = '确认',
}) {
  return showAnimatedDialog<void>(
    context: context,
    barrierLabel: title,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(confirmText),
        ),
      ],
    ),
  );
}
