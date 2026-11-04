import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../services/csv_import_service.dart';
import '../../services/xml_import_service.dart';
import '../../services/product_repository.dart';
import '../../services/financial_repository.dart';
import '../../services/supplier_repository.dart';
import '../../services/order_repository.dart';
import '../../models/supplier_model.dart';
import 'import_confirm_dialog.dart';
import 'import_csv_preview_dialog.dart';

class ArquivoScreen extends StatefulWidget {
  const ArquivoScreen({super.key});

  @override
  State<ArquivoScreen> createState() => _ArquivoScreenState();
}

class _ArquivoScreenState extends State<ArquivoScreen>
    with SingleTickerProviderStateMixin, BackgroundRefreshMixin<ArquivoScreen> {
  final CsvImportService _importService = CsvImportService();
  final XmlImportService _xmlImportService = XmlImportService();
  final ProductRepository _productRepo = ProductRepository();
  final FinancialRepository _financialRepo = FinancialRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final OrderRepository _orderRepo = OrderRepository();

  bool _isLoading = false;
  String _importMessage = '';
  String _exportMessage = '';

  // Nomes de arquivos separados
  String _xmlFileName = '';
  String _csvFileName = '';

  double _progress = 0.0;
  late AnimationController _animationController;

  // Dados para importação manual
  final TextEditingController _xmlController = TextEditingController();
  final TextEditingController _csvController = TextEditingController();
  String _selectedSupplier = '';
  List<SupplierModel> _suppliers = [];

  // NOVO: Dados da análise XML para preview

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animationController.forward();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _xmlController.dispose();
    _csvController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadSuppliers();

  Future<void> _loadSuppliers() async {
    try {
      _suppliers = await _supplierRepo.getAll();
      if (_suppliers.isNotEmpty) {
        _selectedSupplier = _suppliers.first.name;
      }
      setState(() {});
    } catch (e) {
      print('Erro ao carregar fornecedores: $e');
    }
  }

  // ==================== IMPORTAR XML (NF-e / NFS-e) ====================
  Future<void> _importXml() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        dialogTitle: 'Selecione a Nota Fiscal (XML)',
      );

      if (result == null) return;

      final file = result.files.first;
      _xmlFileName = file.name;

      final filePath = file.path!;
      final fileObject = File(filePath);
      final xmlContent = await fileObject.readAsString();

      setState(() {
        _isLoading = true;
        _importMessage = 'Analisando XML...';
        _progress = 0.0;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _progress = 0.3);

      // ANALISAR XML E IDENTIFICAR INSUMOS
      final dadosNota = await _xmlImportService.analisarXml(xmlContent);

      setState(() => _progress = 0.5);

      // MOSTRAR DIÁLOGO COM PREVIEW DOS INSUMOS IDENTIFICADOS
      final resultDialog = await showDialog<Map<String, bool>>(
        context: context,
        builder: (context) => ImportConfirmDialog(
          dadosNota: dadosNota,
        ),
      );

      if (resultDialog == null) {
        setState(() {
          _isLoading = false;
          _importMessage = 'Importação cancelada';
          _xmlFileName = '';
        });
        return;
      }

      setState(() => _progress = 0.7);

      // IMPORTAR COM OPÇÕES (INSUMOS E PRODUTOS)
      final resultado = await _xmlImportService.importarXmlComOpcoes(
        xmlContent,
        importarProdutos: resultDialog['importarProdutos'] ?? true,
        importarInsumos: resultDialog['importarInsumos'] ?? true,
        importarFornecedor: resultDialog['importarFornecedor'] ?? true,
      );

      setState(() {
        _isLoading = false;
        _progress = 1.0;
        _importMessage = '${resultado['mensagem']}';
        _xmlFileName = '';
      });

      // MENSAGEM DETALHADA
      final mensagem =
          '${resultado['tipo']} ${resultado['numero'] ?? ''} importada!\n'
          '${resultado['insumos'] ?? 0} insumos adicionados ao estoque\n'
          '${resultado['produtos'] ?? 0} produtos cadastrados\n'
          'Fornecedor: ${resultado['fornecedor']}\n'
          'Valor: R\$ ${(resultado['valor'] ?? 0).toStringAsFixed(2)}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(mensagem),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _importMessage = 'Erro ao importar XML: $e';
        _xmlFileName = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==================== IMPORTAR CSV/EXCEL/PDF ====================
  Future<void> _importCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xls', 'xlsx', 'pdf'],
        dialogTitle: 'Selecione o arquivo (CSV, XLS, XLSX ou PDF)',
      );

      if (result == null) return;

      final file = result.files.first;
      _csvFileName = file.name;

      final filePath = file.path!;

      setState(() {
        _isLoading = true;
        _importMessage = 'Lendo arquivo...';
        _progress = 0.0;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _progress = 0.3);

      final dados = await _importService.lerArquivo(filePath);

      setState(() => _progress = 0.6);

      if (dados.isEmpty) {
        setState(() {
          _isLoading = false;
          _importMessage = 'Nenhum produto encontrado no arquivo';
          _csvFileName = '';
        });
        return;
      }

      final margem = await showDialog<double>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ImportCsvPreviewDialog(
          produtos: dados,
          onConfirm: (m) {
            Navigator.pop(context, m);
          },
        ),
      );

      if (margem == null) {
        setState(() {
          _isLoading = false;
          _importMessage = 'Importação cancelada';
          _csvFileName = '';
        });
        return;
      }

      setState(() => _progress = 0.8);

      final importados = await _importService.importarProdutos(dados, margem);

      setState(() {
        _isLoading = false;
        _progress = 1.0;
        _importMessage = '$importados produtos importados com sucesso!';
        _csvFileName = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('$importados produtos importados!'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _importMessage = 'Erro ao importar: $e';
        _csvFileName = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==================== EXPORTAR ====================
  Future<void> _exportData(String type) async {
    setState(() => _isLoading = true);

    try {
      String data = '';
      String fileName = '';

      switch (type) {
        case 'pedidos':
          data = await _generateOrdersCsv();
          fileName =
              'pedidos_${DateTime.now().toIso8601String().split('T')[0]}.csv';
          break;
        case 'produtos':
          data = await _generateProductsCsv();
          fileName =
              'produtos_${DateTime.now().toIso8601String().split('T')[0]}.csv';
          break;
        case 'financeiro':
          data = await _generateFinancialCsv();
          fileName =
              'financeiro_${DateTime.now().toIso8601String().split('T')[0]}.csv';
          break;
        default:
          return;
      }

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar relatório',
        fileName: fileName,
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(data);

        setState(() {
          _isLoading = false;
          _exportMessage = 'Relatório exportado com sucesso!';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.download_done, color: Colors.white),
                const SizedBox(width: 8),
                Text('$fileName salvo com sucesso!'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _exportMessage = 'Erro ao exportar: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _generateOrdersCsv() async {
    final orders = await _orderRepo.getAll();
    String csv = 'Número,Cliente,Valor,Status,Data,Criado em\n';
    for (var order in orders) {
      csv +=
          '${order.numero},${order.clienteNome ?? ''},${order.valorTotal},${order.status},${order.dataEntrega ?? ''},${order.dataCriacao}\n';
    }
    return csv;
  }

  Future<String> _generateProductsCsv() async {
    final products = await _productRepo.getAll();
    String csv = 'Código,Nome,Preço,Categoria,Estoque,Unidade\n';
    for (var product in products) {
      csv +=
          '${product.codigo},${product.nome},${product.preco},${product.categoria},${product.estoque},${product.unidade}\n';
    }
    return csv;
  }

  Future<String> _generateFinancialCsv() async {
    final financials = await _financialRepo.getAll();
    String csv = 'Descrição,Valor,Tipo,Data,Vencimento,Pago\n';
    for (var f in financials) {
      csv +=
          '${f.description},${f.amount},${f.type},${f.createdAt},${f.dueDate},${f.isPaid ? "Sim" : "Não"}\n';
    }
    return csv;
  }

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Cabeçalho
            const Row(
              children: [
                Icon(Icons.folder_open, color: Color(0xFF0F62AC), size: 28),
                SizedBox(width: 12),
                Text(
                  'Arquivo e Importação',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F62AC),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Barra de Progresso
            if (_isLoading) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: const Color(0xFF0F62AC),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Text(
                _importMessage,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],

            // ======== IMPORTAR DADOS ========
            Text(
              'Importar Dados',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 12),

            // Selecionar Fornecedor
            if (_suppliers.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business, color: Color(0xFF0F62AC)),
                    const SizedBox(width: 8),
                    const Text('Fornecedor:'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSupplier,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        items: _suppliers.map((s) {
                          return DropdownMenuItem(
                            value: s.name,
                            child: Text(s.name),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setState(() => _selectedSupplier = v!),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Card XML
            _buildImportCard(
              title: 'Importar Nota Fiscal (XML)',
              icon: Icons.receipt_long,
              description: 'Importe uma Nota Fiscal em XML (NF-e ou NFS-e).\n\n'
                  '**Insumos identificados automaticamente:**\n'
                  '• Rolos de Lona, Adesivos, Tintas, Placas, Papel, etc.\n'
                  '• Os insumos vão direto para o **Estoque** (matéria-prima)\n'
                  '• Produtos acabados vão para **Produtos**',
              buttonText: 'Selecionar XML',
              onPressed: _importXml,
              color: const Color(0xFF0F62AC),
              type: 'xml',
              fileName: _xmlFileName,
            ),
            const SizedBox(height: 16),

            // Card CSV
            _buildImportCard(
              title: 'Importar Lista de Produtos (CSV/XLS/PDF)',
              icon: Icons.inventory_2,
              description:
                  'Importe uma lista de produtos a partir de um arquivo CSV, Excel (XLS/XLSX) ou PDF.',
              buttonText: 'Selecionar Arquivo',
              onPressed: _importCsv,
              color: Colors.green,
              type: 'csv',
              fileName: _csvFileName,
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // ======== EXPORTAR DADOS ========
            Text(
              'Exportar Dados',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 12),

            _buildExportButton(
              'Exportar Relatório de Pedidos',
              Icons.description,
              'pedidos',
            ),
            const SizedBox(height: 8),

            _buildExportButton(
              'Exportar Relatório de Produtos',
              Icons.inventory,
              'produtos',
            ),
            const SizedBox(height: 8),

            _buildExportButton(
              'Exportar Contas a Pagar/Receber',
              Icons.monetization_on,
              'financeiro',
            ),

            // Mensagem de exportação
            if (_exportMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _exportMessage,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      onPressed: () => setState(() => _exportMessage = ''),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _buildImportCard({
    required String title,
    required IconData icon,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
    required Color color,
    required String type,
    required String fileName,
  }) =>
      Card(
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
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onPressed,
                      icon: Icon(type == 'xml'
                          ? Icons.file_upload
                          : Icons.upload_file),
                      label: Text(buttonText),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (fileName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              type == 'xml'
                                  ? Icons.insert_drive_file
                                  : Icons.insert_chart,
                              size: 14,
                              color: color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              fileName,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );

  Widget _buildExportButton(
    String label,
    IconData icon,
    String type,
  ) =>
      ElevatedButton.icon(
        onPressed: _isLoading ? null : () => _exportData(type),
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F62AC),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.centerLeft,
        ),
      );
}
