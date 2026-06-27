import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/animated_dialog.dart';

/// AI 错误对话框
///
/// 用于显示 API 调用或识别过程中发生的错误。
/// - 显示简短错误信息（截断过长内容）
/// - 提供"确认"按钮关闭对话框
/// - 提供"复制完整错误"按钮，将完整错误写入剪贴板（不在屏幕上显示完整内容）
/// - 带从下方向上滑入的动画效果
///
/// 调用方式：
/// ```dart
/// await showAiErrorDialog(
///   context: context,
///   title: '识别失败',
///   error: e.toString(),
/// );
/// ```
Future<void> showAiErrorDialog({
  required BuildContext context,
  required String title,
  required String error,
  String? confirmText,
}) async {
  await showAnimatedDialog<void>(
    context: context,
    barrierLabel: '错误提示',
    builder: (dialogContext) => _AiErrorDialog(
      title: title,
      error: error,
      confirmText: confirmText ?? '确认',
    ),
  );
}

class _AiErrorDialog extends StatelessWidget {
  const _AiErrorDialog({
    required this.title,
    required this.error,
    required this.confirmText,
  });

  final String title;
  final String error;
  final String confirmText;

  /// 错误信息在屏幕上显示的最大长度，超出部分用省略号
  static const _maxDisplayLength = 120;

  /// 获取屏幕上显示的简短错误信息
  String get _displayError {
    if (error.length <= _maxDisplayLength) return error;
    return '${error.substring(0, _maxDisplayLength)}…';
  }

  Future<void> _copyError(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: error));
    if (!context.mounted) return;
    // 用 ScaffoldMessenger 显示提示，不显示完整错误
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('完整错误已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              _displayError,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copyError(context),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('复制完整错误'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(confirmText),
        ),
      ],
    );
  }
}
