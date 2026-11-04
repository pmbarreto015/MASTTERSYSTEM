import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:masttersystem/core/supabase/supabase_service.dart';

void main() {
  const projectUrl = 'https://example.supabase.co';
  const publishableKey = 'sb_publishable_123456789012345678901234567890';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('validates public keys and rejects privileged keys', () {
    expect(
      SupabaseService.validatePublishableKey(publishableKey),
      publishableKey,
    );
    expect(
      () => SupabaseService.validatePublishableKey(
        'sb_secret_123456789012345678901234567890',
      ),
      throwsFormatException,
    );

    final serviceRole = _jwt({'role': 'service_role'});
    expect(
      () => SupabaseService.validatePublishableKey(serviceRole),
      throwsFormatException,
    );
    expect(
      SupabaseService.validatePublishableKey(_jwt({'role': 'anon'})),
      isNotEmpty,
    );
  });

  test('connection probe uses apikey without treating it as a JWT', () async {
    final requests = <http.Request>[];
    final service = SupabaseService.forTesting(MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/settings') {
        return http.Response('{}', 200);
      }
      expect(request.url.path, '/rest/v1/rpc/matterdi_health');
      return http.Response(
        jsonEncode({
          'service': 'matterdi-supabase',
          'protocol': 1,
          'version': 29,
          'ready': true,
        }),
        200,
      );
    }));

    await service.testConnection(
      projectUrl: projectUrl,
      publishableKey: publishableKey,
    );

    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.headers['apikey'], publishableKey);
      expect(request.headers['authorization'], isNull);
    }
  });

  test('authenticated RPC sends the user JWT and restores the session',
      () async {
    const userId = '11111111-2222-3333-4444-555555555555';
    final accessToken = _jwt({
      'sub': userId,
      'role': 'authenticated',
    });
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/token') {
        return http.Response(
          jsonEncode({
            'access_token': accessToken,
            'refresh_token': 'refresh-token',
            'expires_in': 3600,
            'user': {'id': userId},
          }),
          200,
        );
      }
      if (request.url.path == '/rest/v1/rpc/matterdi_data') {
        return http.Response('[]', 200);
      }
      return http.Response('not found', 404);
    });
    final service = SupabaseService.forTesting(client);
    await service.configure(
      projectUrl: projectUrl,
      publishableKey: publishableKey,
    );

    expect(
      await service.signInWithPassword(
        email: 'admin@example.com',
        password: 'password-123',
      ),
      userId,
    );
    await service.rpc('matterdi_data', {
      'payload': {'operation': 'query'},
    });

    final rpc = requests.last;
    expect(rpc.headers['apikey'], publishableKey);
    expect(rpc.headers['authorization'], 'Bearer $accessToken');

    final restored = SupabaseService.forTesting(client);
    await restored.configure(
      projectUrl: projectUrl,
      publishableKey: publishableKey,
    );
    expect(await restored.restoreSession(), isTrue);
    expect(restored.currentUserId, userId);
  });
  test('rejects incomplete cloud installation', () async {
    final service = SupabaseService.forTesting(MockClient((request) async =>
        http.Response(
            request.url.path == '/auth/v1/settings'
                ? '{}'
                : jsonEncode({
                    'service': 'matterdi-supabase',
                    'protocol': 1,
                    'version': 29,
                    'ready': false
                  }),
            200)));
    await expectLater(
        service.testConnection(
            projectUrl: projectUrl, publishableKey: publishableKey),
        throwsA(isA<SupabaseException>()));
  });

  test('logout during token persistence cannot restore the session', () async {
    final store = _PausedPreferences();
    SharedPreferencesStorePlatform.instance = store;
    final service =
        SupabaseService.forTesting(MockClient((request) async => http.Response(
            jsonEncode({
              'access_token': _jwt({'sub': 'user-one'}),
              'refresh_token': 'refresh-one',
              'expires_in': 3600,
              'user': {'id': 'user-one'},
            }),
            200)));
    await service.configure(
        projectUrl: projectUrl, publishableKey: publishableKey);
    final login = service.signInWithPassword(
        email: 'user@example.com', password: 'password');
    final canceled = expectLater(login, throwsA(isA<SupabaseException>()));
    await store.started.future;
    final logout = service.signOut();
    expect(service.hasSession, isFalse);
    store.release.complete();
    await Future.wait([canceled, logout]);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getKeys().where((key) => key.startsWith('supabase_')), isEmpty);
    expect(
        (await store.getAll()).keys.where((key) => key.contains('supabase_')),
        isEmpty);
    expect(await service.restoreSession(), isFalse);
  });

  test('invokes the hyphenated user-management Edge function with user JWT',
      () async {
    final requests = <http.Request>[];
    final token = _jwt({'sub': 'user-one'});
    final service = SupabaseService.forTesting(MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/token') {
        return http.Response(
            jsonEncode({
              'access_token': token,
              'refresh_token': 'refresh-one',
              'expires_in': 3600,
              'user': {'id': 'user-one'},
            }),
            200);
      }
      return http.Response('{"ok":true}', 200);
    }));
    await service.configure(
        projectUrl: projectUrl, publishableKey: publishableKey);
    await service.signInWithPassword(
        email: 'user@example.com', password: 'password');
    await service.invokeFunction('matterdi-users', {'action': 'create'});
    expect(requests.last.url.path, '/functions/v1/matterdi-users');
    expect(requests.last.headers['authorization'], 'Bearer $token');
    await expectLater(
        service.invokeFunction('../users', {}), throwsArgumentError);
  });
}

String _jwt(Map<String, Object?> payload) {
  String encode(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode(payload)}.';
}

class _PausedPreferences extends InMemorySharedPreferencesStore {
  _PausedPreferences() : super.empty();
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('supabase_session_project') && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}
