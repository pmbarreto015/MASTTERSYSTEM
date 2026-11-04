import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/product_model.dart';
import '../../models/composicao_model.dart';
import '../../services/product_repository.dart';
import '../../services/composicao_repository.dart';
import '../corte_laser/compositor_screen.dart';
import 'product_form_screen.dart';
import '../../providers/auth_provider.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen>
    with TickerProviderStateMixin, BackgroundRefreshMixin<ProductListScreen> {
  final ProductRepository _repository = ProductRepository();
  final ComposicaoRepository _composicaoRepo = ComposicaoRepository();

  List<ProductModel> _products = [];
  List<ProductModel> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterCategory = 'todos';
  bool _showActiveOnly = true;
  late AnimationController _animationController;

  static const String _uncategorized = 'sem_categoria';

  // ESTATÍSTICAS
  int get _totalProducts => _products.length;
  int get _totalActive => _products.where((p) => p.ativo).length;
  int get _totalLaser => _products.where((p) => p.isCorteLaser).length;
  int get _totalComposicoes => _products.where((p) => p.temComposicao).length;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _loadProducts();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadProducts();

  Future<void> _loadProducts() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final products = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _products = products;
        _applyProductFilters();
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar produtos: $e');
    }
  }

  void _filterProducts() {
    setState(_applyProductFilters);
  }

  void _applyProductFilters() {
    _filteredProducts = _products.where((p) {
      final matchesSearch = _searchQuery.isEmpty ||
          p.nome.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.codigo.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.descricao.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesCategory = _filterCategory == 'todos' ||
          (_filterCategory == _uncategorized && p.categoria.trim().isEmpty) ||
          p.categoria == _filterCategory ||
          (_filterCategory == 'estamparia' && p.isEstamparia);

      final matchesActive = _showActiveOnly ? p.ativo : true;

      return matchesSearch && matchesCategory && matchesActive;
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

  // ============================================================
  // ABRIR COMPOSITOR PARA O PRODUTO
  // ============================================================

  Future<void> _openCompositor(ProductModel product) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.hasPermission('corte_compositor')) {
      _showError('Seu usuário não possui acesso ao Compositor.');
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompositorScreen(
          produtoId: product.id,
          produtoNome: product.nome,
        ),
      ),
    );

    if (result != null) {
      _showSuccess('Composição salva com sucesso!');

      try {
        final updatedProduct = await _repository.getById(product.id!);
        if (updatedProduct != null) {
          setState(() {
            final index = _products.indexWhere((p) => p.id == product.id);
            if (index != -1) {
              _products[index] = updatedProduct;
            }
          });
          _filterProducts();
          _showSuccess('Preço atualizado: ${updatedProduct.formatarPreco()}');
        }
      } catch (e) {
        print('Erro ao atualizar produto: $e');
      }
    }
  }

  // ============================================================
  // VER COMPOSIÇÃO
  // ============================================================

  Future<void> _verComposicao(ProductModel product) async {
    if (!product.temComposicao) {
      _showError('Este produto não possui composição');
      return;
    }

    try {
      final composicao = await _composicaoRepo.getByProduto(product.id!);
      if (composicao == null) {
        _showError('Composição não encontrada');
        return;
      }

      _showComposicaoDetalhes(product, composicao);
    } catch (e) {
      _showError('Erro ao carregar composição: $e');
    }
  }

  void _showComposicaoDetalhes(
      ProductModel product, ComposicaoModel composicao) {
    final NumberFormat moeda =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cut,
                          color: Colors.deepOrange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Composição - ${product.nome}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Código: ${product.codigo}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Custo Total',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            Text(
                              moeda.format(composicao.custoTotal),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white24,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Margem',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            Text(
                              '${composicao.margemLucro.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white24,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Preço Venda',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            Text(
                              moeda.format(composicao.precoVenda),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Materiais',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      ...composicao.materiais.map((item) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 20,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.descricao,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Text(
                                '${item.quantidade.toStringAsFixed(2)} ${item.unidade}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                moeda.format(item.valorTotal),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F62AC),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (composicao.maquinas.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Máquinas',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        ...composicao.maquinas.map((item) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 20,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.descricao,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '${item.quantidade.toStringAsFixed(0)} ${item.unidade}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  moeda.format(item.valorTotal),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (composicao.servicos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Serviços',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        ...composicao.servicos.map((item) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 20,
                                  color: Colors.purple,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.descricao,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  moeda.format(item.valorTotal),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 16),
                      if (composicao.observacoes.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            composicao.observacoes,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openCompositor(product);
                            },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Editar Composição'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F62AC),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // CRIAR/EDITAR PRODUTO
  // ============================================================

  Future<void> _showProductForm({ProductModel? product}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          product: product,
          onSave: _loadProducts,
        ),
      ),
    );

    if (result == true) {
      _loadProducts();
    }
  }

  // ============================================================
  // DELETAR PRODUTO
  // ============================================================

  Future<void> _deleteProduct(ProductModel product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${product.nome}"?'),
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
      await _repository.delete(product.id!);
      _loadProducts();
      _showSuccess('Produto excluído!');
    }
  }

  bool _matchesBulkCategory(ProductModel product, String category) {
    if (category == _uncategorized) return product.categoria.trim().isEmpty;
    if (category == 'estamparia') return product.isEstamparia;
    return product.categoria == category;
  }

  String _bulkCategoryLabel(String category) {
    if (category == _uncategorized) return 'Sem categoria';
    return ProductModel.getCategoriasMap()[category] ?? category;
  }

  List<String> get _bulkCategories {
    final categories = <String>{
      ...ProductModel.getCategorias(),
      ..._products
          .map((product) => product.categoria.trim())
          .where((category) => category.isNotEmpty),
    }.toList()
      ..sort((a, b) => _bulkCategoryLabel(a).compareTo(_bulkCategoryLabel(b)));
    return categories;
  }

  Future<void> _showBulkDeleteDialog() async {
    var selectedCategory = _uncategorized;
    final category = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final count = _products
              .where(
                  (product) => _matchesBulkCategory(product, selectedCategory))
              .length;
          return AlertDialog(
            title: const Text('Excluir produtos por categoria'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: _uncategorized,
                      child: Text('Sem categoria'),
                    ),
                    ..._bulkCategories.map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(_bulkCategoryLabel(category)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  count == 1
                      ? '1 produto será excluído.'
                      : '$count produtos serão excluídos.',
                  style: TextStyle(
                    color: count == 0 ? Colors.grey : Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: count == 0
                    ? null
                    : () => Navigator.pop(dialogContext, selectedCategory),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );

    if (category == null || !mounted) return;
    final products = _products
        .where((product) => _matchesBulkCategory(product, category))
        .toList();
    final label = _bulkCategoryLabel(category);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar exclusão em massa'),
        content: Text(
          'Excluir definitivamente ${products.length} produto(s) da categoria “$label”?\n\nEsta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir todos'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      final ids =
          products.map((product) => product.id).whereType<int>().toList();
      final deleted = await _repository.deleteMany(ids);
      await _loadProducts();
      _showSuccess('$deleted produto(s) excluído(s) de “$label”.');
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showError(
        'Não foi possível excluir. Há produtos usados em vendas ou orçamentos: $e',
      );
    }
  }

  // ============================================================
  // TOGGLE ATIVO
  // ============================================================

  Future<void> _toggleActive(ProductModel product) async {
    final updated = product.copyWith(ativo: !product.ativo);
    await _repository.update(updated);
    _loadProducts();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 620;
    final statCards = [
      _buildStatCard(
          'Total', '$_totalProducts', Icons.inventory_2, Colors.blue, isDark),
      _buildStatCard(
          'Ativos', '$_totalActive', Icons.check_circle, Colors.green, isDark),
      _buildStatCard(
          'Laser', '$_totalLaser', Icons.cut, Colors.deepOrange, isDark),
      _buildStatCard(
          'Comp.', '$_totalComposicoes', Icons.build, Colors.purple, isDark),
    ];
    final searchFilter = TextField(
      decoration: InputDecoration(
        hintText: 'Buscar produto...',
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
      ),
      onChanged: (value) {
        _searchQuery = value;
        _filterProducts();
      },
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
    );
    final categoryFilter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filterCategory,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          selectedItemBuilder: (context) => const [
            Align(alignment: Alignment.centerLeft, child: Text('Todos')),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Sem categoria', overflow: TextOverflow.ellipsis),
            ),
            Align(alignment: Alignment.centerLeft, child: Text('Gráfica')),
            Align(alignment: Alignment.centerLeft, child: Text('Com. Visual')),
            Align(alignment: Alignment.centerLeft, child: Text('Estamparia')),
            Align(alignment: Alignment.centerLeft, child: Text('Presentes')),
            Align(
                alignment: Alignment.centerLeft, child: Text('Corte a Laser')),
          ],
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 12,
          ),
          dropdownColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
          items: const [
            DropdownMenuItem(value: 'todos', child: Text('Todos')),
            DropdownMenuItem(
                value: _uncategorized, child: Text('Sem categoria')),
            DropdownMenuItem(value: 'grafica', child: Text('Gráfica')),
            DropdownMenuItem(
              value: 'comunicacao_visual',
              child: Text('Com. Visual'),
            ),
            DropdownMenuItem(value: 'estamparia', child: Text('Estamparia')),
            DropdownMenuItem(
              value: 'presentes',
              child: Text('Presentes / Lembrancinhas'),
            ),
            DropdownMenuItem(
              value: 'corte_laser',
              child: Text('Corte a Laser'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            _filterCategory = value;
            _filterProducts();
          },
        ),
      ),
    );
    final activeFilter = FilterChip(
      label: const Text('Ativos'),
      selected: _showActiveOnly,
      onSelected: (value) {
        setState(() {
          _showActiveOnly = value;
          _filterProducts();
        });
      },
      backgroundColor: isDark ? Colors.grey.shade800 : Colors.white,
      selectedColor: const Color(0xFF0F62AC).withValues(alpha: 0.1),
      checkmarkColor: const Color(0xFF0F62AC),
      labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black),
    );
    final addButton = ElevatedButton.icon(
      onPressed: _showProductForm,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Novo'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Produtos'),
        backgroundColor:
            isDark ? const Color(0xFF2D2D2D) : const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _products.isEmpty ? null : _showBulkDeleteDialog,
            tooltip: 'Excluir produtos por categoria',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showProductForm,
            tooltip: 'Novo Produto',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // ESTATÍSTICAS
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
            child: LayoutBuilder(
              builder: (context, constraints) => compact
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final card in statCards)
                          SizedBox(
                            width: (constraints.maxWidth - 8) / 2,
                            child: card,
                          ),
                      ],
                    )
                  : Row(
                      children: [
                        for (var i = 0; i < statCards.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          statCards[i],
                        ],
                        const Spacer(),
                        Text(
                          'Total: $_totalProducts',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // FILTROS
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: LayoutBuilder(
              builder: (context, constraints) => compact
                  ? Column(
                      children: [
                        searchFilter,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: categoryFilter),
                            const SizedBox(width: 8),
                            activeFilter,
                            const SizedBox(width: 8),
                            addButton,
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: searchFilter),
                        const SizedBox(width: 12),
                        SizedBox(width: 220, child: categoryFilter),
                        const SizedBox(width: 8),
                        activeFilter,
                        const SizedBox(width: 8),
                        addButton,
                      ],
                    ),
            ),
          ),

          // LISTA DE PRODUTOS
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2,
                                size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum produto cadastrado'
                                  : 'Nenhum produto encontrado',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: _showProductForm,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar Produto'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            final isActive = product.ativo;
                            final isLaser = product.isCorteLaser;
                            final temComposicao = product.temComposicao;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isActive
                                      ? (isLaser
                                          ? Colors.deepOrange.shade200
                                          : Theme.of(context)
                                              .colorScheme
                                              .outlineVariant)
                                      : Colors.red.shade300,
                                  width: isLaser ? 2 : 1,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? (isLaser
                                            ? Colors.deepOrange
                                                .withValues(alpha: 0.1)
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.1))
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isLaser ? Icons.cut : Icons.inventory_2,
                                    color: isActive
                                        ? (isLaser
                                            ? (isDark
                                                ? Colors.deepOrange.shade200
                                                : Colors.deepOrange)
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product.nome,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: isActive
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    if (isLaser)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Laser',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    if (temComposicao)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.purple
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle,
                                              color: Colors.purple,
                                              size: 10,
                                            ),
                                            SizedBox(width: 2),
                                            Text(
                                              'Comp.',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (!isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.red.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Inativo',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Código: ${product.codigo}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: product
                                                .getCategoriaColor()
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            product.getCategoriaLabel(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isDark
                                                  ? Color.lerp(
                                                      product
                                                          .getCategoriaColor(),
                                                      Colors.white,
                                                      0.45,
                                                    )
                                                  : product.getCategoriaColor(),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            product.formatarPreco(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isDark
                                                  ? Colors.green.shade200
                                                  : Colors.green.shade800,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (temComposicao)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.purple
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Composição: R\$ ${product.cost.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? Colors.purple.shade200
                                                    : Colors.purple.shade800,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        if (isLaser && !temComposicao)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Sem Composição',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: compact
                                    ? PopupMenuButton<String>(
                                        tooltip: 'A\u00e7\u00f5es do produto',
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'composition':
                                              _openCompositor(product);
                                              break;
                                            case 'viewComposition':
                                              _verComposicao(product);
                                              break;
                                            case 'toggle':
                                              _toggleActive(product);
                                              break;
                                            case 'edit':
                                              _showProductForm(
                                                  product: product);
                                              break;
                                            case 'delete':
                                              _deleteProduct(product);
                                              break;
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (isLaser)
                                            PopupMenuItem(
                                              value: 'composition',
                                              child: Text(
                                                temComposicao
                                                    ? 'Editar Composi\u00e7\u00e3o'
                                                    : 'Criar Composi\u00e7\u00e3o',
                                              ),
                                            ),
                                          if (temComposicao)
                                            const PopupMenuItem(
                                              value: 'viewComposition',
                                              child: Text(
                                                  'Ver Composi\u00e7\u00e3o'),
                                            ),
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Text(
                                              isActive ? 'Desativar' : 'Ativar',
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Editar'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Excluir'),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isLaser)
                                            IconButton(
                                              icon: Icon(
                                                temComposicao
                                                    ? Icons.edit
                                                    : Icons.calculate,
                                                color: temComposicao
                                                    ? Colors.purple
                                                    : Colors.deepOrange,
                                                size: 18,
                                              ),
                                              onPressed: () =>
                                                  _openCompositor(product),
                                              tooltip: temComposicao
                                                  ? 'Editar Composição'
                                                  : 'Criar Composição',
                                            ),
                                          if (temComposicao)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.visibility,
                                                color: Colors.blue,
                                                size: 18,
                                              ),
                                              onPressed: () =>
                                                  _verComposicao(product),
                                              tooltip: 'Ver Composição',
                                            ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.toggle_on,
                                              color: isActive
                                                  ? Colors.green
                                                  : Colors.grey,
                                              size: 30,
                                            ),
                                            onPressed: () =>
                                                _toggleActive(product),
                                            tooltip: isActive
                                                ? 'Desativar'
                                                : 'Ativar',
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              size: 18,
                                              color: Colors.grey,
                                            ),
                                            onPressed: () => _showProductForm(
                                                product: product),
                                            tooltip: 'Editar',
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            onPressed: () =>
                                                _deleteProduct(product),
                                            tooltip: 'Excluir',
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

  // ============================================================
  // WIDGETS AUXILIARES
  // ============================================================

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            ' $label',
            style: TextStyle(
              fontSize: 9,
              color: isDark ? Colors.white70 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
