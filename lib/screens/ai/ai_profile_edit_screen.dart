import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/animated_dialog.dart';
import 'ai_error_dialog.dart';

/// AI 配置编辑页面
///
/// 创建或编辑一个 AI 配置（Profile）。
/// 文本识别和多模态识别可分别配置不同厂商、API Key 和模型。
/// 例如：文本用 DeepSeek，多模态用 Kimi。
class AiProfileEditScreen extends StatefulWidget {
  const AiProfileEditScreen({super.key, this.profile});

  /// 传入则编辑模式，null 则新建模式
  final AiProfile? profile;

  @override
  State<AiProfileEditScreen> createState() => _AiProfileEditScreenState();
}

class _AiProfileEditScreenState extends State<AiProfileEditScreen> {
  late final TextEditingController _nameCtrl;

  // 文本识别配置
  AiVendor? _textVendor;
  late final TextEditingController _textApiKeyCtrl;
  String? _textModelId;

  // 多模态识别配置（可选）
  bool _enableMultimodal = false;
  AiVendor? _multimodalVendor;
  late final TextEditingController _multimodalApiKeyCtrl;
  String? _multimodalModelId;

  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.name ?? '');

    // 文本配置
    _textVendor = p?.textConfig?.vendor;
    _textApiKeyCtrl = TextEditingController(text: p?.textConfig?.apiKey ?? '');
    _textModelId = p?.textConfig?.modelId;

    // 多模态配置
    _enableMultimodal = p?.multimodalConfig != null;
    _multimodalVendor = p?.multimodalConfig?.vendor;
    _multimodalApiKeyCtrl =
        TextEditingController(text: p?.multimodalConfig?.apiKey ?? '');
    _multimodalModelId = p?.multimodalConfig?.modelId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _textApiKeyCtrl.dispose();
    _multimodalApiKeyCtrl.dispose();
    super.dispose();
  }

  /// 保存配置
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();

    if (name.isEmpty) {
      await showInfoDialog(context: context, title: '输入有误', content: '请输入配置名称');
      return;
    }
    if (_textVendor == null) {
      await showInfoDialog(
          context: context, title: '输入有误', content: '请选择文本识别厂商');
      return;
    }
    if (_textApiKeyCtrl.text.trim().isEmpty) {
      await showInfoDialog(
          context: context, title: '输入有误', content: '请输入文本识别的 API Key');
      return;
    }
    if (_textModelId == null) {
      await showInfoDialog(
          context: context, title: '输入有误', content: '请选择文本识别模型');
      return;
    }

    // 多模态配置校验（如果启用了）
    if (_enableMultimodal) {
      if (_multimodalVendor == null) {
        await showInfoDialog(
            context: context, title: '输入有误', content: '请选择多模态识别厂商');
        return;
      }
      if (_multimodalApiKeyCtrl.text.trim().isEmpty) {
        await showInfoDialog(
            context: context, title: '输入有误', content: '请输入多模态识别的 API Key');
        return;
      }
      if (_multimodalModelId == null) {
        await showInfoDialog(
            context: context, title: '输入有误', content: '请选择多模态识别模型');
        return;
      }
      if (!_multimodalVendor!.supportsMultimodal) {
        await showInfoDialog(
            context: context,
            title: '输入有误',
            content: '${_multimodalVendor!.label} 不支持多模态，请选择 Kimi');
        return;
      }
    }

    setState(() => _verifying = true);

    final ai = context.read<AiProvider>();
    final navigator = Navigator.of(context);
    final isEdit = widget.profile != null;

    bool success = false;
    try {
      final service = AiService();

      // 1. 验证文本配置 API Key
      try {
        await service.verifyApiKey(
          vendor: _textVendor!,
          apiKey: _textApiKeyCtrl.text.trim(),
          modelId: _textModelId!,
        );
      } catch (e) {
        if (!mounted) return;
        await showAiErrorDialog(
          context: context,
          title: '文本识别 API Key 验证失败',
          error: e.toString(),
        );
        return;
      }

      // 2. 验证多模态配置 API Key（如果启用了）
      if (_enableMultimodal) {
        try {
          await service.verifyApiKey(
            vendor: _multimodalVendor!,
            apiKey: _multimodalApiKeyCtrl.text.trim(),
            modelId: _multimodalModelId!,
          );
        } catch (e) {
          if (!mounted) return;
          await showAiErrorDialog(
            context: context,
            title: '多模态识别 API Key 验证失败',
            error: e.toString(),
          );
          return;
        }
      }

      // 3. 保存配置
      final textConfig = AiModelConfig(
        vendor: _textVendor!,
        apiKey: _textApiKeyCtrl.text.trim(),
        modelId: _textModelId!,
      );
      final multimodalConfig = _enableMultimodal
          ? AiModelConfig(
              vendor: _multimodalVendor!,
              apiKey: _multimodalApiKeyCtrl.text.trim(),
              modelId: _multimodalModelId!,
            )
          : null;

      final profile = AiProfile(
        id: isEdit
            ? widget.profile!.id
            : DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        textConfig: textConfig,
        multimodalConfig: multimodalConfig,
      );
      try {
        if (isEdit) {
          await ai.updateProfile(profile);
        } else {
          await ai.addProfile(profile);
        }
      } catch (e) {
        if (!mounted) return;
        await showAiErrorDialog(
          context: context,
          title: '保存失败',
          error: e.toString(),
        );
        return;
      }

      success = true;
    } finally {
      if (mounted) setState(() => _verifying = false);
    }

    if (success && mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.profile != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑配置' : '新建配置'),
        actions: [
          TextButton(
            onPressed: _verifying ? null : _save,
            child: _verifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 配置名称
          _SectionTitle('配置名称'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: '例如：我的配置',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // 文本识别配置
          _SectionTitle('文本识别'),
          _ConfigSection(
            vendor: _textVendor,
            apiKeyCtrl: _textApiKeyCtrl,
            modelId: _textModelId,
            multimodalOnly: false,
            onVendorChanged: (v) => setState(() {
              _textVendor = v;
              _textModelId = null;
            }),
            onModelChanged: (v) => setState(() => _textModelId = v),
          ),

          // 多模态识别配置（可选）
          _SectionTitle('多模态识别（可选）'),
          if (!_enableMultimodal)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('启用多模态识别'),
                  subtitle: const Text('用于图片识别，可使用与文本不同的厂商'),
                  onTap: () => setState(() {
                    _enableMultimodal = true;
                    // 默认选 Kimi（支持多模态）
                    _multimodalVendor = AiVendor.kimi;
                    _multimodalModelId = null;
                  }),
                ),
              ),
            )
          else ...[
            _ConfigSection(
              vendor: _multimodalVendor,
              apiKeyCtrl: _multimodalApiKeyCtrl,
              modelId: _multimodalModelId,
              multimodalOnly: true,
              onVendorChanged: (v) => setState(() {
                _multimodalVendor = v;
                _multimodalModelId = null;
              }),
              onModelChanged: (v) => setState(() => _multimodalModelId = v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _enableMultimodal = false;
                  _multimodalVendor = null;
                  _multimodalApiKeyCtrl.clear();
                  _multimodalModelId = null;
                }),
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('移除多模态识别'),
              ),
            ),
          ],

          const SizedBox(height: 32),
          // 使用说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16),
                        SizedBox(width: 6),
                        Text('使用说明',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '· 文本识别：用于自然语言记账（必填）\n'
                      '· 多模态识别：用于图片记账，可使用不同厂商\n'
                      '· 例如：文本用 DeepSeek，多模态用 Kimi\n'
                      '· 识别时按类型自动选择对应配置',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 单组配置（厂商 + API Key + 模型选择）
class _ConfigSection extends StatelessWidget {
  const _ConfigSection({
    required this.vendor,
    required this.apiKeyCtrl,
    required this.modelId,
    required this.multimodalOnly,
    required this.onVendorChanged,
    required this.onModelChanged,
  });

  final AiVendor? vendor;
  final TextEditingController apiKeyCtrl;
  final String? modelId;
  final bool multimodalOnly;
  final ValueChanged<AiVendor> onVendorChanged;
  final ValueChanged<String?> onModelChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 厂商选择
            ...AiVendor.values.map((v) {
              // 多模态模式下，过滤不支持多模态的厂商
              if (multimodalOnly && !v.supportsMultimodal) {
                return const SizedBox.shrink();
              }
              final selected = vendor == v;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(v.label),
                subtitle: Text(
                  v.supportsMultimodal
                      ? '支持多模态'
                      : '仅文本',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => onVendorChanged(v),
              );
            }),
            if (vendor != null) ...[
              const Divider(height: 1),
              // API Key
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: apiKeyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'API 地址：${vendor!.baseUrl}/chat/completions',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // 模型选择
              _ModelList(
                vendor: vendor!,
                value: modelId,
                multimodalOnly: multimodalOnly,
                onChanged: onModelChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 模型列表选择
class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.vendor,
    required this.value,
    required this.multimodalOnly,
    required this.onChanged,
  });

  final AiVendor vendor;
  final String? value;
  final bool multimodalOnly;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final models = multimodalOnly
        ? vendor.availableModels.where((m) => m.isMultimodal).toList()
        : vendor.availableModels;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              multimodalOnly ? '多模态模型' : '模型',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
        ...models.map((m) {
          final selected = value == m.id;
          return ListTile(
            leading: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: Text(m.id),
            subtitle: m.description != null
                ? Text(
                    '${m.isMultimodal ? "多模态" : "文本"} · ${m.description}',
                    style: const TextStyle(fontSize: 11),
                  )
                : Text(
                    m.isMultimodal ? '多模态' : '文本',
                    style: const TextStyle(fontSize: 11),
                  ),
            onTap: () => onChanged(selected ? null : m.id),
          );
        }),
        if (models.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '该厂商暂无多模态模型',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (value != null)
          ListTile(
            leading: const Icon(Icons.clear, size: 20, color: Colors.grey),
            title: const Text('清除选择'),
            onTap: () => onChanged(null),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
