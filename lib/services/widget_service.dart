import 'package:home_widget/home_widget.dart';

/// 桌面卡片数据服务
///
/// 负责把应用内的月度收支数据同步到 Android 桌面小部件，
/// 并触发小部件刷新。
class WidgetService {
  static const _androidProviderName = 'AnticountWidgetProvider';

  /// 保存月度账单数据并刷新桌面小部件
  ///
  /// [totalAmount] 为当月账单总金额（收入 + 支出），
  /// [billCount] 为当月账单笔数，
  /// [averageAmount] 为当月账单平均金额。
  static Future<void> updateMonthlySummary({
    required String monthLabel,
    required double totalAmount,
    required int billCount,
    required double averageAmount,
  }) async {
    await HomeWidget.saveWidgetData('widget_month_label', monthLabel);
    await HomeWidget.saveWidgetData(
        'widget_total_amount', totalAmount.toStringAsFixed(2));
    await HomeWidget.saveWidgetData(
        'widget_bill_count', billCount.toString());
    await HomeWidget.saveWidgetData(
        'widget_average_amount', averageAmount.toStringAsFixed(2));
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
