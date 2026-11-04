import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/app_database.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String _lastBackup = 'Nenhum backup realizado';
  String _backupPath = '';
  bool _autoBackup = false;
  String _frequency = 'Diário';
  String _time = '18:00';
  double _backupProgress = 0.0;
  late AnimationController _animationController;

  List<Map<String, dynamic>> _backupHistory = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animationController.forward();
    _loadBackupInfo();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadBackupInfo() async {
    // Carregar informações do backup salvas
    try {
      final directory = await getApplicationDocumentsDirectory();
      _backupPath = path.join(directory.path, 'backups');
      await _loadBackupHistory();
    } catch (e) {
      print('Erro ao carregar informações de backup: $e');
    }
  }

  Future<void> _loadBackupHistory() async {
    try {
      final backupDir = Directory(_backupPath);
      if (await backupDir.exists()) {
        final files = backupDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.db') || f.path.endsWith('.zip'))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );

        _backupHistory = files.map((file) {
          final stat = file.statSync();
          return {
            'name': path.basename(file.path),
            'path': file.path,
            'size': _formatSize(stat.size),
            'date': DateTime.fromMillisecondsSinceEpoch(
              stat.modified.millisecondsSinceEpoch,
            ),
          };
        }).toList();

        if (_backupHistory.isNotEmpty) {
          _lastBackup = DateFormat('dd/MM/yyyy HH:mm')
              .format(_backupHistory.first['date'] as DateTime);
        }
        setState(() {});
      }
    } catch (e) {
      print('Erro ao carregar histórico: $e');
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _performBackup() async {
    if (await AppDatabase().isUsingRemoteDatabase()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Faça o backup no PC principal ou na hospedagem do banco.'),
      ));
      return;
    }
    setState(() {
      _isLoading = true;
      _backupProgress = 0.0;
    });

    try {
      // Criar pasta de backup se não existir
      final backupDir = Directory(_backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Nome do backup
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(now);
      final backupFileName = 'backup_$dateStr.db';
      final backupFile = File(path.join(_backupPath, backupFileName));

      setState(() => _backupProgress = 0.3);

      // Cria uma fotografia consistente, incluindo alterações ainda no WAL.
      final db = await AppDatabase().database;
      final escapedBackupPath = backupFile.path.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$escapedBackupPath'");
      if (!await backupFile.exists() || await backupFile.length() == 0) {
        throw const FileSystemException(
          'O arquivo de backup não foi criado corretamente.',
        );
      }
      await AppDatabase().validateDatabaseFile(backupFile.path);
      setState(() => _backupProgress = 0.7);

      // Salvar informações do backup
      await _saveBackupInfo(backupFileName, now);

      setState(() {
        _backupProgress = 1.0;
        _isLoading = false;
        _lastBackup = DateFormat('dd/MM/yyyy HH:mm').format(now);
      });

      await _loadBackupHistory();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Backup concluído: $backupFileName',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _backupProgress = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveBackupInfo(String fileName, DateTime date) async {
    try {
      final infoFile = File(path.join(_backupPath, 'backup_info.json'));
      Map<String, dynamic> info = {};

      if (await infoFile.exists()) {
        final content = await infoFile.readAsString();
        info = jsonDecode(content);
      }

      info[fileName] = {
        'date': date.toIso8601String(),
        'file': fileName,
      };

      await infoFile.writeAsString(jsonEncode(info));
    } catch (e) {
      print('Erro ao salvar informações: $e');
    }
  }

  Future<void> _performRestore() async {
    final prefs = await SharedPreferences.getInstance();
    if (await AppDatabase().isUsingRemoteDatabase() ||
        (prefs.getBool('database_server_enabled') ?? false)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Restaure no PC principal com o servidor de dados desativado.'),
      ));
      return;
    }
    if (_backupHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum backup disponível para restaurar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Selecionar backup
    final selected = await _showSelectBackupDialog();
    if (selected == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Restauração'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Atenção!',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 8),
            const Text(
              'A restauração irá substituir todos os dados atuais do sistema.',
            ),
            const SizedBox(height: 8),
            Text('Backup: ${selected['name']}'),
            Text(
                'Data: ${DateFormat('dd/MM/yyyy HH:mm').format(selected['date'] as DateTime)}'),
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
            ),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
        _backupProgress = 0.0;
      });

      try {
        final backupFile = File(selected['path']);
        if (!await backupFile.exists()) {
          throw Exception('Arquivo de backup não encontrado');
        }

        await AppDatabase().validateDatabaseFile(backupFile.path);
        setState(() => _backupProgress = 0.5);

        // Restaurar banco de dados
        final databaseManager = AppDatabase();
        final dbPath = await databaseManager.getDatabasePath();

        // Fechar conexão atual
        await databaseManager.close();

        // Copiar backup para o local do banco
        await backupFile.copy(dbPath);
        await databaseManager.database;

        setState(() => _backupProgress = 1.0);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.restore, color: Colors.white),
                SizedBox(width: 8),
                Text('Backup restaurado com sucesso!'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );

        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _backupProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao restaurar backup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showSelectBackupDialog() async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Selecionar Backup'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: _backupHistory.isEmpty
              ? const Center(child: Text('Nenhum backup disponível'))
              : ListView.builder(
                  itemCount: _backupHistory.length,
                  itemBuilder: (context, index) {
                    final backup = _backupHistory[index];
                    return ListTile(
                      leading:
                          const Icon(Icons.backup, color: Color(0xFF0F62AC)),
                      title: Text(backup['name']),
                      subtitle: Text(
                        '${DateFormat('dd/MM/yyyy HH:mm').format(backup['date'])} - ${backup['size']}',
                      ),
                      onTap: () => Navigator.pop(context, backup),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir backup "${backup['name']}"?'),
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
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final file = File(backup['path']);
        if (await file.exists()) {
          await file.delete();
        }
        await _loadBackupHistory();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup excluído com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showInfoDialog(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(title),
        content: const Text(
          'Funcionalidade em desenvolvimento.\nEm breve disponível.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cabeçalho
          Row(
            children: [
              const Icon(Icons.backup, color: Color(0xFF0F62AC), size: 28),
              const SizedBox(width: 12),
              Text(
                'Backup e Restauração',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Card: Fazer Backup
          _buildBackupCard(
            'Fazer Backup Completo',
            Icons.backup,
            'Realize um backup completo de todos os dados do sistema.\nÚltimo backup: $_lastBackup',
            'Executar Backup',
            _performBackup,
            const Color(0xFF0F62AC),
          ),
          const SizedBox(height: 16),

          // Barra de Progresso
          if (_isLoading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _backupProgress,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    color: const Color(0xFF0F62AC),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_backupProgress * 100).toStringAsFixed(0)}% concluído',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Card: Restaurar
          _buildBackupCard(
            'Restaurar Backup',
            Icons.restore,
            'Restaura um backup existente a partir dos arquivos salvos.\nLocal: $_backupPath',
            'Restaurar',
            _performRestore,
            Colors.orange,
          ),
          const SizedBox(height: 16),

          // Card: Configurações
          _buildConfigCard(),
          const SizedBox(height: 16),

          // Card: Histórico
          _buildHistoryCard(),
        ],
      ),
    );
  }

  Widget _buildBackupCard(
    String title,
    IconData icon,
    String description,
    String buttonText,
    VoidCallback onPressed,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings,
                      color: Color(0xFF0F62AC), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Configurações de Backup',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Pasta de destino
            Row(
              children: [
                const Icon(Icons.folder, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pasta de destino',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        _backupPath,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),

            // Backup automático
            Row(
              children: [
                const Icon(Icons.schedule, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup automático',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Realizar backup automaticamente',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoBackup,
                  onChanged: (value) => setState(() => _autoBackup = value),
                  activeThumbColor: const Color(0xFF0F62AC),
                ),
              ],
            ),
            const Divider(),

            // Frequência
            Row(
              children: [
                const Icon(Icons.timer, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Frequência',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        _frequency,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_drop_down, size: 24),
                  onPressed: () => _showFrequencyDialog(),
                ),
              ],
            ),
            const Divider(),

            // Horário
            Row(
              children: [
                const Icon(Icons.access_time, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Horário',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        _time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit,
                      size: 18, color: Color(0xFF0F62AC)),
                  onPressed: () => _showTimeDialog(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    _showInfoDialog(context, 'Salvar Configurações'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text('Salvar Configurações'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.history, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Histórico de Backups',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loadBackupHistory,
                  child: const Text('Atualizar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_backupHistory.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nenhum backup encontrado',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount:
                    _backupHistory.length > 5 ? 5 : _backupHistory.length,
                itemBuilder: (context, index) {
                  final backup = _backupHistory[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.backup,
                            color: Color(0xFF0F62AC), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                backup['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${DateFormat('dd/MM/yyyy HH:mm').format(backup['date'])} - ${backup['size']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 18),
                          onPressed: () => _deleteBackup(backup),
                          tooltip: 'Excluir backup',
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (_backupHistory.length > 5)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showHistory = !_showHistory),
                  child: Text(
                    _showHistory
                        ? 'Ver menos'
                        : 'Ver todos os backups (${_backupHistory.length})',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFrequencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Frequência do Backup'),
        content: RadioGroup<String>(
          groupValue: _frequency,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _frequency = value);
            Navigator.pop(context);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Diário'),
                leading: Radio<String>(
                  value: 'Diário',
                ),
              ),
              ListTile(
                title: Text('Semanal'),
                leading: Radio<String>(
                  value: 'Semanal',
                ),
              ),
              ListTile(
                title: Text('Mensal'),
                leading: Radio<String>(
                  value: 'Mensal',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Horário do Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecione o horário para o backup automático.'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _time,
                    decoration: const InputDecoration(
                      labelText: 'Horário',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      '18:00',
                      '19:00',
                      '20:00',
                      '21:00',
                      '22:00',
                      '23:00',
                      '00:00',
                      '01:00',
                      '02:00',
                      '03:00',
                      '04:00',
                      '05:00',
                    ].map((time) {
                      return DropdownMenuItem(
                        value: time,
                        child: Text(time),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _time = value!);
                      Navigator.pop(context);
                      _showInfoDialog(context, 'Horário selecionado: $_time');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
