import 'package:home_widget/home_widget.dart';

/// 桌面卡片数据服务
///
/// 负责把应用内的月度收支数据同步到 Android 桌面小部件，
/// 并触发小部件刷新。
class WidgetService {
  static const _androidProviderName = 'AnticountWidgetProvider';

  /// 保存月度收支数据并刷新桌面小部件
  static Future<void> updateMonthlySummary({
    required double income,
    required double expense,
    required String monthLabel,
  }) async {
    final balance = income - expense;
    await HomeWidget.saveWidgetData('widget_month_label', monthLabel);
    await HomeWidget.saveWidgetData(
        'widget_income', income.toStringAsFixed(2));
    await HomeWidget.saveWidgetData(
        'widget_expense', expense.toStringAsFixed(2));
    await HomeWidget.saveWidgetData(
        'widget_balance', balance.toStringAsFixed(2));
    await HomeWidget.updateWidget(
      name: _androidProviderName,
      androidName: _androidProviderName,
    );
  }

  /// 请求用户将桌面小部件添加到主屏幕
  static Future<void> requestPinWidget() async {
    await HomeWidget.requestPinWidget(
      name: _androidProviderName,
      androidName: _androidProviderName,
    );
  }
}
