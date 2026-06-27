import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置服务
///
/// 持久化用户偏好：主题模式、货币符号、记账分类列表等。
class SettingsService {
  SettingsService(this._prefs);
  final SharedPreferences _prefs;

  static const _kThemeMode = 'settings_theme_mode'; // system/light/dark
  static const _kCurrency = 'settings_currency';
  static const _kIncomeCategories = 'settings_income_categories';
  static const _kExpenseCategories = 'settings_expense_categories';
  static const _kHiddenIncomeCategories = 'settings_hidden_income_categories';
  static const _kHiddenExpenseCategories = 'settings_hidden_expense_categories';
  static const _kRetainDataOnLogout = 'settings_retain_data_on_logout';

  /// 主题模式：system / light / dark
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) => _prefs.setString(_kThemeMode, mode);

  /// 货币符号
  String get currency => _prefs.getString(_kCurrency) ?? '¥';
  Future<void> setCurrency(String currency) =>
      _prefs.setString(_kCurrency, currency);

  /// 收入分类
  List<String> get incomeCategories =>
      _prefs.getStringList(_kIncomeCategories) ??
      const ['工资', '奖金', '投资', '兼职', '其他'];

  Future<void> setIncomeCategories(List<String> value) =>
      _prefs.setStringList(_kIncomeCategories, value);

  /// 支出分类
  List<String> get expenseCategories =>
      _prefs.getStringList(_kExpenseCategories) ??
      const ['餐饮', '交通', '购物', '住房', '娱乐', '医疗', '教育', '其他'];

  Future<void> setExpenseCategories(List<String> value) =>
      _prefs.setStringList(_kExpenseCategories, value);

  /// 隐藏的收入分类
  List<String> get hiddenIncomeCategories =>
      _prefs.getStringList(_kHiddenIncomeCategories) ?? const [];
  Future<void> setHiddenIncomeCategories(List<String> value) =>
      _prefs.setStringList(_kHiddenIncomeCategories, value);

  /// 隐藏的支出分类
  List<String> get hiddenExpenseCategories =>
      _prefs.getStringList(_kHiddenExpenseCategories) ?? const [];
  Future<void> setHiddenExpenseCategories(List<String> value) =>
      _prefs.setStringList(_kHiddenExpenseCategories, value);

  /// 退出登录时是否保留本地数据（默认保留）
  bool get retainDataOnLogout =>
      _prefs.getBool(_kRetainDataOnLogout) ?? true;
  Future<void> setRetainDataOnLogout(bool value) =>
      _prefs.setBool(_kRetainDataOnLogout, value);
}
