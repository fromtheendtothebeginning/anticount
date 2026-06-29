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
import 'ai_error_dialog.dart';

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
      await ai.sendChatMessage(
        text: text,
        base64Images: pendingImages,
        expenseCategories: settings.expenseCategories,
        incomeCategories: settings.incomeCategories,
      );
      _scrollToBottom();
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
  Future<void> _saveResults(List<AiRecognitionResult> results) async {
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
      _showTip('已保存 $success 条账单');
    } else if (success > 0) {
      _showTip('已保存 $success/${results.length} 条');
    } else {
      await showAiErrorDialog(
        context: context,
        title: '保存失败',
        error: lastError ?? '保存失败',
      );
    }
  }

  void _showTip(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
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
                    return _buildMessageBubble(context, msg);
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

  Widget _buildMessageBubble(BuildContext context, AiChatMessage msg) {
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
                  ...msg.results.map((r) => _buildResultChip(r)),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _saving ? null : () => _saveResults(msg.results),
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

  Widget _buildResultChip(AiRecognitionResult result) {
    final prefix = result.type == 'income' ? '收入' : '支出';
    return Chip(
      label: Text('$prefix · ${result.category} · ${result.amount.toStringAsFixed(2)}'),
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
