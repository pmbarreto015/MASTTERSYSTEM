import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/app_database.dart';
import 'database_rpc_server.dart';

class DatabaseServerController {
  static const enabledKey = 'database_server_enabled';
  static const tokenKey = 'database_server_access_token';
  static const portKey = 'database_server_port';

  static final _instance = DatabaseServerController._();
  factory DatabaseServerController() => _instance;
  DatabaseServerController._();

  DatabaseRpcServer? _server;
  String? _activeToken;
  bool get isRunning => _server?.isRunning ?? false;
  int? get port => _server?.port;

  Future<void> startFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(enabledKey) ?? false)) return;
    await configure(
      enabled: true,
      token: prefs.getString(tokenKey) ?? '',
      port: prefs.getInt(portKey) ?? 8080,
    );
  }

  Future<void> configure({
    required bool enabled,
    required String token,
    int port = 8080,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await _server?.stop();
      _server = null;
      _activeToken = null;
      await prefs.setBool(enabledKey, false);
      return;
    }
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      throw StateError('Ative o servidor no computador principal.');
    }
    if (await AppDatabase().isUsingRemoteDatabase()) {
      throw StateError('O servidor precisa usar um banco local neste PC.');
    }
    if (token.trim().length < 24) {
      throw const FormatException(
          'A chave de acesso deve ter ao menos 24 caracteres.');
    }
    if (port < 1024 || port > 65535) {
      throw const FormatException('Informe uma porta entre 1024 e 65535.');
    }
    if (isRunning && this.port == port && _activeToken == token.trim()) return;

    final previousServer = _server;
    final previousPort = previousServer?.port;
    await previousServer?.stop();
    final server = DatabaseRpcServer(
      database: await AppDatabase().database,
      token: token.trim(),
    );
    try {
      await server.start(port: port);
    } catch (_) {
      if (previousServer != null && previousPort != null) {
        await previousServer.start(port: previousPort);
      }
      rethrow;
    }
    _server = server;
    _activeToken = token.trim();
    await prefs.setString(tokenKey, token.trim());
    await prefs.setInt(portKey, port);
    await prefs.setBool(enabledKey, true);
  }

  Future<List<String>> getServerAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final listenPort = port ?? 8080;
    return interfaces
        .expand((interface) => interface.addresses)
        .map((address) => 'http://${address.address}:$listenPort')
        .toSet()
        .toList();
  }
}
