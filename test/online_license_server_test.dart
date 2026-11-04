import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:masttersystem/services/lan_license_server.dart';
import 'package:masttersystem/services/license_server_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const adminToken = 'test-only-admin-token-with-at-least-32-characters';
  late Directory temporary;
  late LicenseServerCore server;
  late http.Client client;
  late String address;
  late DateTime now;

  Future<http.Response> call(String path,
      {Map<String, Object?>? body, String? token = adminToken}) {
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    return body == null
        ? client.get(Uri.parse('$address$path'), headers: headers)
        : client.post(Uri.parse('$address$path'),
            headers: headers, body: jsonEncode(body));
  }

  Map<String, dynamic> decode(http.Response response) =>
      Map<String, dynamic>.from(jsonDecode(response.body) as Map);

  Future<void> create() async {
    final response = await call('/admin/customers', body: {
      'name': 'Cliente online',
      'login': 'cliente',
      'password': 'senha123',
      'max_devices': 2,
      'allowed_platform': 'both',
      'expires_at': now.add(const Duration(days: 7)).toIso8601String(),
    });
    expect(response.statusCode, HttpStatus.ok);
    expect(decode(response)['success'], isTrue);
  }

  Future<Map<String, dynamic>> activate() async =>
      decode(await call('/activate', token: null, body: {
        'login': 'cliente',
        'password': 'senha123',
        'machine_code': '123456789012',
        'machine_name': 'Android remoto',
        'platform': 'android',
      }));

  setUp(() async {
    now = DateTime.utc(2026, 10, 15);
    temporary = await Directory.systemTemp.createTemp('mastter_online_test_');
    client = http.Client();
    server = await LicenseServerCore.create(
        File('${temporary.path}/licenses.json'),
        adminToken: adminToken,
        now: () => now);
    await server.start(
        bindAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        enableDiscovery: false);
    expect(server.serverError, isNull);
    address = 'http://127.0.0.1:${server.boundPort}';
  });

  tearDown(() async {
    client.close();
    await server.stop();
    server.dispose();
    await temporary.delete(recursive: true);
  });

  test(
      'requires authenticated admin access and never returns password or device secrets',
      () async {
    expect((await call('/admin/customers', token: null)).statusCode,
        HttpStatus.unauthorized);
    expect((await call('/admin/customers', token: 'wrong')).statusCode,
        HttpStatus.unauthorized);
    await create();
    final activation = await activate();
    expect(activation['success'], isTrue);
    final response = await call('/admin/customers');
    final data = decode(response);
    final customer = (data['customers'] as List).single as Map;
    expect(customer['login'], 'cliente');
    expect(customer.containsKey('password_hash'), isFalse);
    expect(customer.containsKey('password_salt'), isFalse);
    final device = (customer['devices'] as List).single as Map;
    expect(device['machine_code'], '123456789012');
    expect(device.containsKey('token'), isFalse);
    expect(response.body.contains(activation['token'] as String), isFalse);
    expect(response.body.contains('senha123'), isFalse);
  });

  test(
      'remote admin CRUD governs activation, renewal, blocking and device release',
      () async {
    final admin = await LanLicenseServer.createForTesting(
        File('${temporary.path}/local.json'));
    addTearDown(admin.dispose);
    expect(
        await admin.connectRemote(
            serverAddress: address, adminToken: adminToken),
        isNull);
    expect(admin.isRemote, isTrue);
    expect(admin.isRunning, isTrue);
    expect(
        await admin.createCustomer(
            name: 'Cliente online',
            login: 'cliente',
            password: 'senha123',
            maxDevices: 2,
            expiresAt: now.add(const Duration(days: 7))),
        isNull);
    expect(admin.customers.single.passwordHash, isEmpty);
    final activation = await activate();
    final token = activation['token'] as String;
    await admin.refreshCustomers();
    expect(admin.customers.single.devices.single.token, isEmpty);
    final renewed = now.add(const Duration(days: 30));
    expect(
        await admin.updateCustomerLicense(
            customer: admin.customers.single,
            expiresAt: renewed,
            allowedPlatform: 'android',
            maxDevices: 3),
        isNull);
    expect(server.customers.single.expiresAt, renewed);
    await admin.setCustomerActive(admin.customers.single, false);
    final blocked = decode(await call('/validate', token: null, body: {
      'token': token,
      'machine_code': '123456789012',
      'platform': 'android',
    }));
    expect(blocked['error_code'], 'blocked');
    await admin.setCustomerActive(admin.customers.single, true);
    await admin.releaseDevice(
        admin.customers.single, admin.customers.single.devices.single);
    expect(server.customers.single.devices, isEmpty);
    final released = decode(await call('/validate', token: null, body: {
      'token': token,
      'machine_code': '123456789012',
      'platform': 'android',
    }));
    expect(released['error_code'], 'unauthorized');
    await admin.disconnectRemote();
    expect(admin.isRemote, isFalse);
    expect(admin.customers, isEmpty);
  });

  test(
      'remote failure clears remote records and never falls back to local customer copies',
      () async {
    final admin = await LanLicenseServer.createForTesting(
        File('${temporary.path}/local.json'));
    addTearDown(admin.dispose);
    expect(
        await admin.createCustomer(
            name: 'Cliente local',
            login: 'local',
            password: 'senha123',
            maxDevices: 1),
        isNull);
    await create();
    expect(
        await admin.connectRemote(
            serverAddress: address, adminToken: adminToken),
        isNull);
    expect(admin.customers.single.name, 'Cliente online');
    await server.stop();
    await expectLater(admin.refreshCustomers(), throwsA(anything));
    expect(admin.isRemote, isTrue);
    expect(admin.customers, isEmpty);
    expect(admin.serverError, isNotNull);
    expect(admin.isRunning, isFalse);
    await admin.disconnectRemote();
    expect(admin.customers.single.name, 'Cliente local');
  });

  test('rejects oversized and malformed HTTP bodies without mutation',
      () async {
    final oversized =
        await call('/admin/customers', body: {'name': 'a' * (33 * 1024)});
    expect(oversized.statusCode, HttpStatus.requestEntityTooLarge);
    final malformed =
        await client.post(Uri.parse('$address/activate'), body: '[1,2,3]');
    expect(malformed.statusCode, HttpStatus.badRequest);
    expect(server.customers, isEmpty);
    expect((await call('/health', token: null)).statusCode, HttpStatus.ok);
  });

  test('limits request bursts per IP and recovers after the bounded window',
      () async {
    final limited = await LicenseServerCore.create(
        File('${temporary.path}/limited.json'),
        now: () => now,
        maxRequestsPerMinute: 2);
    await limited.start(
        bindAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        enableDiscovery: false);
    addTearDown(() async {
      await limited.stop();
      limited.dispose();
    });
    final uri = Uri.parse('http://127.0.0.1:${limited.boundPort}/health');
    expect((await client.get(uri)).statusCode, HttpStatus.ok);
    expect((await client.get(uri)).statusCode, HttpStatus.ok);
    expect((await client.get(uri)).statusCode, HttpStatus.tooManyRequests);
    now = now.add(const Duration(minutes: 1));
    expect((await client.get(uri)).statusCode, HttpStatus.ok);
  });

  test(
      'admin routes are absent from the local engine unless explicitly enabled',
      () async {
    final local =
        await LicenseServerCore.create(File('${temporary.path}/lan.json'));
    await local.start(
        bindAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        enableDiscovery: false);
    addTearDown(() async {
      await local.stop();
      local.dispose();
    });
    expect(
        (await client.get(Uri.parse(
                'http://127.0.0.1:${local.boundPort}/admin/customers')))
            .statusCode,
        HttpStatus.notFound);
    await expectLater(
        LicenseServerCore.create(File('${temporary.path}/unsafe.json'),
            adminToken: 'short'),
        throwsArgumentError);
  });

  test(
      'honors the last forwarded IP only when proxy trust is explicitly enabled',
      () async {
    final proxy = await LicenseServerCore.create(
        File('${temporary.path}/proxy.json'),
        trustProxy: true,
        maxRequestsPerMinute: 2,
        now: () => now);
    await proxy.start(
        bindAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        enableDiscovery: false);
    addTearDown(() async {
      await proxy.stop();
      proxy.dispose();
    });
    final uri = Uri.parse('http://127.0.0.1:${proxy.boundPort}/health');
    Future<http.Response> forwarded(String value) =>
        client.get(uri, headers: {'x-forwarded-for': value});
    expect((await forwarded('198.51.100.1')).statusCode, HttpStatus.ok);
    expect((await forwarded('198.51.100.2')).statusCode, HttpStatus.ok);
    expect((await forwarded('198.51.100.3, 198.51.100.1')).statusCode,
        HttpStatus.ok);
    // Changing an untrusted earlier value cannot evade the trusted IP limit.
    expect((await forwarded('198.51.100.4, 198.51.100.1')).statusCode,
        HttpStatus.tooManyRequests);
  });

  test('times out a stalled request body before accepting any mutation',
      () async {
    final limited = await LicenseServerCore.create(
        File('${temporary.path}/slow.json'),
        requestBodyTimeout: const Duration(milliseconds: 100));
    await limited.start(
        bindAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        enableDiscovery: false);
    addTearDown(() async {
      await limited.stop();
      limited.dispose();
    });
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, limited.boundPort!);
    addTearDown(socket.destroy);
    socket.write(
        'POST /activate HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 100\r\nConnection: close\r\n\r\n{');
    await socket.flush();
    final response = await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 3));
    // Dart's HTTP parser may close an incomplete Content-Length request before
    // the application can flush 408. Both outcomes reject the request.
    expect(response.isEmpty || response.contains('408'), isTrue);
    expect(limited.customers, isEmpty);
  });
}
