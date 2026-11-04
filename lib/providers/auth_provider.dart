import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/system_user_model.dart';
import '../core/database/app_database.dart';
import '../core/supabase/supabase_service.dart';
import '../services/system_user_repository.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this.prefs) {
    _checkSession();
  }

  final SharedPreferences prefs;
  final SystemUserRepository _repository = SystemUserRepository();
  SystemUserModel? _currentUser;
  bool _isAuthenticated = false;
  bool _isInitializing = true;
  int _sessionGeneration = 0;
  Future<void> _sessionPersistence = Future<void>.value();

  SystemUserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isInitializing => _isInitializing;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  bool hasPermission(String permission) =>
      _currentUser?.can(permission) ?? false;

  Future<bool> login(String username, String password) async {
    final generation = ++_sessionGeneration;
    final user = await _repository.authenticate(
      username,
      password,
      isCurrent: () => generation == _sessionGeneration,
    );
    if (generation != _sessionGeneration) return false;
    if (user == null) {
      _isInitializing = false;
      notifyListeners();
      return false;
    }
    if (!await _persistProfile(user.toSession(), generation)) return false;
    _currentUser = user;
    _isAuthenticated = true;
    _isInitializing = false;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    final generation = ++_sessionGeneration;
    _currentUser = null;
    _isAuthenticated = false;
    _isInitializing = false;
    final clearing = _persistProfile(null, generation, alwaysRemove: true);
    final cloudLogout =
        prefs.getString(AppDatabase.databaseModeKey) == AppDatabase.supabaseMode
            ? SupabaseService().signOut()
            : Future<void>.value();
    notifyListeners();
    await Future.wait([clearing, cloudLogout]);
  }

  Future<void> _checkSession() async {
    final generation = _sessionGeneration;
    final userData = prefs.getString('user_data');
    if (userData == null) {
      _isInitializing = false;
      notifyListeners();
      return;
    }
    final cloud = prefs.getString(AppDatabase.databaseModeKey) ==
        AppDatabase.supabaseMode;
    try {
      SystemUserModel? current;
      if (cloud) {
        final database = await AppDatabase().database;
        if (generation != _sessionGeneration) return;
        final restored = await SupabaseService().restoreSession();
        if (generation != _sessionGeneration) return;
        if (!restored) {
          await _persistProfile(null, generation);
          return;
        }
        final rows = await database
            .query(
              'system_users',
              where: 'auth_user_id = ? AND active = 1',
              whereArgs: [SupabaseService().currentUserId],
              limit: 1,
            )
            .timeout(const Duration(seconds: 20));
        if (generation != _sessionGeneration) return;
        if (rows.isNotEmpty) current = SystemUserModel.fromMap(rows.first);
      } else {
        final sessionUser = SystemUserModel.fromSession(userData);
        final users =
            await _repository.getAll().timeout(const Duration(seconds: 20));
        if (generation != _sessionGeneration) return;
        for (final user in users) {
          if (user.id == sessionUser.id) {
            current = user;
            break;
          }
        }
      }
      if (current == null || !current.active) {
        await _persistProfile(null, generation);
        if (cloud && generation == _sessionGeneration) {
          await SupabaseService().clearLocalSession();
        }
        return;
      }
      if (!await _persistProfile(current.toSession(), generation)) return;
      _currentUser = current;
      _isAuthenticated = true;
    } catch (_) {
      if (generation == _sessionGeneration) {
        await _persistProfile(null, generation);
        if (cloud && generation == _sessionGeneration) {
          await SupabaseService().clearLocalSession();
        }
      }
    } finally {
      if (generation == _sessionGeneration) {
        _isInitializing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _persistProfile(
    String? value,
    int generation, {
    bool alwaysRemove = false,
  }) {
    final result = _sessionPersistence.then((_) async {
      if (generation != _sessionGeneration && !alwaysRemove) return false;
      if (value == null) {
        await prefs.remove('user_data');
      } else {
        await prefs.setString('user_data', value);
      }
      return generation == _sessionGeneration;
    });
    _sessionPersistence =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
