import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/core/supabase/supabase_service.dart';
import 'package:masttersystem/models/system_user_model.dart';
import 'package:masttersystem/services/system_user_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'cloud creation sends the new account through the authenticated function',
      () async {
    final harness = await _ManagementHarness.create();
    await harness.repository.create(_user);

    expect(harness.requests, hasLength(1));
    final request = harness.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/functions/v1/matterdi-users');
    expect(request.headers['authorization'], 'Bearer test-admin-session');
    expect(request.headers['apikey'], _publicKey);
    final body = jsonDecode(request.body) as Map;
    expect(body['action'], 'create');
    expect(body['password'], _user.password);
    final profile = body['profile'] as Map;
    expect(profile['username'], _user.username);
    expect(profile['email'], _user.email);
    expect(profile['active'], 1);
    expect(profile['is_admin'], 0);
    expect(jsonDecode(profile['permissions'] as String), ['clientes']);
    expect(profile.containsKey('password'), isFalse);
    expect(profile.containsKey('auth_user_id'), isFalse);
    expect(profile.containsKey('id'), isFalse);
  });

  test('missing deployment is explained for create, update and delete',
      () async {
    for (final operation in ['create', 'update', 'delete']) {
      final harness = await _ManagementHarness.create(
        status: 404,
        response: {
          'code': 'NOT_FOUND',
          'message': 'Requested function was not found',
        },
      );
      final pending = switch (operation) {
        'create' => harness.repository.create(_user),
        'update' => harness.repository.update(_linkedUser),
        _ => harness.repository.delete(_linkedUser),
      };
      await expectLater(
        pending,
        throwsA(isA<SupabaseException>()
            .having(
                (error) => error.code, 'code', 'user_management_not_deployed')
            .having((error) => error.statusCode, 'status', 404)
            .having((error) => error.message, 'message',
                contains('matterdi-users'))),
      );
      expect(harness.requests, hasLength(1));
      expect(harness.service.hasSession, isTrue);
    }
  });

  test('missing target profile is not mistaken for a missing function',
      () async {
    final harness = await _ManagementHarness.create(
      status: 404,
      response: {'error': 'Usuario nao encontrado.'},
    );
    await expectLater(
      harness.repository.update(_linkedUser),
      throwsA(isA<SupabaseException>()
          .having(
              (error) => error.message, 'message', 'Usuario nao encontrado.')
          .having((error) => error.code, 'code', isNull)),
    );
  });

  test('authorization and account conflicts preserve the actual failure',
      () async {
    for (final failure in [
      (401, 'Sessao expirada ou invalida.'),
      (403, 'Perfil sem acesso administrativo.'),
      (400, 'A user with this email address has already been registered'),
      (400, 'duplicate key value violates unique constraint'),
    ]) {
      final harness = await _ManagementHarness.create(
        status: failure.$1,
        response: {'error': failure.$2},
      );
      await expectLater(
        harness.repository.create(_user),
        throwsA(isA<SupabaseException>()
            .having((error) => error.statusCode, 'status', failure.$1)
            .having((error) => error.message, 'message', failure.$2)),
      );
      expect(harness.requests, hasLength(1));
    }
  });
}

const _publicKey = 'sb_publishable_123456789012345678901234567890';
const _user = SystemUserModel(
  username: 'operador',
  fullName: 'Operador Teste',
  email: 'operador@example.test',
  password: 'test-password',
  permissions: {'clientes'},
);
const _linkedUser = SystemUserModel(
  id: 4,
  authUserId: '22222222-2222-4222-8222-222222222222',
  username: 'operador',
  fullName: 'Operador Teste',
  email: 'operador@example.test',
  permissions: {'clientes'},
);

class _ManagementHarness {
  _ManagementHarness(this.service, this.repository, this.requests);

  final SupabaseService service;
  final SystemUserRepository repository;
  final List<http.Request> requests;

  static Future<_ManagementHarness> create({
    int status = 200,
    Map<String, Object?> response = const {
      'profile': {'id': 4}
    },
  }) async {
    final requests = <http.Request>[];
    final service = SupabaseService.forTesting(MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        return http.Response(
            jsonEncode({
              'access_token': 'test-admin-session',
              'refresh_token': 'test-refresh',
              'expires_in': 3600,
              'user': {'id': '11111111-1111-4111-8111-111111111111'},
            }),
            200);
      }
      requests.add(request);
      return http.Response(jsonEncode(response), status);
    }));
    await service.configure(
      projectUrl: 'https://example.supabase.co',
      publishableKey: _publicKey,
    );
    await service.signInWithPassword(
      email: 'admin@example.test',
      password: 'test-admin-password',
    );
    return _ManagementHarness(
      service,
      SystemUserRepository(database: _CloudModeOnly(), supabase: service),
      requests,
    );
  }
}

class _CloudModeOnly implements AppDatabase {
  @override
  Future<bool> isUsingSupabaseDatabase() async => true;

  // Cloud account management must never fall back to SQLite on a remote error.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected database access: ${invocation.memberName}');
}
