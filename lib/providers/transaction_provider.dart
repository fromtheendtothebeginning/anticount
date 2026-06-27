import 'package:flutter/foundation.dart';

import '../models/transaction.dart';
import '../services/transaction_service.dart';

/// 账单/记账状态
class TransactionProvider extends ChangeNotifier {
  TransactionProvider(this._service);

  final TransactionService _service;

  List<Transaction> _items = const [];
  bool _loading = false;
  String? _error;

  // 查询条件
  DateTime? _start;
  DateTime? _end;
  TransactionType? _typeFilter;
  String? _categoryFilter;
  String? _keyword;

  List<Transaction> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  DateTime? get start => _start;
  DateTime? get end => _end;
  TransactionType? get typeFilter => _typeFilter;
  String? get categoryFilter => _categoryFilter;
  String? get keyword => _keyword;

  /// 设置过滤条件并刷新
  Future<void> setFilters({
    DateTime? start,
    DateTime? end,
    TransactionType? typeFilter,
    String? categoryFilter,
    String? keyword,
    bool clear = false,
  }) async {
    if (clear) {
      _start = null;
      _end = null;
      _typeFilter = null;
      _categoryFilter = null;
      _keyword = null;
    } else {
      _start = start;
      _end = end;
      _typeFilter = typeFilter;
      _categoryFilter = categoryFilter;
      _keyword = keyword;
    }
    await refresh();
  }

  Future<void> refresh({int? userId}) async {
    if (userId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _service.query(
        userId: userId,
        start: _start,
        end: _end,
        type: _typeFilter,
        category: _categoryFilter,
        keyword: _keyword,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> add(Transaction tx) async {
    try {
      _error = null;
      await _service.add(tx);
      await refresh(userId: tx.userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> update(Transaction tx) async {
    try {
      _error = null;
      await _service.update(tx);
      await refresh(userId: tx.userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> delete(int id, int userId) async {
    try {
      _error = null;
      await _service.delete(id, userId);
      await refresh(userId: userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 统计当前过滤条件下的收支
  Future<({double income, double expense})> summary(int userId) {
    return _service.summary(
      userId: userId,
      start: _start,
      end: _end,
    );
  }
}
