import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../services/customer_repository.dart';
import '../../models/customer_model.dart';
import 'customer_form_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen>
    with BackgroundRefreshMixin<CustomerListScreen> {
  final CustomerRepository _repository = CustomerRepository();
  List<CustomerModel> _customers = [];
  List<CustomerModel> _filteredCustomers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showVipOnly = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  Future<void> refreshInBackground() => _loadCustomers();

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      List<CustomerModel> customers;
      if (_showVipOnly) {
        customers = await _repository.getVipCustomers();
      } else {
        customers = await _repository.getAll();
      }
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _applyCustomerFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar clientes: $e');
    }
  }

  void _filterCustomers(String query) {
    setState(() {
      _searchQuery = query;
      _applyCustomerFilters();
    });
  }

  void _applyCustomerFilters() {
    if (_searchQuery.isEmpty) {
      _filteredCustomers = _customers;
    } else {
      _filteredCustomers = _customers.where((c) {
        final search = _searchQuery.toLowerCase();
        return c.name.toLowerCase().contains(search) ||
            (c.email?.toLowerCase().contains(search) ?? false) ||
            c.phone.contains(search) ||
            (c.document?.contains(search) ?? false) ||
            (c.observations?.toLowerCase().contains(search) ?? false);
      }).toList();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _deleteCustomer(CustomerModel customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${customer.name}"?'),
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
      await _repository.delete(customer.id!);
      _loadCustomers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cliente excluído!'), backgroundColor: Colors.red),
      );
    }
  }

  void _navigateToForm({CustomerModel? customer}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          customer: customer,
          onSave: (savedCustomer) async {
            try {
              if (customer == null) {
                await _repository.create(savedCustomer);
              } else {
                await _repository.update(savedCustomer);
              }
              _loadCustomers();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(customer == null
                      ? 'Cliente criado!'
                      : 'Cliente atualizado!'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              _showError('Erro ao salvar: $e');
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Clientes'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _showVipOnly ? Icons.star : Icons.star_border,
              color: Colors.amber,
            ),
            onPressed: () {
              setState(() {
                _showVipOnly = !_showVipOnly;
                _loadCustomers();
              });
            },
            tooltip: 'Clientes VIP',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar cliente por nome, e-mail, telefone...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: _filterCustomers,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _navigateToForm(),
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
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline,
                                size: 64, color: Color(0xFFE0E0E0)),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum cliente cadastrado'
                                  : 'Nenhum cliente encontrado',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: () => _navigateToForm(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar Cliente'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCustomers,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            final isVip = customer.totalPurchases > 3000;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side:
                                    const BorderSide(color: Color(0xFFE0E0E0)),
                              ),
                              child: ListTile(
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isVip
                                        ? Colors.amber.withValues(alpha: 0.2)
                                        : const Color(0xFF0F62AC)
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isVip ? Icons.star : Icons.person,
                                    color: isVip
                                        ? Colors.amber
                                        : const Color(0xFF0F62AC),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                        child: Text(
                                      customer.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    )),
                                    if (isVip) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.verified,
                                          color: Colors.amber, size: 16),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${customer.phone} | ${customer.email ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 2),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Total compras: R\$ ${customer.totalPurchases.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.green),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 18, color: Colors.grey),
                                      onPressed: () =>
                                          _navigateToForm(customer: customer),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      onPressed: () =>
                                          _deleteCustomer(customer),
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
