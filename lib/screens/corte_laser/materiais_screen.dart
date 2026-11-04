// lib/screens/corte_laser/materiais_screen.dart

import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/material_model.dart';
import '../../services/material_repository.dart';

class MateriaisScreen extends StatefulWidget {
  const MateriaisScreen({super.key, this.materialToEdit});

  final MaterialModel? materialToEdit;

  @override
  State<MateriaisScreen> createState() => _MateriaisScreenState();
}

class _MateriaisScreenState extends State<MateriaisScreen>
    with BackgroundRefreshMixin<MateriaisScreen> {
  final MaterialRepository _repository = MaterialRepository();

  List<MaterialModel> _materiais = [];
  List<MaterialModel> _filteredMateriais = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterCategoria = 'todos';

  @override
  void initState() {
    super.initState();
    _loadMateriais();
    if (widget.materialToEdit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showMaterialDialog(material: widget.materialToEdit);
        }
      });
    }
  }

  @override
  Future<void> refreshInBackground() => _loadMateriais();

  Future<void> _loadMateriais() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final materiais = await _repository.getAll();
      setState(() {
        _materiais = materiais;
        _filteredMateriais = _applyMateriaisFilter(materiais);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erro ao carregar materiais: $e');
    }
  }

  void _filterMateriais() {
    setState(() {
      _filteredMateriais = _applyMateriaisFilter(_materiais);
    });
  }

  List<MaterialModel> _applyMateriaisFilter(List<MaterialModel> materiais) {
    final query = _searchQuery.toLowerCase();
    return materiais.where((material) {
      final matchesSearch = query.isEmpty ||
          material.nome.toLowerCase().contains(query) ||
          material.codigo.toLowerCase().contains(query);
      final matchesCategoria =
          _filterCategoria == 'todos' || material.categoria == _filterCategoria;
      return matchesSearch && matchesCategoria;
    }).toList();
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

  String _getTipoNome(String tipo) {
    switch (tipo) {
      case 'chapa':
        return 'Chapa';
      case 'm2':
        return 'Metro Quadrado (m²)';
      case 'metro':
        return 'Metro';
      case 'un':
        return 'Unidade';
      default:
        return tipo;
    }
  }

  // DIALOG DE CADASTRO/EDIÇÃO DE MATERIAL
  void _showMaterialDialog({MaterialModel? material}) {
    final isEdit = material != null;
    final formKey = GlobalKey<FormState>();

    final nomeController = TextEditingController(text: material?.nome ?? '');
    final codigoController =
        TextEditingController(text: material?.codigo ?? '');
    final fornecedorController =
        TextEditingController(text: material?.fornecedor ?? '');
    final observacoesController =
        TextEditingController(text: material?.observacoes ?? '');

    // Controllers para campos numéricos
    final espessuraController = TextEditingController(
      text: material?.espessura.toString() ?? '',
    );
    final larguraController = TextEditingController(
      text: material?.larguraChapa.toString() ?? '',
    );
    final alturaController = TextEditingController(
      text: material?.alturaChapa.toString() ?? '',
    );
    final precoChapaController = TextEditingController(
      text: material?.precoChapa.toString() ?? '',
    );
    final precoM2Controller = TextEditingController(
      text: material?.precoPorM2.toString() ?? '',
    );
    final precoUnidadeController = TextEditingController(
      text: material?.precoUnidade.toString() ?? '',
    );
    final precoVendaController = TextEditingController(
      text: material?.precoVenda.toString() ?? '',
    );
    final perdaController = TextEditingController(
      text: material?.perdaPadrao.toString() ?? '',
    );
    final estoqueController = TextEditingController(
      text: material?.quantidadeEstoque.toString() ?? '0',
    );
    final minimoController = TextEditingController(
      text: material?.estoqueMinimo.toString() ?? '0',
    );
    final maximoController = TextEditingController(
      text: material?.estoqueMaximo.toString() ?? '0',
    );

    var selectedCategoria = material?.categoria ?? 'acrilico';
    var selectedTipo = MaterialModel.getTipos().contains(material?.tipo)
        ? material!.tipo
        : 'chapa';
    bool isActive = material?.active ?? true;

    double? tryParseNumber(String value) =>
        double.tryParse(value.trim().replaceAll(',', '.'));
    double parseNumber(String value) => tryParseNumber(value) ?? 0;

    String unidadeDoTipo() {
      switch (selectedTipo) {
        case 'chapa':
        case 'm2':
          return 'm²';
        case 'metro':
          return 'm';
        default:
          return 'un';
      }
    }

    void recalculateCostPerSquareMeter() {
      if (selectedTipo != 'chapa') return;

      final widthInMillimeters = tryParseNumber(larguraController.text);
      final heightInMillimeters = tryParseNumber(alturaController.text);
      final sheetCost = tryParseNumber(precoChapaController.text);
      if (widthInMillimeters == null ||
          heightInMillimeters == null ||
          sheetCost == null) {
        return;
      }
      final areaInSquareMeters =
          (widthInMillimeters * heightInMillimeters) / 1000000;

      if (areaInSquareMeters <= 0 || sheetCost < 0) return;

      final calculatedCost = sheetCost / areaInSquareMeters;
      final formattedCost = calculatedCost.toStringAsFixed(2);
      if (precoM2Controller.text == formattedCost) return;

      precoM2Controller.value = TextEditingValue(
        text: formattedCost,
        selection: TextSelection.collapsed(offset: formattedCost.length),
      );
    }

    larguraController.addListener(recalculateCostPerSquareMeter);
    alturaController.addListener(recalculateCostPerSquareMeter);
    precoChapaController.addListener(recalculateCostPerSquareMeter);
    recalculateCostPerSquareMeter();

    String? validateDimension(String? value) {
      if (selectedTipo != 'chapa') return null;
      final dimension = tryParseNumber(value ?? '');
      return dimension == null || dimension <= 0
          ? 'Informe uma medida maior que zero'
          : null;
    }

    String? validatePrice(String? value) {
      final price = tryParseNumber(value ?? '');
      return price == null || price <= 0
          ? 'Informe um preço maior que zero'
          : null;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1.2,
              ),
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
                  isEdit ? 'Editar Material' : 'Novo Material',
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
                child: SizedBox(
                  width: 550,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // NOME E CÓDIGO
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: nomeController,
                              decoration: const InputDecoration(
                                labelText: 'Nome do Material *',
                                prefixIcon: Icon(Icons.inventory_2),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) =>
                                  v!.isEmpty ? 'Obrigatório' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: codigoController,
                              decoration: const InputDecoration(
                                labelText: 'Código *',
                                prefixIcon: Icon(Icons.tag),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) =>
                                  v!.isEmpty ? 'Obrigatório' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // CATEGORIA E TIPO
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedCategoria,
                              decoration: const InputDecoration(
                                labelText: 'Categoria *',
                                prefixIcon: Icon(Icons.category),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: MaterialModel.getCategorias().map((cat) {
                                return DropdownMenuItem<String>(
                                  value: cat,
                                  child:
                                      Text(MaterialModel.getCategoriaNome(cat)),
                                );
                              }).toList(),
                              onChanged: (v) => selectedCategoria = v!,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedTipo,
                              decoration: const InputDecoration(
                                labelText: 'Tipo *',
                                prefixIcon: Icon(Icons.square_foot),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: MaterialModel.getTipos().map((tipo) {
                                return DropdownMenuItem<String>(
                                  value: tipo,
                                  child: Text(_getTipoNome(tipo)),
                                );
                              }).toList(),
                              onChanged: (v) {
                                setStateDialog(() => selectedTipo = v!);
                                recalculateCostPerSquareMeter();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ESPESSURA E FORNECEDOR
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: espessuraController,
                              decoration: const InputDecoration(
                                labelText: 'Espessura (mm)',
                                prefixIcon: Icon(Icons.height),
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

                      // DIMENSÕES DA CHAPA (SÓ PARA TIPO CHAPA)
                      if (selectedTipo == 'chapa')
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: larguraController,
                                    decoration: const InputDecoration(
                                      labelText: 'Largura da Chapa (mm)',
                                      prefixIcon: Icon(Icons.width_wide),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: validateDimension,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: alturaController,
                                    decoration: const InputDecoration(
                                      labelText: 'Altura da Chapa (mm)',
                                      prefixIcon: Icon(Icons.height),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: validateDimension,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),

                      // PREÇOS
                      Text(
                        'Preços',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: selectedTipo == 'chapa'
                                  ? precoChapaController
                                  : selectedTipo == 'm2'
                                      ? precoM2Controller
                                      : precoUnidadeController,
                              decoration: InputDecoration(
                                labelText: selectedTipo == 'chapa'
                                    ? 'Custo total da Chapa (R\$)'
                                    : selectedTipo == 'm2'
                                        ? 'Custo por m² (R\$)'
                                        : selectedTipo == 'metro'
                                            ? 'Custo por Metro (R\$)'
                                            : 'Custo por Unidade (R\$)',
                                prefixIcon: const Icon(Icons.attach_money),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              validator: validatePrice,
                            ),
                          ),
                          if (selectedTipo == 'chapa') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: precoM2Controller,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Custo calculado por m² (R\$)',
                                  helperText: 'Custo da chapa ÷ área da chapa',
                                  prefixIcon: Icon(Icons.calculate),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: precoVendaController,
                        decoration: InputDecoration(
                          labelText:
                              'Preço de Venda por ${unidadeDoTipo()} (R\$)',
                          prefixIcon: const Icon(Icons.sell),
                          suffixText: '/${unidadeDoTipo()}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ESTOQUE
                      Text(
                        'Estoque',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: estoqueController,
                              decoration: const InputDecoration(
                                labelText: 'Quantidade em Estoque',
                                prefixIcon: Icon(Icons.inventory),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
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

                      // PERDA PADRÃO
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: perdaController,
                              decoration: const InputDecoration(
                                labelText: 'Perda Padrão (%)',
                                prefixIcon: Icon(Icons.percent),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // OBSERVAÇÕES E STATUS
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
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: (v) => isActive = v,
                            activeThumbColor: const Color(0xFF0F62AC),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isActive ? 'Ativo' : 'Inativo',
                            style: TextStyle(
                              color: isActive ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                    final materialData = MaterialModel(
                      id: isEdit ? material.id : null,
                      nome: nomeController.text.trim(),
                      codigo: codigoController.text.trim(),
                      tipo: selectedTipo,
                      categoria: selectedCategoria,
                      cor: '',
                      acabamento: '',
                      espessura: parseNumber(espessuraController.text),
                      larguraChapa: parseNumber(larguraController.text),
                      alturaChapa: parseNumber(alturaController.text),
                      areaChapa: (parseNumber(larguraController.text) *
                              parseNumber(alturaController.text)) /
                          1000000,
                      precoChapa: selectedTipo == 'chapa'
                          ? parseNumber(precoChapaController.text)
                          : 0,
                      precoPorM2:
                          selectedTipo == 'chapa' || selectedTipo == 'm2'
                              ? parseNumber(precoM2Controller.text)
                              : 0,
                      perdaPadrao: parseNumber(perdaController.text),
                      precoUnidade:
                          selectedTipo == 'metro' || selectedTipo == 'un'
                              ? parseNumber(precoUnidadeController.text)
                              : 0,
                      precoVenda: parseNumber(precoVendaController.text),
                      unidade: selectedTipo == 'chapa' || selectedTipo == 'm2'
                          ? 'm²'
                          : selectedTipo == 'metro'
                              ? 'm'
                              : 'un',
                      quantidadeEstoque: parseNumber(estoqueController.text),
                      estoqueMinimo: parseNumber(minimoController.text),
                      estoqueMaximo: parseNumber(maximoController.text),
                      fornecedor: fornecedorController.text.trim(),
                      observacoes: observacoesController.text.trim(),
                      active: isActive,
                    );

                    if (isEdit) {
                      await _repository.update(materialData);
                      _showSuccess('Material atualizado!');
                    } else {
                      await _repository.create(materialData);
                      _showSuccess('Material criado!');
                    }
                    Navigator.pop(context);
                    _loadMateriais();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F62AC),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  // DELETAR MATERIAL
  Future<void> _deleteMaterial(MaterialModel material) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${material.nome}"?'),
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
      await _repository.delete(material.id!);
      _loadMateriais();
      _showSuccess('Material excluído!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Materiais para Corte a Laser'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showMaterialDialog(),
            tooltip: 'Novo Material',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMateriais,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // BARRA DE PESQUISA
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar material por nome ou código...',
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
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _filterMateriais();
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
                      value: _filterCategoria,
                      icon: const Icon(Icons.arrow_drop_down),
                      items: [
                        const DropdownMenuItem<String>(
                            value: 'todos', child: Text('Todos')),
                        ...MaterialModel.getCategorias().map((cat) {
                          return DropdownMenuItem<String>(
                            value: cat,
                            child: Text(MaterialModel.getCategoriaNome(cat)),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        _filterCategoria = v!;
                        _filterMateriais();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showMaterialDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // LISTA DE MATERIAIS
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMateriais.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2,
                              size: 80,
                              color: colors.onSurfaceVariant
                                  .withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum material cadastrado'
                                  : 'Nenhum material encontrado',
                              style: TextStyle(
                                fontSize: 16,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: () => _showMaterialDialog(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar Material'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMateriais,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredMateriais.length,
                          itemBuilder: (context, index) {
                            final material = _filteredMateriais[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: material.active
                                      ? colors.outlineVariant
                                      : Colors.red.shade300,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: material.active
                                        ? colors.primary.withValues(alpha: 0.1)
                                        : colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2,
                                    color: material.active
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                                title: Text(
                                  material.nome,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: material.active
                                        ? colors.onSurface
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Código: ${material.codigo}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colors.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            MaterialModel.getCategoriaNome(
                                                material.categoria),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: colors.primary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colors.onSurfaceVariant
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            _getTipoNome(material.tipo),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        if (material.espessura > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${material.espessura}mm',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? Colors.orange.shade200
                                                    : Colors.orange.shade800,
                                              ),
                                            ),
                                          ),
                                        if (material.precoCusto > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Custo: R\$ ${material.precoCusto.toStringAsFixed(2)}/${material.unidadePreco}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? Colors.green.shade200
                                                    : Colors.green.shade800,
                                              ),
                                            ),
                                          ),
                                        if (material.precoVenda > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Venda: R\$ ${material.precoVenda.toStringAsFixed(2)}/${material.unidadeVenda}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? Colors.purple.shade200
                                                    : Colors.purple.shade800,
                                              ),
                                            ),
                                          ),
                                        if (material.quantidadeEstoque > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              material.quantidadeEstoque
                                                  .toStringAsFixed(0),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? Colors.blue.shade200
                                                    : Colors.blue.shade800,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 18, color: Colors.grey),
                                      onPressed: () => _showMaterialDialog(
                                          material: material),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      onPressed: () =>
                                          _deleteMaterial(material),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
