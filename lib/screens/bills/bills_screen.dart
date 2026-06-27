import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/animated_dialog.dart';
import '../accounting/accounting_screen.dart';

/// 账单页面（含记账入口）
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      await context.read<TransactionProvider>().refresh(userId: user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final txProvider = context.watch<TransactionProvider>();
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (user != null) ...[
              CircleAvatar(
                radius: 16,
                foregroundImage:
                    user.avatar != null ? FileImage(File(user.avatar!)) : null,
                child: Text(
                  user.initial,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  user.displayName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _openFilterSheet(context),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        // 避免与悬浮导航栏重叠，向上偏移
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton.extended(
          onPressed: () => showAccountingSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('记账'),
        ),
      ),
      body: Column(
        children: [
          FutureBuilder(
            future: user == null ? null : txProvider.summary(user.id),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final income = data?.income ?? 0;
              final expense = data?.expense ?? 0;
              return _SummaryCard(
                income: income,
                expense: expense,
                currency: settings.currency,
              );
            },
          ),
          if (_hasFilters(txProvider))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: _buildFilterChips(txProvider),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await txProvider.setFilters(clear: true);
                      if (user != null) {
                        await txProvider.refresh(userId: user.id);
                      }
                    },
                    child: const Text('清除'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: txProvider.loading
                ? const Center(child: CircularProgressIndicator())
                : txProvider.items.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 140),
                          itemCount: txProvider.items.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, indent: 56, endIndent: 16),
                          itemBuilder: (context, i) {
                            final tx = txProvider.items[i];
                            return _TransactionTile(
                              tx: tx,
                              currency: settings.currency,
                              onEdit: () =>
                                  showAccountingSheet(context, editing: tx),
                              onDelete: () => _confirmDelete(context, tx),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  bool _hasFilters(TransactionProvider p) =>
      p.start != null ||
      p.end != null ||
      p.typeFilter != null ||
      (p.categoryFilter != null && p.categoryFilter!.isNotEmpty) ||
      (p.keyword != null && p.keyword!.isNotEmpty);

  List<Widget> _buildFilterChips(TransactionProvider p) {
    final chips = <Widget>[];
    final fmt = DateFormat('yyyy-MM-dd');
    if (p.start != null || p.end != null) {
      final s = p.start != null ? fmt.format(p.start!) : '不限';
      final e = p.end != null ? fmt.format(p.end!) : '不限';
      chips.add(_filterChip('时间: $s ~ $e'));
    }
    if (p.typeFilter != null) {
      chips.add(_filterChip('类型: ${p.typeFilter!.label}'));
    }
    if (p.categoryFilter != null && p.categoryFilter!.isNotEmpty) {
      chips.add(_filterChip('分类: ${p.categoryFilter}'));
    }
    if (p.keyword != null && p.keyword!.isNotEmpty) {
      chips.add(_filterChip('关键词: ${p.keyword}'));
    }
    return chips;
  }

  Widget _filterChip(String text) => Chip(
        label: Text(text, style: const TextStyle(fontSize: 12)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  Future<void> _openFilterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _FilterSheet(),
    );
    if (result != null && context.mounted) {
      final user = context.read<AuthProvider>().user;
      final provider = context.read<TransactionProvider>();
      await provider.setFilters(
        start: result['start'] as DateTime?,
        end: result['end'] as DateTime?,
        typeFilter: result['type'] as TransactionType?,
        categoryFilter: result['category'] as String?,
        keyword: result['keyword'] as String?,
      );
      if (user != null) {
        await provider.refresh(userId: user.id);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Transaction tx) async {
    // 使用统一的带动画对话框 helper
    final ok = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '删除确认',
      builder: (_) => _DeleteConfirmDialog(theme: Theme.of(context)),
    );
    if (ok == true && context.mounted) {
      final user = context.read<AuthProvider>().user;
      final provider = context.read<TransactionProvider>();
      if (user != null) {
        await provider.delete(tx.id!, user.id);
      }
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.income,
    required this.expense,
    required this.currency,
  });

  final double income;
  final double expense;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final balance = income - expense;
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _col('收入', income, currency, color: Colors.green),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _col('支出', expense, currency, color: Colors.red),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _col('结余', balance, currency,
                  color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _col(String label, double value, String currency, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          '$currency${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.tx,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final Transaction tx;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type == TransactionType.income;
    final fmt = DateFormat('MM-dd HH:mm');
    return ListTile(
      onTap: onEdit,
      leading: CircleAvatar(
        backgroundColor: (isIncome ? Colors.green : Colors.red).withAlpha(30),
        foregroundColor: isIncome ? Colors.green : Colors.red,
        child: Icon(isIncome ? Icons.south_west : Icons.north_east),
      ),
      title: Text(tx.category),
      subtitle: Text(
        [
          fmt.format(tx.date),
          if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isIncome ? '+' : '-'}$currency${tx.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: isIncome ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
          // 编辑按钮（与删除按钮并列，点击进入编辑）
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '编辑',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '删除',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: Icon(Icons.receipt_long, size: 64, color: Colors.grey)),
        SizedBox(height: 8),
        Center(child: Text('暂无账单记录，点击下方按钮记一笔吧～')),
      ],
    );
  }
}

/// 删除确认对话框
///
/// 配合 showGeneralDialog 使用，呈现从下方滑入的动画效果。
class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部图标
            Icon(Icons.delete_outline,
                size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              '删除记账',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '确认删除该条记录？此操作不可恢复。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  DateTime? _start;
  DateTime? _end;
  TransactionType? _type;
  String? _category;
  String _keyword = '';

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = picked;
        } else {
          _end = DateTime(
              picked.year, picked.month, picked.day, 23, 59, 59, 999);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final categories = _type == TransactionType.income
        ? settings.incomeCategories
        : settings.expenseCategories;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('筛选账单', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.event),
                  label: Text(_start == null
                      ? '开始日期'
                      : DateFormat('yyyy-MM-dd').format(_start!)),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event),
                  label: Text(_end == null
                      ? '结束日期'
                      : DateFormat('yyyy-MM-dd').format(_end!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: _type == null,
                onSelected: (_) => setState(() => _type = null),
              ),
              ChoiceChip(
                label: const Text('收入'),
                selected: _type == TransactionType.income,
                onSelected: (_) => setState(() {
                  _type = TransactionType.income;
                  _category = null;
                }),
              ),
              ChoiceChip(
                label: const Text('支出'),
                selected: _type == TransactionType.expense,
                onSelected: (_) => setState(() {
                  _type = TransactionType.expense;
                  _category = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部分类'),
                selected: _category == null,
                onSelected: (_) => setState(() => _category = null),
              ),
              ...categories.map((c) => ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  )),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: '备注关键词',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => _keyword = v,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'start': _start,
                  'end': _end,
                  'type': _type,
                  'category': _category,
                  'keyword': _keyword.isEmpty ? null : _keyword,
                }),
                child: const Text('应用'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
