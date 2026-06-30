import 'package:sqflite/sqflite.dart' hide Transaction;

import '../models/transaction.dart';

/// 记账/账单查询服务
class TransactionService {
  TransactionService(this._db);
  final Database _db;

  /// 新增一条记账
  Future<Transaction> add(Transaction tx) async {
    final map = tx.toMap();
    map['created_at'] = DateTime.now().millisecondsSinceEpoch;
    final id = await _db.insert('transactions', map);
    return Transaction(
      id: id,
      userId: tx.userId,
      amount: tx.amount,
      type: tx.type,
      category: tx.category,
      date: tx.date,
      note: tx.note,
      createdAt: DateTime.now(),
    );
  }

  /// 更新记账
  Future<int> update(Transaction tx) {
    return _db.update(
      'transactions',
      tx.toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [tx.id, tx.userId],
    );
  }

  /// 删除记账
  Future<int> delete(int id, int userId) {
    return _db.delete(
      'transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  /// 查询账单列表
  ///
  /// [start]/[end] 时间范围（闭区间）；[type] 类型过滤；[category] 分类过滤。
  Future<List<Transaction>> query({
    required int userId,
    DateTime? start,
    DateTime? end,
    TransactionType? type,
    String? category,
    String? keyword,
  }) async {
    final where = StringBuffer('user_id = ?');
    final args = <dynamic>[userId];

    if (start != null) {
      where.write(' AND date >= ?');
      args.add(start.millisecondsSinceEpoch);
    }
    if (end != null) {
      where.write(' AND date <= ?');
      args.add(end.millisecondsSinceEpoch);
    }
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    }
    if (category != null && category.trim().isNotEmpty) {
      where.write(' AND category = ?');
      args.add(category.trim());
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.write(' AND note LIKE ?');
      args.add('%${keyword.trim()}%');
    }

    final rows = await _db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Transaction.fromMap).toList();
  }

  /// 统计：指定时间范围内的总收入/总支出
  Future<({double income, double expense})> summary({
    required int userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final where = StringBuffer('user_id = ?');
    final args = <dynamic>[userId];
    if (start != null) {
      where.write(' AND date >= ?');
      args.add(start.millisecondsSinceEpoch);
    }
    if (end != null) {
      where.write(' AND date <= ?');
      args.add(end.millisecondsSinceEpoch);
    }

    final rows = await _db.rawQuery(
      'SELECT type, SUM(amount) AS total FROM transactions '
      'WHERE $where GROUP BY type',
      args,
    );
    double income = 0, expense = 0;
    for (final row in rows) {
      final t = row['type'] as String?;
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      if (t == TransactionType.income.name) {
        income = total;
      } else if (t == TransactionType.expense.name) {
        expense = total;
      }
    }
    return (income: income, expense: expense);
  }

  /// 统计：指定时间范围内的交易笔数
  Future<int> count({
    required int userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final where = StringBuffer('user_id = ?');
    final args = <dynamic>[userId];
    if (start != null) {
      where.write(' AND date >= ?');
      args.add(start.millisecondsSinceEpoch);
    }
    if (end != null) {
      where.write(' AND date <= ?');
      args.add(end.millisecondsSinceEpoch);
    }

    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM transactions WHERE $where',
      args,
    );
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }
}
