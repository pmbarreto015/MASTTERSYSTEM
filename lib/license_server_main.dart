import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/licensing/license_admin_config.dart';
import 'services/lan_license_server.dart';
import 'services/license_package_store.dart';
import 'services/offline_license_issuer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LicenseAdminConfig.initialize();
  } catch (_) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Não foi possível carregar a senha administrativa. '
              'Verifique o acesso à pasta de dados do servidor e a integridade '
              'do arquivo de credenciais antes de abrir novamente.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }
  final server = await LanLicenseServer.create();
  await server.start();
  final preferences = await SharedPreferences.getInstance();
  runApp(LanLicenseServerApp(
    server: server,
    packages: LicensePackageStore(preferences),
  ));
}

class LanLicenseServerApp extends StatelessWidget {
  const LanLicenseServerApp(
      {super.key, required this.server, required this.packages});

  final LanLicenseServer server;
  final LicensePackageStore packages;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MastterSystem - Administrador de Licenças',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F8BFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF182431),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1720),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFF243447),
        ),
      ),
      home: LicenseAdminGate(server: server, packages: packages),
    );
  }
}

class LicenseAdminGate extends StatefulWidget {
  const LicenseAdminGate(
      {super.key, required this.server, required this.packages});

  final LanLicenseServer server;
  final LicensePackageStore packages;

  @override
  State<LicenseAdminGate> createState() => _LicenseAdminGateState();
}

class _LicenseAdminGateState extends State<LicenseAdminGate> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _unlocked = false;
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (!LicenseAdminConfig.verifyPassword(_passwordController.text)) {
      setState(() => _error = 'Senha administrativa incorreta.');
      return;
    }
    _passwordController.clear();
    setState(() {
      _unlocked = true;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (LicenseAdminConfig.isConfigured) {
      _unlock();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final error = await LicenseAdminConfig.configurePassword(
        _passwordController.text,
        confirmation: _confirmationController.text,
      );
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _saving = false;
          _error = error;
        });
        return;
      }
      _passwordController.clear();
      _confirmationController.clear();
      setState(() {
        _saving = false;
        _unlocked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Não foi possível salvar a senha. Verifique o acesso à pasta de dados e tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return LicenseServerScreen(
        server: widget.server,
        packages: widget.packages,
        onLock: () => setState(() => _unlocked = false),
      );
    }
    final setup = !LicenseAdminConfig.isConfigured;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(0xFF0F62AC),
                      child: Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      setup
                          ? 'Crie sua senha administrativa'
                          : 'Administrador de Licenças',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      setup
                          ? 'Primeiro acesso: defina a senha para proteger o cadastro e a renovação de licenças. Guarde-a em local seguro.'
                          : widget.server.isRunning
                              ? 'O servidor está ativo. Digite a senha administrativa para gerenciar clientes.'
                              : 'O servidor está parado. Entre para verificar a configuração.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _passwordController,
                      enabled: !_saving,
                      autofocus: true,
                      obscureText: !_showPassword,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Senha administrativa',
                        helperText:
                            setup ? 'Use pelo menos 8 caracteres.' : null,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                        errorText: _error,
                      ),
                    ),
                    if (setup) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('license-admin-confirmation'),
                        controller: _confirmationController,
                        enabled: !_saving,
                        obscureText: !_showPassword,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirme a senha administrativa',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ],
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Icon(setup ? Icons.password : Icons.login),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(setup
                              ? 'Criar senha administrativa'
                              : 'Entrar no administrador'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LicenseServerScreen extends StatefulWidget {
  const LicenseServerScreen({
    super.key,
    required this.server,
    required this.packages,
    required this.onLock,
    this.offlineLicenseGenerator,
  });

  final LanLicenseServer server;
  final LicensePackageStore packages;
  final VoidCallback onLock;
  final OfflineLicenseGenerator? offlineLicenseGenerator;

  @override
  State<LicenseServerScreen> createState() => _LicenseServerScreenState();
}

class _LicenseServerScreenState extends State<LicenseServerScreen> {
  List<String> _addresses = const [];
  Timer? _statusTimer;
  final Set<String> _busyCustomers = {};
  final _remoteAddressController = TextEditingController();
  final _remoteTokenController = TextEditingController();
  bool _remoteBusy = false;
  bool _rememberRemoteToken = false;
  bool _showRemoteToken = false;
  String? _remoteMessage;
  static const _remoteAddressKey = 'license_admin_remote_address';
  static const _remoteTokenKey = 'license_admin_remote_token';

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    _loadRemoteSettings();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _remoteAddressController.dispose();
    _remoteTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await widget.server.localAddresses();
      if (mounted) setState(() => _addresses = addresses);
    } catch (_) {
      if (mounted) setState(() => _addresses = const []);
    }
  }

  Future<void> _loadRemoteSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      _remoteAddressController.text = widget.server.remoteAddress ??
          preferences.getString(_remoteAddressKey) ??
          '';
      final token = preferences.getString(_remoteTokenKey) ?? '';
      _remoteTokenController.text = token;
      setState(() => _rememberRemoteToken = token.isNotEmpty);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _remoteMessage = 'Não foi possível carregar a conexão salva.');
      }
    }
  }

  Future<void> _connectRemote() async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteMessage = null;
    });
    try {
      final error = await widget.server.connectRemote(
        serverAddress: _remoteAddressController.text.trim(),
        adminToken: _remoteTokenController.text.trim(),
      );
      if (!mounted) return;
      if (error != null) {
        setState(() => _remoteMessage = error);
        return;
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
          _remoteAddressKey, widget.server.remoteAddress!);
      if (_rememberRemoteToken) {
        await preferences.setString(
            _remoteTokenKey, _remoteTokenController.text.trim());
      } else {
        await preferences.remove(_remoteTokenKey);
      }
      if (mounted) {
        setState(() => _remoteMessage =
            'Conectado. A aba Licenças agora gerencia os clientes deste servidor pela internet.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _remoteMessage = widget.server.isRemote
            ? 'Conexão ativa, mas não foi possível salvar as preferências locais.'
            : 'Não foi possível conectar. Verifique o endereço, a chave administrativa e a internet.');
      }
    } finally {
      if (mounted) setState(() => _remoteBusy = false);
    }
  }

  Future<void> _remoteAction({bool disconnect = false}) async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteMessage = null;
    });
    try {
      if (disconnect) {
        await widget.server.disconnectRemote();
      } else {
        await widget.server.refreshCustomers();
      }
      if (mounted) {
        setState(() => _remoteMessage = disconnect
            ? 'Desconectado da internet. A aba Licenças voltou ao cadastro deste computador.'
            : 'Lista de clientes atualizada.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _remoteMessage =
            'Não foi possível concluir a operação. Verifique a conexão e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _remoteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    return DefaultTabController(
      length: 4,
      child: AnimatedBuilder(
        animation: widget.server,
        builder: (context, _) {
          final customers = widget.server.customers;
          final activeCount = customers
              .where((customer) => customer.active && !customer.isExpired)
              .length;
          final expiredCount = customers
              .where((customer) => customer.active && customer.isExpired)
              .length;
          final blockedCount =
              customers.where((customer) => !customer.active).length;
          return Scaffold(
            appBar: AppBar(
              bottom: const TabBar(isScrollable: true, tabs: [
                Tab(icon: Icon(Icons.key_outlined), text: 'Licenças'),
                Tab(icon: Icon(Icons.public), text: 'Internet'),
                Tab(icon: Icon(Icons.vpn_key_outlined), text: 'Chaves offline'),
                Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Pacotes'),
              ]),
              title: Text(
                  compact ? 'ADM de Licenças' : 'Administrador de Licenças'),
              actions: [
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Chip(
                      avatar: _serverStatusIcon(),
                      label: Text(widget.server.isRemote
                          ? widget.server.isRunning
                              ? 'Internet conectada'
                              : 'Internet indisponível'
                          : widget.server.isRunning
                              ? 'Servidor ativo'
                              : 'Servidor parado'),
                    ),
                  )
                else
                  Tooltip(
                    message: widget.server.isRemote
                        ? widget.server.isRunning
                            ? 'Internet conectada'
                            : 'Internet indisponível'
                        : widget.server.isRunning
                            ? 'Servidor ativo'
                            : 'Servidor parado',
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _serverStatusIcon(),
                    ),
                  ),
                IconButton(
                  tooltip: 'Bloquear administrador',
                  onPressed: widget.onLock,
                  icon: const Icon(Icons.lock_outline),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: TabBarView(children: [
              Scaffold(
                backgroundColor: Colors.transparent,
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: _showCreateCustomerDialog,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Novo acesso'),
                ),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              compact ? 12 : 20, 16, compact ? 12 : 20, 10),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _serverCard(),
                                const SizedBox(height: 18),
                                const Text('Licenças de clientes',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Chip(
                                        label: Text(
                                            '${customers.length} clientes')),
                                    Chip(label: Text('$activeCount ativas')),
                                    Chip(
                                        label: Text('$expiredCount expiradas')),
                                    Chip(
                                        label:
                                            Text('$blockedCount bloqueadas')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (customers.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 48),
                              child: Text(
                                'Crie um acesso de teste para APK ou EXE.\nEscolha o prazo, a plataforma e o limite de dispositivos.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                                compact ? 12 : 20, 0, compact ? 12 : 20, 100),
                            sliver: SliverList.builder(
                              itemCount: customers.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _customerCard(customers[index]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              _internetPanel(),
              _OfflineLicensePanel(generator: widget.offlineLicenseGenerator),
              _LicensePackagesScreen(store: widget.packages),
            ]),
          );
        },
      ),
    );
  }

  Icon _serverStatusIcon() => Icon(
        Icons.circle,
        size: 12,
        color: widget.server.isRunning ? Colors.greenAccent : Colors.redAccent,
      );

  Widget _internetPanel() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Controle de licenças pela internet',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'Conecte este administrador ao seu servidor online para cadastrar, renovar e bloquear clientes de qualquer rede.'),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          widget.server.isRemote
                              ? '${widget.server.isRunning ? 'Conectado' : 'Conexão indisponível'}: ${widget.server.remoteAddress}'
                              : 'Modo atual: servidor deste computador',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('remote-license-address'),
                        controller: _remoteAddressController,
                        enabled: !_remoteBusy && !widget.server.isRemote,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Endereço HTTPS do servidor',
                          hintText: 'https://licencas.suaempresa.com.br',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('remote-license-token'),
                        controller: _remoteTokenController,
                        enabled: !_remoteBusy && !widget.server.isRemote,
                        obscureText: !_showRemoteToken,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Chave administrativa do servidor',
                          helperText:
                              'Uso exclusivo do ADM. Envie ao cliente somente o endereço, login e senha.',
                          helperMaxLines: 3,
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _showRemoteToken = !_showRemoteToken),
                            icon: Icon(_showRemoteToken
                                ? Icons.visibility_off
                                : Icons.visibility),
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title:
                            const Text('Lembrar a chave neste administrador'),
                        subtitle: const Text(
                            'A conexão salva não é enviada nos pacotes dos clientes.'),
                        value: _rememberRemoteToken,
                        onChanged: _remoteBusy || widget.server.isRemote
                            ? null
                            : (value) => setState(
                                () => _rememberRemoteToken = value ?? false),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 8, children: [
                        if (!widget.server.isRemote)
                          FilledButton.icon(
                            key: const ValueKey('remote-license-connect'),
                            onPressed: _remoteBusy ? null : _connectRemote,
                            icon: const Icon(Icons.public),
                            label: const Text('Conectar ao servidor online'),
                          )
                        else ...[
                          FilledButton.icon(
                              onPressed:
                                  _remoteBusy ? null : () => _remoteAction(),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Atualizar clientes')),
                          OutlinedButton.icon(
                              onPressed: _remoteBusy
                                  ? null
                                  : () => _remoteAction(disconnect: true),
                              icon: const Icon(Icons.link_off),
                              label: const Text('Desconectar')),
                        ],
                      ]),
                      if (_remoteBusy)
                        const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: LinearProgressIndicator()),
                      if (_remoteMessage != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(_remoteMessage!,
                                key: const ValueKey('remote-license-message'))),
                    ]),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
                'O servidor deve estar publicado com HTTPS e permanecer online. Depois de conectar, use a aba Licenças para gerenciar os acessos. Para uso sem internet, escolha Chaves offline.'),
          ]),
        ),
      );

  Widget _serverCard() {
    if (widget.server.isRemote) {
      return Card(
        color: widget.server.isRunning
            ? const Color(0xFF123C32)
            : const Color(0xFF4A2025),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                widget.server.isRunning
                    ? 'Gerenciando licenças pela internet'
                    : 'Servidor online indisponível',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText('Servidor: ${widget.server.remoteAddress}'),
            const SizedBox(height: 6),
            const Text(
                'Envie este endereço junto com o login e a senha. O cliente pode ativar de qualquer rede com internet.'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: _remoteBusy ? null : () => _remoteAction(),
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar clientes')),
            if (_remoteBusy) const LinearProgressIndicator(),
            if (widget.server.serverError != null ||
                _remoteMessage != null) ...[
              const SizedBox(height: 10),
              Text(widget.server.serverError ?? _remoteMessage!),
            ],
          ]),
        ),
      );
    }
    final error = widget.server.serverError;
    return Card(
      color: widget.server.isRunning
          ? const Color(0xFF123C32)
          : const Color(0xFF4A2025),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.server.isRunning ? Icons.lan : Icons.warning_amber,
                    size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    error ??
                        'Mantenha este programa aberto no computador principal.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              _addresses.isEmpty
                  ? 'Endereço da rede não identificado.'
                  : 'Endereço: ${_addresses.join('  ou  ')}',
            ),
            const SizedBox(height: 6),
            const Text(
                'O APK e o EXE precisam alcançar este servidor pela rede.'),
            const SizedBox(height: 6),
            const Text(
                'Para ativar de outras redes, configure a aba Internet ou gere uma Chave offline para o aparelho.'),
            if (!widget.server.isRunning) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: widget.server.start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar servidor'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _customerCard(LanLicenseCustomer customer) {
    final busy = _busyCustomers.contains(customer.id);
    final status = !customer.active
        ? 'Bloqueada'
        : customer.isExpired
            ? 'Expirada'
            : customer.expiresAt == null
                ? 'Permanente'
                : 'Ativa';
    final statusColor = !customer.active || customer.isExpired
        ? Colors.orangeAccent
        : Colors.greenAccent;
    return Card(
      child: ExpansionTile(
        key: ValueKey(customer.id),
        leading: CircleAvatar(
          child: Text(
              customer.name.isEmpty ? '?' : customer.name[0].toUpperCase()),
        ),
        title: Wrap(
          spacing: 10,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(customer.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(status, style: TextStyle(color: statusColor, fontSize: 13)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Login: ${customer.login}\n'
            '${_platformLabel(customer.allowedPlatform)} • ${customer.devices.length}/${customer.maxDevices} dispositivos\n'
            '${customer.expiresAt == null ? 'Sem vencimento' : 'Vence em ${_formatDateTime(customer.expiresAt!)}'}',
          ),
        ),
        trailing: Tooltip(
          message: customer.active ? 'Bloquear acesso' : 'Reativar acesso',
          child: Switch(
            value: customer.active,
            onChanged:
                busy ? null : (value) => _setCustomerActive(customer, value),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => _showEditLicenseDialog(customer),
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Renovar / editar licença'),
              ),
            ),
          ),
          if (customer.devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nenhum dispositivo ativado.'),
            )
          else
            ...customer.devices.map(
              (device) => ListTile(
                leading: Icon(device.platform == 'android'
                    ? Icons.phone_android
                    : Icons.computer),
                title: Text(device.machineName.isEmpty
                    ? 'Dispositivo sem nome'
                    : device.machineName),
                subtitle: Text(
                  '${_platformLabel(device.platform)} • ${device.machineCode}\n'
                  'Último acesso: ${_formatDateTime(device.lastSeenAt)}',
                ),
                trailing: IconButton(
                  tooltip: 'Liberar esta vaga',
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed:
                      busy ? null : () => _confirmRelease(customer, device),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Future<void> _setCustomerActive(
      LanLicenseCustomer customer, bool value) async {
    await _customerAction(
        customer, () => widget.server.setCustomerActive(customer, value));
  }

  Future<void> _customerAction(
    LanLicenseCustomer customer,
    Future<void> Function() action,
  ) async {
    if (_busyCustomers.contains(customer.id)) return;
    setState(() => _busyCustomers.add(customer.id));
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Não foi possível salvar a alteração. Tente novamente.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busyCustomers.remove(customer.id));
    }
  }

  Future<void> _showCreateCustomerDialog() async {
    final result = await showDialog<_LicenseEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LicenseEditorDialog(
        server: widget.server,
        addresses: _addresses,
      ),
    );
    if (result == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acesso criado'),
        content:
            SingleChildScrollView(child: SelectableText(result.credentials!)),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result.credentials!));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar e fechar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditLicenseDialog(LanLicenseCustomer customer) async {
    final result = await showDialog<_LicenseEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LicenseEditorDialog(
        server: widget.server,
        addresses: _addresses,
        customer: customer,
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.expiresAt == null
            ? 'Licença atualizada: acesso permanente.'
            : 'Licença atualizada até ${_formatDateTime(result.expiresAt!)}.'),
      ));
    }
  }

  Future<void> _confirmRelease(
    LanLicenseCustomer customer,
    LanLicensedDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liberar dispositivo?'),
        content: Text(
          'O dispositivo “${device.machineName}” perderá o acesso e a vaga poderá ser usada em outro aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Liberar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _customerAction(
          customer, () => widget.server.releaseDevice(customer, device));
    }
  }
}

class _LicenseEditorResult {
  const _LicenseEditorResult({this.credentials, this.expiresAt});

  final String? credentials;
  final DateTime? expiresAt;
}

class _LicenseEditorDialog extends StatefulWidget {
  const _LicenseEditorDialog({
    required this.server,
    required this.addresses,
    this.customer,
  });

  final LanLicenseServer server;
  final List<String> addresses;
  final LanLicenseCustomer? customer;

  @override
  State<_LicenseEditorDialog> createState() => _LicenseEditorDialogState();
}

class _LicenseEditorDialogState extends State<_LicenseEditorDialog> {
  final _nameController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _devicesController = TextEditingController(text: '1');
  final _durationController = TextEditingController(text: '7');
  String _validity = '7';
  String _durationUnit = 'days';
  String _platform = 'both';
  DateTime _durationStart = DateTime.now();
  late DateTime _selectedDeadline;
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedDeadline = _durationStart.add(const Duration(days: 7));
    final customer = widget.customer;
    if (customer != null) {
      _nameController.text = customer.name;
      _loginController.text = customer.login;
      _devicesController.text = customer.maxDevices.toString();
      _platform = customer.allowedPlatform;
      if (customer.expiresAt == null) {
        _validity = 'permanent';
      } else if (!customer.isExpired) {
        _validity = 'date';
        _selectedDeadline = customer.expiresAt!.toLocal();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _devicesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  DateTime? get _expiresAt {
    if (_validity == 'permanent') return null;
    if (_validity == 'date') return _selectedDeadline.toUtc();
    final amount = int.tryParse(
        _validity == 'custom' ? _durationController.text : _validity);
    if (amount == null || amount < 1 || amount > 36500) return null;
    final duration = _validity == 'custom' && _durationUnit == 'hours'
        ? Duration(hours: amount)
        : Duration(days: amount);
    return _durationStart.add(duration).toUtc();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final expiresAt = _expiresAt;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(customer == null
            ? 'Novo acesso de teste'
            : 'Renovar / editar licença'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (customer == null) ...[
                  TextField(
                    key: const ValueKey('license-name'),
                    controller: _nameController,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Nome do cliente'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('license-login'),
                    controller: _loginController,
                    enabled: !_saving,
                    autocorrect: false,
                    decoration:
                        const InputDecoration(labelText: 'Login para ativação'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('license-password'),
                    controller: _passwordController,
                    enabled: !_saving,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Senha para ativação',
                      helperText: 'Pelo menos 6 caracteres.',
                      suffixIcon: IconButton(
                        onPressed: _saving
                            ? null
                            : () =>
                                setState(() => _showPassword = !_showPassword),
                        icon: Icon(_showPassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(customer.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Login: ${customer.login}'),
                  Text(customer.expiresAt == null
                      ? 'Validade atual: permanente'
                      : 'Validade atual: ${_formatDateTime(customer.expiresAt!)}'),
                  if (!customer.active)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                          'Este acesso está bloqueado. Reative-o no painel após salvar.',
                          style: TextStyle(color: Colors.orangeAccent)),
                    ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('license-platform'),
                  initialValue: _platform,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Liberar para'),
                  items: const [
                    DropdownMenuItem(
                        value: 'both', child: Text('APK e EXE (ambos)')),
                    DropdownMenuItem(
                        value: 'android', child: Text('APK (Android)')),
                    DropdownMenuItem(
                        value: 'windows', child: Text('EXE (Windows)')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _platform = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('license-devices'),
                  controller: _devicesController,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Limite de dispositivos',
                    helperText:
                        'Total de celulares e computadores: de 1 a 999.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('license-validity'),
                  initialValue: _validity,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Prazo da licença'),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('Teste de 1 dia')),
                    DropdownMenuItem(
                        value: '7', child: Text('Teste de 7 dias')),
                    DropdownMenuItem(
                        value: '15', child: Text('Teste de 15 dias')),
                    DropdownMenuItem(
                        value: '30', child: Text('Teste de 30 dias')),
                    DropdownMenuItem(
                        value: 'custom', child: Text('Duração personalizada')),
                    DropdownMenuItem(
                        value: 'date',
                        child: Text('Data e hora de vencimento')),
                    DropdownMenuItem(
                        value: 'permanent',
                        child: Text('Permanente (sem vencimento)')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                            _validity = value!;
                            _durationStart = DateTime.now();
                            _error = null;
                          }),
                ),
                if (_validity == 'custom') ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('license-duration'),
                    controller: _durationController,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration:
                        const InputDecoration(labelText: 'Quantidade de tempo'),
                    onChanged: (_) => setState(() {
                      _durationStart = DateTime.now();
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('license-duration-unit'),
                    initialValue: _durationUnit,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Unidade do prazo'),
                    items: const [
                      DropdownMenuItem(value: 'hours', child: Text('Horas')),
                      DropdownMenuItem(value: 'days', child: Text('Dias')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                              _durationUnit = value!;
                              _durationStart = DateTime.now();
                            }),
                  ),
                ],
                if (_validity == 'date') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('license-date'),
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(_formatDateTime(_selectedDeadline)
                            .split(' ')
                            .first),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('license-time'),
                        onPressed: _saving ? null : _pickTime,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(
                            _formatDateTime(_selectedDeadline).split(' ').last),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _validity == 'permanent'
                        ? 'Acesso permanente, sem data de vencimento.'
                        : expiresAt == null
                            ? 'Informe uma duração entre 1 e 36.500.'
                            : 'Vencimento: ${_formatDateTime(expiresAt)}\n'
                                'Horário deste computador. O acesso será bloqueado ao vencer.',
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('license-save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(customer == null ? 'Criar acesso' : 'Salvar licença'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 100, 12, 31);
    final initialDate = _selectedDeadline.isBefore(firstDate)
        ? firstDate
        : _selectedDeadline.isAfter(lastDate)
            ? lastDate
            : _selectedDeadline;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Data de vencimento',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (date == null || !mounted) return;
    setState(() {
      _selectedDeadline = DateTime(date.year, date.month, date.day,
          _selectedDeadline.hour, _selectedDeadline.minute);
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDeadline),
      helpText: 'Hora de vencimento',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selectedDeadline = DateTime(
          _selectedDeadline.year,
          _selectedDeadline.month,
          _selectedDeadline.day,
          time.hour,
          time.minute);
      _error = null;
    });
  }

  Future<void> _save() async {
    final expiresAt = _expiresAt;
    if (_validity != 'permanent' && expiresAt == null) {
      setState(() => _error = 'Informe uma duração entre 1 e 36.500.');
      return;
    }
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
      setState(
          () => _error = 'Escolha uma data e hora de vencimento no futuro.');
      return;
    }
    final maxDevices = int.tryParse(_devicesController.text) ?? 0;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final customer = widget.customer;
      final error = customer == null
          ? await widget.server.createCustomer(
              name: _nameController.text,
              login: _loginController.text,
              password: _passwordController.text,
              maxDevices: maxDevices,
              expiresAt: expiresAt,
              allowedPlatform: _platform,
            )
          : await widget.server.updateCustomerLicense(
              customer: customer,
              expiresAt: expiresAt,
              allowedPlatform: _platform,
              maxDevices: maxDevices,
            );
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _error = error;
          _saving = false;
        });
        return;
      }
      final addresses = widget.server.isRemote
          ? widget.server.remoteAddress!
          : widget.addresses.isEmpty
              ? 'Consulte o endereço no painel do servidor.'
              : widget.addresses
                  .map((address) => 'http://$address')
                  .join(' ou ');
      final credentials = customer == null
          ? 'Cliente: ${_nameController.text.trim()}\n'
              'Login: ${_loginController.text.trim().toLowerCase()}\n'
              'Senha: ${_passwordController.text}\n'
              'Plataforma: ${_platformLabel(_platform)}\n'
              'Limite: $maxDevices dispositivo(s)\n'
              'Validade: ${expiresAt == null ? 'Permanente (sem vencimento)' : _formatDateTime(expiresAt)}\n'
              'Servidor: $addresses\n'
              '${widget.server.isRemote ? 'Escolha a ativação pela internet e informe o servidor, login e senha. Pode usar qualquer rede com internet.' : 'Conecte o aplicativo à rede deste servidor para ativar e validar o acesso.'}'
          : null;
      setState(() => _saving = false);
      Navigator.pop(
          context,
          _LicenseEditorResult(
            credentials: credentials,
            expiresAt: expiresAt,
          ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Não foi possível salvar a licença. Verifique o acesso à pasta de dados e tente novamente.';
      });
    }
  }
}

String _platformLabel(String platform) => switch (platform) {
      'android' => 'APK (Android)',
      'windows' => 'EXE (Windows)',
      _ => 'APK e EXE',
    };

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

typedef OfflineLicenseGenerator = Future<String> Function({
  required String customerName,
  required String installationCode,
  required String platform,
  required DateTime expiresAt,
});

class _OfflineLicensePanel extends StatefulWidget {
  const _OfflineLicensePanel({this.generator});

  final OfflineLicenseGenerator? generator;

  @override
  State<_OfflineLicensePanel> createState() => _OfflineLicensePanelState();
}

class _OfflineLicensePanelState extends State<_OfflineLicensePanel>
    with AutomaticKeepAliveClientMixin {
  final _nameController = TextEditingController();
  final _installationController = TextEditingController();
  final _durationController = TextEditingController(text: '7');
  String _platform = 'windows';
  String _validity = '7';
  String _durationUnit = 'days';
  DateTime _durationStart = DateTime.now();
  late DateTime _selectedDeadline;
  DateTime? _issuedDeadline;
  String? _licenseKey;
  String? _message;
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedDeadline = _durationStart.add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _installationController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) => setState(() {
        change();
        _licenseKey = null;
        _issuedDeadline = null;
        _message = null;
      });

  DateTime? get _expiresAt {
    if (_validity == 'date') return _selectedDeadline.toUtc();
    final amount = int.tryParse(
        _validity == 'custom' ? _durationController.text : _validity);
    if (amount == null || amount < 1 || amount > 36500) return null;
    return _durationStart
        .add(_validity == 'custom' && _durationUnit == 'hours'
            ? Duration(hours: amount)
            : Duration(days: amount))
        .toUtc();
  }

  String get _receipt => 'Licença offline MastterSystem\n'
      'Cliente: ${_nameController.text.trim()}\n'
      'Código do aparelho: ${_installationController.text.trim()}\n'
      'Plataforma: ${_platformLabel(_platform)}\n'
      'Validade: ${_formatDateTime(_issuedDeadline!)}\n\n'
      'Chave:\n$_licenseKey\n\n'
      'No aplicativo, escolha Por chave offline e cole a chave ou importe o arquivo .lic. '
      'A chave é válida apenas para este aparelho. Para renovar, solicite outra chave.';

  Future<void> _generate() async {
    if (_busy) return;
    final deadline = _expiresAt;
    if (_nameController.text.trim().isEmpty) {
      setState(() => _message = 'Informe o nome do cliente.');
      return;
    }
    if (!RegExp(r'^\d{12}$').hasMatch(_installationController.text.trim())) {
      setState(() => _message =
          'Informe os 12 dígitos do código exibido no aplicativo do cliente.');
      return;
    }
    if (deadline == null || !deadline.isAfter(DateTime.now().toUtc())) {
      setState(
          () => _message = 'Escolha um prazo válido com vencimento no futuro.');
      return;
    }
    setState(() {
      _busy = true;
      _licenseKey = null;
      _message = null;
    });
    try {
      final OfflineLicenseGenerator generator = widget.generator ??
          (await OfflineLicenseIssuer.fromCompiledKey()).issue;
      final key = await generator(
        customerName: _nameController.text.trim(),
        installationCode: _installationController.text.trim(),
        platform: _platform,
        expiresAt: deadline,
      );
      if (!mounted) return;
      setState(() {
        _licenseKey = key;
        _issuedDeadline = deadline;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Não foi possível gerar a chave: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy({bool withDetails = false}) async {
    try {
      await Clipboard.setData(
          ClipboardData(text: withDetails ? _receipt : _licenseKey!));
      if (mounted) {
        setState(() => _message = withDetails
            ? 'Dados e chave copiados.'
            : 'Chave copiada. Envie ao cliente.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Não foi possível copiar. Selecione a chave e copie manualmente.');
      }
    }
  }

  Future<void> _export() async {
    if (_busy || _licenseKey == null) return;
    final key = _licenseKey!;
    final installation = _installationController.text.trim();
    setState(() => _busy = true);
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar chave offline',
        fileName: 'MastterSystem_$installation.lic',
        type: FileType.custom,
        allowedExtensions: const ['lic'],
        bytes: Uint8List.fromList(utf8.encode(key)),
      );
      if (destination == null) return;
      final path = destination.toLowerCase().endsWith('.lic')
          ? destination
          : '$destination.lic';
      await File(path).writeAsString(key, encoding: utf8, flush: true);
      if (mounted) setState(() => _message = 'Chave salva em $path');
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Não foi possível salvar o arquivo. Escolha uma pasta com permissão de gravação.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = DateTime(now.year + 100, 12, 31);
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline.isBefore(first)
          ? first
          : _selectedDeadline.isAfter(last)
              ? last
              : _selectedDeadline,
      firstDate: first,
      lastDate: last,
      helpText: 'Data de vencimento',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (date == null || !mounted) return;
    _change(() => _selectedDeadline = DateTime(date.year, date.month, date.day,
        _selectedDeadline.hour, _selectedDeadline.minute));
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDeadline),
      helpText: 'Hora de vencimento',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (time == null || !mounted) return;
    _change(() => _selectedDeadline = DateTime(
        _selectedDeadline.year,
        _selectedDeadline.month,
        _selectedDeadline.day,
        time.hour,
        time.minute));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final deadline = _expiresAt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Gerar chave com prazo para um aparelho',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Peça ao cliente o código de 12 dígitos exibido na ativação. Gere a chave e envie por mensagem ou arquivo .lic. O APK e o EXE podem funcionar sem estar na sua rede.'),
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                            key: const ValueKey('offline-license-name'),
                            controller: _nameController,
                            enabled: !_busy,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => _change(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Nome do cliente')),
                        const SizedBox(height: 12),
                        TextField(
                            key: const ValueKey('offline-license-installation'),
                            controller: _installationController,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(12)
                            ],
                            onChanged: (_) => _change(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Código do aparelho (12 dígitos)',
                                helperText:
                                    'Copie o código da tela de ativação do cliente.')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('offline-license-platform'),
                          initialValue: _platform,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Plataforma do aparelho'),
                          items: const [
                            DropdownMenuItem(
                                value: 'windows', child: Text('EXE (Windows)')),
                            DropdownMenuItem(
                                value: 'android', child: Text('APK (Android)'))
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => _change(() => _platform = value!),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('offline-license-validity'),
                          initialValue: _validity,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Prazo da chave'),
                          items: const [
                            DropdownMenuItem(
                                value: '1', child: Text('Teste de 1 dia')),
                            DropdownMenuItem(
                                value: '7', child: Text('Teste de 7 dias')),
                            DropdownMenuItem(
                                value: '15', child: Text('Teste de 15 dias')),
                            DropdownMenuItem(
                                value: '30', child: Text('Teste de 30 dias')),
                            DropdownMenuItem(
                                value: 'custom',
                                child: Text('Duração personalizada')),
                            DropdownMenuItem(
                                value: 'date',
                                child: Text('Data e hora de vencimento'))
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => _change(() {
                                    _validity = value!;
                                    _durationStart = DateTime.now();
                                  }),
                        ),
                        if (_validity == 'custom') ...[
                          const SizedBox(height: 12),
                          TextField(
                              key: const ValueKey('offline-license-duration'),
                              controller: _durationController,
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: const InputDecoration(
                                  labelText: 'Quantidade de tempo'),
                              onChanged: (_) => _change(
                                  () => _durationStart = DateTime.now())),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              key: const ValueKey(
                                  'offline-license-duration-unit'),
                              initialValue: _durationUnit,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Unidade do prazo'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'hours', child: Text('Horas')),
                                DropdownMenuItem(
                                    value: 'days', child: Text('Dias'))
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => _change(() {
                                        _durationUnit = value!;
                                        _durationStart = DateTime.now();
                                      })),
                        ],
                        if (_validity == 'date') ...[
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(
                                key: const ValueKey('offline-license-date'),
                                onPressed: _busy ? null : _pickDate,
                                icon: const Icon(Icons.calendar_today),
                                label: Text(_formatDateTime(_selectedDeadline)
                                    .split(' ')
                                    .first)),
                            OutlinedButton.icon(
                                key: const ValueKey('offline-license-time'),
                                onPressed: _busy ? null : _pickTime,
                                icon: const Icon(Icons.schedule),
                                label: Text(_formatDateTime(_selectedDeadline)
                                    .split(' ')
                                    .last)),
                          ]),
                        ],
                        const SizedBox(height: 14),
                        Text(
                            deadline == null
                                ? 'Informe uma duração entre 1 e 36.500.'
                                : 'Vencimento: ${_formatDateTime(deadline)} (horário deste computador).',
                            key: const ValueKey('offline-license-deadline')),
                        const SizedBox(height: 14),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                                key: const ValueKey('offline-license-generate'),
                                onPressed: _busy ? null : _generate,
                                icon: const Icon(Icons.vpn_key),
                                label: const Text('Gerar chave offline'))),
                        if (_busy)
                          const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: LinearProgressIndicator()),
                        if (_message != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(_message!,
                                  key: const ValueKey(
                                      'offline-license-message'))),
                      ]))),
          if (_licenseKey != null) ...[
            const SizedBox(height: 12),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'Chave gerada · vence em ${_formatDateTime(_issuedDeadline!)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          SelectableText(_licenseKey!,
                              key: const ValueKey('offline-license-result')),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(
                                key: const ValueKey('offline-license-copy'),
                                onPressed: _busy ? null : () => _copy(),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copiar chave')),
                            OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _copy(withDetails: true),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Copiar dados e chave')),
                            FilledButton.icon(
                                key: const ValueKey('offline-license-export'),
                                onPressed: _busy ? null : _export,
                                icon: const Icon(Icons.save_alt),
                                label: const Text('Salvar arquivo .lic')),
                          ]),
                        ]))),
          ],
          const SizedBox(height: 14),
          const Text(
              'A chave tem prazo e vale apenas para o aparelho informado. Para renovar, gere e envie outra chave. Bloqueio imediato à distância depende do modo pela internet.'),
        ]),
      ),
    );
  }
}

class _LicensePackagesScreen extends StatefulWidget {
  const _LicensePackagesScreen({required this.store});

  final LicensePackageStore store;

  @override
  State<_LicensePackagesScreen> createState() => _LicensePackagesScreenState();
}

class _LicensePackagesScreenState extends State<_LicensePackagesScreen> {
  final Map<LicensePackageKind, String?> _paths = {};
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final kind in LicensePackageKind.values) {
      _paths[kind] = await widget.store.packagePath(kind);
    }
    if (mounted) setState(() {});
  }

  Future<void> _import(LicensePackageKind kind) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kind == LicensePackageKind.windows
          ? const ['exe', 'zip']
          : const ['apk'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _busy = true);
    final error = await widget.store.importPackage(kind, path);
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? 'Pacote importado com sucesso.';
    });
  }

  Future<void> _export(LicensePackageKind kind) async {
    final source = _paths[kind];
    if (source == null) return;
    final destination = await FilePicker.platform.saveFile(
      fileName: source.split(RegExp(r'[\\/]')).last,
      type: FileType.any,
    );
    if (destination == null) return;
    final error = await widget.store.exportPackage(kind, destination);
    if (mounted) {
      setState(() => _message = error ?? 'Cópia salva em $destination');
    }
  }

  Future<void> _openWindows(String path) async {
    try {
      if (path.toLowerCase().endsWith('.exe')) {
        await Process.start(path, const [], mode: ProcessStartMode.detached);
        return;
      }
      final destination = await FilePicker.platform.getDirectoryPath();
      if (destination == null) return;
      final result =
          await Process.run('tar.exe', ['-xf', path, '-C', destination]);
      if (result.exitCode != 0) throw Exception('${result.stderr}');
      final executable =
          File('$destination${Platform.pathSeparator}matterdisistem.exe');
      if (await executable.exists()) {
        await Process.start(executable.path, const [],
            mode: ProcessStartMode.detached);
      }
      if (mounted) setState(() => _message = 'Pacote extraído em $destination');
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Não foi possível abrir o pacote: $error');
      }
    }
  }

  Widget _packageCard(LicensePackageKind kind) {
    final path = _paths[kind];
    final isWindows = kind == LicensePackageKind.windows;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isWindows ? Icons.desktop_windows : Icons.android, size: 30),
            const SizedBox(width: 12),
            Expanded(
                child: Text(widget.store.label(kind),
                    style: Theme.of(context).textTheme.titleMedium)),
            Chip(label: Text(path == null ? 'Não cadastrado' : 'Disponível')),
          ]),
          const SizedBox(height: 8),
          Text(path ??
              'Importe um ${isWindows ? 'EXE ou ZIP' : 'APK'} ou inclua o pacote ao compilar o administrador.'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _import(kind),
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar')),
            if (path != null)
              OutlinedButton.icon(
                  onPressed: () => _export(kind),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Salvar cópia')),
            if (isWindows && path != null)
              FilledButton.icon(
                  onPressed: () => _openWindows(path),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(path.toLowerCase().endsWith('.zip')
                      ? 'Extrair e abrir'
                      : 'Executar')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Pacotes do cliente',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
                'Guarde e distribua os instaladores de Windows e Android junto do administrador.'),
            if (_message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!)),
            const SizedBox(height: 10),
            _packageCard(LicensePackageKind.windows),
            _packageCard(LicensePackageKind.android),
          ]),
        ),
      );
}
