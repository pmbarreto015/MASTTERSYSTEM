import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class LicenseAdminConfig {
  const LicenseAdminConfig._();

  static const String passwordHash =
      String.fromEnvironment('LICENSE_ADMIN_HASH');

  static const int _iterations = 120000;
  static const String _algorithm = 'pbkdf2-hmac-sha256';
  static File? _credentialsFile;
  static String? _storedSalt;
  static String? _storedHash;
  static bool _initialized = false;
  static bool _configurationFailed = false;
  static bool _configuring = false;

  static bool get _hasCompiledHash =>
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(passwordHash);

  static bool get isConfigured =>
      !_configurationFailed && (_storedHash != null || _hasCompiledHash);

  static Future<void> initialize({File? credentialsFile}) async {
    _initialized = false;
    _configurationFailed = false;
    _storedSalt = null;
    _storedHash = null;
    try {
      if (credentialsFile == null) {
        final directory = await getApplicationSupportDirectory();
        credentialsFile = File(
          '${directory.path}${Platform.pathSeparator}license_admin_credentials.json',
        );
      }
      _credentialsFile = credentialsFile;
      if (await credentialsFile.exists()) {
        final contents = Map<String, dynamic>.from(
          jsonDecode(await credentialsFile.readAsString()) as Map,
        );
        final salt = contents['salt']?.toString() ?? '';
        final hash = contents['password_hash']?.toString() ?? '';
        if (contents['version'] != 1 ||
            contents['algorithm'] != _algorithm ||
            contents['iterations'] != _iterations ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(salt) ||
            base64Url.decode(base64Url.normalize(salt)).length != 32 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('Credenciais inválidas.');
        }
        _storedSalt = salt;
        _storedHash = hash;
      }
      _initialized = true;
    } catch (_) {
      _configurationFailed = true;
      throw StateError(
        'Não foi possível ler as credenciais do administrador. '
        'O arquivo de configuração pode estar danificado ou inacessível. '
        'Restaure o arquivo original para acessar o administrador.',
      );
    }
  }

  static Future<String?> configurePassword(
    String password, {
    String? confirmation,
  }) async {
    if (_configurationFailed || !_initialized || _credentialsFile == null) {
      return 'As credenciais do administrador não puderam ser inicializadas.';
    }
    if (isConfigured || _configuring) {
      return 'A senha do administrador já está configurada.';
    }
    if (password.length < 8 || password.trim().isEmpty) {
      return 'A senha deve possuir pelo menos 8 caracteres.';
    }
    if (confirmation != null && password != confirmation) {
      return 'A confirmação da senha não confere.';
    }
    _configuring = true;
    File? temporary;
    try {
      final file = _credentialsFile!;
      if (await file.exists()) {
        _configurationFailed = true;
        return 'Já existe um arquivo de credenciais. Reinicie o administrador para carregá-lo.';
      }
      final random = Random.secure();
      final salt = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      final hash = _deriveHash(password, salt);
      await file.parent.create(recursive: true);
      temporary = File('${file.path}.$salt.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'algorithm': _algorithm,
          'iterations': _iterations,
          'salt': salt,
          'password_hash': hash,
        }),
        flush: true,
      );
      if (await file.exists()) {
        _configurationFailed = true;
        return 'Já existe um arquivo de credenciais. Reinicie o administrador para carregá-lo.';
      }
      await temporary.rename(file.path);
      temporary = null;
      _storedSalt = salt;
      _storedHash = hash;
      return null;
    } catch (_) {
      return 'Não foi possível salvar a senha do administrador. Verifique o acesso à pasta do aplicativo.';
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {
        // A failed cleanup must not enable changing an existing credential.
      }
      _configuring = false;
    }
  }

  static bool verifyPassword(String password) {
    if (!isConfigured || password.isEmpty) return false;
    final storedHash = _storedHash;
    if (storedHash != null) {
      return _constantTimeEquals(
          _deriveHash(password, _storedSalt!), storedHash);
    }
    final informed = sha256.convert(utf8.encode(password)).toString();
    return _constantTimeEquals(informed, passwordHash.toLowerCase());
  }

  static String _deriveHash(String password, String salt) {
    // PBKDF2-HMAC-SHA256, one 32-byte block. The salt and cost are persisted.
    final hmac = Hmac(sha256, utf8.encode(password));
    var block = hmac.convert([
      ...base64Url.decode(base64Url.normalize(salt)),
      0,
      0,
      0,
      1,
    ]).bytes;
    final derived = List<int>.from(block);
    for (var iteration = 1; iteration < _iterations; iteration++) {
      block = hmac.convert(block).bytes;
      for (var index = 0; index < derived.length; index++) {
        derived[index] ^= block[index];
      }
    }
    return derived.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String informed, String expected) {
    if (informed.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < informed.length; index++) {
      difference |= informed.codeUnitAt(index) ^ expected.codeUnitAt(index);
    }
    return difference == 0;
  }
}
