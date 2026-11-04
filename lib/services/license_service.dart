import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/licensing/license_code.dart';
import '../core/licensing/license_mode.dart';
import '../core/licensing/offline_license.dart';
import 'lan_license_api_client.dart';

class LicenseActivationResult {
  const LicenseActivationResult({
    required this.success,
    required this.message,
    this.customerName,
    this.maxDevices,
    this.usedDevices,
    this.expiresAt,
  });

  final bool success;
  final String message;
  final String? customerName;
  final int? maxDevices;
  final int? usedDevices;
  final DateTime? expiresAt;
}

class LicenseService {
  LicenseService(
    this._prefs, {
    LanLicenseApiClient? api,
    DateTime Function()? now,
    bool? lanMode,
    String? platform,
    Future<String> Function()? fingerprint,
    OfflineLicenseVerifier? offlineVerifier,
  })  : _lanApi = api ?? const LanLicenseApiClient(),
        _now = now ?? DateTime.now,
        _lanMode = lanMode,
        _platform = platform ?? Platform.operatingSystem,
        _fingerprint = fingerprint,
        _offlineVerifier = offlineVerifier ?? OfflineLicenseVerifier();

  static const _legacyActivationKey = 'desktop_license_activation';
  static const _installationKey = 'desktop_license_installation';
  static const _failedAttemptsKey = 'desktop_license_failed_attempts';
  static const _lockUntilKey = 'desktop_license_lock_until';
  static const _lanServerKey = 'desktop_lan_license_server';
  static const _lanLoginKey = 'desktop_lan_license_login';
  static const _lanTokenKey = 'desktop_lan_license_token';
  static const _lastLanValidationKey = 'desktop_lan_license_last_validation';
  static const _lanExpiryKey = 'desktop_lan_license_expires_at';
  static const _lanDeniedKey = 'desktop_lan_license_denied';
  static const _mobileIdentityKey = 'license_mobile_identity';
  static const _activationMethodKey = 'license_activation_method';
  static const _offlineCodeKey = 'license_offline_signed_code';
  static const _offlineExpiryKey = 'license_offline_expiry';
  static const _offlineLastSeenKey = 'license_offline_last_seen';
  static const _lanGracePeriod = Duration(days: 3);
  static const String packagedSetupFileName = 'acesso_cliente.json';

  final SharedPreferences _prefs;
  final LanLicenseApiClient _lanApi;
  final DateTime Function() _now;
  final bool? _lanMode;
  final String _platform;
  final Future<String> Function()? _fingerprint;
  final OfflineLicenseVerifier _offlineVerifier;
  OfflineLicenseClaims? _offlineClaims;
  DateTime? _offlineClockStart;
  Stopwatch? _offlineClock;
  DateTime? _serverTime;
  Stopwatch? _serverClock;

  String? lastValidationMessage;

  bool get isLanMode => _lanMode ?? LicenseMode.isLan;
  bool get isOfflineLicense =>
      isLanMode && _prefs.getString(_activationMethodKey) == 'offline';
  String get savedLanServer =>
      _prefs.getString(_lanServerKey) ?? LicenseMode.defaultServer;
  String get savedLanLogin => _prefs.getString(_lanLoginKey) ?? '';
  DateTime? get expiresAt => isOfflineLicense
      ? _offlineClaims?.expiresAt ??
          DateTime.tryParse(_prefs.getString(_offlineExpiryKey) ?? '')?.toUtc()
      : DateTime.tryParse(_prefs.getString(_lanExpiryKey) ?? '')?.toUtc();
  Duration? get remainingLicenseTime {
    final expiry = expiresAt;
    if (expiry == null) return null;
    final now = isOfflineLicense
        ? _effectiveOfflineNow()
        : _serverTime?.add(_serverClock?.elapsed ?? Duration.zero) ??
            _now().toUtc();
    return expiry.difference(now);
  }

  Future<void> loadPackagedSetup() async {
    if (!isLanMode || !Platform.isWindows) return;
    final file = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}$packagedSetupFileName',
    );
    if (!await file.exists()) return;
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      final login = data['login']?.toString().trim().toLowerCase() ?? '';
      final server = data['server']?.toString().trim() ?? '';
      if ((_prefs.getString(_lanLoginKey) ?? '').isEmpty && login.isNotEmpty) {
        await _prefs.setString(_lanLoginKey, login);
      }
      if ((_prefs.getString(_lanServerKey) ?? '').isEmpty &&
          server.isNotEmpty) {
        await _prefs.setString(_lanServerKey, server);
      }
    } catch (_) {
      // A descoberta automática e o preenchimento manual continuam disponíveis.
    }
  }

  Future<String> getInstallationCode() async {
    final fingerprint = await (_fingerprint?.call() ?? _machineFingerprint());
    return installationCodeFromFingerprint(fingerprint);
  }

  Future<bool> isActivated() async {
    if (!isLanMode) return _isLegacyActivated();
    return isOfflineLicense ? _isOfflineActivated() : _isLanActivated();
  }

  Future<LicenseActivationResult> activateOffline(String input) async {
    try {
      final code = input.trim();
      final claims = await _offlineVerifier.verify(code);
      final error = await _offlineAccessError(claims);
      if (error != null) {
        return LicenseActivationResult(success: false, message: error);
      }
      // Commit a new method only after the entire signed license is valid.
      await _prefs.setString(_offlineCodeKey, code);
      await _prefs.setString(
          _offlineExpiryKey, claims.expiresAt.toIso8601String());
      await _prefs.setString(
          _offlineLastSeenKey, _effectiveOfflineNow().toIso8601String());
      await _prefs.setString(_activationMethodKey, 'offline');
      await _prefs.remove(_lanTokenKey);
      _offlineClaims = claims;
      _anchorOfflineClock();
      lastValidationMessage = 'Licença por chave ativada neste aparelho.';
      return LicenseActivationResult(
        success: true,
        message: lastValidationMessage!,
        customerName: claims.customerName,
        expiresAt: claims.expiresAt,
      );
    } on FormatException {
      return const LicenseActivationResult(
        success: false,
        message:
            'Chave inválida ou não reconhecida. Confira a chave fornecida pelo administrador.',
      );
    } catch (_) {
      return const LicenseActivationResult(
        success: false,
        message: 'Não foi possível ativar a chave. Tente novamente.',
      );
    }
  }

  Future<bool> _isOfflineActivated() async {
    final code = _prefs.getString(_offlineCodeKey);
    if (code == null) return false;
    try {
      final claims = await _offlineVerifier.verify(code);
      final error = await _offlineAccessError(claims);
      if (error != null) {
        lastValidationMessage = error;
        return false;
      }
      _offlineClaims = claims;
      _anchorOfflineClock();
      await _prefs.setString(
          _offlineLastSeenKey, _effectiveOfflineNow().toIso8601String());
      lastValidationMessage = 'Licença por chave válida.';
      return true;
    } catch (_) {
      lastValidationMessage =
          'A chave salva é inválida. Solicite uma nova chave ao administrador.';
      return false;
    }
  }

  Future<String?> _offlineAccessError(OfflineLicenseClaims claims) async {
    if (claims.installationCode != await getInstallationCode()) {
      return 'Esta chave pertence a outro aparelho.';
    }
    if (claims.platform != _platform) {
      return 'Esta chave não foi emitida para este tipo de aparelho.';
    }
    final wallTime = _now().toUtc();
    final lastSeen =
        DateTime.tryParse(_prefs.getString(_offlineLastSeenKey) ?? '')?.toUtc();
    const tolerance = Duration(minutes: 2);
    if (wallTime.isBefore(claims.issuedAt.subtract(tolerance)) ||
        (lastSeen != null && wallTime.isBefore(lastSeen.subtract(tolerance)))) {
      return 'Confira a data e a hora do aparelho para validar a licença.';
    }
    if (!_effectiveOfflineNow().isBefore(claims.expiresAt)) {
      return 'Seu prazo de acesso expirou. Solicite uma nova chave ao administrador.';
    }
    return null;
  }

  DateTime _effectiveOfflineNow() {
    final wall = _now().toUtc();
    final anchored =
        _offlineClockStart?.add(_offlineClock?.elapsed ?? Duration.zero);
    var current = anchored != null && anchored.isAfter(wall) ? anchored : wall;
    final saved =
        DateTime.tryParse(_prefs.getString(_offlineLastSeenKey) ?? '')?.toUtc();
    if (saved != null && saved.isAfter(current)) current = saved;
    return current;
  }

  void _anchorOfflineClock() {
    final current = _effectiveOfflineNow();
    _offlineClockStart = current;
    _offlineClock = Stopwatch()..start();
  }

  Future<String?> discoverLanServer() => _lanApi.discoverServer();

  Future<LicenseActivationResult> activateLan({
    required String serverAddress,
    required String login,
    required String password,
  }) async {
    final normalizedServer = serverAddress.trim();
    final normalizedLogin = login.trim().toLowerCase();
    if (normalizedServer.isEmpty) {
      return const LicenseActivationResult(
        success: false,
        message: 'Informe o endereço HTTPS do servidor ou localize-o na rede.',
      );
    }
    if (normalizedLogin.isEmpty || password.isEmpty) {
      return const LicenseActivationResult(
        success: false,
        message: 'Informe o login e a senha fornecidos pelo administrador.',
      );
    }

    final installation = await getInstallationCode();
    final result = await _lanApi.activate(
      serverAddress: normalizedServer,
      login: normalizedLogin,
      password: password,
      machineCode: installation,
      machineName: _platform == 'android'
          ? 'Android ${installation.substring(0, 4)}'
          : Platform.localHostname,
      platform: _platform,
    );
    if (result.success && (result.token == null || result.token!.isEmpty)) {
      return const LicenseActivationResult(
        success: false,
        message: 'O servidor não retornou uma autorização válida.',
      );
    }
    if (result.success && result.token != null) {
      await _prefs.setString(_lanServerKey, normalizedServer);
      await _prefs.setString(_lanLoginKey, normalizedLogin);
      await _prefs.setString(_lanTokenKey, result.token!);
      await _prefs.setString(_installationKey, installation);
      await _recordValidLicense(result);
      await _prefs.setString(_activationMethodKey, 'online');
      await _prefs.remove(_offlineCodeKey);
      await _prefs.remove(_offlineExpiryKey);
      _offlineClaims = null;
    }
    lastValidationMessage = result.message;
    return LicenseActivationResult(
      success: result.success,
      message: result.message,
      customerName: result.customerName,
      maxDevices: result.maxDevices,
      usedDevices: result.usedDevices,
      expiresAt: result.expiresAt,
    );
  }

  Future<LicenseActivationResult> activateLegacy(String input) async {
    final now = DateTime.now();
    final lockUntilText = _prefs.getString(_lockUntilKey);
    final lockUntil =
        lockUntilText == null ? null : DateTime.tryParse(lockUntilText);
    if (lockUntil != null && lockUntil.isAfter(now)) {
      final minutes = lockUntil.difference(now).inMinutes + 1;
      return LicenseActivationResult(
        success: false,
        message:
            'Muitas tentativas incorretas. Aguarde $minutes minuto(s) e tente novamente.',
      );
    }

    final activation = input.replaceAll(RegExp(r'\D'), '');
    if (activation.length != 6) {
      return const LicenseActivationResult(
        success: false,
        message: 'A chave de ativação deve possuir exatamente 6 números.',
      );
    }

    final installation = await getInstallationCode();
    final expected = activationCodeForInstallation(installation);
    if (activation == expected) {
      await _prefs.setString(_legacyActivationKey, activation);
      await _prefs.setString(_installationKey, installation);
      await _prefs.remove(_failedAttemptsKey);
      await _prefs.remove(_lockUntilKey);
      return const LicenseActivationResult(
        success: true,
        message: 'Sistema ativado com sucesso neste computador.',
      );
    }

    final attempts = (_prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
    if (attempts >= 5) {
      final until = now.add(const Duration(minutes: 5));
      await _prefs.setInt(_failedAttemptsKey, 0);
      await _prefs.setString(_lockUntilKey, until.toIso8601String());
      return const LicenseActivationResult(
        success: false,
        message:
            'Chave incorreta. Por segurança, novas tentativas foram bloqueadas por 5 minutos.',
      );
    }

    await _prefs.setInt(_failedAttemptsKey, attempts);
    return LicenseActivationResult(
      success: false,
      message: 'Chave incorreta. Restam ${5 - attempts} tentativa(s).',
    );
  }

  Future<bool> _isLanActivated() async {
    final server = _prefs.getString(_lanServerKey);
    final token = _prefs.getString(_lanTokenKey);
    if (server == null || token == null) return false;

    final installation = await getInstallationCode();
    final result = await _lanApi.validate(
      serverAddress: server,
      token: token,
      machineCode: installation,
      platform: _platform,
    );
    lastValidationMessage = result.message;
    if (result.success) {
      await _recordValidLicense(result);
      final remaining = remainingLicenseTime;
      if (remaining != null && remaining <= Duration.zero) {
        lastValidationMessage =
            'Seu prazo de acesso expirou. Solicite a renovação ao administrador.';
        return false;
      }
      return true;
    }
    if (!result.retryable) {
      // A denial cannot become an offline authorization on the next launch.
      await _prefs.setBool(_lanDeniedKey, true);
      await _prefs.remove(_lastLanValidationKey);
    }
    if (result.retryable &&
        expiresAt == null &&
        !(_prefs.getBool(_lanDeniedKey) ?? false) &&
        _isInsideLanGracePeriod()) {
      lastValidationMessage =
          'Servidor indisponível. Acesso temporário liberado.';
      return true;
    }
    if (result.retryable && expiresAt != null) {
      lastValidationMessage =
          'Conecte-se ao servidor para validar seu acesso com prazo de validade.';
    }
    return false;
  }

  Future<void> _recordValidLicense(LanLicenseResult result) async {
    _serverTime = result.serverTime?.toUtc() ?? _now().toUtc();
    _serverClock = Stopwatch()..start();
    if (result.expiresAt == null) {
      await _prefs.remove(_lanExpiryKey);
    } else {
      await _prefs.setString(
          _lanExpiryKey, result.expiresAt!.toUtc().toIso8601String());
    }
    await _prefs.setBool(_lanDeniedKey, false);
    await _prefs.setString(
        _lastLanValidationKey, _now().toUtc().toIso8601String());
  }

  Future<bool> _isLegacyActivated() async {
    final savedActivation = _prefs.getString(_legacyActivationKey);
    final savedInstallation = _prefs.getString(_installationKey);
    if (savedActivation == null || savedInstallation == null) return false;

    final currentInstallation = await getInstallationCode();
    if (savedInstallation != currentInstallation) return false;
    return savedActivation ==
        activationCodeForInstallation(currentInstallation);
  }

  bool _isInsideLanGracePeriod() {
    final text = _prefs.getString(_lastLanValidationKey);
    final lastValidation = text == null ? null : DateTime.tryParse(text);
    if (lastValidation == null) return false;
    final elapsed = _now().toUtc().difference(lastValidation.toUtc());
    return !elapsed.isNegative && elapsed <= _lanGracePeriod;
  }

  Future<String> _machineFingerprint() async {
    if (_platform == 'android' || _platform == 'ios') {
      var identity = _prefs.getString(_mobileIdentityKey);
      if (identity == null || identity.isEmpty) {
        identity = const Uuid().v4();
        await _prefs.setString(_mobileIdentityKey, identity);
      }
      return '$_platform:$identity';
    }
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'reg.exe',
          [
            'query',
            r'HKLM\SOFTWARE\Microsoft\Cryptography',
            '/v',
            'MachineGuid',
          ],
          runInShell: false,
        );
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final guid = RegExp(
            r'MachineGuid\s+REG_SZ\s+([^\r\n]+)',
            caseSensitive: false,
          ).firstMatch(output)?.group(1)?.trim();
          if (guid != null && guid.isNotEmpty) return 'WINDOWS:$guid';
        }
      } catch (_) {
        // O fallback abaixo mantém a ativação utilizável.
      }
    }

    final environment = Platform.environment;
    return 'FALLBACK:${[
      Platform.localHostname,
      Platform.operatingSystem,
      environment['COMPUTERNAME'] ?? '',
      environment['PROCESSOR_IDENTIFIER'] ?? '',
      environment['NUMBER_OF_PROCESSORS'] ?? '',
      environment['SYSTEMDRIVE'] ?? '',
    ].join('|')}';
  }
}
