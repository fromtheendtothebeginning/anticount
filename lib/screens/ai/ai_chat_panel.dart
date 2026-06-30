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
import 'ai_error_dialog.dart';
import 'auto_save_confirm_dialog.dart';

/// AI 记账对话模式面板
///
/// 支持文字 + 图片的多轮对话，AI 可在信息足够时返回可保存的账单结果。
class AiChatPanel extends StatefulWidget {
  const AiChatPanel({super.key});

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<File> _pendingImages = [];
  final List<String> _pendingBase64 = [];
  bool _sending = false;
  bool _saving = false;

  /// 缓存每条 AI 消息识别结果的重复检测 Future（key=消息索引）
  final Map<int, Future<List<List<Transaction>>>> _duplicatesCache = {};

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 滚动到消息列表底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 选择图片
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked.isEmpty) return;
    for (final xFile in picked) {
      final file = File(xFile.path);
      final bytes = await file.readAsBytes();
      setState(() {
        _pendingImages.add(file);
        _pendingBase64.add(base64Encode(bytes));
      });
    }
  }

  /// 移除待发送图片
  void _removePendingImage(int index) {
    setState(() {
      _pendingImages.removeAt(index);
      _pendingBase64.removeAt(index);
    });
  }

  /// 发送消息
  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _pendingBase64.isEmpty) return;

    final ai = context.read<AiProvider>();
    final settings = context.read<SettingsProvider>();

    final pendingImages = List<String>.from(_pendingBase64);
    _textCtrl.clear();
    setState(() {
      _pendingImages.clear();
      _pendingBase64.clear();
      _sending = true;
    });

    try {
      final response = await ai.sendChatMessage(
        text: text,
        base64Images: pendingImages,
        expenseCategories: settings.expenseCategories,
        incomeCategories: settings.incomeCategories,
      );
      _scrollToBottom();

      // 自动保存：设置开启且 AI 返回识别结果时触发
      // 助手消息已追加到历史末尾，索引为 history.length - 1
      if (settings.autoSaveAiBills && response.results.isNotEmpty && mounted) {
        final messageIndex = ai.chatHistory.length - 1;
        await _autoSaveResults(messageIndex, response.results);
      }
    } catch (e) {
      if (!mounted) return;
      await showAiErrorDialog(
        context: context,
        title: '发送失败',
        error: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 保存某条 AI 消息中的识别结果
  ///
  /// [messageIndex] 用于保存成功后标记该消息为已保存状态。
  Future<void> _saveResults(
      int messageIndex, List<AiRecognitionResult> results) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    if (results.isEmpty) return;

    setState(() => _saving = true);
    final provider = context.read<TransactionProvider>();
    final now = DateTime.now();
    int success = 0;
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
        success++;
      } else {
        lastError = provider.error;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (success == results.length) {
      // 保存成功后不再弹出 SnackBar，按钮会变为「已加入账单」作为反馈
      context.read<AiProvider>().markChatMessageSaved(messageIndex);
    } else if (success > 0) {
      // 部分保存也标记为已保存，避免重复保存
      context.read<AiProvider>().markChatMessageSaved(messageIndex);
    } else {
      await showAiErrorDialog(
        context: context,
        title: '保存失败',
        error: lastError ?? '保存失败',
      );
    }
  }

  /// 自动保存识别结果
  ///
  /// [messageIndex] 用于标记该消息为已保存状态。
  /// 先检测是否有重复账单，有重复时弹出确认对话框；
  /// 用户确认（或无重复）后调用 [_saveResults] 保存。
  Future<void> _autoSaveResults(
      int messageIndex, List<AiRecognitionResult> results) async {
    final duplicates = await _findDuplicates(results);
    if (!mounted) return;

    final hasDuplicates = duplicates.any((list) => list.isNotEmpty);
    bool? confirmed = true;
    if (hasDuplicates) {
      confirmed = await showAnimatedDialog<bool>(
        context: context,
        barrierLabel: '确认保存',
        builder: (dialogContext) => AutoSaveConfirmDialog(
          results: results,
          duplicates: duplicates,
        ),
      );
    }

    if (confirmed == true && mounted) {
      await _saveResults(messageIndex, results);
    }
  }

  /// 检测识别结果中是否有与已有账单重复的
  ///
  /// 判断条件：同一用户、同一天、相同金额、相同类型、相同分类
  /// 返回每个识别结果对应的重复交易列表（索引与 results 对应）。
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

  /// 获取某条 AI 消息识别结果的重复检测信息（带缓存）
  Future<List<List<Transaction>>> _getDuplicates(
      int messageIndex, List<AiRecognitionResult> results) {
    return _duplicatesCache.putIfAbsent(
      messageIndex,
      () => _findDuplicates(results),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();
    final history = ai.chatHistory;

    return Column(
      children: [
        // 消息列表
        Expanded(
          child: history.isEmpty
              ? _buildEmptyHint(context)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final msg = history[index];
                    return _buildMessageBubble(context, index, msg);
                  },
                ),
        ),
        // 底部输入区
        _buildInputArea(context),
      ],
    );
  }

  Widget _buildEmptyHint(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text(
              '开始与 AI 对话记账',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '例如："午饭花了 35 元"\n也可以发送账单图片',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
      BuildContext context, int index, AiChatMessage msg) {
    final isUser = msg.isUser;
    final theme = Theme.of(context);
    final bgColor = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fgColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Card(
          color: bgColor,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (msg.text != null && msg.text!.isNotEmpty)
                  Text(
                    msg.text!,
                    style: TextStyle(color: fgColor, fontSize: 15),
                  ),
                if (isUser && msg.base64Images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildImageGrid(msg.base64Images),
                ],
                if (!isUser && msg.results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // 已保存的账单直接展示结果；未保存时异步检测重复并标识
                  if (msg.saved)
                    ...msg.results.map((r) => _buildResultChip(r)),
                  if (!msg.saved)
                    FutureBuilder<List<List<Transaction>>>(
                      future: _getDuplicates(index, msg.results),
                      builder: (context, snapshot) {
                        final duplicates = snapshot.data ??
                            List.generate(msg.results.length, (_) => []);
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < msg.results.length; i++)
                              _buildResultChip(
                                msg.results[i],
                                isDuplicate: i < duplicates.length &&
                                    duplicates[i].isNotEmpty,
                              ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 8),
                  if (msg.saved)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            size: 16, color: Colors.green[600]),
                        const SizedBox(width: 4),
                        Text(
                          '已加入账单',
                          style: TextStyle(
                            color: Colors.green[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  else
                    FilledButton.tonal(
                      onPressed: _saving
                          ? null
                          : () => _saveResults(index, msg.results),
                      child: Text(_saving ? '保存中...' : '保存到账单'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<String> base64Images) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: base64Images.map((b64) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(b64),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResultChip(AiRecognitionResult result,
      {bool isDuplicate = false}) {
    final prefix = result.type == 'income' ? '收入' : '支出';
    return Chip(
      avatar: isDuplicate
          ? const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 18)
          : null,
      label: Text(
          '$prefix · ${result.category} · ${result.amount.toStringAsFixed(2)}'),
      backgroundColor: isDuplicate ? Colors.orange.withAlpha(30) : null,
      side: isDuplicate
          ? BorderSide(color: Colors.orange.withAlpha(120))
          : null,
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImages.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingImages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _pendingImages[index],
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _removePendingImage(index),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: _sending ? null : _pickImages,
                  icon: const Icon(Icons.image_outlined),
                  tooltip: '添加图片',
                ),
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: const InputDecoration(
                      hintText: '输入记账内容…',
                      border: InputBorder.none,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                        tooltip: '发送',
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
