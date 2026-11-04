import 'package:flutter/material.dart';
import '../../models/customer_model.dart';
import '../../models/product_model.dart';
import '../../models/order_model.dart';
import '../../services/customer_repository.dart';
import '../../services/product_repository.dart';
import '../../services/order_repository.dart';

class ConsultasScreen extends StatefulWidget {
  const ConsultasScreen({super.key});

  @override
  State<ConsultasScreen> createState() => _ConsultasScreenState();
}

class _ConsultasScreenState extends State<ConsultasScreen> {
  final CustomerRepository _customerRepo = CustomerRepository();
  final ProductRepository _productRepo = ProductRepository();
  final OrderRepository _orderRepo = OrderRepository();

  String _searchQuery = '';
  String _searchType = 'Cliente';
  bool _isSearching = false;

  List<dynamic> _results = [];
  String _errorMessage = '';

  final List<String> _searchTypes = [
    'Cliente',
    'Produto',
    'Pedido',
  ];

  Future<void> _performSearch() async {
    if (_searchQuery.trim().isEmpty) {
      setState(() {
        _results = [];
        _errorMessage = 'Digite um termo para buscar.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _results = [];
      _errorMessage = '';
    });

    try {
      List<dynamic> results = [];
      final query = _searchQuery.trim();

      switch (_searchType) {
        case 'Cliente':
          results = await _customerRepo.searchByName(query);
          break;
        case 'Produto':
          results = await _productRepo.search(query);
          break;
        case 'Pedido':
          results = await _orderRepo.search(query);
          break;
      }

      setState(() {
        _results = results;
        _isSearching = false;
        if (results.isEmpty) {
          _errorMessage = 'Nenhum resultado encontrado para "$query".';
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Erro ao realizar a busca: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Barra de Busca
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      initialValue: _searchType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Busca',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _searchTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _searchType = v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Digite o termo para buscar...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _searchQuery = v,
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _isSearching ? null : _performSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F62AC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            children: [
                              Icon(Icons.search, size: 18),
                              SizedBox(width: 8),
                              Text('Buscar'),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Área de Resultados
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Resultados ($_searchType)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F62AC),
                          ),
                        ),
                        if (_results.isNotEmpty)
                          Text(
                            '${_results.length} encontrado(s)',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: _isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : _errorMessage.isNotEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 48,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _errorMessage,
                                        style:
                                            const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : _results.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Realize uma busca para ver os resultados',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _results.length,
                                      itemBuilder: (context, index) {
                                        final result = _results[index];
                                        return _buildResultCard(result);
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(dynamic result) {
    if (result is CustomerModel) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        child: ListTile(
          leading: const Icon(Icons.person, color: Color(0xFF0F62AC)),
          title: Text(result.name),
          subtitle: Text('${result.phone} • ${result.email}'),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        ),
      );
    } else if (result is ProductModel) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        child: ListTile(
          leading: const Icon(Icons.inventory_2, color: Color(0xFF0F62AC)),
          title: Text(result.nome),
          subtitle: Text(
              '${result.codigo} • R\$ ${result.preco.toStringAsFixed(2)} • Estoque: ${result.estoque}'),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        ),
      );
    } else if (result is OrderModel) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        child: ListTile(
          leading: const Icon(Icons.receipt_long, color: Color(0xFF0F62AC)),
          title: Text('Pedido #${result.numero}'),
          subtitle: Text(
            'Cliente: ${result.clienteNome ?? 'Não informado'} • Total: R\$ ${result.valorTotal.toStringAsFixed(2)}',
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
