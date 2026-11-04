import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqlite_api.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/core/database/supabase_database.dart';
import 'package:masttersystem/core/supabase/supabase_service.dart';
import 'package:masttersystem/services/system_user_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('invalid credentials are rejected before looking up a profile',
      () async {
    final login = await _LoginHarness.create(
      authStatus: 400,
      authError: {
        'error_code': 'invalid_credentials',
        'msg': 'Invalid login credentials',
      },
    );

    expect(await login.authenticate(), isNull);
    expect(login.requests, hasLength(1));
    expect(login.service.hasSession, isFalse);
  });

  test('legacy invalid credentials remain a normal login rejection', () async {
    final login = await _LoginHarness.create(
      authStatus: 400,
      authError: {'error_description': 'Invalid login credentials'},
    );

    expect(await login.authenticate(), isNull);
    expect(login.requests, hasLength(1));
  });

  test('unconfirmed email has a specific message and no profile lookup',
      () async {
    final login = await _LoginHarness.create(
      authStatus: 400,
      authError: {
        'error_code': 'email_not_confirmed',
        'msg': 'Email not confirmed',
      },
    );

    await expectLater(
      login.authenticate(),
      throwsA(isA<SupabaseException>()
          .having((error) => error.code, 'code', 'email_not_confirmed')
          .having((error) => error.message, 'message', contains('Confirme'))),
    );
    expect(login.requests, hasLength(1));
    expect(login.service.hasSession, isFalse);
  });

  test('other Auth failures are not reported as an incorrect password',
      () async {
    for (final status in [400, 401, 403]) {
      final login = await _LoginHarness.create(
        authStatus: status,
        authError: {'message': 'Invalid API key', 'code': 'invalid_api_key'},
      );

      await expectLater(
        login.authenticate(),
        throwsA(isA<SupabaseException>()
            .having((error) => error.code, 'code', 'invalid_api_key')
            .having((error) => error.statusCode, 'statusCode', status)),
      );
      expect(login.requests, hasLength(1));
      expect(login.service.hasSession, isFalse);
    }
  });

  test('valid password without an active profile explains the missing access',
      () async {
    final login = await _LoginHarness.create(profileResponse: []);

    await expectLater(
      login.authenticate(),
      throwsA(isA<SupabaseException>()
          .having((error) => error.code, 'code', 'system_profile_unavailable')
          .having(
              (error) => error.message, 'message', contains('senha aceitos'))
          .having(
              (error) => error.message, 'message', contains('perfil ativo'))),
    );
    expect(login.service.hasSession, isFalse);
    expect(login.service.currentUserId, isNull);
    expect(login.requests, hasLength(2));
    final profileRequest = jsonDecode(login.requests.last.body) as Map;
    expect((profileRequest['payload'] as Map)['operation'], 'query');
  });

  test('profile permission failures never become invalid-password messages',
      () async {
    for (final status in [400, 401, 403]) {
      final login = await _LoginHarness.create(
        profileStatus: status,
        profileResponse: {
          'code': '42501',
          'message': 'permission denied for function matterdi_data',
        },
      );

      await expectLater(
        login.authenticate(),
        throwsA(isA<SupabaseException>()
            .having((error) => error.code, 'code', '42501')
            .having((error) => error.message, 'message',
                contains('permissões do banco'))),
      );
      expect(login.requests, hasLength(2));
      expect(login.service.hasSession, isFalse);
    }
  });

  test('profile installation errors are preserved and the session is cleared',
      () async {
    final login = await _LoginHarness.create(
      profileStatus: 400,
      profileResponse: {
        'code': '42P01',
        'message': 'relation public.system_users does not exist',
      },
    );

    await expectLater(
      login.authenticate(),
      throwsA(isA<SupabaseException>()
          .having((error) => error.code, 'code', '42P01')
          .having(
              (error) => error.message, 'message', contains('does not exist'))),
    );
    expect(login.service.hasSession, isFalse);
  });

  test('inactive or mismatched profiles cannot grant access', () async {
    for (final profile in [
      {..._profile, 'active': 0},
      {..._profile, 'auth_user_id': 'another-user'},
    ]) {
      final login = await _LoginHarness.create(profileResponse: [profile]);

      await expectLater(
        login.authenticate(),
        throwsA(isA<SupabaseException>().having(
            (error) => error.code, 'code', 'system_profile_unavailable')),
      );
      expect(login.requests, hasLength(2));
      expect(login.service.hasSession, isFalse);
    }
  });

  test('active linked profile retains only its existing permissions', () async {
    final login = await _LoginHarness.create(profileResponse: [_profile]);

    final user = await login.authenticate();

    expect(user, isNotNull);
    expect(user!.authUserId, _userId);
    expect(user.isAdmin, isFalse);
    expect(user.permissions, {'customers'});
    expect(login.requests, hasLength(2));
    expect(login.service.hasSession, isTrue);
  });
}

const _userId = '11111111-2222-3333-4444-555555555555';
const _profile = <String, Object?>{
  'id': 7,
  'auth_user_id': _userId,
  'username': 'operator',
  'full_name': 'Operator',
  'email': 'user@example.com',
  'active': 1,
  'is_admin': 0,
  'permissions': ['customers'],
};

class _LoginHarness {
  _LoginHarness(this.service, this.repository, this.requests);

  final SupabaseService service;
  final SystemUserRepository repository;
  final List<http.Request> requests;

  static Future<_LoginHarness> create({
    int authStatus = 200,
    Map<String, Object?>? authError,
    int profileStatus = 200,
    Object? profileResponse = const [],
  }) async {
    final requests = <http.Request>[];
    final service = SupabaseService.forTesting(MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/token') {
        return http.Response(
          jsonEncode(authError ??
              {
                'access_token': 'test-access-token',
                'refresh_token': 'test-refresh-token',
                'expires_in': 3600,
                'user': {'id': _userId},
              }),
          authStatus,
        );
      }
      expect(request.url.path, '/rest/v1/rpc/matterdi_data');
      expect(request.headers['authorization'], 'Bearer test-access-token');
      return http.Response(jsonEncode(profileResponse), profileStatus);
    }));
    await service.configure(
      projectUrl: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_123456789012345678901234567890',
    );
    final database = await SupabaseDatabase.connect(service: service);
    return _LoginHarness(
      service,
      SystemUserRepository(
        database: _CloudAppDatabase(database),
        supabase: service,
      ),
      requests,
    );
  }

  Future<dynamic> authenticate() =>
      repository.authenticate('user@example.com', 'test-password');
}

class _CloudAppDatabase implements AppDatabase {
  _CloudAppDatabase(this._database);
  final Database _database;

  @override
  Future<Database> get database async => _database;

  @override
  Future<bool> isUsingSupabaseDatabase() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
