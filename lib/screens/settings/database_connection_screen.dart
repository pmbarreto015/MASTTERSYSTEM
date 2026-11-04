import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/database/remote_database.dart';
import '../../core/supabase/supabase_config.dart';
import '../../core/supabase/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/database_server_controller.dart';
import '../auth/login_screen.dart';

class DatabaseConnectionScreen extends StatefulWidget {
  const DatabaseConnectionScreen({super.key});

  @override
  State<DatabaseConnectionScreen> createState() =>
      _DatabaseConnectionScreenState();
}

class _DatabaseConnectionScreenState extends State<DatabaseConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _remoteTokenController = TextEditingController();
  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();
  final _serverTokenController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  final _server = DatabaseServerController();
  bool _loading = true;
  bool _busy = false;
  String _selectedMode = AppDatabase.localMode;
  bool _serverEnabled = false;
  bool _obscureRemoteToken = true;
  bool _obscureSupabaseKey = true;
  bool _obscureServerToken = true;
  bool _localUsesShared = false;
  String _sharedPath = '';
  String? _loadError;
  List<String> _addresses = [];

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get _remote => _selectedMode == AppDatabase.remoteMode;
  bool get _supabase => _selectedMode == AppDatabase.supabaseMode;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _remoteTokenController.dispose();
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    _serverTokenController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(AppDatabase.databaseModeKey);
      _selectedMode =
          mode == AppDatabase.remoteMode || mode == AppDatabase.supabaseMode
              ? mode!
              : AppDatabase.localMode;
      _localUsesShared = mode == AppDatabase.sharedMode;
      _sharedPath = prefs.getString(AppDatabase.databasePathKey) ?? '';
      _urlController.text =
          prefs.getString(AppDatabase.databaseServerUrlKey) ?? '';
      _remoteTokenController.text =
          prefs.getString(AppDatabase.databaseServerTokenKey) ?? '';
      _supabaseUrlController.text =
          prefs.getString(AppDatabase.supabaseProjectUrlKey) ??
              SupabaseConfig.projectUrl;
      _supabaseKeyController.text =
          prefs.getString(AppDatabase.supabasePublishableKeyKey) ??
              SupabaseConfig.publishableKey;
      _serverEnabled =
          prefs.getBool(DatabaseServerController.enabledKey) ?? false;
      _serverTokenController.text =
          prefs.getString(DatabaseServerController.tokenKey) ?? '';
      _portController.text =
          '${prefs.getInt(DatabaseServerController.portKey) ?? 8080}';
      if (_isDesktop) _addresses = await _server.getServerAddresses();
    } catch (error) {
      _loadError = 'Não foi possível carregar a configuração: $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  String? _validateUrl(String? value) {
    try {
      RemoteDatabase.normalizeServerUrl(value ?? '');
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Informe um endereço válido.';
    } on FormatException {
      return 'Informe um endereço válido.';
    }
  }

  String? _validateToken(String? value) {
    if ((value?.trim().length ?? 0) < 24) {
      return 'A chave de acesso deve ter pelo menos 24 caracteres.';
    }
    return null;
  }

  String? _validateSupabaseUrl(String? value) {
    try {
      SupabaseService.normalizeProjectUrl(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateSupabaseKey(String? value) {
    try {
      SupabaseService.validatePublishableKey(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port < 1024 || port > 65535) {
      return 'Informe uma porta entre 1024 e 65535.';
    }
    return null;
  }

  void _generateToken() {
    final random = Random.secure();
    _serverTokenController.text = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    setState(() => _obscureServerToken = false);
  }

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showMessage(message);
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_supabase) {
        await AppDatabase().testSupabaseConnection(
          projectUrl: _supabaseUrlController.text.trim(),
          publishableKey: _supabaseKeyController.text.trim(),
        );
      } else {
        await AppDatabase().testRemoteConnection(
          serverUrl: _urlController.text.trim(),
          token: _remoteTokenController.text.trim(),
        );
      }
      _showMessage('Conexão com o banco funcionando.');
    } catch (error) {
      _showMessage('Não foi possível conectar: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    try {
      if (_remote) {
        await AppDatabase().testRemoteConnection(
          serverUrl: _urlController.text.trim(),
          token: _remoteTokenController.text.trim(),
        );
      }
      if (_supabase) {
        await AppDatabase().testSupabaseConnection(
          projectUrl: _supabaseUrlController.text.trim(),
          publishableKey: _supabaseKeyController.text.trim(),
        );
      }
      await auth.logout();
      if (_isDesktop && ((_remote || _supabase) || !_serverEnabled)) {
        await _server.configure(
          enabled: false,
          token: _serverTokenController.text.trim(),
          port: int.tryParse(_portController.text.trim()) ?? 8080,
        );
      }
      if (_remote) {
        await AppDatabase().configureRemoteDatabase(
          serverUrl: _urlController.text.trim(),
          token: _remoteTokenController.text.trim(),
        );
      } else if (_supabase) {
        await AppDatabase().configureSupabaseDatabase(
          projectUrl: _supabaseUrlController.text.trim(),
          publishableKey: _supabaseKeyController.text.trim(),
        );
      } else {
        await AppDatabase().configureDatabase(
          useSharedDatabase: _localUsesShared,
          sharedPath: _sharedPath,
        );
        if (_isDesktop) {
          await _server.configure(
            enabled: _serverEnabled,
            token: _serverTokenController.text.trim(),
            port: int.tryParse(_portController.text.trim()) ?? 8080,
          );
        }
      }
      if (!mounted) return;
      _showMessage('Conexão salva. Entre novamente no sistema.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      _showMessage('Não foi possível salvar a conexão: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tokenField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback toggleVisibility,
  }) =>
      TextFormField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        validator: _validateToken,
        decoration: InputDecoration(
          labelText: 'Chave de acesso',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: obscure ? 'Mostrar chave' : 'Ocultar chave',
            onPressed: toggleVisibility,
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      );

  Widget _buildServerSettings() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compartilhar este banco com o celular'),
                subtitle: const Text(
                  'Ative o servidor neste PC e informe o endereço e a chave no celular.',
                ),
                value: _serverEnabled,
                onChanged: (value) {
                  setState(() => _serverEnabled = value);
                  if (value && _serverTokenController.text.isEmpty) {
                    _generateToken();
                  }
                },
              ),
              if (_serverEnabled) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  validator: _validatePort,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Porta do servidor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _tokenField(
                  controller: _serverTokenController,
                  obscure: _obscureServerToken,
                  toggleVisibility: () => setState(
                    () => _obscureServerToken = !_obscureServerToken,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _generateToken,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Gerar nova chave'),
                    ),
                    TextButton.icon(
                      onPressed: () => _copy(
                        _serverTokenController.text.trim(),
                        'Chave copiada.',
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar chave'),
                    ),
                  ],
                ),
                const Text(
                  'Salve para iniciar o servidor. O PC deve ficar ligado com o sistema aberto. '
                  'O celular deve estar no mesmo Wi-Fi. Permita a porta no firewall do PC, se necessário.',
                ),
                const SizedBox(height: 12),
                Text(
                  _server.isRunning
                      ? 'Servidor ativo na porta ${_server.port}.'
                      : 'Servidor ainda não está ativo.',
                ),
                if (_addresses.isEmpty)
                  const Text(
                    'Endereço: http://IP-DO-PC:PORTA. Consulte o IP do PC na sua rede.',
                  ),
                ..._addresses.map((address) {
                  final uri = Uri.parse(address).replace(
                    port: int.tryParse(_portController.text.trim()) ?? 8080,
                  );
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(uri.toString()),
                    trailing: IconButton(
                      tooltip: 'Copiar endereço',
                      onPressed: () => _copy(
                        uri.toString(),
                        'Endereço copiado.',
                      ),
                      icon: const Icon(Icons.copy),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Conexão com o banco')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(
                  absorbing: _busy,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Escolha onde os dados ficam. O Supabase permite usar o mesmo banco no PC e no celular pela internet.',
                              ),
                              if (_loadError != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _loadError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: Icon(
                                        !_remote && !_supabase
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                      ),
                                      title: Text(
                                        _localUsesShared
                                            ? 'Banco deste PC (arquivo compartilhado)'
                                            : 'Banco deste dispositivo',
                                      ),
                                      subtitle: const Text(
                                        'Usar os dados locais já configurados.',
                                      ),
                                      onTap: () => setState(() =>
                                          _selectedMode =
                                              AppDatabase.localMode),
                                    ),
                                    ListTile(
                                      leading: Icon(
                                        _remote
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                      ),
                                      title: const Text(
                                          'Banco por IP ou hospedagem'),
                                      subtitle: const Text(
                                        'Conectar ao mesmo banco do servidor.',
                                      ),
                                      onTap: () => setState(() =>
                                          _selectedMode =
                                              AppDatabase.remoteMode),
                                    ),
                                    ListTile(
                                      leading: Icon(
                                        _supabase
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                      ),
                                      title: const Text('Supabase (internet)'),
                                      subtitle: const Text(
                                        'Mesmo banco PostgreSQL no PC e no celular, mesmo em redes diferentes.',
                                      ),
                                      onTap: () => setState(() =>
                                          _selectedMode =
                                              AppDatabase.supabaseMode),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_supabase) ...[
                                TextFormField(
                                  controller: _supabaseUrlController,
                                  validator: _validateSupabaseUrl,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'URL do projeto Supabase',
                                    hintText: 'https://seu-projeto.supabase.co',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _supabaseKeyController,
                                  validator: _validateSupabaseKey,
                                  obscureText: _obscureSupabaseKey,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: InputDecoration(
                                    labelText: 'Chave pública Publishable',
                                    helperText:
                                        'Use sb_publishable_. Nunca informe Secret key ou service_role.',
                                    helperMaxLines: 2,
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: _obscureSupabaseKey
                                          ? 'Mostrar chave'
                                          : 'Ocultar chave',
                                      onPressed: () => setState(() =>
                                          _obscureSupabaseKey =
                                              !_obscureSupabaseKey),
                                      icon: Icon(_obscureSupabaseKey
                                          ? Icons.visibility_off
                                          : Icons.visibility),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'O acesso aos dados exige um usuário do Supabase. O banco continua disponível mesmo com o PC desligado.',
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _testConnection,
                                  icon: const Icon(Icons.cloud_done_outlined),
                                  label: const Text('Testar Supabase'),
                                ),
                              ] else if (_remote) ...[
                                TextFormField(
                                  controller: _urlController,
                                  validator: _validateUrl,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'Endereço IP ou URL do servidor',
                                    hintText: '192.168.1.10:8080',
                                    helperText:
                                        'Ex.: IP-DO-PC:8080 ou https://seu-dominio.com',
                                    helperMaxLines: 2,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _tokenField(
                                  controller: _remoteTokenController,
                                  obscure: _obscureRemoteToken,
                                  toggleVisibility: () => setState(
                                    () => _obscureRemoteToken =
                                        !_obscureRemoteToken,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Informe a mesma chave configurada no servidor. '
                                  'Para acessar o PC por IP, use o mesmo Wi-Fi e mantenha o PC ligado. '
                                  'Para acesso pela internet, use uma hospedagem com HTTPS e o servidor do sistema instalado.',
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _testConnection,
                                  icon: const Icon(Icons.wifi_tethering),
                                  label: const Text('Testar conexão'),
                                ),
                              ] else if (_isDesktop)
                                _buildServerSettings(),
                              const SizedBox(height: 16),
                              const Text(
                                'Ao salvar, sua sessão será encerrada. Entre com o usuário e a senha do banco escolhido.',
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _busy ? null : _save,
                                icon: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save),
                                label: Text(
                                  _busy
                                      ? 'Aguarde...'
                                      : 'Salvar e voltar ao login',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
}
