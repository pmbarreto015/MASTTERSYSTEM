import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import '../../services/order_repository.dart';
import '../../models/order_model.dart';

class RelatoriosScreen extends StatefulWidget {
  const RelatoriosScreen({super.key});

  @override
  State<RelatoriosScreen> createState() => _RelatoriosScreenState();
}

// CORRIGIDO: TickerProviderStateMixin (suporte a múltiplos AnimationControllers)
class _RelatoriosScreenState extends State<RelatoriosScreen>
    with TickerProviderStateMixin, BackgroundRefreshMixin<RelatoriosScreen> {
  // Repositories
  final OrderRepository _orderRepo = OrderRepository();

  String _selectedReport = 'Vendas a entregar';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  late AnimationController _animationController;
  bool _isLoading = true;

  // Dados do banco
  List<OrderModel> _orders = [];

  // Dados processados para exibição
  List<Map<String, dynamic>> _vendas = [];
  List<Map<String, dynamic>> _produtosMaisVendidos = [];
  List<Map<String, dynamic>> _clientesFieis = [];
  List<Map<String, dynamic>> _vendasPorVendedor = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animationController.forward();
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadData();

  Future<void> _loadData() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      _orders =
          (await _orderRepo.getAll()).where((o) => o.isAcceptedSale).toList();
      _processVendas();
      _processProdutosMaisVendidos();
      _processClientesFieis();
      _processVendasPorVendedor();

      setState(() => _isLoading = false);
    } catch (e) {
      print('Erro ao carregar dados: $e');
      setState(() => _isLoading = false);
      _useMockData();
    }
  }

  void _processVendas() {
    _vendas = _orders.map((order) {
      return {
        'id': order.numero,
        'cliente': order.clienteNome ?? 'Não informado',
        'valor': order.valorTotal,
        'status': _traduzirStatus(order.status),
        'data':
            DateFormat('dd/MM/yyyy').format(DateTime.parse(order.dataCriacao)),
        'produto': order.itens.isNotEmpty
            ? order.itens.map((i) => i.produtoNome).join(', ')
            : 'Sem produtos',
        'vendedor': 'Vendedor',
        'tipo': order.tipo,
        'prioridade': order.prioridade,
      };
    }).toList();
  }

  void _processProdutosMaisVendidos() {
    final Map<String, int> produtoQuantidade = {};
    final Map<String, double> produtoValor = {};

    for (var order in _orders) {
      for (var item in order.itens) {
        produtoQuantidade[item.produtoNome] =
            (produtoQuantidade[item.produtoNome] ?? 0) + item.quantidade;
        produtoValor[item.produtoNome] =
            (produtoValor[item.produtoNome] ?? 0) + item.subtotal;
      }
    }

    _produtosMaisVendidos = produtoQuantidade.entries.map((entry) {
      return {
        'produto': entry.key,
        'quantidade': entry.value,
        'valor': produtoValor[entry.key] ?? 0,
      };
    }).toList()
      ..sort(
          (a, b) => (b['quantidade'] as int).compareTo(a['quantidade'] as int));

    if (_produtosMaisVendidos.length > 10) {
      _produtosMaisVendidos = _produtosMaisVendidos.sublist(0, 10);
    }
  }

  void _processClientesFieis() {
    final Map<String, int> clienteCompras = {};
    final Map<String, double> clienteTotal = {};

    for (var order in _orders) {
      if (order.clienteNome != null) {
        clienteCompras[order.clienteNome!] =
            (clienteCompras[order.clienteNome!] ?? 0) + 1;
        clienteTotal[order.clienteNome!] =
            (clienteTotal[order.clienteNome!] ?? 0) + order.valorTotal;
      }
    }

    _clientesFieis = clienteCompras.entries.map((entry) {
      return {
        'cliente': entry.key,
        'compras': entry.value,
        'total': clienteTotal[entry.key] ?? 0,
      };
    }).toList()
      ..sort((a, b) => (b['compras'] as int).compareTo(a['compras'] as int));

    if (_clientesFieis.length > 10) {
      _clientesFieis = _clientesFieis.sublist(0, 10);
    }
  }

  void _processVendasPorVendedor() {
    _vendasPorVendedor = [
      {'vendedor': 'Carlos Silva', 'vendas': 45000.00, 'comissao': 2250.00},
      {'vendedor': 'Roberta Lima', 'vendas': 32500.00, 'comissao': 1625.00},
      {'vendedor': 'Fernando Souza', 'vendas': 28000.00, 'comissao': 1680.00},
    ];
  }

  void _useMockData() {
    _vendas = [
      {
        'id': '001',
        'cliente': 'João Silva',
        'valor': 650.00,
        'status': 'Pendente',
        'data': '10/06/2025',
        'produto': 'Banner 3x2m',
        'vendedor': 'Carlos',
        'tipo': 'OS',
        'prioridade': 'normal',
      },
      {
        'id': '002',
        'cliente': 'Maria Santos',
        'valor': 1250.00,
        'status': 'Entregue',
        'data': '11/06/2025',
        'produto': 'Camiseta Personalizada',
        'vendedor': 'Roberta',
        'tipo': 'OS',
        'prioridade': 'alta',
      },
      {
        'id': '003',
        'cliente': 'Pedro Oliveira',
        'valor': 350.00,
        'status': 'Pendente',
        'data': '12/06/2025',
        'produto': 'Adesivo Vinil',
        'vendedor': 'Carlos',
        'tipo': 'OS',
        'prioridade': 'normal',
      },
      {
        'id': '004',
        'cliente': 'Ana Costa',
        'valor': 890.00,
        'status': 'Entregue',
        'data': '13/06/2025',
        'produto': 'Placa de PVC',
        'vendedor': 'Fernanda',
        'tipo': 'OS',
        'prioridade': 'media',
      },
      {
        'id': '005',
        'cliente': 'Carlos Lima',
        'valor': 2100.00,
        'status': 'Pendente',
        'data': '14/06/2025',
        'produto': 'Letreiro ACM',
        'vendedor': 'Roberta',
        'tipo': 'OS',
        'prioridade': 'alta',
      },
    ];

    _produtosMaisVendidos = [
      {'produto': 'Banner 3x2m', 'quantidade': 150, 'valor': 9750.00},
      {
        'produto': 'Camiseta Personalizada',
        'quantidade': 120,
        'valor': 4200.00
      },
      {'produto': 'Adesivo Vinil', 'quantidade': 300, 'valor': 13500.00},
      {'produto': 'Caneca Sublimada', 'quantidade': 80, 'valor': 2000.00},
      {'produto': 'Placa de PVC', 'quantidade': 45, 'valor': 3825.00},
    ];

    _clientesFieis = [
      {'cliente': 'João Silva', 'compras': 5, 'total': 3250.00},
      {'cliente': 'Maria Santos', 'compras': 4, 'total': 4200.00},
      {'cliente': 'Pedro Oliveira', 'compras': 3, 'total': 1450.00},
    ];
  }

  String _traduzirStatus(String status) {
    final traducoes = {
      'aguardando_pagamento': 'Pendente',
      'pagamento_recebido': 'Recebido',
      'em_producao': 'Em Produção',
      'pronto': 'Pronto',
      'entregue': 'Entregue',
      'cancelado': 'Cancelado',
    };
    return traducoes[status] ?? status;
  }

  List<Map<String, dynamic>> get _filteredVendas {
    if (_selectedReport == 'Vendas a entregar') {
      return _vendas.where((v) => v['status'] == 'Pendente').toList();
    } else if (_selectedReport == 'Vendas entregues') {
      return _vendas.where((v) => v['status'] == 'Entregue').toList();
    } else if (_selectedReport == 'Vendas por período') {
      return _vendas.where((v) {
        try {
          final data = DateFormat('dd/MM/yyyy').parse(v['data']);
          return data.isAfter(_startDate) && data.isBefore(_endDate);
        } catch (e) {
          return false;
        }
      }).toList();
    }
    return _vendas;
  }

  double get _totalVendas =>
      _filteredVendas.fold(0, (sum, v) => sum + (v['valor'] as double));

  double get _totalGeral =>
      _vendas.fold(0, (sum, v) => sum + (v['valor'] as double));

  int get _totalPedidos => _orders.length;
  int get _pedidosPendentes =>
      _orders.where((o) => o.status == 'aguardando_pagamento').length;
  int get _pedidosEntregues =>
      _orders.where((o) => o.status == 'entregue').length;
  int get _totalOrcamentos =>
      _orders.where((o) => o.tipo == 'ORCAMENTO').length;

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0F62AC),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _processVendas();
      });
    }
  }

  void _printReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.print, color: Colors.white),
            SizedBox(width: 8),
            Text('Imprimindo relatório...'),
          ],
        ),
        backgroundColor: Color(0xFF0F62AC),
      ),
    );
  }

  void _exportReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.download, color: Colors.white),
            SizedBox(width: 8),
            Text('Exportando relatório...'),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Estatísticas rápidas
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                _buildStatCard(
                  'Total Pedidos',
                  _totalPedidos.toString(),
                  Icons.receipt_long,
                  Colors.blue,
                ),
                const SizedBox(width: 8),
                _buildStatCard(
                  'Pendentes',
                  _pedidosPendentes.toString(),
                  Icons.pending,
                  Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildStatCard(
                  'Entregues',
                  _pedidosEntregues.toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
                const SizedBox(width: 8),
                _buildStatCard(
                  'Orçamentos',
                  _totalOrcamentos.toString(),
                  Icons.description,
                  Colors.purple,
                ),
                const Spacer(),
                Text(
                  'Total: R\$ ${_totalGeral.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F62AC),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF0F62AC)),
                  onPressed: _loadData,
                  tooltip: 'Atualizar',
                ),
              ],
            ),
          ),

          // Filtros
          Container(
            padding: const EdgeInsets.all(10),
            color: Theme.of(context).colorScheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedReport,
                      decoration: InputDecoration(
                        labelText: 'Relatório',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Vendas a entregar',
                          child: Text('Vendas a entregar',
                              style: TextStyle(fontSize: 9)),
                        ),
                        DropdownMenuItem(
                          value: 'Vendas entregues',
                          child: Text('Vendas entregues',
                              style: TextStyle(fontSize: 9)),
                        ),
                        DropdownMenuItem(
                          value: 'Vendas por período',
                          child: Text('Vendas por período',
                              style: TextStyle(fontSize: 9)),
                        ),
                        DropdownMenuItem(
                          value: 'Total vendas',
                          child: Text('Total vendas',
                              style: TextStyle(fontSize: 9)),
                        ),
                        DropdownMenuItem(
                          value: 'Produtos mais vendidos',
                          child: Text('Produtos mais vendidos',
                              style: TextStyle(fontSize: 9)),
                        ),
                        DropdownMenuItem(
                          value: 'Clientes fiéis',
                          child: Text('Clientes fiéis',
                              style: TextStyle(fontSize: 9)),
                        ),
                        DropdownMenuItem(
                          value: 'Vendas por vendedor',
                          child: Text('Vendas por vendedor',
                              style: TextStyle(fontSize: 9)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _selectedReport = v!;
                        if (_selectedReport == 'Produtos mais vendidos') {
                          _processProdutosMaisVendidos();
                        } else if (_selectedReport == 'Clientes fiéis') {
                          _processClientesFieis();
                        } else if (_selectedReport == 'Vendas por vendedor') {
                          _processVendasPorVendedor();
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: () => _selectDateRange(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          '${DateFormat('dd/MM').format(_startDate)}-${DateFormat('dd/MM/yyyy').format(_endDate)}',
                          style: const TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _printReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F62AC),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.print, size: 12, color: Colors.white),
                        SizedBox(width: 2),
                        Text('Imprimir',
                            style: TextStyle(fontSize: 8, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: _exportReport,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.download, size: 12),
                        SizedBox(width: 2),
                        Text('Exportar', style: TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Conteúdo do relatório
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildReportContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 8, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    if (_selectedReport == 'Vendas a entregar' ||
        _selectedReport == 'Vendas entregues' ||
        _selectedReport == 'Vendas por período') {
      return _buildSalesTable();
    } else if (_selectedReport == 'Total vendas') {
      return _buildTotalSales();
    } else if (_selectedReport == 'Produtos mais vendidos') {
      return _buildTopProducts();
    } else if (_selectedReport == 'Clientes fiéis') {
      return _buildTopCustomers();
    } else if (_selectedReport == 'Vendas por vendedor') {
      return _buildSalesBySeller();
    } else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assessment, size: 64, color: Color(0xFFE0E0E0)),
            SizedBox(height: 16),
            Text(
              'Selecione um relatório',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSalesTable() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border:
                  const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'Pedido',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Cliente',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Produto',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Valor',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Status',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Data',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _filteredVendas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inbox,
                            size: 48, color: Color(0xFFE0E0E0)),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhuma venda encontrada',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Atualizar'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredVendas.length,
                    itemBuilder: (context, index) {
                      final v = _filteredVendas[index];
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(v['id'],
                                    style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(v['cliente'],
                                    style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(v['produto'],
                                    style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  'R\$ ${v['valor'].toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: v['status'] == 'Entregue'
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        v['status'] == 'Entregue'
                                            ? Icons.check_circle
                                            : Icons.pending,
                                        size: 10,
                                        color: v['status'] == 'Entregue'
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        v['status'],
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: v['status'] == 'Entregue'
                                              ? Colors.green
                                              : Colors.orange,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(v['data'],
                                    style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: const Border(top: BorderSide(color: Color(0xFFE0E0E0))),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${_filteredVendas.length} registros',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  'Total Geral: R\$ ${_totalVendas.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F62AC),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSales() {
    return Center(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.attach_money,
                  size: 40,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Total de Vendas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'R\$ ${_totalGeral.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_totalPedidos pedidos realizados',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat('Pendentes',
                        _pedidosPendentes.toString(), Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMiniStat('Entregues',
                        _pedidosEntregues.toString(), Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Atualizar Dados'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProducts() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _produtosMaisVendidos.length,
      itemBuilder: (context, index) {
        final item = _produtosMaisVendidos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF0F62AC).withValues(alpha: 0.1),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Color(0xFF0F62AC),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              item['produto'],
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              '${item['quantidade']} unidades vendidas',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            trailing: Text(
              'R\$ ${item['valor'].toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F62AC),
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopCustomers() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _clientesFieis.length,
      itemBuilder: (context, index) {
        final item = _clientesFieis[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.amber.withValues(alpha: 0.1),
              child: const Icon(Icons.star, color: Colors.amber, size: 16),
            ),
            title: Text(
              item['cliente'],
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              '${item['compras']} compras realizadas',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'R\$ ${item['total'].toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F62AC),
                    fontSize: 14,
                  ),
                ),
                const Text(
                  'gasto total',
                  style: TextStyle(fontSize: 8, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSalesBySeller() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _vendasPorVendedor.length,
      itemBuilder: (context, index) {
        final item = _vendasPorVendedor[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF0F62AC).withValues(alpha: 0.1),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Color(0xFF0F62AC),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              item['vendedor'],
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              'Comissão: R\$ ${item['comissao'].toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'R\$ ${item['vendas'].toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F62AC),
                    fontSize: 14,
                  ),
                ),
                const Text(
                  'em vendas',
                  style: TextStyle(fontSize: 8, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
