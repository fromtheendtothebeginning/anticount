import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/animated_dialog.dart';
import 'ai_profile_edit_screen.dart';

/// AI 配置页面
///
/// 展示所有 AI 配置（Profile），支持创建、编辑、删除、切换激活。
class AiConfigScreen extends StatelessWidget {
  const AiConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('AI 配置')),
      body: ai.profiles.isEmpty
          ? _buildEmpty(context)
          : _buildProfileList(context, ai),
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

  /// 配置列表
  Widget _buildProfileList(BuildContext context, AiProvider ai) {
    final activeId = ai.activeProfile?.id;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: ai.profiles.length,
      itemBuilder: (context, i) {
        final profile = ai.profiles[i];
        final isActive = profile.id == activeId;
        return _ProfileCard(
          profile: profile,
          isActive: isActive,
          onActivate: isActive ? null : () => ai.setActiveProfile(profile.id),
          onEdit: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AiProfileEditScreen(profile: profile),
            ),
          ),
          onDelete: ai.profiles.length <= 1
              ? null
              : () => _confirmDelete(context, ai, profile),
        );
      },
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
      builder: (_) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确认删除配置「${profile.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
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

/// 单个配置卡片
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  final AiProfile profile;
  final bool isActive;
  final VoidCallback? onActivate;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            leading: Icon(
              isActive ? Icons.check_circle : Icons.circle_outlined,
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: Row(
              children: [
                Text(profile.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '使用中',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              profile.hasTextModel
                  ? profile.textConfig!.vendor.label
                  : '未配置',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
          // 模型信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _modelRow(
                  context,
                  Icons.text_fields,
                  '文本识别',
                  profile.textConfig != null
                      ? '${profile.textConfig!.vendor.label} · ${profile.textConfig!.modelId}'
                      : '未配置',
                  profile.hasTextModel,
                ),
                const SizedBox(height: 4),
                _modelRow(
                  context,
                  Icons.image,
                  '多模态识别',
                  profile.multimodalConfig != null
                      ? '${profile.multimodalConfig!.vendor.label} · ${profile.multimodalConfig!.modelId}'
                      : '未配置',
                  profile.hasMultimodalModel,
                ),
              ],
            ),
          ),
          // 激活按钮
          if (!isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onActivate,
                  child: const Text('切换为此配置'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modelRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    bool configured,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Text('$label：', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: configured ? null : Colors.red[300],
            fontWeight: configured ? FontWeight.w500 : null,
          ),
        ),
      ],
    );
  }
}
