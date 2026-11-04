import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:masttersystem/services/lan_license_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These tests exercise the actual local HTTP protocol.
  HttpOverrides.global = null;

  late Directory temporaryDirectory;
  late File dataFile;
  late LanLicenseServer server;
  late http.Client client;
  late String url;
  late DateTime now;

  Future<void> startServer() async {
    server = await LanLicenseServer.createForTesting(dataFile, now: () => now);
    await server.start(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      enableDiscovery: false,
    );
    expect(server.serverError, isNull);
    expect(server.boundPort, isNotNull);
    url = 'http://127.0.0.1:${server.boundPort}';
  }

  Future<void> reloadServer() async {
    await server.stop();
    server.dispose();
    await startServer();
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await client.post(
      Uri.parse('$url$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    expect(response.statusCode, HttpStatus.ok);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<LanLicenseCustomer> createCustomer({
    DateTime? expiresAt,
    String allowedPlatform = 'both',
    int maxDevices = 2,
  }) async {
    expect(
      await server.createCustomer(
        name: 'Cliente de teste',
        login: 'cliente',
        password: 'senha123',
        maxDevices: maxDevices,
        expiresAt: expiresAt,
        allowedPlatform: allowedPlatform,
      ),
      isNull,
    );
    return server.customers.single;
  }

  Future<Map<String, dynamic>> activate({
    String machineCode = '123456789012',
    String? platform,
    String machineName = 'Dispositivo de teste',
    String password = 'senha123',
  }) =>
      post('/activate', {
        'login': 'cliente',
        'password': password,
        'machine_code': machineCode,
        'machine_name': machineName,
        if (platform != null) 'platform': platform,
      });

  Future<Map<String, dynamic>> validate(
    String token, {
    String machineCode = '123456789012',
    String? platform,
  }) =>
      post('/validate', {
        'token': token,
        'machine_code': machineCode,
        if (platform != null) 'platform': platform,
      });

  setUp(() async {
    now = DateTime.utc(2026, 10, 14, 12);
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'masttersystem_license_test_',
    );
    dataFile = File('${temporaryDirectory.path}/licenses.json');
    client = http.Client();
    await startServer();
  });

  tearDown(() async {
    client.close();
    await server.stop();
    server.dispose();
    // Only the directory returned by createTemp above is removed.
    await temporaryDirectory.delete(recursive: true);
  });

  test('rejects elapsed deadlines and invalid license settings', () async {
    Future<String?> create({
      DateTime? expiresAt,
      String allowedPlatform = 'both',
      int maxDevices = 1,
    }) =>
        server.createCustomer(
          name: 'Cliente',
          login: 'cliente',
          password: 'senha123',
          maxDevices: maxDevices,
          expiresAt: expiresAt,
          allowedPlatform: allowedPlatform,
        );

    expect(await create(expiresAt: now), isNotNull);
    expect(
      await create(expiresAt: now.subtract(const Duration(seconds: 1))),
      isNotNull,
    );
    expect(await create(allowedPlatform: 'linux'), isNotNull);
    expect(await create(maxDevices: 0), isNotNull);
    expect(await create(maxDevices: 1000), isNotNull);
    expect(server.customers, isEmpty);

    final offsetExpiry = DateTime.parse('2026-10-14T11:00:00-03:00');
    final customer = await createCustomer(expiresAt: offsetExpiry);
    expect(customer.expiresAt!.isUtc, isTrue);
    expect(customer.expiresAt, DateTime.utc(2026, 10, 14, 14));
    expect(customer.createdAt, now);
    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: now,
        allowedPlatform: 'both',
        maxDevices: 2,
      ),
      isNotNull,
    );
    expect(customer.expiresAt, offsetExpiry);
  });

  test('blocks activation and validation at the exact expiration boundary',
      () async {
    final expiration = now.add(const Duration(hours: 1));
    final customer = await createCustomer(expiresAt: expiration);
    final activation = await activate(platform: 'windows');
    final token = activation['token'] as String;
    expect(activation['success'], isTrue);
    expect(activation['expires_at'], expiration.toIso8601String());
    expect(activation['server_time'], now.toIso8601String());
    expect(activation['allowed_platform'], 'both');
    expect(customer.devices.single.activatedAt, now);

    now = expiration.subtract(const Duration(microseconds: 1));
    expect((await validate(token))['success'], isTrue);
    final lastSuccessfulSeen = customer.devices.single.lastSeenAt;
    expect(customer.isExpiredAt(now), isFalse);

    now = expiration;
    expect(customer.isExpiredAt(now), isTrue);
    final expiredValidation = await validate(token, platform: 'windows');
    expect(expiredValidation['success'], isFalse);
    expect(expiredValidation['error_code'], 'expired');
    expect(expiredValidation['expires_at'], expiration.toIso8601String());
    expect(expiredValidation['server_time'], expiration.toIso8601String());
    expect((await activate())['error_code'], 'expired');
    expect(
      (await activate(
          machineCode: '222222222222', platform: 'android'))['error_code'],
      'expired',
    );
    expect(customer.devices, hasLength(1));
    expect(customer.devices.single.lastSeenAt, lastSuccessfulSeen);

    now = expiration.add(const Duration(days: 1));
    expect((await validate(token))['error_code'], 'expired');
  });

  test('renewal restores the same token and survives a server restart',
      () async {
    final customer = await createCustomer(
      expiresAt: now.add(const Duration(minutes: 5)),
      allowedPlatform: 'windows',
    );
    final activation = await activate();
    final token = activation['token'] as String;
    now = now.add(const Duration(minutes: 5));
    expect((await validate(token))['error_code'], 'expired');

    final renewedExpiration = now.add(const Duration(days: 7));
    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: renewedExpiration,
        allowedPlatform: 'windows',
        maxDevices: 3,
      ),
      isNull,
    );
    final renewed = await validate(token);
    expect(renewed['success'], isTrue);
    expect(renewed['expires_at'], renewedExpiration.toIso8601String());
    expect(renewed['max_devices'], 3);
    expect(renewed['used_devices'], 1);

    await reloadServer();
    expect(server.customers.single.expiresAt, renewedExpiration);
    expect(server.customers.single.allowedPlatform, 'windows');
    expect(server.customers.single.devices.single.platform, 'windows');
    expect((await validate(token))['success'], isTrue);

    expect(
      await server.updateCustomerLicense(
        customer: server.customers.single,
        expiresAt: null,
        allowedPlatform: 'both',
        maxDevices: 3,
      ),
      isNull,
    );
    now = now.add(const Duration(days: 3650));
    final permanent = await validate(token);
    expect(permanent['success'], isTrue);
    expect(permanent['expires_at'], isNull);
  });

  test('enforces Android and Windows permissions on activation and validation',
      () async {
    final customer = await createCustomer(allowedPlatform: 'android');
    expect((await activate())['error_code'], 'platform_not_allowed');
    expect((await activate(platform: 'linux'))['error_code'],
        'platform_not_allowed');
    expect(customer.devices, isEmpty);

    final activation = await activate(platform: 'android');
    final token = activation['token'] as String;
    expect(activation['success'], isTrue);
    expect(customer.devices.single.platform, 'android');
    expect((await validate(token, platform: 'android'))['success'], isTrue);
    expect((await validate(token))['error_code'], 'platform_not_allowed');
    expect((await validate(token, platform: 'windows'))['error_code'],
        'platform_not_allowed');

    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: null,
        allowedPlatform: 'windows',
        maxDevices: 2,
      ),
      isNull,
    );
    // A client cannot bypass a restriction by claiming a different platform.
    expect((await validate(token))['error_code'], 'platform_not_allowed');
    expect((await validate(token, platform: 'windows'))['error_code'],
        'platform_not_allowed');

    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: null,
        allowedPlatform: 'both',
        maxDevices: 2,
      ),
      isNull,
    );
    expect((await validate(token, platform: 'android'))['success'], isTrue);
    expect((await activate(platform: 'windows'))['error_code'],
        'platform_not_allowed');
    expect(
      (await activate(
          machineCode: '222222222222', platform: 'windows'))['success'],
      isTrue,
    );
    expect(customer.devices, hasLength(2));
    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: null,
        allowedPlatform: 'both',
        maxDevices: 1,
      ),
      isNotNull,
    );
    expect(customer.maxDevices, 2);
  });

  test('retains device limits, blocking, reactivation and release behavior',
      () async {
    final customer = await createCustomer(maxDevices: 1);
    final activation = await activate();
    final token = activation['token'] as String;
    expect((await activate(password: 'incorreta'))['error_code'],
        'invalid_credentials');
    final reactivation = await activate(machineName: 'Nome atualizado');
    expect(reactivation['success'], isTrue);
    expect(reactivation['token'], token);
    expect(customer.devices.single.machineName, 'Nome atualizado');
    expect(
      (await activate(
          machineCode: '222222222222', platform: 'android'))['error_code'],
      'device_limit',
    );

    await server.setCustomerActive(customer, false);
    expect((await activate())['error_code'], 'blocked');
    expect((await validate(token))['error_code'], 'blocked');
    await server.setCustomerActive(customer, true);
    expect((await validate(token))['success'], isTrue);

    await server.releaseDevice(customer, customer.devices.single);
    expect((await validate(token))['error_code'], 'unauthorized');
    expect(
      (await activate(
          machineCode: '222222222222', platform: 'android'))['success'],
      isTrue,
    );
  });

  test('loads previous signed records as permanent Windows device licenses',
      () async {
    final customer = await createCustomer();
    final activation = await activate();
    final token = activation['token'] as String;

    final legacyCustomer = customer.toJson()
      ..remove('expires_at')
      ..remove('allowed_platform');
    final legacyDevice = customer.devices.single.toJson()..remove('platform');
    legacyCustomer['devices'] = [legacyDevice];
    await server.stop();
    server.dispose();
    // Recreate the version-1 on-disk format used before timed licensing.
    final payload = utf8.encode(jsonEncode({
      'version': 1,
      'customers': [legacyCustomer],
    }));
    await dataFile.writeAsString(jsonEncode({
      'payload': base64Encode(payload),
      'signature': Hmac(
        sha256,
        utf8.encode('MastterSystem-LAN-License-Store-2026-7e51c94b'),
      ).convert(payload).toString(),
    }));
    now = now.add(const Duration(days: 3650));
    await startServer();

    final restored = server.customers.single;
    expect(restored.expiresAt, isNull);
    expect(restored.allowedPlatform, 'both');
    expect(restored.devices.single.platform, 'windows');
    expect((await validate(token))['success'], isTrue);
    expect(
      (await activate(
          machineCode: '222222222222', platform: 'android'))['success'],
      isTrue,
    );
    await reloadServer();
    expect(server.customers.single.expiresAt, isNull);
    expect(server.customers.single.devices.map((item) => item.platform),
        ['windows', 'android']);
  });

  test('corrupt license files block startup and cannot be overwritten',
      () async {
    await server.stop();
    server.dispose();
    const corrupted = '{"payload":"invalid","signature":"invalid"}';
    await dataFile.writeAsString(corrupted);
    server = await LanLicenseServer.createForTesting(dataFile, now: () => now);
    final error = server.serverError;
    expect(error, isNotNull);
    expect(server.customers, isEmpty);
    await server.start(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      enableDiscovery: false,
    );
    expect(server.isRunning, isFalse);
    expect(server.serverError, error);
    expect(
      await server.createCustomer(
        name: 'Cliente',
        login: 'cliente',
        password: 'senha123',
        maxDevices: 1,
      ),
      error,
    );
    expect(server.customers, isEmpty);
    expect(await dataFile.readAsString(), corrupted);
  });

  test('failed admin writes roll back and subsequent writes can recover',
      () async {
    final customer = await createCustomer();
    final activation = await activate();
    final device = customer.devices.single;
    final stored = await dataFile.readAsString();
    // A directory where the temporary file belongs reliably causes write
    // failures on Windows and Unix without changing host permissions.
    final blocker = Directory('${dataFile.path}.tmp');
    await blocker.create();

    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: now.add(const Duration(days: 1)),
        allowedPlatform: 'android',
        maxDevices: 3,
      ),
      isNotNull,
    );
    expect(customer.expiresAt, isNull);
    expect(customer.allowedPlatform, 'both');
    expect(customer.maxDevices, 2);
    await expectLater(
      server.setCustomerActive(customer, false),
      throwsA(isA<StateError>()),
    );
    expect(customer.active, isTrue);
    await expectLater(
      server.releaseDevice(customer, device),
      throwsA(isA<StateError>()),
    );
    expect(customer.devices.single, same(device));
    expect(
      await server.createCustomer(
        name: 'Outro cliente',
        login: 'outro',
        password: 'senha123',
        maxDevices: 1,
      ),
      isNotNull,
    );
    expect(server.customers.single, same(customer));
    expect(await dataFile.readAsString(), stored);
    final unavailable = await validate(activation['token'] as String);
    expect(unavailable['success'], isFalse);
    expect(unavailable['error_code'], 'storage_unavailable');
    expect(unavailable['retryable'], isTrue);

    await blocker.delete();
    expect(
      await server.updateCustomerLicense(
        customer: customer,
        expiresAt: now.add(const Duration(days: 2)),
        allowedPlatform: 'both',
        maxDevices: 3,
      ),
      isNull,
    );
    expect(server.serverError, isNull);
    expect((await validate(activation['token'] as String))['success'], isTrue);
    await reloadServer();
    expect(server.customers.single.expiresAt, now.add(const Duration(days: 2)));
    expect(server.customers.single.maxDevices, 3);
    expect(server.customers.single.devices.single.token, activation['token']);
  });

  test('failed activation returns no token and HTTP retries safely recover',
      () async {
    final customer = await createCustomer();
    final blocker = Directory('${dataFile.path}.tmp');
    await blocker.create();
    final failed = await activate();
    expect(failed['success'], isFalse);
    expect(failed['error_code'], 'storage_unavailable');
    expect(failed['token'], isNull);
    expect(customer.devices, isEmpty);

    await blocker.delete();
    final activation = await activate(machineName: 'Nome original');
    final token = activation['token'] as String;
    expect(activation['success'], isTrue);
    final device = customer.devices.single;
    final lastSeen = device.lastSeenAt;
    now = now.add(const Duration(minutes: 1));
    await blocker.create();
    expect((await activate(machineName: 'Nome rejeitado'))['error_code'],
        'storage_unavailable');
    expect(device.machineName, 'Nome original');
    expect(device.lastSeenAt, lastSeen);
    expect((await validate(token))['error_code'], 'storage_unavailable');
    expect(device.lastSeenAt, lastSeen);

    await blocker.delete();
    expect((await validate(token))['success'], isTrue);
    expect(device.lastSeenAt, now);
    expect(server.serverError, isNull);
    expect(customer.devices, hasLength(1));
    await reloadServer();
    expect(server.customers.single.devices.single.token, token);
    expect(server.customers.single.devices.single.machineName, 'Nome original');
  });

  test('concurrent activation requests preserve the device limit', () async {
    final customer = await createCustomer(maxDevices: 1);
    final responses = await Future.wait(
      List.generate(
        5,
        (index) => activate(machineCode: '${index + 1}11111111111'),
      ),
    );
    expect(
        responses.where((result) => result['success'] == true), hasLength(1));
    expect(
      responses.where((result) => result['error_code'] == 'device_limit'),
      hasLength(4),
    );
    expect(customer.devices, hasLength(1));
    await reloadServer();
    expect(server.customers.single.devices, hasLength(1));
  });
}
