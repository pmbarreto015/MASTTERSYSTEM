import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masttersystem/services/lan_license_api_client.dart';
import 'package:masttersystem/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final serverTime = DateTime.utc(2026, 10, 14, 12);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('trial uses server time, sends platform and denies offline access',
      () async {
    var online = true;
    final prefs = await SharedPreferences.getInstance();
    final expiry = serverTime.add(const Duration(hours: 1));
    final api = LanLicenseApiClient(client: MockClient((request) async {
      if (!online) return http.Response('{}', 503);
      expect(jsonDecode(request.body)['platform'], 'android');
      return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Válida',
            'token': 'token',
            'expires_at': expiry.toIso8601String(),
            'server_time': serverTime.toIso8601String(),
          }),
          200);
    }));
    final service = LicenseService(prefs,
        api: api,
        platform: 'android',
        now: () => DateTime.utc(2000),
        fingerprint: () async => 'phone-one');
    expect(
        (await service.activateLan(
                serverAddress: 'localhost',
                login: 'teste',
                password: 'senha123'))
            .success,
        isTrue);
    expect(service.expiresAt, expiry);
    expect(service.remainingLicenseTime!.inMinutes, inInclusiveRange(59, 60));
    expect(await service.isActivated(), isTrue);
    online = false;
    expect(await service.isActivated(), isFalse);
    expect(service.lastValidationMessage, contains('Conecte-se'));
    final restarted = LicenseService(prefs,
        api: api,
        platform: 'android',
        now: () => DateTime.utc(2000),
        fingerprint: () async => 'phone-one');
    expect(await restarted.isActivated(), isFalse);
  });

  test('permanent grace survives an outage but cannot bypass a server denial',
      () async {
    var response = 'valid';
    final prefs = await SharedPreferences.getInstance();
    final service = LicenseService(prefs,
        now: () => serverTime,
        fingerprint: () async => 'desktop-one',
        api: LanLicenseApiClient(client: MockClient((request) async {
          if (response == 'offline') return http.Response('{}', 503);
          return http.Response(
              jsonEncode({
                'success': response == 'valid',
                'message': response,
                'token': 'token',
                'expires_at': null,
                'server_time': serverTime.toIso8601String(),
              }),
              200);
        })));
    await service.activateLan(
        serverAddress: 'localhost', login: 'teste', password: 'senha123');
    response = 'offline';
    expect(await service.isActivated(), isTrue);
    response = 'blocked';
    expect(await service.isActivated(), isFalse);
    response = 'offline';
    expect(await service.isActivated(), isFalse);
    response = 'valid';
    expect(await service.isActivated(), isTrue);
  });

  test('mobile installations retain distinct identities across restarts',
      () async {
    final firstPrefs = await SharedPreferences.getInstance();
    final first = await LicenseService(firstPrefs, platform: 'android')
        .getInstallationCode();
    expect(
        await LicenseService(firstPrefs, platform: 'android')
            .getInstallationCode(),
        first);
    SharedPreferences.setMockInitialValues({});
    final secondPrefs = await SharedPreferences.getInstance();
    final second = await LicenseService(secondPrefs, platform: 'android')
        .getInstallationCode();
    expect(second, isNot(first));
    expect(first, matches(RegExp(r'^\d{12}$')));
  });

  test('malformed trial deadline is rejected instead of becoming permanent',
      () async {
    final api = LanLicenseApiClient(
        client: MockClient((_) async => http.Response(
            jsonEncode({'success': true, 'expires_at': 'invalid'}), 200)));
    final result = await api.validate(
        serverAddress: 'localhost',
        token: 'token',
        machineCode: '123456789012');
    expect(result.success, isFalse);
    expect(result.retryable, isFalse);
  });

  test('server addresses preserve HTTPS and explicit ports', () {
    expect(LanLicenseApiClient.normalizeServerAddress('192.168.0.10'),
        'http://192.168.0.10:8787');
    expect(
        LanLicenseApiClient.normalizeServerAddress('https://lic.example.com/'),
        'https://lic.example.com');
    expect(LanLicenseApiClient.normalizeServerAddress('http://localhost:9999/'),
        'http://localhost:9999');
    expect(LanLicenseApiClient.normalizeServerAddress('licencas.onrender.com'),
        'https://licencas.onrender.com');
    expect(
        () => LanLicenseApiClient.normalizeServerAddress(
            'http://licencas.example.com'),
        throwsFormatException);
    expect(
        () =>
            LanLicenseApiClient.normalizeServerAddress('http://host/activate'),
        throwsFormatException);
  });
}
