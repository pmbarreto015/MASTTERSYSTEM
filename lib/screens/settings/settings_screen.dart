import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/database/app_database.dart';
import '../auth/login_screen.dart';
import 'user_access_section.dart';
import 'database_connection_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _companyNameController;
  late TextEditingController _cnpjController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _emailController;
  late TextEditingController _websiteController;
  late TextEditingController _maxDiscountController;
  late TextEditingController _databasePathController;

  bool _isLoading = true;
  File? _logoImage;
  bool _darkMode = false;
  bool _useSharedDatabase = false;
  bool _useRemoteDatabase = false;
  String _localDatabasePath = '';

  String _selectedPrinter = 'HP LaserJet Pro M404dn';
  final List<String> _printerOptions = [
    'HP LaserJet Pro M404dn',
    'Epson EcoTank L3150',
    'Brother DCP-L5652DN',
    'Samsung Xpress M2070',
    'PDF (Salvar como arquivo)',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _cnpjController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _maxDiscountController.dispose();
    _databasePathController.dispose();
    super.dispose();
  }

  Future<String> _getDatabasePath() async {
    try {
      final dbPath = await AppDatabase().getDatabasePath();
      print('Banco de dados em: $dbPath');
      return dbPath;
    } catch (e) {
      final directory = Directory.current;
      final dbPath = path.join(directory.path, 'matterdi_sistem.db');
      print('Banco de dados (fallback) em: $dbPath');
      return dbPath;
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      _companyNameController = TextEditingController(
        text: prefs.getString('company_name') ?? 'MatterdiSistem Ltda',
      );
      _cnpjController = TextEditingController(
        text: prefs.getString('company_cnpj') ?? '12.345.678/0001-99',
      );
      _phoneController = TextEditingController(
        text: prefs.getString('company_phone') ?? '(11) 4002-8922',
      );
      _addressController = TextEditingController(
        text: prefs.getString('company_address') ??
            'Rua das Gráficas, 123 - São Paulo, SP',
      );
      _emailController = TextEditingController(
        text: prefs.getString('company_email') ?? 'contato@matterdi.com.br',
      );
      _websiteController = TextEditingController(
        text: prefs.getString('company_website') ?? 'www.matterdi.com.br',
      );
      _maxDiscountController = TextEditingController(
        text: prefs.getString('max_discount') ?? '10',
      );
      _useSharedDatabase = (prefs.getString(AppDatabase.databaseModeKey) ??
              AppDatabase.localMode) ==
          AppDatabase.sharedMode;
      final databaseMode = prefs.getString(AppDatabase.databaseModeKey);
      _useRemoteDatabase = databaseMode == AppDatabase.remoteMode ||
          databaseMode == AppDatabase.supabaseMode;
      _databasePathController = TextEditingController(
        text: prefs.getString(AppDatabase.databasePathKey) ?? '',
      );
      final documentsDirectory = await getApplicationDocumentsDirectory();
      _localDatabasePath =
          path.join(documentsDirectory.path, 'matterdi_sistem.db');

      _darkMode = prefs.getBool('dark_mode') ?? false;
      _selectedPrinter =
          prefs.getString('selected_printer') ?? 'HP LaserJet Pro M404dn';

      final logoPath = prefs.getString('company_logo');
      if (logoPath != null && File(logoPath).existsSync()) {
        _logoImage = File(logoPath);
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      print('Erro ao carregar configurações: $e');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('company_name', _companyNameController.text);
      await prefs.setString('company_cnpj', _cnpjController.text);
      await prefs.setString('company_phone', _phoneController.text);
      await prefs.setString('company_address', _addressController.text);
      await prefs.setString('company_email', _emailController.text);
      await prefs.setString('company_website', _websiteController.text);
      await prefs.setString('max_discount', _maxDiscountController.text);
      await prefs.setBool('dark_mode', _darkMode);
      await prefs.setString('selected_printer', _selectedPrinter);

      final databaseMode = prefs.getString(AppDatabase.databaseModeKey);
      if (databaseMode != AppDatabase.remoteMode &&
          databaseMode != AppDatabase.supabaseMode) {
        await AppDatabase().configureDatabase(
          useSharedDatabase: _useSharedDatabase,
          sharedPath: _databasePathController.text,
        );
      }

      if (_logoImage != null) {
        await prefs.setString('company_logo', _logoImage!.path);
      }

      if (!mounted) return;
      if (!mounted) return;
      setState(() => _isLoading = false);

      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      await themeProvider.setDarkMode(_darkMode);

      _showSnackBar('Configurações salvas com sucesso!');
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Erro ao salvar: $e', isError: true);
    }
  }

  Future<void> _selectDatabaseFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Selecione o banco de dados do PC principal',
      type: FileType.custom,
      allowedExtensions: ['db'],
      lockParentWindow: true,
    );
    final selectedPath = result?.files.single.path;
    if (selectedPath != null && mounted) {
      setState(() => _databasePathController.text = selectedPath);
    }
  }

  Future<void> _testDatabaseConnection() async {
    setState(() => _isLoading = true);
    try {
      if (_useSharedDatabase) {
        await AppDatabase().validateDatabaseFile(
          _databasePathController.text,
          requireWriteAccess: true,
        );
      } else {
        final localPath = await AppDatabase().getDatabasePath();
        final localFile = File(localPath);
        if (await localFile.exists()) {
          await AppDatabase().validateDatabaseFile(localPath);
        }
      }
      _showSnackBar('Conexão com o banco de dados funcionando!');
    } catch (e) {
      _showSnackBar('Não foi possível acessar o banco: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetSystem() async {
    final prefs = await SharedPreferences.getInstance();
    if (await AppDatabase().isUsingRemoteDatabase() ||
        (prefs.getBool('database_server_enabled') ?? false)) {
      _showSnackBar(
        'Para resetar, use o PC principal com o servidor de dados desativado.',
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Resetar Sistema',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ATENÇÃO! Esta ação irá:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            SizedBox(height: 8),
            Text('• Apagar TODOS os dados do sistema'),
            Text('• Remover clientes, produtos, pedidos e financeiro'),
            Text('• Limpar completamente o estoque'),
            Text('• Restaurar configurações padrão'),
            Text('• Voltar para a tela de login'),
            SizedBox(height: 16),
            Text(
              'Esta ação NÃO pode ser desfeita!',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            SizedBox(height: 8),
            Text(
              'Tem certeza que deseja continuar?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Sim, Resetar Tudo'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await _deleteDatabase();
        await _deleteAllDataFolders();

        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        if (!mounted) return;
        setState(() => _isLoading = false);

        _showSnackBar('Sistema resetado com sucesso!');

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (BuildContext context) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnackBar('Erro ao resetar: $e', isError: true);
      }
    }
  }

  Future<void> _deleteDatabase() async {
    try {
      try {
        final db = AppDatabase();
        await db.close();
        print('Conexão com banco fechada');
      } catch (e) {
        print('Erro ao fechar banco: $e');
      }

      final dbPath = await _getDatabasePath();

      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
        print('Banco de dados removido: $dbPath');
      } else {
        print('Banco de dados não encontrado em: $dbPath');

        final alternativePaths = [
          path.join(Directory.current.path, 'matterdi_sistem.db'),
          path.join(Directory.current.path, 'data', 'matterdi_sistem.db'),
          r'C:\Users\Pedro Barreto\Documents\matterdi_sistem.db',
        ];

        for (var altPath in alternativePaths) {
          final altFile = File(altPath);
          if (await altFile.exists()) {
            await altFile.delete();
            print('Banco de dados removido (alternativo): $altPath');
          }
        }
      }

      const extensions = ['-journal', '-wal', '-shm'];
      for (var ext in extensions) {
        final filePath = '$dbPath$ext';
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          print('Arquivo$ext removido');
        }
      }

      print('Banco de dados completamente removido!');
    } catch (e) {
      print('Erro ao deletar banco: $e');
      rethrow;
    }
  }

  Future<void> _deleteAllDataFolders() async {
    try {
      final directory = Directory.current;

      final foldersToDelete = [
        'backups',
        'pedidos_impressao',
        'xml_importados',
        'relatorios',
        'logs',
        'temp',
        'cache',
      ];

      for (var folderName in foldersToDelete) {
        final folder = Directory(path.join(directory.path, folderName));
        if (await folder.exists()) {
          await folder.delete(recursive: true);
          print('Pasta $folderName removida');
        }
      }

      final tempFiles = await Directory(directory.path)
          .list()
          .where((file) =>
              file.path.endsWith('.tmp') || file.path.endsWith('.temp'))
          .toList();

      for (var file in tempFiles) {
        await file.delete();
        print('Arquivo temporário removido: ${file.path}');
      }

      print('Todas as pastas de dados foram removidas!');
    } catch (e) {
      print('Erro ao deletar pastas: $e');
      rethrow;
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 200,
      maxHeight: 200,
    );
    if (pickedFile != null) {
      setState(() {
        _logoImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _testPrinter() async {
    _showSnackBar('Testando impressora...');
    await Future.delayed(const Duration(seconds: 1));
    _showSnackBar('Impressora funcionando!');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      appBar: AppBar(
        title: const Text('Configurações'),
        backgroundColor:
            isDark ? const Color(0xFF2D2D2D) : const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (authProvider.isAdmin) ...[
                    _buildSectionTitle('Controle de Acesso', isDark),
                    UserAccessSection(isDark: isDark),
                    const SizedBox(height: 16),
                  ],
                  // ========== LOGOTIPO ==========
                  _buildSectionTitle('Logotipo da Empresa', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _pickLogo,
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade200,
                                backgroundImage: _logoImage != null
                                    ? FileImage(_logoImage!)
                                    : null,
                                child: _logoImage == null
                                    ? Icon(
                                        Icons.add_a_photo,
                                        size: 40,
                                        color: isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _pickLogo,
                              child: Text(
                                _logoImage == null
                                    ? 'Adicionar Logotipo'
                                    : 'Alterar Logotipo',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : null,
                                ),
                              ),
                            ),
                            if (_logoImage != null)
                              TextButton(
                                onPressed: () {
                                  setState(() => _logoImage = null);
                                },
                                child: const Text(
                                  'Remover',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ========== INFORMAÇÕES DA EMPRESA ==========
                  _buildSectionTitle('Informações da Empresa', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      _buildTextField(
                        _companyNameController,
                        'Nome da Empresa *',
                        Icons.business,
                        isDark,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _cnpjController,
                              'CNPJ *',
                              Icons.badge,
                              isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              _phoneController,
                              'Telefone *',
                              Icons.phone,
                              isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _addressController,
                        'Endereço Completo *',
                        Icons.location_on,
                        isDark,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _emailController,
                              'E-mail *',
                              Icons.email,
                              isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              _websiteController,
                              'Site / Website',
                              Icons.public,
                              isDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ========== LIMITE DE DESCONTO ==========
                  _buildSectionTitle('Limite de Desconto', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      Column(
                        children: [
                          SizedBox(
                            child: TextField(
                              controller: _maxDiscountController,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Desconto Máximo (%)',
                                prefixIcon: Icon(
                                  Icons.percent,
                                  color: isDark ? Colors.white70 : Colors.grey,
                                ),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.grey.shade800
                                    : Colors.white,
                                labelStyle: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black,
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.blue.shade900
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.blue.shade700
                                    : Colors.blue.shade200,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : Colors.blue,
                                  size: 20,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Vendedores não podem ultrapassar este limite',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.blue.shade300
                                        : Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ========== BANCO DE DADOS ==========
                  _buildSectionTitle('Banco de Dados', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dns),
                        title: const Text('Conexão com o banco'),
                        subtitle: Text(
                          _useRemoteDatabase
                              ? 'Usando o banco do servidor por IP ou hospedagem.'
                              : 'Conectar o celular ao PC ou a uma hospedagem.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DatabaseConnectionScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_useRemoteDatabase)
                    _buildCard(
                      isDark: isDark,
                      children: [
                        ListTile(
                          onTap: () =>
                              setState(() => _useSharedDatabase = false),
                          title: Text(
                            'Banco local (este computador)',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Os dados ficam somente neste computador.',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          leading: Icon(
                            _useSharedDatabase
                                ? Icons.radio_button_unchecked
                                : Icons.radio_button_checked,
                            color: const Color(0xFF0F62AC),
                          ),
                          trailing: const Icon(Icons.computer),
                        ),
                        if (!_useSharedDatabase &&
                            _localDatabasePath.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: SelectableText(
                              'Local do banco: $_localDatabasePath',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                        ListTile(
                          onTap: () =>
                              setState(() => _useSharedDatabase = true),
                          title: Text(
                            'Banco compartilhado (PC principal)',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Este computador usará o mesmo banco de dados da rede.',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          leading: Icon(
                            _useSharedDatabase
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: const Color(0xFF0F62AC),
                          ),
                          trailing: const Icon(Icons.lan),
                        ),
                        if (_useSharedDatabase) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _databasePathController,
                            readOnly: true,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Arquivo do banco no PC principal',
                              hintText:
                                  r'Ex.: \\PC-PRINCIPAL\Matterdi\matterdi_sistem.db',
                              prefixIcon: const Icon(Icons.storage),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Selecionar arquivo',
                                onPressed: _selectDatabaseFile,
                                icon: const Icon(Icons.folder_open),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No Windows, compartilhe a pasta do banco no PC principal com permissão de leitura e gravação. Mantenha o PC principal ligado.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.amber.shade200
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _testDatabaseConnection,
                          icon: const Icon(Icons.wifi_tethering),
                          label: const Text('Testar conexão'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),

                  // ========== IMPRESSORA ==========
                  _buildSectionTitle('Configuração de Impressora', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedPrinter,
                        decoration: InputDecoration(
                          labelText: 'Impressora Padrão',
                          prefixIcon: Icon(
                            Icons.print,
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          border: const OutlineInputBorder(),
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black,
                          ),
                        ),
                        dropdownColor:
                            isDark ? const Color(0xFF2D2D2D) : Colors.white,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        items: _printerOptions.map((printer) {
                          return DropdownMenuItem(
                            value: printer,
                            child:
                                Text(printer, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedPrinter = value!);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _testPrinter,
                              icon: const Icon(Icons.print, size: 16),
                              label: const Text('Testar Impressora'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F62AC),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ========== APARÊNCIA ==========
                  _buildSectionTitle('Aparência', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      SwitchListTile(
                        title: Text(
                          'Modo Escuro',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: Text(
                          'Ativar tema escuro em todo o sistema',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        value: _darkMode,
                        onChanged: (value) {
                          setState(() {
                            _darkMode = value;
                          });
                          _saveSettings();
                        },
                        activeThumbColor: const Color(0xFF0F62AC),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF0F62AC).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _darkMode ? Icons.dark_mode : Icons.light_mode,
                            color: const Color(0xFF0F62AC),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ========== BOTÃO SALVAR ==========
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save, size: 20),
                      label: const Text(
                        'Salvar Todas as Configurações',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ========== BOTÃO RESETAR ==========
                  if (authProvider.isAdmin) ...[
                    Container(
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.red.shade300, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _resetSystem,
                          icon: const Icon(Icons.warning_amber, size: 20),
                          label: const Text(
                            'Resetar Sistema (Limpar Todos os Dados)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ========== AVISO ==========
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'O reset irá apagar TODOS os dados e voltar para a tela de login.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ========== SOBRE ==========
                  _buildSectionTitle('Sobre o Sistema', isDark),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF0F62AC).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.info_outline,
                              color: Color(0xFF0F62AC)),
                        ),
                        title: Text(
                          'MatterdiSistem ERP',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: Text(
                          'Versão 5.5 Plus - Build 2025.08.15',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                        onTap: () {
                          _showAboutDialog(isDark);
                        },
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            Text(
                              'Desenvolvido por FpqSystem 2025',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF0F62AC),
        ),
      ),
    );
  }

  Widget _buildCard({
    required List<Widget> children,
    required bool isDark,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : const Color(0xFFE0E0E0),
        ),
      ),
      color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    bool isDark,
  ) {
    return TextField(
      controller: controller,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          size: 18,
          color: isDark ? Colors.white70 : Colors.grey,
        ),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: isDark ? Colors.grey.shade800 : Colors.white,
        labelStyle: TextStyle(
          color: isDark ? Colors.white70 : Colors.black,
        ),
      ),
    );
  }

  void _showAboutDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info, color: Color(0xFF0F62AC)),
            ),
            const SizedBox(width: 12),
            Text(
              'Sobre o Sistema',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MatterdiSistem ERP',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Versão 5.5 Plus',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black,
              ),
            ),
            Text(
              'Sistema para Comunicação Visual e Gráficas',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Módulos disponíveis:',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            Text(
              '  • Vendas e Orçamentos',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              '  • Produção (Ordens de Serviço)',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              '  • Financeiro (Contas a Pagar/Receber)',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              '  • Estoque e Produtos',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              '  • Clientes e Fornecedores',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              '  • Relatórios Gerenciais',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              '  • Backup e Restauração',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '2025 FpqSystem - Todos os direitos reservados',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
