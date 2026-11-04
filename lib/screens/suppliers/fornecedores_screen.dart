import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/supplier_model.dart';
import '../../services/supplier_repository.dart';
import 'purchase_orders_screen.dart';

class FornecedoresScreen extends StatefulWidget {
  const FornecedoresScreen({super.key});

  @override
  State<FornecedoresScreen> createState() => _FornecedoresScreenState();
}

class _FornecedoresScreenState extends State<FornecedoresScreen>
    with BackgroundRefreshMixin<FornecedoresScreen> {
  final SupplierRepository _repository = SupplierRepository();
  List<SupplierModel> _suppliers = [];
  List<SupplierModel> _filteredSuppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showActiveOnly = true;

  // TOTAIS
  int get _totalAtivos => _suppliers.where((s) => s.active).length;
  int get _totalInativos => _suppliers.where((s) => !s.active).length;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  Future<void> refreshInBackground() => _loadSuppliers();

  Future<void> _loadSuppliers() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final suppliers = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _applySupplierFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar fornecedores: $e');
    }
  }

  void _filterSuppliers(String query) {
    setState(() {
      _searchQuery = query;
      _applySupplierFilters();
    });
  }

  void _applySupplierFilters() {
    _filteredSuppliers = _suppliers.where((s) {
      final matchesSearch = _searchQuery.isEmpty ||
          s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.product.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.document.contains(_searchQuery) ||
          s.phone.contains(_searchQuery) ||
          s.address.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesActive = _showActiveOnly ? s.active : true;

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

  // DIALOG DE CADASTRO/EDIÇÃO (UNIFICADO)
  Future<void> _showSupplierForm({SupplierModel? supplier}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final documentController =
        TextEditingController(text: supplier?.document ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final emailController = TextEditingController(text: supplier?.email ?? '');
    final addressController =
        TextEditingController(text: supplier?.address ?? '');
    final productController =
        TextEditingController(text: supplier?.product ?? '');
    bool isActive = supplier?.active ?? true;

    return showDialog(
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
              child: Icon(
                supplier == null ? Icons.business : Icons.edit,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              supplier == null ? 'Novo Fornecedor' : 'Editar Fornecedor',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nome
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Fornecedor *',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),

                  // CNPJ/CPF
                  TextFormField(
                    controller: documentController,
                    decoration: const InputDecoration(
                      labelText: 'CPF/CNPJ',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  // Telefone e Email
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Telefone',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Endereço
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(
                      labelText: 'Endereço',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Produto/Material
                  TextFormField(
                    controller: productController,
                    decoration: const InputDecoration(
                      labelText: 'Produto/Material Fornecido',
                      prefixIcon: Icon(Icons.inventory),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Status
                  Row(
                    children: [
                      Switch(
                        value: isActive,
                        onChanged: (value) => isActive = value,
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
                final supplierData = supplier != null
                    ? supplier.copyWith(
                        name: nameController.text.trim(),
                        document: documentController.text.trim(),
                        phone: phoneController.text.trim(),
                        email: emailController.text.trim(),
                        address: addressController.text.trim(),
                        product: productController.text.trim(),
                        active: isActive,
                      )
                    : SupplierModel.create(
                        name: nameController.text.trim(),
                        document: documentController.text.trim(),
                        phone: phoneController.text.trim(),
                        email: emailController.text.trim(),
                        address: addressController.text.trim(),
                        product: productController.text.trim(),
                        active: isActive,
                      );

                if (supplier == null) {
                  await _repository.create(supplierData);
                } else {
                  await _repository.update(supplierData);
                }
                Navigator.pop(context);
                _loadSuppliers();
                _showSuccess(
                  supplier == null
                      ? 'Fornecedor criado com sucesso!'
                      : 'Fornecedor atualizado com sucesso!',
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F62AC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(supplier == null ? 'Criar Fornecedor' : 'Atualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSupplier(SupplierModel supplier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${supplier.name}"?'),
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
      await _repository.delete(supplier.id!);
      _loadSuppliers();
      _showSuccess('Fornecedor excluído com sucesso!');
    }
  }

  void _toggleActive(SupplierModel supplier) async {
    final updated = supplier.copyWith(active: !supplier.active);
    await _repository.update(updated);
    _loadSuppliers();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.business, color: Color(0xFF0F62AC), size: 24),
                const SizedBox(width: 12),
                Text(
                  'Fornecedores',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
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
                      const Icon(Icons.check_circle,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '$_totalAtivos ativos',
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
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel, size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        '$_totalInativos inativos',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PurchaseOrdersScreen()),
                  ),
                  icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                  label: const Text('Ordens de compra'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF0F62AC)),
                  onPressed: _loadSuppliers,
                  tooltip: 'Atualizar',
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
                      hintText: 'Buscar fornecedor por nome, produto, CNPJ...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: _filterSuppliers,
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Ativos'),
                  selected: _showActiveOnly,
                  onSelected: (value) {
                    setState(() {
                      _showActiveOnly = value;
                      _filterSuppliers(_searchQuery);
                    });
                  },
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedColor: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                  checkmarkColor: const Color(0xFF0F62AC),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showSupplierForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.business_center,
                                size: 64, color: Color(0xFFE0E0E0)),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum fornecedor cadastrado'
                                  : 'Nenhum fornecedor encontrado',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: () => _showSupplierForm(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar Fornecedor'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSuppliers,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = _filteredSuppliers[index];
                            final isActive = supplier.active;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isActive
                                      ? const Color(0xFFE0E0E0)
                                      : Colors.red.shade300,
                                ),
                              ),
                              child: ListTile(
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFF0F62AC)
                                            .withValues(alpha: 0.1)
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.business,
                                    color: isActive
                                        ? const Color(0xFF0F62AC)
                                        : Colors.grey,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        supplier.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
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
                                      '${supplier.phone} | ${supplier.email}',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
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
                                            color: Colors.blue
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            supplier.product.isNotEmpty
                                                ? supplier.product
                                                : 'Sem produto',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            supplier.document.isNotEmpty
                                                ? supplier.document
                                                : 'Sem documento',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.grey,
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
                                    IconButton(
                                      icon: Icon(
                                        Icons.toggle_on,
                                        color: isActive
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 30,
                                      ),
                                      onPressed: () => _toggleActive(supplier),
                                      tooltip:
                                          isActive ? 'Desativar' : 'Ativar',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 18, color: Colors.grey),
                                      onPressed: () =>
                                          _showSupplierForm(supplier: supplier),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      onPressed: () =>
                                          _deleteSupplier(supplier),
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
