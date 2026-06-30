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
  static const _kAutoSaveAiBills = 'settings_auto_save_ai_bills';
  static const _kAiChatMode = 'settings_ai_chat_mode'; // true=对话模式，false=批量处理模式
  static const _kBillGroupMode = 'settings_bill_group_mode'; // day/week/month/year
  static const _kAiImportEnabled = 'settings_ai_import_enabled'; // true=允许AI处理非标准格式
  static const _kAutoProcessImportedBills = 'settings_auto_process_imported_bills'; // true=AI解析后自动保存

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

  /// AI 记账识别后是否自动保存到账单（默认关闭）
  bool get autoSaveAiBills =>
      _prefs.getBool(_kAutoSaveAiBills) ?? false;
  Future<void> setAutoSaveAiBills(bool value) =>
      _prefs.setBool(_kAutoSaveAiBills, value);

  /// AI 记账默认是否为对话模式（默认 false，即批量处理模式）
  bool get aiChatMode => _prefs.getBool(_kAiChatMode) ?? false;
  Future<void> setAiChatMode(bool value) => _prefs.setBool(_kAiChatMode, value);

  /// 账单分组模式：day / week / month / year（默认按周）
  String get billGroupMode =>
      _prefs.getString(_kBillGroupMode) ?? 'week';
  Future<void> setBillGroupMode(String mode) =>
      _prefs.setString(_kBillGroupMode, mode);

  /// 是否允许 AI 处理非标准格式的导入文件（默认开启）
  bool get aiImportEnabled =>
      _prefs.getBool(_kAiImportEnabled) ?? true;
  Future<void> setAiImportEnabled(bool value) =>
      _prefs.setBool(_kAiImportEnabled, value);

  /// AI 导入识别后是否自动保存到账单（默认关闭）
  bool get autoProcessImportedBills =>
      _prefs.getBool(_kAutoProcessImportedBills) ?? false;
  Future<void> setAutoProcessImportedBills(bool value) =>
      _prefs.setBool(_kAutoProcessImportedBills, value);
}
