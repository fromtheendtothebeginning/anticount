import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'transaction_service.dart';

/// 账单导出服务
///
/// 负责按日期范围查询交易记录，并生成 CSV 文件保存到临时目录。
/// CSV 使用 UTF-8 编码并附加 BOM，确保在 Windows Excel 中打开中文不乱码。
class ExportService {
  ExportService(this._transactionService);

  final TransactionService _transactionService;

  /// 将指定日期范围内的交易导出为 CSV 文件
  ///
  /// 返回生成的文件路径，调用方通常随后使用 share_plus 分享该文件。
  Future<String> exportToCsv({
    required int userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final items = await _transactionService.query(
      userId: userId,
      start: start,
      end: end,
    );

    final rows = <List<String>>[
      // CSV 表头
      ['日期', '类型', '分类', '金额', '备注', '创建时间'],
      for (final tx in items)
        [
          DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.date),
          tx.type.label,
          tx.category,
          tx.amount.toStringAsFixed(2),
          tx.note ?? '',
          tx.createdAt != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.createdAt!)
              : '',
        ],
    ];

    // 使用 csv 包生成标准 CSV 格式
    final csv = const ListToCsvConverter().convert(rows);

    // UTF-8 BOM，确保 Excel 正确识别中文
    final csvBytes = utf8.encode(csv);
    final bytes = Uint8List(csvBytes.length + 3);
    bytes[0] = 0xEF;
    bytes[1] = 0xBB;
    bytes[2] = 0xBF;
    bytes.setRange(3, bytes.length, csvBytes);

    final dir = await getTemporaryDirectory();
    final fileName =
        'anticount_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
