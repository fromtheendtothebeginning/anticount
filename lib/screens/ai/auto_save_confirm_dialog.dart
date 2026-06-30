import 'package:flutter/material.dart';

import '../../models/transaction.dart';
import '../../services/ai_service.dart';

/// 自动保存确认对话框
///
/// 展示 AI 识别结果，并提示是否有重复账单。
/// 用户确认后才执行保存操作。
class AutoSaveConfirmDialog extends StatelessWidget {
  const AutoSaveConfirmDialog({
    super.key,
    required this.results,
    required this.duplicates,
    this.isManualSave = false,
  });

  /// AI 识别结果列表
  final List<AiRecognitionResult> results;

  /// 每个识别结果对应的重复交易列表（索引与 results 对应）
  final List<List<Transaction>> duplicates;

  /// 是否为手动保存触发的重复确认
  final bool isManualSave;

  @override
  Widget build(BuildContext context) {
    // 统计重复数量
    final hasDuplicates = duplicates.any((list) => list.isNotEmpty);
    final dupCount =
        duplicates.where((list) => list.isNotEmpty).length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasDuplicates ? Icons.warning_amber_rounded : Icons.check_circle,
            color: hasDuplicates ? Colors.orange : Colors.green,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(isManualSave
              ? (hasDuplicates ? '发现重复账单' : '确认保存')
              : '确认保存账单'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 重复警告
            if (hasDuplicates) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '检测到 $dupCount 条识别结果与已有账单重复（同一天、相同金额、分类），确认是否继续保存？',
                        style: const TextStyle(fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 识别结果列表
            Text(
              '识别结果（${results.length} 条）',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < results.length; i++) ...[
              _buildResultSummary(context, results[i], i),
              if (i < results.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认保存'),
        ),
      ],
    );
  }

  /// 单条识别结果摘要
  Widget _buildResultSummary(
      BuildContext context, AiRecognitionResult result, int index) {
    final isDuplicate = index < duplicates.length && duplicates[index].isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: isDuplicate
            ? Border.all(color: Colors.orange.withAlpha(120))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${index + 1}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (isDuplicate) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '重复',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '¥${result.amount.toStringAsFixed(2)} · '
            '${result.type == 'income' ? '收入' : '支出'} · '
            '${result.category}',
            style: const TextStyle(fontSize: 13),
          ),
          if (result.note != null && result.note!.isNotEmpty)
            Text(
              '备注：${result.note}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }
}
