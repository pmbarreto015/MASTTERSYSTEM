import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../services/sales_repository.dart';
import '../../models/seller_model.dart';

class VendedoresScreen extends StatefulWidget {
  const VendedoresScreen({super.key});

  @override
  State<VendedoresScreen> createState() => _VendedoresScreenState();
}

class _VendedoresScreenState extends State<VendedoresScreen>
    with BackgroundRefreshMixin<VendedoresScreen> {
  final SalesRepository _repository = SalesRepository();
  List<SellerModel> _vendedores = [];
  List<SellerModel> _filteredVendedores = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showActiveOnly = true;

  // TOTAIS ATUALIZADOS
  double get _totalVendas =>
      _vendedores.fold(0.0, (sum, v) => sum + v.totalSales);
  double get _totalComissao => _vendedores.fold(
      0.0, (sum, v) => sum + (v.totalSales * v.commission / 100));

  @override
  void initState() {
    super.initState();
    _loadVendedores();
  }

  @override
  Future<void> refreshInBackground() => _loadVendedores();

  Future<void> _loadVendedores() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      // ATUALIZA OS TOTAIS DE VENDAS DE TODOS OS VENDEDORES
      await _repository.atualizarTodosVendedores();
      if (!mounted) return;

      final vendedores = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _vendedores = vendedores;
        _applyVendedorFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar vendedores: $e');
    }
  }

  // ATUALIZAR UM VENDEDOR ESPECÍFICO
  Future<void> _atualizarVendasVendedor(SellerModel vendedor) async {
    try {
      await _repository.atualizarVendasVendedor(vendedor.id!);
      await _loadVendedores();
      _showSuccess('Vendas de ${vendedor.name} atualizadas!');
    } catch (e) {
      _showError('Erro ao atualizar vendas: $e');
    }
  }

  void _filterVendedores(String query) {
    setState(() {
      _searchQuery = query;
      _applyVendedorFilters();
    });
  }

  void _applyVendedorFilters() {
    _filteredVendedores = _vendedores.where((v) {
      final matchesSearch = _searchQuery.isEmpty ||
          v.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          v.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          v.phone.contains(_searchQuery);

      final matchesActive = _showActiveOnly ? v.active : true;

      return matchesSearch && matchesActive;
    }).toList();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _showAddVendedorDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final comissaoController = TextEditingController();

    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_add, color: Color(0xFF0F62AC)),
            ),
            const SizedBox(width: 12),
            const Text('Novo Vendedor'),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: comissaoController,
                  decoration: const InputDecoration(
                    labelText: 'Comissão (%) *',
                    prefixIcon: Icon(Icons.percent),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final seller = SellerModel.create(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  email: emailController.text.trim(),
                  commission: double.parse(comissaoController.text),
                );
                await _repository.create(seller);
                Navigator.pop(context, true);
                _loadVendedores();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vendedor adicionado com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditVendedorDialog(SellerModel vendedor) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: vendedor.name);
    final phoneController = TextEditingController(text: vendedor.phone);
    final emailController = TextEditingController(text: vendedor.email);
    final comissaoController = TextEditingController(
      text: vendedor.commission.toString(),
    );
    bool isActive = vendedor.active;

    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit, color: Color(0xFF0F62AC)),
            ),
            const SizedBox(width: 12),
            const Text('Editar Vendedor'),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: comissaoController,
                  decoration: const InputDecoration(
                    labelText: 'Comissão (%) *',
                    prefixIcon: Icon(Icons.percent),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Ativo'),
                  value: isActive,
                  onChanged: (value) {
                    setState(() {
                      isActive = value;
                    });
                  },
                  activeThumbColor: const Color(0xFF0F62AC),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final updatedSeller = vendedor.copyWith(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  email: emailController.text.trim(),
                  commission: double.parse(comissaoController.text),
                  active: isActive,
                );
                await _repository.update(updatedSeller);
                Navigator.pop(context, true);
                _loadVendedores();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vendedor atualizado com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F62AC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteVendedor(SellerModel vendedor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${vendedor.name}"?'),
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
      await _repository.delete(vendedor.id!);
      _loadVendedores();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vendedor excluído com sucesso!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleActive(SellerModel vendedor) async {
    final updated = vendedor.copyWith(active: !vendedor.active);
    await _repository.update(updated);
    _loadVendedores();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Cabeçalho com estatísticas
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                const Icon(Icons.people, color: Color(0xFF0F62AC), size: 24),
                const SizedBox(width: 12),
                Text(
                  'Vendedores',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // Botão para recalcular vendas
                ElevatedButton.icon(
                  onPressed: _loadVendedores,
                  icon: const Icon(Icons.calculate, size: 16),
                  label: const Text('Recalcular Vendas'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Estatísticas
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Total Vendas: R\$ ${_totalVendas.toStringAsFixed(2)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.percent, size: 14, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        'Comissões: R\$ ${_totalComissao.toStringAsFixed(2)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Barra de busca
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar vendedor por nome, e-mail, telefone...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: _filterVendedores,
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Ativos'),
                  selected: _showActiveOnly,
                  onSelected: (value) {
                    setState(() {
                      _showActiveOnly = value;
                      _filterVendedores(_searchQuery);
                    });
                  },
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedColor: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                  checkmarkColor: const Color(0xFF0F62AC),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showAddVendedorDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF0F62AC)),
                  onPressed: _loadVendedores,
                  tooltip: 'Atualizar',
                ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredVendedores.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline,
                                size: 64, color: Color(0xFFE0E0E0)),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum vendedor cadastrado'
                                  : 'Nenhum vendedor encontrado',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadVendedores,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredVendedores.length,
                          itemBuilder: (context, index) {
                            final v = _filteredVendedores[index];
                            final isActive = v.active;
                            final comissaoTotal =
                                v.totalSales * v.commission / 100;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isActive
                                      ? Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                      : Colors.red.shade300,
                                ),
                              ),
                              child: ListTile(
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isActive
                                          ? [
                                              const Color(0xFF0F62AC),
                                              const Color(0xFF4589FF)
                                            ]
                                          : [
                                              Colors.grey.shade400,
                                              Colors.grey.shade600
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      v.name[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        v.name,
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
                                    if (!isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.red.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Inativo',
                                          style: TextStyle(
                                              fontSize: 10, color: Colors.red),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${v.phone} | ${v.email}',
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
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F62AC)
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Comissão: ${v.commission}%',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
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
                                            'Vendas: R\$ ${v.totalSales.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: isDark
                                                  ? Colors.green.shade200
                                                  : Colors.green.shade800,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
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
                                            'Comissão: R\$ ${comissaoTotal.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: isDark
                                                  ? Colors.blue.shade200
                                                  : Colors.blue.shade800,
                                              fontWeight: FontWeight.w500,
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
                                    // Botão para atualizar vendas individual
                                    IconButton(
                                      icon: const Icon(Icons.calculate,
                                          color: Color(0xFF0F62AC), size: 18),
                                      onPressed: () =>
                                          _atualizarVendasVendedor(v),
                                      tooltip: 'Atualizar Vendas',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.toggle_on,
                                        color: isActive
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 30,
                                      ),
                                      onPressed: () => _toggleActive(v),
                                      tooltip:
                                          isActive ? 'Desativar' : 'Ativar',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 18, color: Colors.grey),
                                      onPressed: () =>
                                          _showEditVendedorDialog(v),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      onPressed: () => _deleteVendedor(v),
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
