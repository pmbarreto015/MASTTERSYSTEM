import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/license_service.dart';

class LicenseProvider extends ChangeNotifier with WidgetsBindingObserver {
  LicenseProvider(SharedPreferences prefs, {LicenseService? service})
      : _service = service ?? LicenseService(prefs) {
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  final LicenseService _service;
  bool _isLoading = true;
  bool _isActivated = false;
  bool _disposed = false;
  bool _validating = false;
  String _installationCode = '';
  String? _statusMessage;
  Timer? _validationTimer;
  Timer? _expiryTimer;

  bool get isLoading => _isLoading;
  bool get isActivated => _isActivated;
  String get installationCode => _installationCode;
  bool get isLanMode => _service.isLanMode;
  bool get isOfflineLicense => _service.isOfflineLicense;
  String get savedLanServer => _service.savedLanServer;
  String get savedLanLogin => _service.savedLanLogin;
  String? get statusMessage => _statusMessage;
  DateTime? get expiresAt => _service.expiresAt;

  Future<void> _initialize() async {
    try {
      await _service.loadPackagedSetup();
      _installationCode = await _service.getInstallationCode();
      await revalidate();
      if (!_disposed && isLanMode) {
        _validationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
          revalidate();
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Falha ao verificar licença: $error');
      debugPrintStack(stackTrace: stackTrace);
      _isActivated = false;
      _statusMessage = 'Não foi possível verificar a licença. Tente novamente.';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> revalidate({bool showLoading = false}) async {
    if (_validating || _disposed) return;
    _validating = true;
    if (showLoading) {
      _isLoading = true;
      _notify();
    }
    try {
      final activated = await _service.isActivated();
      if (_disposed) return;
      _isActivated = activated;
      _statusMessage = _service.lastValidationMessage;
      _scheduleExpiry();
    } catch (_) {
      _isActivated = false;
      _statusMessage = 'Não foi possível verificar a licença. Tente novamente.';
    } finally {
      _validating = false;
      if (showLoading) _isLoading = false;
      _notify();
    }
  }

  Future<String?> discoverLanServer() => _service.discoverLanServer();

  Future<LicenseActivationResult> activateLan({
    required String serverAddress,
    required String login,
    required String password,
  }) async {
    if (_validating) {
      return const LicenseActivationResult(
          success: false,
          message: 'Aguarde a verificação da licença e tente novamente.');
    }
    _validating = true;
    try {
      final result = await _service.activateLan(
        serverAddress: serverAddress,
        login: login,
        password: password,
      );
      if (_disposed) return result;
      _statusMessage = result.message;
      if (result.success) {
        _isActivated = true;
        _scheduleExpiry();
      }
      _notify();
      return result;
    } catch (_) {
      return const LicenseActivationResult(
          success: false,
          message: 'Não foi possível ativar a licença. Tente novamente.');
    } finally {
      _validating = false;
    }
  }

  Future<LicenseActivationResult> activateLegacy(String code) async {
    final result = await _service.activateLegacy(code);
    if (_disposed) return result;
    _statusMessage = result.message;
    if (result.success) _isActivated = true;
    _notify();
    return result;
  }

  Future<LicenseActivationResult> activateOffline(String code) async {
    if (_validating) {
      return const LicenseActivationResult(
        success: false,
        message: 'Aguarde a verificação da licença e tente novamente.',
      );
    }
    _validating = true;
    try {
      final result = await _service.activateOffline(code);
      if (_disposed) return result;
      _statusMessage = result.message;
      if (result.success) {
        _isActivated = true;
        _scheduleExpiry();
      }
      _notify();
      return result;
    } finally {
      _validating = false;
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (!isLanMode || !_isActivated) return;
    final remaining = _service.remainingLicenseTime;
    if (remaining == null) return;
    if (remaining <= Duration.zero) {
      _expire();
    } else {
      _expiryTimer = Timer(remaining, _expire);
    }
  }

  void _expire() {
    if (_disposed) return;
    _isActivated = false;
    _statusMessage =
        'Seu prazo de acesso expirou. Solicite a renovação ao administrador.';
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isLanMode) {
      revalidate(showLoading: expiresAt != null);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _validationTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}
