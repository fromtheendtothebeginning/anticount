import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/animated_dialog.dart';
import 'category_management_screen.dart';
import 'change_password_screen.dart';
import 'delete_account_screen.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      user.initial,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(user.displayName),
                  subtitle: Text('@${user.username}'),
                ),
              ),
            ),
          _SectionTitle('外观'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题模式'),
                trailing: DropdownButton<String>(
                  value: settings.themeMode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                    DropdownMenuItem(value: 'light', child: Text('浅色')),
                    DropdownMenuItem(value: 'dark', child: Text('深色')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await settings.setThemeMode(v);
                  },
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.attach_money),
                title: const Text('货币符号'),
                trailing: DropdownButton<String>(
                  value: settings.currency,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: '¥', child: Text('¥ 人民币')),
                    DropdownMenuItem(value: '\$', child: Text('\$ 美元')),
                    DropdownMenuItem(value: '€', child: Text('€ 欧元')),
                    DropdownMenuItem(value: '£', child: Text('£ 英镑')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await settings.setCurrency(v);
                  },
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('分类管理'),
                subtitle: const Text('排序、隐藏、添加分类'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CategoryManagementScreen(),
                )),
              ),
            ],
          ),
          _SectionTitle('账户安全'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.save_outlined),
                title: const Text('退出登录时保留数据'),
                subtitle: const Text('关闭后，退出登录将清除本地记账数据'),
                value: settings.retainDataOnLogout,
                onChanged: (v) => settings.setRetainDataOnLogout(v),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('修改密码'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ChangePasswordScreen(),
                )),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error),
                title: Text('删除账号',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const DeleteAccountScreen(),
                )),
              ),
            ],
          ),
          _SectionTitle('关于'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                trailing: const Text('v1.0.0',
                    style: TextStyle(color: Colors.grey)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('开源许可'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Anticount',
                  applicationVersion: '1.0.0',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 退出登录按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 退出登录确认
  Future<void> _confirmLogout(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final settings = context.read<SettingsProvider>();
    final retain = settings.retainDataOnLogout;
    final ok = await showAnimatedDialog<bool>(
      context: context,
      barrierLabel: '退出登录',
      builder: (_) => AlertDialog(
        title: const Text('退出登录'),
        content: Text(retain
            ? '确认退出当前账号？\n你的记账数据将保留，下次登录可继续查看。'
            : '确认退出当前账号？\n根据你的设置，退出后本地记账数据将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await authProvider.logout(retainData: retain);
    }
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

/// 设置项卡片容器
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: children),
      ),
    );
  }
}
