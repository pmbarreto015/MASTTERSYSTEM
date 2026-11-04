import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:masttersystem/core/licensing/offline_license.dart';
import 'package:masttersystem/services/lan_license_api_client.dart';
import 'package:masttersystem/services/license_service.dart';
import 'package:masttersystem/services/offline_license_issuer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late OfflineLicenseIssuer issuer;
  late OfflineLicenseVerifier verifier;
  late DateTime now;
  late LicenseService service;
  var requests = 0;
  var serverAllows = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 15, 12);
    requests = 0;
    serverAllows = true;
    final seed = List<int>.generate(32, (i) => i);
    final key = await Ed25519().newKeyPairFromSeed(seed);
    verifier = OfflineLicenseVerifier(trustedKeys: {
      'test': base64UrlEncode((await key.extractPublicKey()).bytes),
    });
    issuer = OfflineLicenseIssuer(
        privateKeySeed: base64UrlEncode(seed), keyId: 'test');
    service = LicenseService(
      prefs,
      now: () => now,
      platform: 'windows',
      fingerprint: () async => 'desktop-one',
      offlineVerifier: verifier,
      api: LanLicenseApiClient(client: MockClient((_) async {
        requests++;
        return http.Response(
            jsonEncode({
              'success': serverAllows,
              'message': serverAllows ? 'Válida' : 'Bloqueada',
              'token': 'online-token',
              'server_time': now.toIso8601String(),
              'expires_at': now.add(const Duration(days: 2)).toIso8601String(),
            }),
            200);
      })),
    );
  });

  Future<String> key(
          {String? installation,
          String platform = 'windows',
          int hours = 1}) async =>
      issuer.issue(
        customerName: 'Cliente Teste',
        installationCode: installation ?? await service.getInstallationCode(),
        platform: platform,
        expiresAt: now.add(Duration(hours: hours)),
        now: now,
      );

  test('signed key works offline across restart and expires at signed deadline',
      () async {
    final code = await key();
    expect((await service.activateOffline(code)).success, isTrue);
    expect(service.isOfflineLicense, isTrue);
    expect(await service.isActivated(), isTrue);
    expect(requests, 0);
    // Cached display metadata is never authority for the expiration.
    await prefs.setString(
        'license_offline_expiry', DateTime.utc(2099).toIso8601String());
    final restarted = LicenseService(prefs,
        now: () => now,
        platform: 'windows',
        fingerprint: () async => 'desktop-one',
        offlineVerifier: verifier);
    expect(await restarted.isActivated(), isTrue);
    expect(restarted.expiresAt, DateTime.utc(2026, 10, 15, 13));
    now = now.add(const Duration(hours: 1));
    expect(await restarted.isActivated(), isFalse);
    expect(restarted.lastValidationMessage, contains('expirou'));
  });

  test(
      'rejects another installation and another platform without replacing key',
      () async {
    expect((await service.activateOffline(await key())).success, isTrue);
    expect(
        (await service.activateOffline(await key(installation: '000000000001')))
            .success,
        isFalse);
    expect(
        (await service.activateOffline(await key(platform: 'android'))).success,
        isFalse);
    expect(await service.isActivated(), isTrue);
  });

  test('clock rollback blocks key and a new key renews expired access',
      () async {
    expect((await service.activateOffline(await key())).success, isTrue);
    now = now.add(const Duration(minutes: 30));
    expect(await service.isActivated(), isTrue);
    now = now.subtract(const Duration(minutes: 10));
    expect(await service.isActivated(), isFalse);
    expect(service.lastValidationMessage, contains('data e a hora'));
    now = DateTime.utc(2026, 10, 15, 14);
    expect(await service.isActivated(), isFalse);
    expect(
        (await service.activateOffline(await key(hours: 24))).success, isTrue);
    expect(await service.isActivated(), isTrue);
  });

  test('small clock rollbacks across restarts never lower the recorded time',
      () async {
    expect((await service.activateOffline(await key())).success, isTrue);
    now = now.add(const Duration(minutes: 30));
    expect(await service.isActivated(), isTrue);
    final highWater =
        DateTime.parse(prefs.getString('license_offline_last_seen')!);
    for (var i = 0; i < 3; i++) {
      now = highWater.subtract(const Duration(minutes: 1));
      final restarted = LicenseService(prefs,
          now: () => now,
          platform: 'windows',
          fingerprint: () async => 'desktop-one',
          offlineVerifier: verifier);
      expect(await restarted.isActivated(), isTrue);
      expect(
          DateTime.parse(prefs.getString('license_offline_last_seen')!)
              .isBefore(highWater),
          isFalse);
    }
    now = highWater.subtract(const Duration(minutes: 3));
    expect(await service.isActivated(), isFalse);
  });

  test(
      'switching online discards offline authorization and honors server denial',
      () async {
    expect((await service.activateOffline(await key())).success, isTrue);
    expect(
        (await service.activateLan(
                serverAddress: 'https://licenses.example.com',
                login: 'teste',
                password: 'senha123'))
            .success,
        isTrue);
    expect(service.isOfflineLicense, isFalse);
    expect(prefs.containsKey('license_offline_signed_code'), isFalse);
    serverAllows = false;
    expect(await service.isActivated(), isFalse);
    expect(requests, 2);
  });
}
