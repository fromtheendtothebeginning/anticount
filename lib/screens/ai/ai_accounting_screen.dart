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
import 'ai_config_screen.dart';
import 'ai_error_dialog.dart';

/// AI 记账界面
///
/// 用户可输入文字、选择图片，由 AI 自动识别金额和分类，
/// 确认后保存到数据库。无可用配置时隐藏提交按钮并提示配置。
class AiAccountingScreen extends StatefulWidget {
  const AiAccountingScreen({super.key});

  @override
  State<AiAccountingScreen> createState() => _AiAccountingScreenState();
}

class _AiAccountingScreenState extends State<AiAccountingScreen> {
  final _textCtrl = TextEditingController();
  File? _selectedImage;
  String? _base64Image;
  bool _recognizing = false;
  bool _saving = false;
  AiRecognitionResult? _result;

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

  /// 选择图片
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;
    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    setState(() {
      _selectedImage = file;
      _base64Image = base64Encode(bytes);
    });
  }

  /// 调用 AI 识别
  ///
  /// 根据识别类型自动选择模型：
  /// - 有图片 → 多模态模型（recognizeFromImage，用 multimodalModelId）
  /// - 无图片 → 自然语言模型（recognizeFromText，用 textModelId）
  ///
  /// 如果用户想在文字识别时使用多模态模型，可在配置界面将"自然语言模型"
  /// 选为多模态模型（自然语言模型可选所有模型）。
  Future<void> _recognize() async {
    final ai = context.read<AiProvider>();
    final settings = context.read<SettingsProvider>();

    final hasImage = _base64Image != null;
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
      _result = null;
    });

    try {
      final expenseCats = settings.expenseCategories;
      final incomeCats = settings.incomeCategories;

      final result = useImage
          ? await ai.recognizeFromImage(
              base64Image: _base64Image!,
              textHint: hasText ? _textCtrl.text.trim() : null,
              expenseCategories: expenseCats,
              incomeCategories: incomeCats,
            )
          : await ai.recognizeFromText(
              text: _textCtrl.text.trim(),
              expenseCategories: expenseCats,
              incomeCategories: incomeCats,
            );

      if (!mounted) return;
      setState(() => _result = result);
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

  /// 确认保存
  Future<void> _confirmSave() async {
    final result = _result;
    if (result == null) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _saving = true);
    final provider = context.read<TransactionProvider>();
    final ok = await provider.add(Transaction(
      userId: user.id,
      amount: result.amount,
      type: result.type == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      category: result.category,
      date: DateTime.now(),
      note: result.note,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _textCtrl.clear();
      setState(() {
        _selectedImage = null;
        _base64Image = null;
        _result = null;
      });
      _showTip('已保存');
    } else {
      // 保存失败用错误对话框显示
      await showAiErrorDialog(
        context: context,
        title: '保存失败',
        error: provider.error ?? '保存失败，请重试',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();
    final hasProfile = ai.hasAvailableProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
        actions: [
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
          : _buildContent(context, ai),
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
    final activeProfile = ai.activeProfile;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 当前配置信息 + 识别模型
          if (activeProfile != null)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activeProfile.name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AiConfigScreen()),
                          ),
                          child: const Text('切换'),
                        ),
                      ],
                    ),
                    const Divider(height: 8),
                    // 显示当前识别类型对应的模型
                    Row(
                      children: [
                        Icon(
                          _selectedImage != null
                              ? Icons.image_outlined
                              : Icons.text_snippet_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedImage != null
                              ? '图片识别 → ${activeProfile.multimodalConfig?.modelId ?? "未配置多模态"}'
                              : '文字识别 → ${activeProfile.textConfig?.modelId ?? "未配置文本"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
            if (_selectedImage != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _selectedImage = null;
                        _base64Image = null;
                      }),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('选择图片（账单/小票）'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            const SizedBox(height: 20),
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
            label: Text(_recognizing ? '识别中...' : 'AI 识别'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 识别结果
          if (_result != null) _buildResultCard(context, _result!),
        ],
      ),
    );
  }

  /// 识别结果卡片
  Widget _buildResultCard(BuildContext context, AiRecognitionResult result) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text('识别结果',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(height: 20),
            _resultRow('金额', '¥${result.amount.toStringAsFixed(2)}'),
            _resultRow('类型', result.type == 'income' ? '收入' : '支出'),
            _resultRow('分类', result.category),
            if (result.note != null && result.note!.isNotEmpty)
              _resultRow('备注', result.note!),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _confirmSave,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_saving ? '保存中...' : '确认保存'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
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
