import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/database/app_database.dart';
import '../core/supabase/supabase_service.dart';
import '../models/system_user_model.dart';

class SystemUserRepository {
  SystemUserRepository({AppDatabase? database, SupabaseService? supabase})
      : _db = database ?? AppDatabase(),
        _supabase = supabase ?? SupabaseService();

  final AppDatabase _db;
  final SupabaseService _supabase;

  String _hashPassword(String password) {
    final random = Random.secure();
    final salt = base64UrlEncode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    );
    final digest = sha256.convert(utf8.encode('$salt:$password'));
    return '$salt:$digest';
  }

  bool _verifyPassword(String stored, String password) {
    final separator = stored.indexOf(':');
    if (separator < 0) return stored == password;
    final salt = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    final actual = sha256.convert(utf8.encode('$salt:$password')).toString();
    return actual == expected;
  }

  Future<void> ensureAdmin() async {
    if (await _db.isUsingSupabaseDatabase()) return;
    final database = await _db.database;
    final existing = await database.query(
      'system_users',
      columns: ['id'],
      where: 'username = ?',
      whereArgs: ['admin'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final admin = SystemUserModel(
      username: 'admin',
      fullName: 'Administrador do Sistema',
      email: 'admin@matterdi.com',
      password: _hashPassword('admin123'),
      isAdmin: true,
    );
    final map = admin.toMap()..remove('id');
    await database.insert('system_users', map);
  }

  Future<SystemUserModel?> authenticate(
    String username,
    String password, {
    bool Function()? isCurrent,
  }) async {
    if (await _db.isUsingSupabaseDatabase()) {
      final database = await _db.database;
      if (isCurrent?.call() == false) return null;
      late String userId;
      try {
        userId = await _supabase.signInWithPassword(
          email: username,
          password: password,
        );
      } on SupabaseException catch (error) {
        if (isCurrent?.call() == false) return null;
        await _supabase.clearLocalSession();
        if (error.code == 'invalid_credentials' ||
            (error.code == null &&
                error.message.trim().toLowerCase() ==
                    'invalid login credentials')) {
          return null;
        }
        if (error.code == 'email_not_confirmed' ||
            (error.code == null &&
                error.message.trim().toLowerCase() == 'email not confirmed')) {
          throw SupabaseException(
            'Confirme seu e-mail no Supabase antes de entrar no sistema.',
            statusCode: error.statusCode,
            code: 'email_not_confirmed',
          );
        }
        rethrow;
      }
      if (isCurrent?.call() == false) return null;
      try {
        final rows = await database.query(
          'system_users',
          where: 'auth_user_id = ? AND active = 1',
          whereArgs: [userId],
          limit: 1,
        );
        if (isCurrent?.call() == false) return null;
        if (rows.isEmpty) {
          throw const SupabaseException(
            'E-mail e senha aceitos, mas não foi encontrado um perfil ativo '
            'para este usuário no sistema. Peça ao administrador para '
            'verificar o vínculo e as permissões de acesso.',
            code: 'system_profile_unavailable',
          );
        }
        final user = SystemUserModel.fromMap(rows.first);
        if (!user.active || user.authUserId != userId) {
          throw const SupabaseException(
            'E-mail e senha aceitos, mas o perfil retornado não permite '
            'acesso ao sistema. Peça ao administrador para verificar seu '
            'cadastro.',
            code: 'system_profile_unavailable',
          );
        }
        return user;
      } catch (error) {
        if (isCurrent?.call() == false) return null;
        await _supabase.clearLocalSession();
        if (error is SupabaseException &&
            (error.statusCode == 401 ||
                error.statusCode == 403 ||
                error.code == '42501')) {
          throw SupabaseException(
            'E-mail e senha aceitos, mas o Supabase não permitiu consultar '
            'seu perfil de acesso. Peça ao administrador para verificar '
            'a instalação e as permissões do banco.',
            statusCode: error.statusCode,
            code: error.code,
          );
        }
        rethrow;
      }
    }
    await ensureAdmin();
    final database = await _db.database;
    final rows = await database.query(
      'system_users',
      where: 'LOWER(username) = LOWER(?) AND active = 1',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final user = SystemUserModel.fromMap(rows.first);
    if (!_verifyPassword(user.password, password)) return null;
    if (!user.password.contains(':')) {
      await database.update(
        'system_users',
        {'password': _hashPassword(password)},
        where: 'id = ?',
        whereArgs: [user.id],
      );
    }
    return user;
  }

  Future<List<SystemUserModel>> getAll() async {
    final cloud = await _db.isUsingSupabaseDatabase();
    if (!cloud) await ensureAdmin();
    final database = await _db.database;
    final rows = await database.query(
      'system_users',
      orderBy: 'is_admin DESC, full_name COLLATE NOCASE',
    );
    return rows.map(SystemUserModel.fromMap).toList();
  }

  Future<void> create(SystemUserModel user) async {
    if (await _db.isUsingSupabaseDatabase()) {
      await _invokeUserFunction({
        'action': 'create',
        'profile': _cloudProfile(user),
        'password': user.password,
      });
      return;
    }
    final database = await _db.database;
    final map = user.toMap()
      ..remove('id')
      ..['password'] = _hashPassword(user.password);
    await database.insert('system_users', map);
  }

  Future<void> update(SystemUserModel user, {String? newPassword}) async {
    if (await _db.isUsingSupabaseDatabase()) {
      await _invokeUserFunction({
        'action': 'update',
        'profile': _cloudProfile(user),
        if (newPassword != null && newPassword.isNotEmpty)
          'password': newPassword,
      });
      return;
    }
    final database = await _db.database;
    final map = user.toMap()
      ..remove('id')
      ..remove('created_at');
    if (newPassword == null || newPassword.isEmpty) {
      map.remove('password');
    } else {
      map['password'] = _hashPassword(newPassword);
    }
    await database.update(
      'system_users',
      map,
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> updateAdminPassword(
    SystemUserModel user,
    String newPassword,
  ) async {
    if (!user.isAdmin || user.id == null) {
      throw StateError('Administrador principal nao encontrado.');
    }
    if (await _db.isUsingSupabaseDatabase()) {
      if (user.authUserId == _supabase.currentUserId) {
        await _supabase.updateOwnPassword(newPassword);
      } else {
        await _invokeUserFunction({
          'action': 'update',
          'profile': _cloudProfile(user),
          'password': newPassword,
        });
      }
      return;
    }
    final database = await _db.database;
    await database.update(
      'system_users',
      {
        'password': _hashPassword(newPassword),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND is_admin = 1',
      whereArgs: [user.id],
    );
  }

  Future<void> delete(SystemUserModel user) async {
    if (user.isAdmin) {
      throw StateError('O administrador principal não pode ser excluído.');
    }
    if (await _db.isUsingSupabaseDatabase()) {
      await _invokeUserFunction({
        'action': 'delete',
        'profile': _cloudProfile(user),
      });
      return;
    }
    final database = await _db.database;
    await database.delete(
      'system_users',
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> _invokeUserFunction(Map<String, Object?> body) async {
    try {
      await _supabase.invokeFunction('matterdi-users', body);
    } on SupabaseException catch (error) {
      if (error.statusCode == 404 && error.code == 'NOT_FOUND') {
        throw const SupabaseException(
          'O serviço de usuários ainda não foi publicado no Supabase. '
          'Publique a função matterdi-users em Edge Functions e tente novamente.',
          statusCode: 404,
          code: 'user_management_not_deployed',
        );
      }
      rethrow;
    }
  }

  Map<String, dynamic> _cloudProfile(SystemUserModel user) {
    final map = user.toMap(includeAuthUserId: true)
      ..remove('password')
      ..remove('created_at')
      ..remove('updated_at');
    if (map['id'] == null) map.remove('id');
    if (map['auth_user_id'] == null) map.remove('auth_user_id');
    return map;
  }
}
