import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/animated_dialog.dart';
import 'ai_error_dialog.dart';

/// AI 配置编辑页面
///
/// 创建或编辑一个 AI 配置（Profile）。
/// 简化布局：配置名称 + 厂商选择（单选）+ API Key + 展示该厂商支持的模型。
/// 同一 Profile 使用同一厂商和 API Key；
/// 文字识别和图像识别的具体模型在配置主界面中切换。
class AiProfileEditScreen extends StatefulWidget {
  const AiProfileEditScreen({super.key, this.profile});

  /// 传入则编辑模式，null 则新建模式
  final AiProfile? profile;

  @override
  State<AiProfileEditScreen> createState() => _AiProfileEditScreenState();
}

class _AiProfileEditScreenState extends State<AiProfileEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _apiKeyCtrl;

  /// 当前选中的厂商
  AiVendor? _vendor;

  /// 编辑模式下保留的原有模型 ID（同厂商时沿用，避免覆盖用户在配置界面的选择）
  String? _textModelId;
  String? _multimodalModelId;

  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    // 编辑模式：取 textConfig 的厂商和 API Key 作为默认
    _vendor = p?.textConfig?.vendor;
    _apiKeyCtrl = TextEditingController(text: p?.textConfig?.apiKey ?? '');
    _textModelId = p?.textConfig?.modelId;
    _multimodalModelId = p?.multimodalConfig?.modelId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  /// 切换厂商时重置模型 ID（新厂商的旧 modelId 无效）
  void _onVendorChanged(AiVendor v) {
    if (_vendor == v) return;
    setState(() {
      _vendor = v;
      // 使用新厂商的默认模型
      _textModelId = v.availableModels.isNotEmpty
          ? v.availableModels.first.id
          : null;
      _multimodalModelId = v.multimodalModelIds.isNotEmpty
          ? v.multimodalModelIds.first
          : null;
    });
  }

  /// 保存配置
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();

    if (name.isEmpty) {
      await showInfoDialog(context: context, title: '输入有误', content: '请输入配置名称');
      return;
    }
    if (_vendor == null) {
      await showInfoDialog(context: context, title: '输入有误', content: '请选择厂商');
      return;
    }
    if (_apiKeyCtrl.text.trim().isEmpty) {
      await showInfoDialog(context: context, title: '输入有误', content: '请输入 API Key');
      return;
    }

    // 确定默认模型 ID（若未设置）
    final vendor = _vendor!;
    final textModelId = _textModelId ??
        (vendor.availableModels.isNotEmpty
            ? vendor.availableModels.first.id
            : '');
    if (textModelId.isEmpty) {
      await showInfoDialog(
          context: context, title: '输入有误', content: '该厂商暂无可用模型');
      return;
    }

    setState(() => _verifying = true);

    final ai = context.read<AiProvider>();
    final navigator = Navigator.of(context);
    final isEdit = widget.profile != null;

    bool success = false;
    try {
      final service = AiService();

      // 1. 验证 API Key
      try {
        await service.verifyApiKey(
          vendor: vendor,
          apiKey: _apiKeyCtrl.text.trim(),
          modelId: textModelId,
        );
      } catch (e) {
        if (!mounted) return;
        await showAiErrorDialog(
          context: context,
          title: 'API Key 验证失败',
          error: e.toString(),
        );
        return;
      }

      // 2. 构造配置
      final textConfig = AiModelConfig(
        vendor: vendor,
        apiKey: _apiKeyCtrl.text.trim(),
        modelId: textModelId,
      );
      // 若厂商支持多模态，自动配置多模态（使用默认多模态模型）
      final multimodalConfig = vendor.supportsMultimodal &&
              vendor.multimodalModelIds.isNotEmpty
          ? AiModelConfig(
              vendor: vendor,
              apiKey: _apiKeyCtrl.text.trim(),
              modelId: _multimodalModelId ?? vendor.multimodalModelIds.first,
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
                hintText: '例如：我的deepseek',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // 厂商选择（圆角矩形 + PopupMenuButton 弹出动画）
          _SectionTitle('厂商'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _VendorPicker(
              vendor: _vendor,
              onChanged: _onVendorChanged,
            ),
          ),

          // API Key
          if (_vendor != null) ...[
            _SectionTitle('API Key'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _apiKeyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-...',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'API 地址：${_vendor!.baseUrl}/chat/completions',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 该厂商支持的模型列表（仅展示，不可选择）
            _SectionTitle('API 支持模型'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final model in _vendor!.availableModels)
                      ListTile(
                        leading: Icon(
                          model.isMultimodal
                              ? Icons.image_outlined
                              : Icons.text_snippet_outlined,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        title: Text(model.id),
                        subtitle: Text(
                          [
                            model.isMultimodal ? '多模态' : '文本',
                            if (model.description != null) model.description!,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                        dense: true,
                      ),
                  ],
                ),
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
                      '· 每个 Profile 使用同一厂商和 API Key\n'
                      '· 保存后可在配置主界面切换具体的文字/图像识别模型\n'
                      '· 文字识别可用所有模型，图像识别仅可用多模态模型\n'
                      '· DeepSeek 仅支持文本，Kimi 支持多模态',
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

/// 厂商选择器
///
/// 圆角矩形外观 + 自定义 Overlay 下拉列表。
/// 弹出列表宽度与选择组件一致，显示在选择组件正下方，不遮挡选择组件。
/// 带卷帘门（下拉展开）动画。
class _VendorPicker extends StatefulWidget {
  const _VendorPicker({required this.vendor, required this.onChanged});

  final AiVendor? vendor;
  final ValueChanged<AiVendor> onChanged;

  @override
  State<_VendorPicker> createState() => _VendorPickerState();
}

class _VendorPickerState extends State<_VendorPicker>
    with SingleTickerProviderStateMixin {
  final GlobalKey _key = GlobalKey();
  OverlayEntry? _overlayEntry;
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animCtrl.dispose();
    super.dispose();
  }

  /// 移除弹出列表
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// 打开 / 关闭下拉列表
  void _toggle() {
    if (_overlayEntry != null) {
      _close();
    } else {
      _open();
    }
  }

  /// 打开下拉列表
  ///
  /// 通过 GlobalKey 获取选择组件的位置和大小，
  /// 将弹出列表定位在选择组件正下方，宽度与选择组件一致。
  void _open() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    final rect = position & size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _VendorDropdown(
        rect: rect,
        vendor: widget.vendor,
        animCtrl: _animCtrl,
        onSelect: (v) {
          widget.onChanged(v);
          _close();
        },
        onDismiss: _close,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _animCtrl.forward(from: 0);
  }

  /// 关闭下拉列表
  void _close() {
    _animCtrl.reverse().then((_) {
      _removeOverlay();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.vendor != null
                ? Theme.of(context).colorScheme.primary.withAlpha(120)
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Row(
          children: [
            if (widget.vendor != null)
              Icon(
                widget.vendor!.supportsMultimodal
                    ? Icons.image_outlined
                    : Icons.text_snippet_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              )
            else
              Icon(Icons.business_outlined, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: widget.vendor == null
                  ? Text('选择厂商',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14))
                  : Text(
                      '${widget.vendor!.label}（${widget.vendor!.supportsMultimodal ? '支持多模态' : '仅文本'}）',
                      style: const TextStyle(fontSize: 14),
                    ),
            ),
            // 下拉箭头
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// 厂商下拉列表（Overlay）
///
/// 定位在选择组件正下方，宽度与选择组件一致。
/// 点击选项或外部区域时关闭。
class _VendorDropdown extends StatelessWidget {
  const _VendorDropdown({
    required this.rect,
    required this.vendor,
    required this.animCtrl,
    required this.onSelect,
    required this.onDismiss,
  });

  /// 选择组件的位置和大小
  final Rect rect;
  final AiVendor? vendor;
  final AnimationController animCtrl;
  final ValueChanged<AiVendor> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 全屏透明遮罩，点击关闭
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        // 弹出列表：定位在选择组件下方，宽度一致
        Positioned(
          left: rect.left,
          top: rect.bottom + 4,
          width: rect.width,
          child: AnimatedBuilder(
            animation: animCtrl,
            builder: (context, child) {
              // 卷帘门效果：用 ClipRect + Align(heightFactor) 从顶部向下展开
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: animCtrl.value,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AiVendor.values.map((v) {
                    final selected = vendor == v;
                    return InkWell(
                      onTap: () => onSelect(v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              v.supportsMultimodal
                                  ? Icons.image_outlined
                                  : Icons.text_snippet_outlined,
                              size: 18,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${v.label}（${v.supportsMultimodal ? '支持多模态' : '仅文本'}）',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                  fontWeight:
                                      selected ? FontWeight.w600 : null,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
