import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/licensing/license_code.dart';
import '../../providers/license_provider.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _codeController = TextEditingController();
  final _serverController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _initialized = false;
  bool _activating = false;
  bool _locatingServer = false;
  bool _showPassword = false;
  bool _useOfflineKey = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final license = context.read<LicenseProvider>();
    _serverController.text = license.savedLanServer;
    _loginController.text = license.savedLanLogin;
    _useOfflineKey = license.isOfflineLicense;
    _initialized = true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _serverController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_activating) return;
    setState(() {
      _activating = true;
      _error = null;
    });
    final provider = context.read<LicenseProvider>();
    final result = provider.isLanMode
        ? _useOfflineKey
            ? await provider.activateOffline(_codeController.text)
            : await provider.activateLan(
                serverAddress: _serverController.text,
                login: _loginController.text,
                password: _passwordController.text,
              )
        : await provider.activateLegacy(_codeController.text);
    if (!mounted) return;
    setState(() {
      _activating = false;
      if (!result.success) _error = result.message;
    });
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _importOfflineKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lic', 'txt'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 16384 || file.bytes == null) {
        setState(() => _error = 'Selecione um arquivo de licença válido.');
        return;
      }
      final code = utf8.decode(file.bytes!).trim();
      if (!code.startsWith('MSL1.') || code.length > 8192) {
        setState(
            () => _error = 'O arquivo não contém uma chave de licença válida.');
        return;
      }
      setState(() {
        _codeController.text = code;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível ler o arquivo da licença.');
      }
    }
  }

  Future<void> _locateServer() async {
    if (_locatingServer) return;
    setState(() {
      _locatingServer = true;
      _error = null;
    });
    final address = await context.read<LicenseProvider>().discoverLanServer();
    if (!mounted) return;
    setState(() {
      _locatingServer = false;
      if (address == null) {
        _error =
            'Servidor não localizado. Confira se o administrador está aberto no computador principal.';
      } else {
        _serverController.text = address;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseProvider>();
    final installation = formatInstallationCode(license.installationCode);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final message = _error ?? license.statusMessage;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F62AC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        license.isLanMode
                            ? Icons.lan
                            : Icons.verified_user_outlined,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      license.isLanMode
                          ? 'Acesso do MastterSystem'
                          : 'Ativação do MastterSystem',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      license.isLanMode
                          ? 'Entre com a licença criada pelo administrador para este aparelho.'
                          : 'Esta licença será vinculada somente a este computador.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 22),
                    _machineCodeCard(isDark, installation, license),
                    const SizedBox(height: 18),
                    if (license.isLanMode) ...[
                      SegmentedButton<bool>(
                        key: const ValueKey('activation-method'),
                        segments: const [
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.cloud_outlined),
                            label: Text('Internet / rede'),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.key_outlined),
                            label: Text('Chave offline'),
                          ),
                        ],
                        selected: {_useOfflineKey},
                        onSelectionChanged: _activating
                            ? null
                            : (selection) => setState(() {
                                  _useOfflineKey = selection.single;
                                  _error = null;
                                }),
                      ),
                      const SizedBox(height: 18),
                      if (_useOfflineKey) _offlineFields() else _lanFields(),
                    ] else
                      _legacyField(),
                    if (message != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          message,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _activating ? null : _activate,
                        icon: _activating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              _activating ? 'Validando...' : 'Entrar e ativar'),
                        ),
                      ),
                    ),
                    if (license.isLanMode) ...[
                      const SizedBox(height: 12),
                      Text(
                        _useOfflineKey
                            ? 'Envie o código deste aparelho ao administrador e cole a chave recebida. Para renovar, solicite outra chave.'
                            : 'Use o endereço HTTPS fornecido pelo administrador para ativar de qualquer lugar. A localização automática funciona na rede local.',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (!_useOfflineKey && license.savedLanLogin.isNotEmpty)
                        TextButton.icon(
                          onPressed: _activating
                              ? null
                              : () async {
                                  setState(() => _error = null);
                                  await license.revalidate(showLoading: true);
                                },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Verificar renovação'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _machineCodeCard(
    bool isDark,
    String installation,
    LicenseProvider license,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: .05)
            : const Color(0xFFF2F7FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF0F62AC).withValues(alpha: .25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.computer, color: Color(0xFF0F62AC)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Código deste aparelho',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                SelectableText(
                  installation,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.3),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar código',
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: license.installationCode),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Código copiado.')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _lanFields() {
    return Column(
      children: [
        TextField(
          controller: _serverController,
          enabled: !_activating && !_locatingServer,
          decoration: InputDecoration(
            labelText: 'Servidor de licenças',
            hintText: 'https://licencas.exemplo.com',
            helperText: 'Internet: endereço HTTPS. Rede local: IP e porta.',
            prefixIcon: const Icon(Icons.dns_outlined),
            suffixIcon: IconButton(
              tooltip: 'Localizar automaticamente',
              onPressed: _locatingServer ? null : _locateServer,
              icon: _locatingServer
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginController,
          enabled: !_activating,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Login',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          enabled: !_activating,
          obscureText: !_showPassword,
          onSubmitted: (_) => _activate(),
          decoration: InputDecoration(
            labelText: 'Senha',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon:
                  Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
      ],
    );
  }

  Widget _offlineFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('offline-activation-code'),
          controller: _codeController,
          enabled: !_activating,
          minLines: 3,
          maxLines: 5,
          maxLength: 8192,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Chave enviada pelo administrador',
            hintText: 'MSL1.…',
            counterText: '',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _activating ? null : _importOfflineKey,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Importar arquivo de licença'),
        ),
      ],
    );
  }

  Widget _legacyField() {
    return TextField(
      controller: _codeController,
      enabled: !_activating,
      autofocus: true,
      textAlign: TextAlign.center,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _activate(),
      decoration: const InputDecoration(
        labelText: 'Chave de ativação (6 números)',
        prefixIcon: Icon(Icons.key),
        border: OutlineInputBorder(),
        counterText: '',
      ),
    );
  }
}
