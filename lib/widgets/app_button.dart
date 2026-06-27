import 'package:flutter/material.dart';

/// 应用主按钮
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: danger ? colorScheme.error : null,
        foregroundColor: danger ? colorScheme.onError : null,
        minimumSize: const Size.fromHeight(48),
      ),
      icon: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: danger ? colorScheme.onError : colorScheme.onPrimary,
              ),
            )
          : (icon ?? const SizedBox.shrink()),
      label: Text(label),
    );
  }
}
