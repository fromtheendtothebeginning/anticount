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
        _expenseCategories = _service.expenseCategories,
        _hiddenIncome = _service.hiddenIncomeCategories,
        _hiddenExpense = _service.hiddenExpenseCategories,
        _retainDataOnLogout = _service.retainDataOnLogout,
        _autoSaveAiBills = _service.autoSaveAiBills,
        _aiChatMode = _service.aiChatMode,
        _billGroupMode = _service.billGroupMode,
        _aiImportEnabled = _service.aiImportEnabled,
        _autoProcessImportedBills = _service.autoProcessImportedBills;

  final SettingsService _service;

  String _themeMode;
  String _currency;
  List<String> _incomeCategories;
  List<String> _expenseCategories;
  List<String> _hiddenIncome;
  List<String> _hiddenExpense;
  bool _retainDataOnLogout;
  bool _autoSaveAiBills;
  bool _aiChatMode;
  String _billGroupMode;
  bool _aiImportEnabled;
  bool _autoProcessImportedBills;

  String get themeMode => _themeMode;
  String get currency => _currency;
  List<String> get incomeCategories => _incomeCategories;
  List<String> get expenseCategories => _expenseCategories;
  List<String> get hiddenIncomeCategories => _hiddenIncome;
  List<String> get hiddenExpenseCategories => _hiddenExpense;
  bool get retainDataOnLogout => _retainDataOnLogout;
  /// AI 识别后是否自动保存到账单
  bool get autoSaveAiBills => _autoSaveAiBills;
  /// AI 记账默认是否为对话模式（true=对话模式，false=批量处理模式）
  bool get aiChatMode => _aiChatMode;
  /// 账单分组模式：day / week / month / year
  String get billGroupMode => _billGroupMode;
  /// 是否允许 AI 处理非标准格式的导入文件
  bool get aiImportEnabled => _aiImportEnabled;
  /// AI 导入识别后是否自动保存到账单
  bool get autoProcessImportedBills => _autoProcessImportedBills;

  /// 记账界面可见的收入分类（排除隐藏项）
  List<String> get visibleIncomeCategories =>
      _incomeCategories.where((c) => !_hiddenIncome.contains(c)).toList();

  /// 记账界面可见的支出分类（排除隐藏项）
  List<String> get visibleExpenseCategories =>
      _expenseCategories.where((c) => !_hiddenExpense.contains(c)).toList();

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

  /// 设置隐藏的收入分类
  Future<void> setHiddenIncomeCategories(List<String> value) async {
    _hiddenIncome = value;
    await _service.setHiddenIncomeCategories(value);
    notifyListeners();
  }

  /// 设置隐藏的支出分类
  Future<void> setHiddenExpenseCategories(List<String> value) async {
    _hiddenExpense = value;
    await _service.setHiddenExpenseCategories(value);
    notifyListeners();
  }

  /// 设置退出登录时是否保留数据
  Future<void> setRetainDataOnLogout(bool value) async {
    _retainDataOnLogout = value;
    await _service.setRetainDataOnLogout(value);
    notifyListeners();
  }

  /// 设置 AI 识别后是否自动保存到账单
  Future<void> setAutoSaveAiBills(bool value) async {
    _autoSaveAiBills = value;
    await _service.setAutoSaveAiBills(value);
    notifyListeners();
  }

  /// 设置 AI 记账默认是否为对话模式
  Future<void> setAiChatMode(bool value) async {
    _aiChatMode = value;
    await _service.setAiChatMode(value);
    notifyListeners();
  }

  /// 设置账单分组模式（day / week / month / year）
  Future<void> setBillGroupMode(String mode) async {
    _billGroupMode = mode;
    await _service.setBillGroupMode(mode);
    notifyListeners();
  }

  /// 设置是否允许 AI 处理非标准格式的导入文件
  Future<void> setAiImportEnabled(bool value) async {
    _aiImportEnabled = value;
    await _service.setAiImportEnabled(value);
    notifyListeners();
  }

  /// 设置 AI 导入识别后是否自动保存到账单
  Future<void> setAutoProcessImportedBills(bool value) async {
    _autoProcessImportedBills = value;
    await _service.setAutoProcessImportedBills(value);
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
      // 同时从隐藏列表中移除
      await setHiddenIncomeCategories(
          _hiddenIncome.where((c) => c != name).toList());
    } else {
      await setExpenseCategories(
          _expenseCategories.where((c) => c != name).toList());
      await setHiddenExpenseCategories(
          _hiddenExpense.where((c) => c != name).toList());
    }
  }

  /// 切换分类的隐藏状态
  /// [type] 为 income 或 expense
  Future<void> toggleCategoryHidden(String type, String name) async {
    if (type == 'income') {
      if (_hiddenIncome.contains(name)) {
        await setHiddenIncomeCategories(
            _hiddenIncome.where((c) => c != name).toList());
      } else {
        await setHiddenIncomeCategories([..._hiddenIncome, name]);
      }
    } else {
      if (_hiddenExpense.contains(name)) {
        await setHiddenExpenseCategories(
            _hiddenExpense.where((c) => c != name).toList());
      } else {
        await setHiddenExpenseCategories([..._hiddenExpense, name]);
      }
    }
  }

  /// 重排分类（拖拽排序后调用）
  /// [type] 为 income 或 expense
  Future<void> reorderCategories(String type, List<String> newOrder) async {
    if (type == 'income') {
      await setIncomeCategories(newOrder);
    } else {
      await setExpenseCategories(newOrder);
    }
  }
}
