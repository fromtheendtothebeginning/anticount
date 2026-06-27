import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../widgets/animated_dialog.dart';

/// 分类管理页面
///
/// 支持分类的排序（拖拽）、隐藏/显示、添加、删除。
/// 通过设置页面入口进入。
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String _type = 'expense'; // expense / income

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _type = _tabCtrl.index == 0 ? 'expense' : 'income');
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final allCategories = _type == 'expense'
        ? settings.expenseCategories
        : settings.incomeCategories;
    final hidden = _type == 'expense'
        ? settings.hiddenExpenseCategories
        : settings.hiddenIncomeCategories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '支出'),
            Tab(text: '收入'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 提示信息
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '长按拖拽排序，点击眼睛图标隐藏/显示',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                // 添加按钮
                TextButton.icon(
                  onPressed: () => _addCategory(context, settings),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 分类列表（可拖拽排序）
          Expanded(
            child: allCategories.isEmpty
                ? const Center(child: Text('暂无分类'))
                : ReorderableListView.builder(
                    itemCount: allCategories.length,
                    onReorder: (oldIndex, newIndex) async {
                      // ReorderableListView 的 newIndex 在 oldIndex 之后时需要 -1
                      if (newIndex > oldIndex) newIndex--;
                      final list = [...allCategories];
                      final item = list.removeAt(oldIndex);
                      list.insert(newIndex, item);
                      await settings.reorderCategories(_type, list);
                    },
                    itemBuilder: (context, index) {
                      final cat = allCategories[index];
                      final isHidden = hidden.contains(cat);
                      return _CategoryTile(
                        key: ValueKey('$_type-$cat'),
                        name: cat,
                        index: index,
                        isHidden: isHidden,
                        onToggleHidden: () =>
                            settings.toggleCategoryHidden(_type, cat),
                        onDelete: () =>
                            _confirmDelete(context, settings, cat),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 添加分类对话框
  Future<void> _addCategory(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '添加分类',
      builder: (_) => AlertDialog(
        title: const Text('添加分类'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分类名称',
            hintText: '请输入分类名称（最多 10 个字）',
            border: OutlineInputBorder(),
          ),
          maxLength: 10,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (ok != true) {
      ctrl.dispose();
      return;
    }

    final added = await settings.addCategory(_type, ctrl.text);
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    if (added) {
      messenger.showSnackBar(
        SnackBar(content: Text('已添加分类：${ctrl.text.trim()}')),
      );
    } else {
      if (!context.mounted) {
        ctrl.dispose();
        return;
      }
      await showInfoDialog(
        context: context,
        title: '添加失败',
        content: '添加失败（可能已存在或数量超限）',
      );
    }
    ctrl.dispose();
  }

  /// 确认删除分类
  Future<void> _confirmDelete(
    BuildContext context,
    SettingsProvider settings,
    String name,
  ) async {
    final ok = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '删除分类',
      builder: (_) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确认删除分类「$name」？\n已使用此分类的记账记录不会被修改。'),
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
      await settings.removeCategory(_type, name);
    }
  }
}

/// 单个分类项
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.name,
    required this.index,
    required this.isHidden,
    required this.onToggleHidden,
    required this.onDelete,
  });

  final String name;
  final int index;
  final bool isHidden;
  final VoidCallback onToggleHidden;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: key,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄
          const Icon(Icons.drag_handle, color: Colors.grey),
          const SizedBox(width: 8),
          Text('${index + 1}'),
        ],
      ),
      title: Text(
        name,
        style: TextStyle(
          color: isHidden ? Colors.grey : null,
          decoration: isHidden ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: isHidden ? const Text('已隐藏', style: TextStyle(fontSize: 12)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 隐藏/显示切换
          IconButton(
            icon: Icon(
              isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
            ),
            tooltip: isHidden ? '显示' : '隐藏',
            onPressed: onToggleHidden,
          ),
          // 删除
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
