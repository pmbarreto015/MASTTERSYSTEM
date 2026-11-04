import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class LanLicenseResult {
  const LanLicenseResult({
    required this.success,
    required this.message,
    this.token,
    this.customerName,
    this.maxDevices,
    this.usedDevices,
    this.expiresAt,
    this.serverTime,
    this.allowedPlatform,
    this.errorCode,
    this.retryable = false,
  });

  final bool success;
  final String message;
  final String? token;
  final String? customerName;
  final int? maxDevices;
  final int? usedDevices;
  final DateTime? expiresAt;
  final DateTime? serverTime;
  final String? allowedPlatform;
  final String? errorCode;
  final bool retryable;
}

class LanLicenseApiClient {
  const LanLicenseApiClient({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const int serverPort = 8787;
  static const int discoveryPort = 8788;

  Future<String?> discoverServer() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final completer = Completer<String?>();
      late final StreamSubscription<RawSocketEvent> subscription;
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final message = utf8.decode(datagram.data, allowMalformed: true);
        if (message.startsWith('MASTTER_LICENSE_SERVER|')) {
          final port = int.tryParse(message.split('|').last) ?? serverPort;
          if (!completer.isCompleted) {
            completer.complete('${datagram.address.address}:$port');
          }
        }
      });
      socket.send(
        utf8.encode('MASTTER_LICENSE_DISCOVER'),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
      final result = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      await subscription.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  Future<LanLicenseResult> activate({
    required String serverAddress,
    required String login,
    required String password,
    required String machineCode,
    required String machineName,
    String platform = 'windows',
  }) {
    return _call(
      serverAddress,
      '/activate',
      {
        'login': login,
        'password': password,
        'machine_code': machineCode,
        'machine_name': machineName,
        'platform': platform,
      },
    );
  }

  Future<LanLicenseResult> validate({
    required String serverAddress,
    required String token,
    required String machineCode,
    String platform = 'windows',
  }) {
    return _call(
      serverAddress,
      '/validate',
      {'token': token, 'machine_code': machineCode, 'platform': platform},
    );
  }

  Future<LanLicenseResult> _call(
    String serverAddress,
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final baseUrl = normalizeServerAddress(serverAddress);
      final client = _client ?? http.Client();
      late final http.Response response;
      try {
        response = await client
            .post(
              Uri.parse('$baseUrl$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 8));
      } finally {
        if (_client == null) client.close();
      }
      if (response.statusCode != HttpStatus.ok) {
        return LanLicenseResult(
          success: false,
          message: 'O servidor de licenças não respondeu corretamente.',
          retryable: response.statusCode >= 500,
        );
      }
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      final expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '');
      final serverTime =
          DateTime.tryParse(data['server_time']?.toString() ?? '');
      if (data['success'] == true &&
          data['expires_at'] != null &&
          (expiresAt == null || serverTime == null)) {
        return const LanLicenseResult(
            success: false,
            message: 'O servidor retornou um prazo de licença inválido.');
      }
      return LanLicenseResult(
        success: data['success'] == true,
        message:
            data['message']?.toString() ?? 'Resposta inválida do servidor.',
        token: data['token']?.toString(),
        customerName: data['customer_name']?.toString(),
        maxDevices: int.tryParse(data['max_devices']?.toString() ?? ''),
        usedDevices: int.tryParse(data['used_devices']?.toString() ?? ''),
        expiresAt: expiresAt?.toUtc(),
        serverTime: serverTime?.toUtc(),
        allowedPlatform: data['allowed_platform']?.toString(),
        errorCode: data['error_code']?.toString(),
      );
    } on FormatException catch (error) {
      return LanLicenseResult(success: false, message: error.message);
    } on SocketException {
      return const LanLicenseResult(
        success: false,
        message:
            'Não foi possível alcançar o servidor de licenças. Confira o endereço e a conexão.',
        retryable: true,
      );
    } catch (_) {
      return const LanLicenseResult(
        success: false,
        message: 'Não foi possível consultar o servidor de licenças.',
        retryable: true,
      );
    }
  }

  static String normalizeServerAddress(String value) {
    var address = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!address.startsWith('http://') && !address.startsWith('https://')) {
      final host = Uri.tryParse('http://$address')?.host ?? '';
      address = '${_isLocalHost(host) ? 'http' : 'https'}://$address';
    }
    final uri = Uri.parse(address);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
          'Informe o endereço do servidor de licenças.');
    }
    if (uri.scheme != 'https' && !_isLocalHost(uri.host)) {
      throw const FormatException(
          'Para ativar pela internet, use um endereço HTTPS.');
    }
    // HTTPS proxies use their normal port; bare LAN addresses use 8787.
    return uri
        .replace(
            port: uri.hasPort || uri.scheme == 'https' ? null : serverPort,
            path: '')
        .toString()
        .replaceFirst(RegExp(r'/+$'), '');
  }

  static bool _isLocalHost(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(name);
    if (address == null) {
      return name.isNotEmpty && !name.contains('.') && !name.contains(':');
    }
    if (address.isLoopback) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    return (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }
}
