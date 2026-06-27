import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

/// 应用设置状态
///
/// 持有内存中的设置值，并通过 [SettingsService] 同步到磁盘。
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._service)
      : _themeMode = _service.themeMode,
        _currency = _service.currency,
        _incomeCategories = _service.incomeCategories,
        _expenseCategories = _service.expenseCategories;

  final SettingsService _service;

  String _themeMode;
  String _currency;
  List<String> _incomeCategories;
  List<String> _expenseCategories;

  String get themeMode => _themeMode;
  String get currency => _currency;
  List<String> get incomeCategories => _incomeCategories;
  List<String> get expenseCategories => _expenseCategories;

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    await _service.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    _currency = currency;
    await _service.setCurrency(currency);
    notifyListeners();
  }

  Future<void> setIncomeCategories(List<String> value) async {
    _incomeCategories = value;
    await _service.setIncomeCategories(value);
    notifyListeners();
  }

  Future<void> setExpenseCategories(List<String> value) async {
    _expenseCategories = value;
    await _service.setExpenseCategories(value);
    notifyListeners();
  }

  /// 添加自定义分类（去重，最多 20 个）
  /// [type] 为 income 或 expense
  /// 返回是否添加成功
  Future<bool> addCategory(String type, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (type == 'income') {
      if (_incomeCategories.contains(trimmed)) return false;
      if (_incomeCategories.length >= 20) return false;
      await setIncomeCategories([..._incomeCategories, trimmed]);
    } else {
      if (_expenseCategories.contains(trimmed)) return false;
      if (_expenseCategories.length >= 20) return false;
      await setExpenseCategories([..._expenseCategories, trimmed]);
    }
    return true;
  }

  /// 删除自定义分类
  /// [type] 为 income 或 expense
  Future<void> removeCategory(String type, String name) async {
    if (type == 'income') {
      await setIncomeCategories(
          _incomeCategories.where((c) => c != name).toList());
    } else {
      await setExpenseCategories(
          _expenseCategories.where((c) => c != name).toList());
    }
  }
}
