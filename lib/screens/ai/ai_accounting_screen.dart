import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/transaction.dart';
import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/animated_dialog.dart';
import 'ai_chat_panel.dart';
import 'ai_config_screen.dart';
import 'ai_error_dialog.dart';

/// AI 记账界面
///
/// 用户可输入文字、选择多张图片（账单/小票），由 AI 自动识别金额和分类。
/// 支持一次生成多条账单，并可在设置中开启"自动记入账单"。
/// 无可用配置时隐藏提交按钮并提示配置。
class AiAccountingScreen extends StatefulWidget {
  const AiAccountingScreen({super.key});

  @override
  State<AiAccountingScreen> createState() => _AiAccountingScreenState();
}

class _AiAccountingScreenState extends State<AiAccountingScreen> {
  final _textCtrl = TextEditingController();
  // 多张图片：原始文件 + base64 编码
  final List<File> _selectedImages = [];
  final List<String> _base64Images = [];
  bool _recognizing = false;
  bool _saving = false;
  // 多条识别结果
  List<AiRecognitionResult> _results = const [];
  // 是否为对话模式（与单次识别模式可互相切换）
  bool _isChatMode = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  /// 统一显示提示（floating 样式，避免黑色弹窗）
  void _showTip(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 选择多张图片
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    // 使用 pickMultiImage 支持多选
    final picked = await picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked.isEmpty) return;
    final newFiles = <File>[];
    final newBase64 = <String>[];
    for (final xFile in picked) {
      final file = File(xFile.path);
      final bytes = await file.readAsBytes();
      newFiles.add(file);
      newBase64.add(base64Encode(bytes));
    }
    setState(() {
      _selectedImages.addAll(newFiles);
      _base64Images.addAll(newBase64);
    });
  }

  /// 删除指定索引的图片
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _base64Images.removeAt(index);
    });
  }

  /// 调用 AI 识别
  ///
  /// 根据识别类型自动选择模型：
  /// - 有图片 → 多模态模型（recognizeFromImage），对每张图片分别识别
  /// - 无图片 → 自然语言模型（recognizeFromText）
  ///
  /// 多张图片会生成多条识别结果，可在设置中开启自动保存。
  Future<void> _recognize() async {
    final ai = context.read<AiProvider>();
    final settings = context.read<SettingsProvider>();

    final hasImage = _base64Images.isNotEmpty;
    final hasText = _textCtrl.text.trim().isNotEmpty;

    if (!hasImage && !hasText) {
      _showTip('请输入文字或选择图片');
      return;
    }

    // 有图片但配置不支持多模态
    if (hasImage && !ai.supportsMultimodal) {
      if (!hasText) {
        // 有图片但不支持多模态，且没有文字辅助，无法识别
        await showAiErrorDialog(
          context: context,
          title: '无法识别',
          error: '当前配置不支持图片识别，且未输入文字描述。\n\n'
              '解决方法：\n'
              '· 切换到支持多模态的配置（如 Kimi）\n'
              '· 或输入文字描述（例如"午饭 35 元"）',
        );
        return;
      }
      // 有文字辅助，降级为自然语言识别
      _showTip('当前配置不支持图片识别，将使用自然语言识别');
    }

    // 实际是否使用图片识别（有图且支持多模态）
    final useImage = hasImage && ai.supportsMultimodal;

    setState(() {
      _recognizing = true;
      _results = const [];
    });

    try {
      final expenseCats = settings.expenseCategories;
      final incomeCats = settings.incomeCategories;
      final textHint = hasText ? _textCtrl.text.trim() : null;

      final List<AiRecognitionResult> results = [];

      if (useImage) {
        // 图片识别：对每张图片分别调用，收集多个结果
        for (var i = 0; i < _base64Images.length; i++) {
          final result = await ai.recognizeFromImage(
            base64Image: _base64Images[i],
            textHint: textHint,
            expenseCategories: expenseCats,
            incomeCategories: incomeCats,
          );
          results.add(result);
        }
      } else {
        // 纯文字识别
        final result = await ai.recognizeFromText(
          text: _textCtrl.text.trim(),
          expenseCategories: expenseCats,
          incomeCategories: incomeCats,
        );
        results.add(result);
      }

      if (!mounted) return;
      setState(() => _results = results);

      // 自动保存：如果设置中开启，弹出确认对话框让用户确认后再保存
      if (settings.autoSaveAiBills && results.isNotEmpty) {
        await _showAutoSaveConfirmDialog();
      }
    } catch (e) {
      if (!mounted) return;
      // API 调用或识别错误统一弹窗显示
      await showAiErrorDialog(
        context: context,
        title: '识别失败',
        error: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  /// 自动保存确认对话框
  ///
  /// 自动记账模式下，识别完成后弹出此对话框展示识别结果，
  /// 并检测是否有重复账单，用户确认后才保存。
  Future<void> _showAutoSaveConfirmDialog() async {
    final duplicates = await _findDuplicates(_results);
    if (!mounted) return;

    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '确认保存',
      builder: (dialogContext) => _AutoSaveConfirmDialog(
        results: _results,
        duplicates: duplicates,
      ),
    );

    if (confirmed == true && mounted) {
      await _saveAllResults(autoMode: true);
    }
  }

  /// 检测识别结果中是否有与已有账单重复的
  ///
  /// 判断条件：同一用户、同一天、相同金额、相同类型、相同分类
  /// 返回每个识别结果对应的重复交易列表（索引与 _results 对应）。
  Future<List<List<Transaction>>> _findDuplicates(
      List<AiRecognitionResult> results) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return List.generate(results.length, (_) => []);

    final provider = context.read<TransactionProvider>();
    final now = DateTime.now();
    // 查询最近 7 天的交易用于比对
    final recent = await provider.queryByRange(
      userId: user.id,
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );

    // 为每个识别结果查找重复
    final duplicates = <List<Transaction>>[];
    for (final result in results) {
      final type = result.type == 'income'
          ? TransactionType.income
          : TransactionType.expense;
      // 重复判断：同一天、相同金额、相同类型、相同分类
      final matches = recent.where((tx) {
        return tx.amount == result.amount &&
            tx.type == type &&
            tx.category == result.category &&
            _isSameDay(tx.date, now);
      }).toList();
      duplicates.add(matches);
    }
    return duplicates;
  }

  /// 判断两个日期是否为同一天
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 手动保存时检测重复并提示
  ///
  /// 返回 true 表示用户确认保存（或无重复），false 表示取消。
  Future<bool> _checkDuplicatesBeforeManualSave() async {
    final duplicates = await _findDuplicates(_results);
    // 如果没有重复，直接返回 true
    final hasAnyDuplicate = duplicates.any((list) => list.isNotEmpty);
    if (!hasAnyDuplicate) return true;

    if (!mounted) return false;
    // 有重复，弹出确认对话框
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '重复账单确认',
      builder: (dialogContext) => _AutoSaveConfirmDialog(
        results: _results,
        duplicates: duplicates,
        isManualSave: true,
      ),
    );
    return confirmed == true;
  }

  /// 保存所有识别结果到数据库
  ///
  /// [autoMode] 为 true 时表示由"自动保存"触发，不弹错误对话框；
  /// 为 false 时表示用户手动点击"确认保存"。
  Future<void> _saveAllResults({bool autoMode = false}) async {
    final results = _results;
    if (results.isEmpty) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _saving = true);
    final provider = context.read<TransactionProvider>();
    final now = DateTime.now();

    int successCount = 0;
    String? lastError;
    for (final result in results) {
      final ok = await provider.add(Transaction(
        userId: user.id,
        amount: result.amount,
        type: result.type == 'income'
            ? TransactionType.income
            : TransactionType.expense,
        category: result.category,
        date: now,
        note: result.note,
      ));
      if (ok) {
        successCount++;
      } else {
        lastError = provider.error;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (successCount == results.length) {
      // 全部保存成功
      _textCtrl.clear();
      setState(() {
        _selectedImages.clear();
        _base64Images.clear();
        _results = const [];
      });
      _showTip(autoMode
          ? '已自动保存 $successCount 条账单'
          : '已保存 $successCount 条账单');
    } else if (successCount > 0) {
      // 部分成功
      _showTip('已保存 $successCount/${results.length} 条，部分失败');
      if (!autoMode && lastError != null) {
        await showAiErrorDialog(
          context: context,
          title: '部分保存失败',
          error: lastError,
        );
      }
      setState(() {
        _results = const [];
        _selectedImages.clear();
        _base64Images.clear();
      });
    } else {
      // 全部失败
      if (!autoMode) {
        await showAiErrorDialog(
          context: context,
          title: '保存失败',
          error: lastError ?? '保存失败，请重试',
        );
      } else {
        _showTip('自动保存失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();
    final settings = context.watch<SettingsProvider>();
    final hasProfile = ai.hasAvailableProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
        actions: [
          // 自动保存状态标识（仅单次识别模式显示）
          if (!_isChatMode && settings.autoSaveAiBills)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 4),
                      Text(
                        '自动记账',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 对话模式下可清空当前对话
          if (_isChatMode && ai.chatHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () {
                ai.clearChatHistory();
                _showTip('已清空对话');
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'AI 配置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiConfigScreen()),
            ),
          ),
        ],
      ),
      body: !hasProfile
          ? _buildNoProfileHint(context, ai)
          : Column(
              children: [
                // 模式切换：单次识别 / 对话模式
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('单次识别'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('对话模式'),
                      ),
                    ],
                    selected: {_isChatMode},
                    onSelectionChanged: (value) {
                      setState(() => _isChatMode = value.first);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // 根据模式显示不同面板
                Expanded(
                  child: _isChatMode
                      ? const AiChatPanel()
                      : _buildContent(context, ai),
                ),
              ],
            ),
    );
  }

  /// 无可用配置时的提示
  Widget _buildNoProfileHint(BuildContext context, AiProvider ai) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              ai.profiles.isEmpty ? '尚未创建 AI 配置' : '当前配置未完成',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              ai.profiles.isEmpty
                  ? '请先创建 AI 配置（厂商、API Key、模型），才能使用 AI 记账功能。'
                  : '请选择一个已配置文本模型的配置，或编辑当前配置补充模型。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiConfigScreen()),
              ),
              icon: const Icon(Icons.settings),
              label: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AiProvider ai) {
    final showImagePicker = ai.supportsMultimodal;
    // 在 build 方法中用 watch 建立依赖，确保设置变化时 UI 更新
    final autoSave = context.watch<SettingsProvider>().autoSaveAiBills;
    return SingleChildScrollView(
      // 底部留出足够空间，确保识别结果和保存按钮能滚动到导航栏上方
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 文本输入
          TextField(
            controller: _textCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '自然语言描述',
              hintText: '例如：今天午饭花了 35 元',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图片选择（仅多模态配置显示）
          if (showImagePicker) ...[
            if (_selectedImages.isNotEmpty)
              // 多张图片网格展示
              _buildImageGrid(context)
            else
              OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.image_outlined),
                label: const Text('选择图片（账单/小票，可多选）'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 已选图片时，提供继续添加按钮
            if (_selectedImages.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                  label: const Text('继续添加'),
                ),
              ),
            const SizedBox(height: 12),
          ],
          // 识别按钮
          FilledButton.icon(
            onPressed: _recognizing ? null : _recognize,
            icon: _recognizing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_recognizing
                ? '识别中... (${_base64Images.isNotEmpty ? "处理 ${_base64Images.length} 张图片" : "处理中"})'
                : 'AI 识别'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 识别结果（多条）
          if (_results.isNotEmpty) ...[
            Text(
              '识别结果（${_results.length} 条）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // 多条结果列表
            for (var i = 0; i < _results.length; i++)
              _buildResultCard(context, _results[i], i),
            // 统一保存按钮（关闭自动保存时显示）
            if (!autoSave)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    // 手动保存前先检测重复，有重复时弹出确认对话框
                    onPressed: _saving
                        ? null
                        : () async {
                            final confirmed =
                                await _checkDuplicatesBeforeManualSave();
                            if (confirmed && mounted) {
                              await _saveAllResults(autoMode: false);
                            }
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_saving
                        ? '保存中...'
                        : '全部保存（${_results.length} 条）'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 多张图片网格展示
  Widget _buildImageGrid(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _selectedImages[index],
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _removeImage(index),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 序号标签
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 识别结果卡片
  ///
  /// [index] 用于在多条结果中显示序号
  Widget _buildResultCard(BuildContext context, AiRecognitionResult result, int index) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text('识别结果 #${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(height: 20),
            _resultRow('金额', '¥${result.amount.toStringAsFixed(2)}'),
            _resultRow('类型', result.type == 'income' ? '收入' : '支出'),
            _resultRow('分类', result.category),
            if (result.note != null && result.note!.isNotEmpty)
              _resultRow('备注', result.note!),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 自动保存确认对话框
///
/// 展示 AI 识别结果，并提示是否有重复账单。
/// 用户确认后才执行保存操作。
class _AutoSaveConfirmDialog extends StatelessWidget {
  const _AutoSaveConfirmDialog({
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
