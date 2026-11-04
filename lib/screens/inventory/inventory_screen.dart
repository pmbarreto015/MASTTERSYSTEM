import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:provider/provider.dart';
import '../../services/insumo_repository.dart';
import '../../services/material_repository.dart';
import '../../models/insumo_model.dart';
import '../../models/material_model.dart';
import '../corte_laser/materiais_screen.dart';
import '../../providers/auth_provider.dart';

enum _InventorySource { insumo, corteLaser }

class _InventoryItem {
  const _InventoryItem._({
    required this.source,
    this.insumo,
    this.material,
  });

  factory _InventoryItem.fromInsumo(InsumoModel value) => _InventoryItem._(
        source: _InventorySource.insumo,
        insumo: value,
      );

  factory _InventoryItem.fromMaterial(MaterialModel value) => _InventoryItem._(
        source: _InventorySource.corteLaser,
        material: value,
      );

  final _InventorySource source;
  final InsumoModel? insumo;
  final MaterialModel? material;

  bool get isCorteLaser => source == _InventorySource.corteLaser;
  String get codigo => insumo?.codigo ?? material!.codigo;
  String get nome => insumo?.nome ?? material!.nome;
  String get categoria => insumo?.categoria ?? material!.categoria;
  double get quantidade => insumo?.quantidade ?? material!.quantidadeEstoque;
  String get unidade => insumo?.unidade ?? material!.unidadePreco;
  String get fornecedor => insumo?.fornecedor ?? material!.fornecedor;
  double get estoqueMinimo => insumo?.estoqueMinimo ?? material!.estoqueMinimo;
  double get estoqueMaximo => insumo?.estoqueMaximo ?? material!.estoqueMaximo;
  String get observacoes => insumo?.observacoes ?? material!.observacoes;

  double get precoUnitario {
    if (insumo != null) return insumo!.precoUnitario;
    return material!.precoCusto;
  }

  String get status {
    if (quantidade <= 0) return 'Esgotado';
    if (quantidade <= estoqueMinimo) return 'Baixo';
    if (estoqueMaximo > 0 && quantidade >= estoqueMaximo) return 'Excedente';
    return 'OK';
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

// CORRIGIDO: TickerProviderStateMixin
class _InventoryScreenState extends State<InventoryScreen>
    with TickerProviderStateMixin, BackgroundRefreshMixin<InventoryScreen> {
  final InsumoRepository _insumoRepo = InsumoRepository();
  final MaterialRepository _materialRepo = MaterialRepository();

  List<_InventoryItem> _items = [];
  List<_InventoryItem> _filteredItems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'Todos';
  final TextEditingController _searchController = TextEditingController();

  late AnimationController _animationController;

  final List<String> _statusList = [
    'Todos',
    'OK',
    'Baixo',
    'Crítico',
    'Esgotado',
    'Excedente',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadInventory();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadInventory();

  Future<void> _loadInventory() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final insumos = await _insumoRepo.getAll();
      final materiais = await _materialRepo.getActive();
      final items = [
        ...insumos.map(_InventoryItem.fromInsumo),
        ...materiais.map(_InventoryItem.fromMaterial),
      ]..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _filterItems();
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar o estoque: $e');
    }
  }

  void _filterItems() {
    setState(() {
      final query = _searchQuery.toLowerCase();
      _filteredItems = _items.where((i) {
        final matchesSearch = _searchQuery.isEmpty ||
            i.nome.toLowerCase().contains(query) ||
            i.codigo.toLowerCase().contains(query) ||
            i.categoria.toLowerCase().contains(query) ||
            i.fornecedor.toLowerCase().contains(query) ||
            (i.isCorteLaser && 'corte a laser'.contains(query));

        final matchesStatus =
            _filterStatus == 'Todos' || i.status == _filterStatus;

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  // CORES E STATUS
  Color _getStatusColor(String status) {
    switch (status) {
      case 'OK':
        return Colors.green;
      case 'Baixo':
        return Colors.orange;
      case 'Crítico':
        return Colors.red;
      case 'Esgotado':
        return Colors.grey;
      case 'Excedente':
        return Colors.purple;
      default:
        return const Color(0xFF0F62AC);
    }
  }

  String _getCategoriaNome(String categoria) {
    final nomes = {
      'materiais': 'Materiais',
      'impressao': 'Impressão',
      'tintas': 'Tintas',
      'papelaria': 'Papelaria',
      'ferramentas': 'Ferramentas',
      'embalagens': 'Embalagens',
      'costura': 'Costura',
      'adesivos': 'Adesivos',
      'corte': 'Corte',
      'outros': 'Outros',
    };
    return nomes[categoria] ?? categoria;
  }

  String _getCategoriaId(String categoriaComEmoji) {
    final map = {
      'Materiais': 'materiais',
      'Impressão': 'impressao',
      'Tintas': 'tintas',
      'Papelaria': 'papelaria',
      'Ferramentas': 'ferramentas',
      'Embalagens': 'embalagens',
      'Costura': 'costura',
      'Adesivos': 'adesivos',
      'Corte': 'corte',
      'Outros': 'outros',
    };
    return map[categoriaComEmoji] ?? categoriaComEmoji;
  }

  Color _getCategoriaColor(String categoria) {
    switch (categoria) {
      case 'materiais':
        return Colors.blue;
      case 'impressao':
        return Colors.purple;
      case 'tintas':
        return Colors.red;
      case 'papelaria':
        return Colors.green;
      case 'ferramentas':
        return Colors.orange;
      case 'embalagens':
        return Colors.teal;
      case 'costura':
        return Colors.pink;
      case 'adesivos':
        return Colors.cyan;
      case 'corte':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  // DIALOG DE ADICIONAR/EDITAR INSUMO - CORRIGIDO
  void _showInsumoDialog({InsumoModel? insumo}) {
    final isEdit = insumo != null;
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: insumo?.nome ?? '');
    final codigoController = TextEditingController(text: insumo?.codigo ?? '');
    final quantidadeController =
        TextEditingController(text: insumo?.quantidade.toString() ?? '0');
    final precoController =
        TextEditingController(text: insumo?.precoUnitario.toString() ?? '');
    final fornecedorController =
        TextEditingController(text: insumo?.fornecedor ?? '');
    final minimoController =
        TextEditingController(text: insumo?.estoqueMinimo.toString() ?? '0');
    final maximoController =
        TextEditingController(text: insumo?.estoqueMaximo.toString() ?? '0');
    final observacoesController =
        TextEditingController(text: insumo?.observacoes ?? '');

    var selectedCategoria = insumo?.categoria ?? 'materiais';
    var selectedUnidade = insumo?.unidade ?? 'un';

    final categorias = _insumoRepo.getCategorias();
    final unidades = _insumoRepo.getUnidades();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEdit ? Icons.edit : Icons.add_box,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Editar Insumo' : 'Novo Insumo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // CORREÇÃO: Categoria COM emojis
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategoria,
                      decoration: const InputDecoration(
                        labelText: 'Categoria *',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: categorias.map((cat) {
                        return DropdownMenuItem<String>(
                          value: _getCategoriaId(cat),
                          child: Text(cat),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setStateDialog(() {
                          selectedCategoria = v!;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    // Nome
                    TextFormField(
                      controller: nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Insumo *',
                        prefixIcon: Icon(Icons.inventory_2),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: 10),
                    // Código
                    TextFormField(
                      controller: codigoController,
                      decoration: const InputDecoration(
                        labelText: 'Código *',
                        prefixIcon: Icon(Icons.tag),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: 10),
                    // Quantidade e Unidade
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: quantidadeController,
                            decoration: const InputDecoration(
                              labelText: 'Quantidade *',
                              prefixIcon: Icon(Icons.inventory),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedUnidade,
                            decoration: const InputDecoration(
                              labelText: 'Unidade *',
                              prefixIcon: Icon(Icons.square_foot),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: unidades.map((uni) {
                              return DropdownMenuItem(
                                value: uni,
                                child: Text(uni),
                              );
                            }).toList(),
                            onChanged: (v) => selectedUnidade = v!,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Preço e Fornecedor
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: precoController,
                            decoration: const InputDecoration(
                              labelText: 'Preço Unitário',
                              prefixIcon: Icon(Icons.attach_money),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: fornecedorController,
                            decoration: const InputDecoration(
                              labelText: 'Fornecedor',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Min e Max
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minimoController,
                            decoration: const InputDecoration(
                              labelText: 'Estoque Mínimo',
                              prefixIcon: Icon(Icons.warning),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: maximoController,
                            decoration: const InputDecoration(
                              labelText: 'Estoque Máximo',
                              prefixIcon: Icon(Icons.trending_up),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Observações
                    TextFormField(
                      controller: observacoesController,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    try {
                      final insumoData = InsumoModel(
                        id: isEdit ? insumo.id : null,
                        codigo: codigoController.text,
                        nome: nomeController.text,
                        categoria: selectedCategoria,
                        quantidade:
                            double.tryParse(quantidadeController.text) ?? 0,
                        unidade: selectedUnidade,
                        precoUnitario:
                            double.tryParse(precoController.text) ?? 0,
                        fornecedor: fornecedorController.text,
                        estoqueMinimo:
                            double.tryParse(minimoController.text) ?? 0,
                        estoqueMaximo:
                            double.tryParse(maximoController.text) ?? 0,
                        observacoes: observacoesController.text,
                      );

                      if (isEdit) {
                        await _insumoRepo.update(insumoData);
                        _showSuccess('Insumo atualizado!');
                      } else {
                        await _insumoRepo.create(insumoData);
                        _showSuccess('Insumo adicionado!');
                      }
                      Navigator.pop(context);
                      _loadInventory();
                    } catch (e) {
                      _showError('Erro ao salvar: $e');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F62AC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(isEdit ? 'Atualizar' : 'Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  // DIALOG DE AJUSTE DE ESTOQUE
  void _showAdjustStockDialog(_InventoryItem item) {
    final formKey = GlobalKey<FormState>();
    final quantityController = TextEditingController();
    var operation = 'adicionar';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Ajustar Estoque',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Item: ${item.nome}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Quantidade atual: ${item.quantidade.toStringAsFixed(2)} ${item.unidade}',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: operation,
                decoration: const InputDecoration(
                  labelText: 'Operação',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'adicionar', child: Text('Adicionar')),
                  DropdownMenuItem(value: 'remover', child: Text('Remover')),
                  DropdownMenuItem(value: 'definir', child: Text('Definir')),
                ],
                onChanged: (v) => operation = v!,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Campo obrigatório';
                  }
                  final value = double.tryParse(v.replaceAll(',', '.'));
                  return value == null || value < 0
                      ? 'Informe uma quantidade válida'
                      : null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final qty = double.parse(
                    quantityController.text.replaceAll(',', '.'),
                  );
                  var newQuantity = item.quantidade;

                  switch (operation) {
                    case 'adicionar':
                      newQuantity = item.quantidade + qty;
                      break;
                    case 'remover':
                      newQuantity = item.quantidade - qty;
                      if (newQuantity < 0) newQuantity = 0;
                      break;
                    case 'definir':
                      newQuantity = qty;
                      break;
                  }

                  if (item.insumo != null) {
                    final updatedInsumo =
                        item.insumo!.copyWith(quantidade: newQuantity);
                    await _insumoRepo.update(updatedInsumo);
                  } else {
                    await _materialRepo.atualizarEstoque(
                      item.material!.id!,
                      newQuantity,
                    );
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await _loadInventory();
                  if (!mounted) return;
                  _showSuccess(
                    'Estoque atualizado: ${newQuantity.toStringAsFixed(2)} ${item.unidade}',
                  );
                } catch (e) {
                  if (!mounted) return;
                  _showError('Erro ao atualizar o estoque: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F62AC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // DELETE INSUMO
  Future<void> _deleteInsumo(InsumoModel insumo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${insumo.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _insumoRepo.delete(insumo.id!);
      await _loadInventory();
      _showSuccess('Insumo excluído!');
    }
  }

  Future<void> _editLaserMaterial(MaterialModel material) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MateriaisScreen(materialToEdit: material),
      ),
    );
    if (!mounted) return;
    await _loadInventory();
  }

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredItems.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadInventory,
                          child: Container(
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _buildTableHeader(),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _filteredItems.length,
                                    itemBuilder: (context, index) {
                                      final item = _filteredItems[index];
                                      return _buildInventoryRow(item, index);
                                    },
                                  ),
                                ),
                                _buildTableFooter(),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      );

  Widget _buildToolbar() => Container(
        padding: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar item por nome, código, fornecedor...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _filterItems();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterStatus,
                      icon: const Icon(Icons.arrow_drop_down),
                      items: _statusList.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Row(
                            children: [
                              if (status != 'Todos')
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(status),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        _filterStatus = v!;
                        _filterItems();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showInsumoDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo Insumo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Color(0xFF0F62AC), size: 22),
                  onPressed: _loadInventory,
                  tooltip: 'Atualizar',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_filteredItems.length} item(ns) encontrado(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const Spacer(),
                if (_searchQuery.isNotEmpty || _filterStatus != 'Todos')
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      _searchQuery = '';
                      _filterStatus = 'Todos';
                      _filterItems();
                    },
                    child: const Text('Limpar filtros',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _buildTableHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF0F62AC),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
        ),
        child: const Row(
          children: [
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(Icons.tag, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Código',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Item',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(Icons.production_quantity_limits,
                      color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Qtd',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(Icons.attach_money, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Preço',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(Icons.business, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Fornecedor',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(Icons.category, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Categoria',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Text('Ações',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );

  Widget _buildInventoryRow(_InventoryItem item, int index) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final status = item.status;
    final statusColor = _getStatusColor(status);
    final isLowStock = item.quantidade <= item.estoqueMinimo;

    return Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.grey.shade50 : Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Text(
                item.codigo,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isLowStock ? Colors.red : Colors.grey.shade700,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nome,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.isCorteLaser ? 'Corte a Laser' : 'Insumo',
                    style: TextStyle(
                      fontSize: 9,
                      color: item.isCorteLaser
                          ? Colors.deepOrange
                          : Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.observacoes.isNotEmpty)
                    Text(
                      item.observacoes,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.quantidade.toStringAsFixed(2)} ${item.unidade}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                item.precoUnitario > 0
                    ? 'R\$ ${item.precoUnitario.toStringAsFixed(2)}'
                    : '-',
                style: TextStyle(
                  fontSize: 11,
                  color: item.precoUnitario > 0
                      ? const Color(0xFF0F62AC)
                      : Colors.grey.shade400,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                item.fornecedor.isNotEmpty ? item.fornecedor : '-',
                style: TextStyle(
                  fontSize: 11,
                  color: item.fornecedor.isNotEmpty
                      ? Colors.grey.shade700
                      : Colors.grey.shade400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: (item.isCorteLaser
                          ? Colors.deepOrange
                          : _getCategoriaColor(item.categoria))
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.isCorteLaser
                      ? MaterialModel.getCategoriaNome(item.categoria)
                      : _getCategoriaNome(item.categoria),
                  style: TextStyle(
                    fontSize: 9,
                    color: item.isCorteLaser
                        ? Colors.deepOrange
                        : _getCategoriaColor(item.categoria),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                    onPressed: () {
                      if (!item.isCorteLaser) {
                        _showInsumoDialog(insumo: item.insumo);
                      } else if (auth.hasPermission('corte_materiais')) {
                        _editLaserMaterial(item.material!);
                      } else {
                        _showError(
                          'Seu usuário não possui acesso ao cadastro de materiais.',
                        );
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.inventory,
                        size: 16, color: Color(0xFF0F62AC)),
                    onPressed: () => _showAdjustStockDialog(item),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Ajustar Estoque',
                  ),
                  const SizedBox(width: 4),
                  if (!item.isCorteLaser)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Colors.red,
                      ),
                      onPressed: () => _deleteInsumo(item.insumo!),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableFooter() => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          children: [
            Text(
              'Total: ${_filteredItems.length} itens',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
            const Spacer(),
            Text(
              'Valor Total: R\$ ${_filteredItems.fold(0.0, (sum, i) => sum + (i.quantidade * i.precoUnitario)).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'Nenhum item cadastrado'
                  : 'Nenhum item encontrado',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_searchQuery.isEmpty)
              ElevatedButton.icon(
                onPressed: () => _showInsumoDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Adicionar Primeiro Insumo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F62AC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      );
}
