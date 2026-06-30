import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import 'ai_service.dart';
import 'transaction_service.dart';

/// 待导入账单
///
/// 用于导入流程中的临时数据结构，支持用户手动编辑、勾选、删除。
class ImportBill {
  ImportBill({
    required this.id,
    required this.date,
    required this.type,
    required this.category,
    required this.amount,
    this.note,
    this.selected = true,
    this.isDuplicate = false,
    this.aiSource = false,
  });

  final String id;
  DateTime date;
  TransactionType type;
  String category;
  double amount;
  String? note;
  bool selected;
  bool isDuplicate;
  final bool aiSource;

  ImportBill copyWith({
    DateTime? date,
    TransactionType? type,
    String? category,
    double? amount,
    String? note,
    bool? selected,
    bool? isDuplicate,
  }) =>
      ImportBill(
        id: id,
        date: date ?? this.date,
        type: type ?? this.type,
        category: category ?? this.category,
        amount: amount ?? this.amount,
        note: note ?? this.note,
        selected: selected ?? this.selected,
        isDuplicate: isDuplicate ?? this.isDuplicate,
        aiSource: aiSource,
      );
}

/// 导入解析结果
class ImportResult {
  ImportResult({
    this.bills = const [],
    this.error,
    this.aiProcessed = false,
    this.rawRowCount = 0,
    this.parsedCount = 0,
  });

  final List<ImportBill> bills;
  final String? error;
  final bool aiProcessed;
  final int rawRowCount;
  final int parsedCount;

  ImportResult copyWith({
    List<ImportBill>? bills,
    String? error,
    bool? aiProcessed,
    int? rawRowCount,
    int? parsedCount,
  }) =>
      ImportResult(
        bills: bills ?? this.bills,
        error: error ?? this.error,
        aiProcessed: aiProcessed ?? this.aiProcessed,
        rawRowCount: rawRowCount ?? this.rawRowCount,
        parsedCount: parsedCount ?? this.parsedCount,
      );
}

/// 导入服务
///
/// 负责文件选择、CSV/Excel 读取、系统格式解析、AI 非标准格式解析及重复检测。
class ImportService {
  ImportService(this._aiService, this._transactionService);

  final AiService _aiService;
  final TransactionService _transactionService;

  /// 系统导出 CSV 表头
  static const _systemHeaders = ['日期', '类型', '分类', '金额', '备注', '创建时间'];

  /// 选择本地文件并读取为文本
  ///
  /// CSV 直接读取文本；Excel 转换为类 CSV 文本返回。
  /// 返回 null 表示用户取消选择。
  Future<({String content, String fileName, String extension})?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final ext = (file.extension ?? 'csv').toLowerCase();
    final content = await _readFileContent(bytes, ext);
    return (content: content, fileName: file.name, extension: ext);
  }

  /// 根据文件扩展名读取内容
  Future<String> _readFileContent(Uint8List bytes, String ext) async {
    if (ext == 'xlsx' || ext == 'xls') {
      try {
        final excel = Excel.decodeBytes(bytes);
        final sb = StringBuffer();
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table]!;
          for (final row in sheet.rows) {
            final cells = row.map((c) => c?.value?.toString() ?? '').toList();
            if (cells.every((c) => c.isEmpty)) continue;
            sb.writeln(const ListToCsvConverter().convert([cells]));
          }
        }
        return sb.toString();
      } catch (e) {
        throw Exception('Excel 文件读取失败：$e');
      }
    }

    // CSV：处理 UTF-8 BOM
    var raw = bytes;
    if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
      raw = Uint8List.sublistView(raw, 3);
    }
    return utf8.decode(raw, allowMalformed: true);
  }

  /// 判断内容是否为系统导出格式
  bool isSystemFormat(String content) {
    final rows = const CsvToListConverter().convert(content, shouldParseNumbers: false);
    if (rows.isEmpty) return false;
    final header = rows.first.map((e) => e.toString().trim()).toList();
    return _systemHeaders.every(header.contains);
  }

  /// 解析系统格式 CSV
  ImportResult parseSystemCsv(String content) {
    final rows = const CsvToListConverter().convert(content, shouldParseNumbers: false);
    if (rows.isEmpty) {
      return ImportResult(error: '文件为空');
    }
    final bills = <ImportBill>[];
    var index = 0;
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.toString().trim().isEmpty)) continue;
      try {
        if (row.length < 4) continue;
        final dateStr = row[0].toString().trim();
        final typeStr = row[1].toString().trim();
        final category = row[2].toString().trim();
        final amount = double.tryParse(row[3].toString().trim()) ?? 0;
        final note = row.length > 4 ? row[4].toString().trim() : null;
        final date = _parseDate(dateStr);
        final type = typeStr == '收入' ? TransactionType.income : TransactionType.expense;
        if (amount <= 0 || category.isEmpty || date == null) continue;
        bills.add(ImportBill(
          id: 'sys_$index',
          date: date,
          type: type,
          category: category,
          amount: amount,
          note: note?.isEmpty == true ? null : note,
        ));
        index++;
      } catch (_) {
        // 跳过格式异常行
      }
    }
    return ImportResult(
      bills: bills,
      rawRowCount: rows.length - 1,
      parsedCount: bills.length,
    );
  }

  /// 使用 AI 解析非标准格式内容
  ///
  /// [config] 使用当前激活的文本识别配置。
  Future<ImportResult> parseWithAi({
    required AiModelConfig config,
    required String content,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) async {
    if (config.apiKey.isEmpty || config.modelId.isEmpty) {
      return ImportResult(error: '未配置文本识别模型');
    }

    final response = await _aiService.chat(
      config: config,
      history: const [],
      userMessage: AiChatMessage(
        role: 'user',
        text: '请识别以下文件中的账单记录：\n\n$content',
        time: DateTime.now(),
      ),
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );

    final text = response.text ?? '';
    final bills = _parseAiBills(
      text,
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );
    if (bills.isEmpty) {
      return ImportResult(
        error: 'AI 未能从文件中识别出有效账单',
        aiProcessed: true,
      );
    }
    return ImportResult(
      bills: bills,
      aiProcessed: true,
      parsedCount: bills.length,
    );
  }

  /// 从 AI 回复文本中解析账单数组
  List<ImportBill> _parseAiBills(
    String content, {
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) {
    final results = <ImportBill>[];
    final validCategories = <String>{...expenseCategories, ...incomeCategories};
    var jsonStr = content.trim();

    // 优先匹配 ```json ... ``` 代码块
    if (jsonStr.contains('```')) {
      final matches = RegExp(r'```(?:json)?\s*([\s\S]*?)```').allMatches(jsonStr);
      for (final match in matches) {
        final block = match.group(1)?.trim() ?? '';
        try {
          final decoded = jsonDecode(block);
          if (decoded is Map<String, dynamic> && decoded.containsKey('bills')) {
            final list = decoded['bills'] as List;
            for (var i = 0; i < list.length; i++) {
              final bill = _parseSingleAiBill(
                list[i] as Map<String, dynamic>,
                validCategories: validCategories,
                index: i,
              );
              if (bill != null) results.add(bill);
            }
          }
        } catch (_) {
          // 忽略非 JSON 代码块
        }
      }
      if (results.isNotEmpty) return results;
    }

    // 尝试整体 JSON 解析
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic> && decoded.containsKey('bills')) {
        final list = decoded['bills'] as List;
        for (var i = 0; i < list.length; i++) {
          final bill = _parseSingleAiBill(
            list[i] as Map<String, dynamic>,
            validCategories: validCategories,
            index: i,
          );
          if (bill != null) results.add(bill);
        }
      }
    } catch (_) {
      // 不是 JSON，忽略
    }
    return results;
  }

  ImportBill? _parseSingleAiBill(
    Map<String, dynamic> map, {
    required Set<String> validCategories,
    required int index,
  }) {
    final rawAmount = map['amount'];
    if (rawAmount == null) return null;
    final amount = (rawAmount as num).toDouble();
    if (amount <= 0) return null;

    final typeStr = (map['type'] as String?)?.toLowerCase();
    final type = typeStr == 'income'
        ? TransactionType.income
        : TransactionType.expense;

    var category = (map['category'] as String?)?.trim() ?? '';
    if (category.isEmpty || !validCategories.contains(category)) {
      // 优先回退到"其他"，否则取第一个可用分类
      category = validCategories.contains('其他')
          ? '其他'
          : (validCategories.isEmpty ? '其他' : validCategories.first);
    }
    if (category.isEmpty) return null;

    final date = _parseDate((map['date'] as String?) ?? '') ?? DateTime.now();

    final note = map['note'] as String?;
    return ImportBill(
      id: 'ai_$index',
      date: date,
      type: type,
      category: category,
      amount: amount,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      aiSource: true,
    );
  }

  /// 解析日期字符串
  DateTime? _parseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    const formats = [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd',
      'yyyy/MM/dd HH:mm:ss',
      'yyyy/MM/dd HH:mm',
      'yyyy/MM/dd',
    ];
    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parseLoose(trimmed);
      } catch (_) {
        // 尝试下一种格式
      }
    }
    return null;
  }

  /// 标记与已有账单重复的待导入账单
  ///
  /// 重复标准：同一天、同金额、同类型、同分类。
  Future<List<ImportBill>> markDuplicates({
    required List<ImportBill> bills,
    required int userId,
  }) async {
    if (bills.isEmpty) return bills;
    final existing = await _transactionService.query(
      userId: userId,
      start: DateTime(2000),
      end: DateTime.now().add(const Duration(days: 1)),
    );
    return bills.map((bill) {
      final isDup = existing.any((tx) =>
          tx.amount == bill.amount &&
          tx.type == bill.type &&
          tx.category == bill.category &&
          _isSameDay(tx.date, bill.date));
      return bill.copyWith(isDuplicate: isDup);
    }).toList();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
