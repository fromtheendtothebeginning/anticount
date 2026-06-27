/// 账单/记账交易模型
class Transaction {
  Transaction({
    this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.note,
    this.createdAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == (map['type'] as String),
        orElse: () => TransactionType.expense,
      ),
      category: map['category'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      note: map['note'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final int userId;
  final double amount;
  final TransactionType type;
  final String category;
  final DateTime date;
  final String? note;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'type': type.name,
      'category': category,
      'date': date.millisecondsSinceEpoch,
      'note': note,
      'created_at': createdAt?.millisecondsSinceEpoch,
    };
  }
}

/// 交易类型
enum TransactionType {
  /// 收入
  income,
  /// 支出
  expense;

  String get label {
    switch (this) {
      case TransactionType.income:
        return '收入';
      case TransactionType.expense:
        return '支出';
    }
  }
}
