import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'lan_license_api_client.dart';
import 'license_server_core.dart';

export 'license_server_core.dart' show LanLicenseCustomer, LanLicensedDevice;

/// Desktop facade for the local engine or an authenticated internet server.
class LanLicenseServer extends ChangeNotifier {
  LanLicenseServer._();

  late final LicenseServerCore _core;
  bool _disposed = false;
  String? _remoteAddress;
  String? _remoteToken;
  String? _remoteError;
  bool _remoteConnected = false;
  final List<LanLicenseCustomer> _remoteCustomers = [];
  Future<void> _remoteQueue = Future<void>.value();
  int _connectionGeneration = 0;

  static const int port = LicenseServerCore.port;
  static const int discoveryPort = LicenseServerCore.discoveryPort;
  static const String provisionFileName = LicenseServerCore.provisionFileName;

  bool get isRemote => _remoteAddress != null;
  String? get remoteAddress => _remoteAddress;
  List<LanLicenseCustomer> get customers =>
      isRemote ? List.unmodifiable(_remoteCustomers) : _core.customers;
  bool get isRunning => isRemote ? _remoteConnected : _core.isRunning;
  int? get boundPort => isRemote ? null : _core.boundPort;
  String? get serverError => isRemote ? _remoteError : _core.serverError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static Future<LanLicenseServer> create() async {
    final directory = await getApplicationSupportDirectory();
    return _create(
        File('${directory.path}${Platform.pathSeparator}lan_licenses.json'),
        importProvision: true);
  }

  @visibleForTesting
  static Future<LanLicenseServer> createForTesting(File dataFile,
          {DateTime Function()? now}) =>
      _create(dataFile, now: now);

  static Future<LanLicenseServer> _create(File dataFile,
      {DateTime Function()? now, bool importProvision = false}) async {
    final facade = LanLicenseServer._();
    facade._core = await LicenseServerCore.create(dataFile,
        now: now, onChanged: facade._notify, importProvision: importProvision);
    return facade;
  }

  Future<void> start(
      {InternetAddress? bindAddress,
      int listenPort = port,
      bool enableDiscovery = true}) async {
    if (isRemote) {
      await refreshCustomers();
      return;
    }
    await _core.start(
        bindAddress: bindAddress,
        listenPort: listenPort,
        enableDiscovery: enableDiscovery);
  }

  Future<void> stop() async {
    if (isRemote) {
      await disconnectRemote();
    } else {
      await _core.stop();
    }
  }

  Future<List<String>> localAddresses() async =>
      isRemote ? [_remoteAddress!] : await _core.localAddresses();

  /// The bearer credential stays only in memory. Never falls back to local
  /// customer records if a remote connection fails.
  Future<String?> connectRemote(
      {required String serverAddress, required String adminToken}) async {
    String address;
    try {
      address = LanLicenseApiClient.normalizeServerAddress(serverAddress);
      final uri = Uri.parse(address);
      if (uri.scheme != 'https' &&
          !const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
        return 'Use HTTPS para proteger a credencial do administrador pela internet.';
      }
    } catch (_) {
      return 'Informe o endereço HTTPS do servidor de licenças.';
    }
    if (adminToken.trim().length < 32) {
      return 'A credencial administrativa deve possuir pelo menos 32 caracteres.';
    }
    await _core.stop();
    _connectionGeneration++;
    _remoteAddress = address;
    _remoteToken = adminToken.trim();
    _remoteError = null;
    _remoteConnected = false;
    _remoteCustomers.clear();
    _notify();
    try {
      await refreshCustomers();
      return null;
    } catch (_) {
      return _remoteError ?? 'Não foi possível conectar ao servidor online.';
    }
  }

  Future<void> disconnectRemote() async {
    _connectionGeneration++;
    _remoteAddress = null;
    _remoteToken = null;
    _remoteError = null;
    _remoteConnected = false;
    _remoteCustomers.clear();
    _notify();
  }

  Future<void> refreshCustomers() async {
    if (!isRemote) {
      _notify();
      return;
    }
    await _remoteOperation('/admin/customers', method: 'GET');
  }

  Future<String?> createCustomer(
      {required String name,
      required String login,
      required String password,
      required int maxDevices,
      DateTime? expiresAt,
      String allowedPlatform = 'both'}) async {
    if (!isRemote) {
      return _core.createCustomer(
          name: name,
          login: login,
          password: password,
          maxDevices: maxDevices,
          expiresAt: expiresAt,
          allowedPlatform: allowedPlatform);
    }
    return _remoteMutation('/admin/customers', {
      'name': name,
      'login': login,
      'password': password,
      'max_devices': maxDevices,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'allowed_platform': allowedPlatform,
    });
  }

  Future<String?> updateCustomerLicense(
      {required LanLicenseCustomer customer,
      required DateTime? expiresAt,
      required String allowedPlatform,
      required int maxDevices}) async {
    if (!isRemote) {
      return _core.updateCustomerLicense(
          customer: customer,
          expiresAt: expiresAt,
          allowedPlatform: allowedPlatform,
          maxDevices: maxDevices);
    }
    return _remoteMutation('/admin/update', {
      'customer_id': customer.id,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'allowed_platform': allowedPlatform,
      'max_devices': maxDevices,
    });
  }

  Future<void> setCustomerActive(
      LanLicenseCustomer customer, bool active) async {
    if (!isRemote) {
      return _core.setCustomerActive(customer, active);
    }
    await _remoteOperation('/admin/active',
        body: {'customer_id': customer.id, 'active': active});
  }

  Future<void> releaseDevice(
      LanLicenseCustomer customer, LanLicensedDevice device) async {
    if (!isRemote) {
      return _core.releaseDevice(customer, device);
    }
    await _remoteOperation('/admin/release',
        body: {'customer_id': customer.id, 'machine_code': device.machineCode});
  }

  String createCustomerProvision(LanLicenseCustomer customer) {
    if (isRemote) {
      throw StateError(
          'Clientes online usam o endereço HTTPS e o login. Não exporte configuração de servidor local.');
    }
    return _core.createCustomerProvision(customer);
  }

  Future<String?> _remoteMutation(
      String path, Map<String, Object?> body) async {
    try {
      await _remoteOperation(path, body: body);
      return null;
    } catch (_) {
      return _remoteError ?? 'Não foi possível atualizar o servidor online.';
    }
  }

  Future<void> _remoteOperation(String path,
      {String method = 'POST', Map<String, Object?>? body}) {
    final generation = _connectionGeneration;
    final operation = _remoteQueue.then((_) =>
        _callRemote(path, method: method, body: body, generation: generation));
    _remoteQueue = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    return operation;
  }

  Future<void> _callRemote(String path,
      {required String method,
      required int generation,
      Map<String, Object?>? body}) async {
    if (!isRemote || generation != _connectionGeneration) {
      throw StateError('Conexão alterada.');
    }
    final client = http.Client();
    try {
      final uri = Uri.parse('$_remoteAddress$path');
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $_remoteToken',
          'Content-Type': 'application/json'
        });
      if (body != null) request.body = jsonEncode(body);
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 8 * 1024 * 1024) {
          throw const FormatException('Resposta muito grande.');
        }
        bytes.addAll(chunk);
      }
      if (generation != _connectionGeneration) {
        throw StateError('Conexão alterada.');
      }
      if (response.statusCode == HttpStatus.unauthorized) {
        throw StateError('Credencial administrativa inválida.');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
            'O servidor online retornou erro ${response.statusCode}.');
      }
      final data =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      if (data['success'] != true) {
        throw StateError(data['message']?.toString() ?? 'Operação recusada.');
      }
      final list = data['customers'];
      if (list is! List) {
        throw const FormatException('Lista de clientes ausente.');
      }
      final customers = list
          .map((item) => LanLicenseCustomer.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      _remoteCustomers
        ..clear()
        ..addAll(customers);
      _remoteConnected = true;
      _remoteError = null;
      _notify();
    } catch (error) {
      if (generation == _connectionGeneration) {
        _remoteCustomers.clear();
        _remoteConnected = false;
        _remoteError = error is StateError
            ? error.message.toString()
            : 'Não foi possível consultar o servidor online. Verifique o endereço, a conexão e a credencial.';
        _notify();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionGeneration++;
    _remoteToken = null;
    _core.dispose();
    super.dispose();
  }
}
