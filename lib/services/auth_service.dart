import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/user.dart';

/// 用户认证服务
///
/// 提供注册、登录、密码重置、账号删除等功能。
/// 使用本地 SQLite + sha256 哈希存储密码，会话通过 SharedPreferences 持久化。
class AuthService {
  AuthService(this._db);
  final Database _db;

  static const _kSessionKey = 'session_user_id';

  String _hash(String password) {
    return sha256.convert(utf8.encode('anticount::$password')).toString();
  }

  /// 注册新用户
  /// 返回新用户实例，失败抛出 [AuthException]
  Future<AppUser> register({
    required String username,
    required String password,
    String? email,
  }) async {
    username = username.trim();
    if (username.isEmpty) {
      throw const AuthException('用户名不能为空');
    }
    if (password.length < 6) {
      throw const AuthException('密码长度至少 6 位');
    }

    try {
      final id = await _db.insert('users', {
        'username': username,
        'password_hash': _hash(password),
        'email': email?.trim().isEmpty == true ? null : email?.trim(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      return AppUser(
        id: id,
        username: username,
        passwordHash: _hash(password),
        email: email,
        createdAt: DateTime.now(),
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const AuthException('用户名已存在');
      }
      rethrow;
    }
  }

  /// 登录
  Future<AppUser> login({
    required String username,
    required String password,
  }) async {
    final rows = await _db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('用户名或密码错误');
    }
    final user = AppUser.fromMap(rows.first);
    if (user.passwordHash != _hash(password)) {
      throw const AuthException('用户名或密码错误');
    }
    await _saveSession(user.id);
    return user;
  }

  /// 重置密码
  ///
  /// 通过用户名校验身份后设置新密码（本地应用，不依赖邮箱）。
  Future<void> resetPassword({
    required String username,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw const AuthException('新密码长度至少 6 位');
    }
    final rows = await _db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('用户名不存在');
    }
    final userId = rows.first['id'] as int;
    await _db.update(
      'users',
      {'password_hash': _hash(newPassword)},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// 修改密码（已登录用户）
  Future<void> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw const AuthException('新密码长度至少 6 位');
    }
    final rows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('用户不存在');
    }
    final user = AppUser.fromMap(rows.first);
    if (user.passwordHash != _hash(oldPassword)) {
      throw const AuthException('原密码错误');
    }
    await _db.update(
      'users',
      {'password_hash': _hash(newPassword)},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// 删除账号（含全部记账数据）
  Future<void> deleteAccount(int userId, String password) async {
    final rows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('用户不存在');
    }
    final user = AppUser.fromMap(rows.first);
    if (user.passwordHash != _hash(password)) {
      throw const AuthException('密码错误');
    }
    await _db.delete('transactions', where: 'user_id = ?', whereArgs: [userId]);
    await _db.delete('users', where: 'id = ?', whereArgs: [userId]);
    await clearSession();
  }

  /// 更新用户资料（昵称、头像）
  Future<AppUser> updateProfile({
    required int userId,
    String? nickname,
    String? avatar,
  }) async {
    await _db.update(
      'users',
      {
        'nickname': nickname?.trim().isEmpty == true ? null : nickname?.trim(),
        'avatar': avatar,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    final rows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('用户不存在');
    }
    return AppUser.fromMap(rows.first);
  }

  /// 保存会话
  Future<void> _saveSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSessionKey, userId);
  }

  /// 清除会话
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
  }

  /// 读取当前登录用户，未登录返回 null
  Future<AppUser?> currentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_kSessionKey);
    if (userId == null) return null;
    final rows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }
}

/// 认证异常
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
