// 基础冒烟测试。
//
// 完整的 Widget 测试需要 SQLite 环境，这里仅验证关键模型逻辑。
import 'package:flutter_test/flutter_test.dart';

import 'package:anticount/models/transaction.dart';

void main() {
  test('Transaction toMap/fromMap round-trip', () {
    final tx = Transaction(
      userId: 1,
      amount: 12.5,
      type: TransactionType.expense,
      category: '餐饮',
      date: DateTime(2026, 6, 27, 10, 30),
      note: '午餐',
    );
    final map = tx.toMap();
    map['id'] = 42;
    map['created_at'] = tx.date.millisecondsSinceEpoch;
    final restored = Transaction.fromMap(map);

    expect(restored.id, 42);
    expect(restored.userId, 1);
    expect(restored.amount, 12.5);
    expect(restored.type, TransactionType.expense);
    expect(restored.category, '餐饮');
    expect(restored.note, '午餐');
  });

  test('TransactionType labels', () {
    expect(TransactionType.income.label, '收入');
    expect(TransactionType.expense.label, '支出');
  });
}
