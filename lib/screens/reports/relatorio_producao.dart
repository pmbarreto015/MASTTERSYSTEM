// lib/screens/relatorios/relatorio_producao.dart

import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../services/order_repository.dart';
import '../../services/maquina_repository.dart';
import '../../services/material_repository.dart';
import '../../services/retalho_repository.dart';
import '../../models/order_model.dart';
import '../../models/maquina_model.dart';
import '../../models/material_model.dart';
import '../../models/retalho_model.dart';

class RelatorioProducaoScreen extends StatefulWidget {
  const RelatorioProducaoScreen({super.key});

  @override
  State<RelatorioProducaoScreen> createState() =>
      _RelatorioProducaoScreenState();
}

class _RelatorioProducaoScreenState extends State<RelatorioProducaoScreen>
    with BackgroundRefreshMixin<RelatorioProducaoScreen> {
  final OrderRepository _orderRepo = OrderRepository();
  final MaquinaRepository _maquinaRepo = MaquinaRepository();
  final MaterialRepository _materialRepo = MaterialRepository();
  final RetalhoRepository _retalhoRepo = RetalhoRepository();

  bool _isLoading = true;
  String _periodo = 'mes';
  DateTime _dataInicio = DateTime.now().subtract(const Duration(days: 30));
  DateTime _dataFim = DateTime.now();

  // Dados dos relatórios
  List<OrderModel> _orders = [];
  List<MaquinaModel> _maquinas = [];
  List<MaterialModel> _materiais = [];
  List<RetalhoModel> _retalhos = [];

  // Totais
  double _totalVendas = 0;
  double _totalCusto = 0;
  double _totalLucro = 0;
  double _margemMedia = 0;
  int _totalPedidos = 0;
  int _totalProduzidos = 0;

  // Uso de máquinas
  final Map<String, double> _usoMaquinas = {};

  // Materiais mais usados
  final Map<String, double> _materiaisMaisUsados = {};

  // Retalhos gerados
  int _totalRetalhos = 0;
  double _totalAreaRetalhos = 0;
  double _totalEconomiaRetalhos = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Future<void> refreshInBackground() => _loadData();

  Future<void> _loadData() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      _orders =
          (await _orderRepo.getAll()).where((o) => o.isAcceptedSale).toList();
      _maquinas = await _maquinaRepo.getAll();
      _materiais = await _materialRepo.getAll();
      _retalhos = await _retalhoRepo.getAll();

      _calcularTotais();
      _calcularUsoMaquinas();
      _calcularMateriaisMaisUsados();
      _calcularRetalhos();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erro ao carregar dados: $e');
    }
  }

  void _calcularTotais() {
    final ordersFiltrados = _orders.where((o) {
      final data = DateTime.parse(o.dataCriacao);
      return data.isAfter(_dataInicio) && data.isBefore(_dataFim);
    }).toList();

    _totalPedidos = ordersFiltrados.length;
    _totalProduzidos =
        ordersFiltrados.where((o) => o.status == 'entregue').length;
    _totalVendas = ordersFiltrados.fold(0, (sum, o) => sum + o.valorTotal);

    // TODO: Calcular custo real dos pedidos
    _totalCusto = _totalVendas * 0.5; // Placeholder
    _totalLucro = _totalVendas - _totalCusto;
    _margemMedia = _totalVendas > 0 ? (_totalLucro / _totalVendas) * 100 : 0;
  }

  void _calcularUsoMaquinas() {
    // TODO: Calcular uso real das máquinas
    for (var maquina in _maquinas) {
      _usoMaquinas[maquina.nome] = (maquina.custoTotalHora / 10); // Placeholder
    }
  }

  void _calcularMateriaisMaisUsados() {
    // TODO: Calcular materiais mais usados
    for (var material in _materiais) {
      _materiaisMaisUsados[material.nome] =
          material.quantidadeEstoque / 10; // Placeholder
    }
  }

  void _calcularRetalhos() {
    final retalhosDisponiveis =
        _retalhos.where((r) => r.status == 'disponivel').toList();
    _totalRetalhos = retalhosDisponiveis.length;
    _totalAreaRetalhos = retalhosDisponiveis.fold(0, (sum, r) => sum + r.area);
    _totalEconomiaRetalhos =
        retalhosDisponiveis.fold(0, (sum, r) => sum + r.valorEstimado);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Relatórios de Produção'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // TODO: Exportar relatório
              _showSuccess('Relatório exportado!');
            },
            tooltip: 'Exportar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // FILTRO DE PERÍODO
                  _buildPeriodoSelector(),
                  const SizedBox(height: 16),

                  // CARDS DE RESUMO
                  _buildResumoCards(),
                  const SizedBox(height: 16),

                  // GRÁFICO DE USO DE MÁQUINAS
                  _buildUsoMaquinas(),
                  const SizedBox(height: 16),

                  // MATERIAIS MAIS USADOS
                  _buildMateriaisMaisUsados(),
                  const SizedBox(height: 16),

                  // RETALHOS
                  _buildRetalhos(),
                  const SizedBox(height: 16),

                  // ÚLTIMOS PEDIDOS
                  _buildUltimosPedidos(),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodoSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Color(0xFF0F62AC)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _periodo,
                decoration: const InputDecoration(
                  labelText: 'Período',
                  border: InputBorder.none,
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'semana', child: Text('Última Semana')),
                  DropdownMenuItem(value: 'mes', child: Text('Último Mês')),
                  DropdownMenuItem(
                      value: 'trimestre', child: Text('Último Trimestre')),
                  DropdownMenuItem(value: 'ano', child: Text('Último Ano')),
                  DropdownMenuItem(
                      value: 'personalizado', child: Text('Personalizado')),
                ],
                onChanged: (v) {
                  setState(() {
                    _periodo = v!;
                    _atualizarPeriodo();
                  });
                },
              ),
            ),
            if (_periodo == 'personalizado') ...[
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selecionarPeriodo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F62AC),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: const Text('Selecionar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _atualizarPeriodo() {
    final now = DateTime.now();
    switch (_periodo) {
      case 'semana':
        _dataInicio = now.subtract(const Duration(days: 7));
        break;
      case 'mes':
        _dataInicio = now.subtract(const Duration(days: 30));
        break;
      case 'trimestre':
        _dataInicio = now.subtract(const Duration(days: 90));
        break;
      case 'ano':
        _dataInicio = now.subtract(const Duration(days: 365));
        break;
      default:
        break;
    }
    _dataFim = now;
    _calcularTotais();
  }

  Future<void> _selecionarPeriodo() async {
    final inicio = await showDatePicker(
      context: context,
      initialDate: _dataInicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (inicio != null) {
      final fim = await showDatePicker(
        context: context,
        initialDate: _dataFim,
        firstDate: inicio,
        lastDate: DateTime.now(),
      );
      if (fim != null) {
        setState(() {
          _dataInicio = inicio;
          _dataFim = fim;
        });
        _calcularTotais();
      }
    }
  }

  Widget _buildResumoCards() {
    return Row(
      children: [
        Expanded(
          child: _buildResumoCard(
            'Vendas',
            'R\$ ${_totalVendas.toStringAsFixed(2)}',
            '$_totalPedidos pedidos',
            Colors.blue,
            Icons.attach_money,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildResumoCard(
            'Lucro',
            'R\$ ${_totalLucro.toStringAsFixed(2)}',
            '${_margemMedia.toStringAsFixed(1)}% margem',
            Colors.green,
            Icons.trending_up,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildResumoCard(
            'Produzidos',
            '$_totalProduzidos',
            '$_totalPedidos pedidos',
            Colors.orange,
            Icons.factory,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildResumoCard(
            'Retalhos',
            '$_totalRetalhos',
            '${_totalAreaRetalhos.toStringAsFixed(2)} m²',
            Colors.purple,
            Icons.recycling,
          ),
        ),
      ],
    );
  }

  Widget _buildResumoCard(
      String title, String value, String subtitle, Color color, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsoMaquinas() {
    if (_usoMaquinas.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('Nenhuma máquina cadastrada',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Uso de Máquinas',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ..._usoMaquinas.entries.map((entry) {
              final percentual = entry.value;
              final isHigh = percentual > 70;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${percentual.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                isHigh ? Colors.red : const Color(0xFF0F62AC),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentual / 100,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isHigh ? Colors.red : const Color(0xFF0F62AC),
                      ),
                      minHeight: 8,
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMateriaisMaisUsados() {
    if (_materiaisMaisUsados.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Materiais Mais Usados',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ..._materiaisMaisUsados.entries.take(5).map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      color: const Color(0xFF0F62AC),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '${entry.value.toStringAsFixed(1)} m²',
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
          ],
        ),
      ),
    );
  }

  Widget _buildRetalhos() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Retalhos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildRetalhoItem(
                    'Total Retalhos',
                    '$_totalRetalhos',
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildRetalhoItem(
                    'Área Total',
                    '${_totalAreaRetalhos.toStringAsFixed(2)} m²',
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildRetalhoItem(
                    'Economia',
                    'R\$ ${_totalEconomiaRetalhos.toStringAsFixed(2)}',
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRetalhoItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUltimosPedidos() {
    final ultimos = _orders.take(5).toList();
    if (ultimos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('Nenhum pedido encontrado',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Últimos Pedidos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...ultimos.map((order) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.numero,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            order.clienteNome ?? 'Cliente não informado',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'R\$ ${order.valorTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _traduzirStatus(order.status),
                        style: TextStyle(
                          fontSize: 10,
                          color: _getStatusColor(order.status),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _traduzirStatus(String status) {
    final traducoes = {
      'aguardando_pagamento': 'Pendente',
      'pagamento_recebido': 'Pago',
      'em_producao': 'Em Produção',
      'pronto': 'Pronto',
      'entregue': 'Entregue',
      'cancelado': 'Cancelado',
    };
    return traducoes[status] ?? status;
  }

  Color _getStatusColor(String status) {
    final colors = {
      'aguardando_pagamento': Colors.orange,
      'pagamento_recebido': Colors.green,
      'em_producao': Colors.blue,
      'pronto': Colors.purple,
      'entregue': Colors.green,
      'cancelado': Colors.red,
    };
    return colors[status] ?? Colors.grey;
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }
}
