import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/animated_dialog.dart';
import 'ai_profile_edit_screen.dart';

/// AI 配置页面
///
/// 上半部分按"文字识别 / 图像识别"分组展示当前选中模型，
/// 展开后按 Profile 分组列出该厂商所有可选模型，用户可任意切换。
/// 下半部分为配置管理（创建 / 编辑 / 删除 Profile）。
class AiConfigScreen extends StatelessWidget {
  const AiConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('AI 配置')),
      body: ai.profiles.isEmpty
          ? _buildEmpty(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                // 文字识别分组
                _RecognitionSection(
                  title: '文字识别',
                  icon: Icons.text_fields_outlined,
                  isMultimodal: false,
                ),
                const SizedBox(height: 8),
                // 图像识别分组
                _RecognitionSection(
                  title: '图像识别',
                  icon: Icons.image_outlined,
                  isMultimodal: true,
                ),
                const SizedBox(height: 16),
                // 配置管理
                _ManagementSection(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiProfileEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新建配置'),
      ),
    );
  }

  /// 空状态
  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('尚未创建 AI 配置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              '点击右下角按钮创建第一个配置\n每个配置包含厂商、API Key 和模型选择',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// 识别类型分组（文字识别 / 图像识别）
///
/// 展开后按 Profile 分组，列出每个 Profile 对应厂商的所有可选模型。
/// 用户点击具体模型即可切换激活的 Profile + 模型。
class _RecognitionSection extends StatelessWidget {
  const _RecognitionSection({
    required this.title,
    required this.icon,
    required this.isMultimodal,
  });

  final String title;
  final IconData icon;
  final bool isMultimodal;

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();

    // 当前激活的 Profile 和模型 ID
    final activeProfile =
        isMultimodal ? ai.activeMultimodalProfile : ai.activeTextProfile;
    final activeModelId =
        isMultimodal ? ai.activeMultimodalModelId : ai.activeTextModelId;

    // 可用的 Profile 列表（有对应配置的）
    final availableProfiles = ai.profiles.where((p) {
      if (isMultimodal) {
        return p.hasMultimodalModel &&
            p.multimodalConfig!.vendor.supportsMultimodal;
      }
      return p.hasTextModel;
    }).toList();

    // 当前选中描述
    final currentText = (activeProfile != null && activeModelId != null)
        ? '${activeProfile.name} - $activeModelId'
        : (availableProfiles.isEmpty ? '暂无可用配置' : '未选择');

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 28, top: 2),
          child: Text(
            currentText,
            style: TextStyle(
              fontSize: 13,
              color: activeProfile != null
                  ? Theme.of(context).colorScheme.onSurface.withAlpha(180)
                  : Colors.red[300],
            ),
          ),
        ),
        children: availableProfiles.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isMultimodal
                        ? '暂无支持图像识别的配置（需多模态厂商，如 Kimi）'
                        : '暂无可用文字识别配置',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              ]
            : [
                for (int i = 0; i < availableProfiles.length; i++) ...[
                  _ProfileModelGroup(
                    profile: availableProfiles[i],
                    isMultimodal: isMultimodal,
                    activeProfileId: activeProfile?.id,
                    activeModelId: activeModelId,
                  ),
                  if (i < availableProfiles.length - 1) const Divider(height: 1),
                ],
              ],
      ),
    );
  }
}

/// 单个 Profile 下的模型列表
///
/// 显示 Profile 名称作为子标题，下面列出该厂商所有可选模型。
/// 文字识别列出所有模型，图像识别仅列出多模态模型。
class _ProfileModelGroup extends StatelessWidget {
  const _ProfileModelGroup({
    required this.profile,
    required this.isMultimodal,
    required this.activeProfileId,
    required this.activeModelId,
  });

  final AiProfile profile;
  final bool isMultimodal;
  final String? activeProfileId;
  final String? activeModelId;

  @override
  Widget build(BuildContext context) {
    final ai = context.read<AiProvider>();
    final vendor = isMultimodal
        ? profile.multimodalConfig!.vendor
        : profile.textConfig!.vendor;

    // 文字识别：列出该厂商所有模型（多模态模型也可用于文字）
    // 图像识别：仅列出多模态模型
    final models = isMultimodal
        ? vendor.availableModels.where((m) => m.isMultimodal).toList()
        : vendor.availableModels;

    // 当前是否选中此 Profile + 模型
    final isThisProfileActive = activeProfileId == profile.id;
    final activeModel = isThisProfileActive ? activeModelId : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile 名称
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  profile.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  vendor.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          // 模型列表（自定义单选样式，避免 RadioListTile 弃用 API）
          for (final model in models)
            _ModelTile(
              modelId: model.id,
              description: model.description,
              selected: isThisProfileActive && activeModel == model.id,
              onTap: () {
                if (isMultimodal) {
                  ai.selectMultimodalModel(profile.id, model.id);
                } else {
                  ai.selectTextModel(profile.id, model.id);
                }
              },
            ),
        ],
      ),
    );
  }
}

/// 单个模型选项（自定义单选样式）
class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.modelId,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String modelId;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 单选指示器
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modelId,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description!,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 配置管理区域
///
/// 列出所有 Profile，支持编辑和删除。删除最后一个 Profile 不允许。
class _ManagementSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                const Text('配置管理',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AiProfileEditScreen()),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建'),
                ),
              ],
            ),
            const Divider(),
            for (final profile in ai.profiles)
              _ProfileManageTile(profile: profile),
          ],
        ),
      ),
    );
  }
}

/// 配置管理中的单条 Profile
class _ProfileManageTile extends StatelessWidget {
  const _ProfileManageTile({required this.profile});

  final AiProfile profile;

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();
    final canDelete = ai.profiles.length > 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: const Icon(Icons.account_circle_outlined),
      title: Text(profile.name,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        [
          if (profile.hasTextModel)
            '文字：${profile.textConfig!.vendor.label} · ${profile.textConfig!.modelId}',
          if (profile.hasMultimodalModel)
            '图像：${profile.multimodalConfig!.vendor.label} · ${profile.multimodalConfig!.modelId}',
          if (!profile.hasTextModel && !profile.hasMultimodalModel) '未配置模型',
        ].join('\n'),
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: _ProfileMenuButton(
        items: [
          const _MenuItem(
              value: 'edit', label: '编辑', icon: Icons.edit_outlined),
          if (canDelete)
            const _MenuItem(
                value: 'delete', label: '删除', icon: Icons.delete_outline),
        ],
        onSelected: (v) {
          if (v == 'edit') {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AiProfileEditScreen(profile: profile),
            ));
          } else if (v == 'delete') {
            _confirmDelete(context, ai, profile);
          }
        },
      ),
    );
  }

  /// 确认删除
  Future<void> _confirmDelete(
    BuildContext context,
    AiProvider ai,
    AiProfile profile,
  ) async {
    final ok = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '删除配置',
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确认删除配置「${profile.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ai.removeProfile(profile.id);
    }
  }
}

/// 菜单项数据
class _MenuItem {
  const _MenuItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

/// 配置管理中的更多操作按钮（三个点）
///
/// 自定义 Overlay 实现：
/// - 弹出菜单显示在按钮下方（不覆盖三个点按钮）
/// - 展开后再次点击按钮收起菜单
/// - 点击菜单项或外部区域时关闭
class _ProfileMenuButton extends StatefulWidget {
  const _ProfileMenuButton({
    required this.items,
    required this.onSelected,
  });

  final List<_MenuItem> items;
  final ValueChanged<String> onSelected;

  @override
  State<_ProfileMenuButton> createState() => _ProfileMenuButtonState();
}

class _ProfileMenuButtonState extends State<_ProfileMenuButton> {
  final GlobalKey _key = GlobalKey();
  OverlayEntry? _overlayEntry;

  /// 打开 / 关闭菜单（再次点击收起）
  void _toggle() {
    if (_overlayEntry != null) {
      _close();
    } else {
      _open();
    }
  }

  /// 打开菜单
  ///
  /// 通过 GlobalKey 获取按钮位置，将菜单定位在按钮正下方，不覆盖按钮。
  void _open() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    final rect = position & size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _ProfileMenuDropdown(
        rect: rect,
        items: widget.items,
        onSelect: (v) {
          _close();
          widget.onSelected(v);
        },
        onDismiss: _close,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 关闭菜单
  void _close() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _key,
      icon: const Icon(Icons.more_vert),
      onPressed: _toggle,
    );
  }
}

/// 弹出菜单（Overlay）
///
/// 定位在三个点按钮下方，不覆盖按钮本身。
/// 点击选项或外部区域时关闭。
class _ProfileMenuDropdown extends StatelessWidget {
  const _ProfileMenuDropdown({
    required this.rect,
    required this.items,
    required this.onSelect,
    required this.onDismiss,
  });

  /// 按钮的位置和大小
  final Rect rect;
  final List<_MenuItem> items;
  final ValueChanged<String> onSelect;
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
        // 弹出菜单：定位在按钮下方，右对齐按钮，不覆盖按钮
        Positioned(
          right: MediaQuery.of(context).size.width - rect.right,
          top: rect.bottom + 4,
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
                children: items.map((item) {
                  return InkWell(
                    onTap: () => onSelect(item.value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.icon, size: 18, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(item.label, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
