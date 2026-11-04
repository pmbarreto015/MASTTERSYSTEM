// lib/screens/production/apontamento_producao_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/order_model.dart';
import '../../models/maquina_model.dart';
import '../../services/order_repository.dart';
import '../../services/maquina_repository.dart';

class ApontamentoProducaoScreen extends StatefulWidget {
  const ApontamentoProducaoScreen({super.key});

  @override
  State<ApontamentoProducaoScreen> createState() =>
      _ApontamentoProducaoScreenState();
}

class _ApontamentoProducaoScreenState extends State<ApontamentoProducaoScreen>
    with BackgroundRefreshMixin<ApontamentoProducaoScreen> {
  final OrderRepository _orderRepo = OrderRepository();
  final MaquinaRepository _maquinaRepo = MaquinaRepository();

  List<OrderModel> _orders = [];
  List<OrderModel> _filteredOrders = [];
  List<MaquinaModel> _maquinas = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'todos';

  // Estado da produção
  bool _cronometroAtivo = false;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Future<void> refreshInBackground() async {
    if (!_cronometroAtivo) await _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final orders = await _orderRepo.getAll();
      final maquinas = await _maquinaRepo.getAll();
      if (!mounted) return;
      setState(() {
        _orders = orders
            .where((o) =>
                o.isAcceptedSale &&
                (o.status == 'pagamento_recebido' ||
                    o.status == 'em_producao' ||
                    o.status == 'pronto'))
            .toList();
        _maquinas = maquinas;
        _applyOrderFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar dados: $e');
    }
  }

  void _filterOrders() {
    setState(_applyOrderFilters);
  }

  void _applyOrderFilters() {
    _filteredOrders = _orders.where((o) {
      final matchesSearch = _searchQuery.isEmpty ||
          o.numero.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (o.clienteNome ?? '')
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchesStatus =
          _filterStatus == 'todos' || o.status == _filterStatus;
      return matchesSearch && matchesStatus;
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
  // INICIAR PRODUÇÃO
  // ============================================================
  void _iniciarProducao(OrderModel order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.blue, Color(0xFF0F62AC)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Iniciar Produção',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pedido: ${order.numero}'),
            Text('Cliente: ${order.clienteNome ?? 'Não informado'}'),
            const SizedBox(height: 16),
            const Text(
              'Ao iniciar a produção, o estoque será baixado automaticamente.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Atualizar status para 'em_producao'
              final updated = order.copyWith(status: 'em_producao');
              await _orderRepo.update(updated);

              // Iniciar cronômetro
              setState(() {
                _cronometroAtivo = true;
                _stopwatch.start();
              });

              Navigator.pop(context);
              _loadData();
              _showSuccess('Produção iniciada!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAUSAR PRODUÇÃO
  // ============================================================
  void _pausarProducao() {
    setState(() {
      _cronometroAtivo = false;
      _stopwatch.stop();
    });
    _showSuccess('Produção pausada');
  }

  // ============================================================
  // FINALIZAR PRODUÇÃO
  // ============================================================
  void _finalizarProducao(OrderModel order) {
    final tempoReal = _stopwatch.elapsed;
    var materialUtilizado = 0.0;
    var perda = 0.0;
    var observacoes = '';
    var selectedMaquina = _maquinas.isNotEmpty ? _maquinas.first : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final tempoRealMinutos = tempoReal.inMinutes.toDouble();

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
                      colors: [Colors.green, Color(0xFF42BE65)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Finalizar Produção',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido: ${order.numero}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // TEMPO REAL
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tempo Real',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatDuration(tempoReal),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              Text(
                                '${tempoRealMinutos.toStringAsFixed(0)} minutos',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // MATERIAL UTILIZADO
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Material Utilizado (m²)',
                              prefixIcon: Icon(Icons.inventory),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              materialUtilizado =
                                  double.tryParse(v.replaceAll(',', '.')) ?? 0;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Perda (m²)',
                              prefixIcon: Icon(Icons.delete_outline),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              perda =
                                  double.tryParse(v.replaceAll(',', '.')) ?? 0;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // MÁQUINA
                    if (_maquinas.isNotEmpty)
                      DropdownButtonFormField<MaquinaModel>(
                        initialValue: selectedMaquina,
                        decoration: const InputDecoration(
                          labelText: 'Máquina Utilizada',
                          prefixIcon: Icon(Icons.precision_manufacturing),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _maquinas.map((m) {
                          return DropdownMenuItem<MaquinaModel>(
                            value: m,
                            child: Text(m.nome),
                          );
                        }).toList(),
                        onChanged: (v) => selectedMaquina = v,
                      ),
                    const SizedBox(height: 12),

                    // CRIAR RETALHO
                    const CheckboxListTile(
                      title: Text(
                        'Criar retalho a partir da sobra',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Cadastre a sobra no menu Retalhos após finalizar',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      value: false,
                      onChanged: null,
                      activeColor: Colors.green,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    const SizedBox(height: 12),

                    // OBSERVAÇÕES
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Observações da Produção',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                      onChanged: (v) => observacoes = v,
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
                  final apontamento = <String>[
                    'Produção finalizada em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    'Tempo: ${_formatDuration(tempoReal)}',
                    if (selectedMaquina != null)
                      'Máquina: ${selectedMaquina!.nome}',
                    if (materialUtilizado > 0)
                      'Material utilizado: ${materialUtilizado.toStringAsFixed(2)} m²',
                    if (perda > 0) 'Perda: ${perda.toStringAsFixed(2)} m²',
                    if (observacoes.trim().isNotEmpty) observacoes.trim(),
                  ].join(' | ');
                  final updated = order.copyWith(
                    status: 'pronto',
                    observacoes: order.observacoes.trim().isEmpty
                        ? apontamento
                        : '${order.observacoes.trim()}\n$apontamento',
                  );
                  await _orderRepo.update(updated);
                  if (!mounted) return;

                  // Resetar cronômetro
                  setState(() {
                    _cronometroAtivo = false;
                    _stopwatch.reset();
                  });

                  Navigator.pop(context);
                  _loadData();
                  _showSuccess('Produção finalizada!');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Finalizar Produção'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // CANCELAR PRODUÇÃO
  // ============================================================
  Future<void> _cancelarProducao(OrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Produção'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja cancelar a produção do pedido?'),
            const SizedBox(height: 8),
            Text('Pedido: ${order.numero}'),
            const SizedBox(height: 8),
            const Text(
              'O estoque será restaurado automaticamente.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = order.copyWith(status: 'pagamento_recebido');
      await _orderRepo.update(updated);
      setState(() {
        _cronometroAtivo = false;
        _stopwatch.reset();
      });
      _loadData();
      _showSuccess('Produção cancelada');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Apontamento de Produção'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_cronometroAtivo) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_stopwatch.elapsed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon:
                        const Icon(Icons.pause, color: Colors.white, size: 20),
                    onPressed: _pausarProducao,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // FILTROS
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar pedido...',
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
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _filterOrders();
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
                      items: const [
                        DropdownMenuItem<String>(
                            value: 'todos', child: Text('Todos')),
                        DropdownMenuItem<String>(
                            value: 'pagamento_recebido',
                            child: Text('Pagamento Recebido')),
                        DropdownMenuItem<String>(
                            value: 'em_producao', child: Text('Em Produção')),
                        DropdownMenuItem<String>(
                            value: 'pronto', child: Text('Pronto')),
                      ],
                      onChanged: (v) {
                        _filterStatus = v!;
                        _filterOrders();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // LISTA DE PEDIDOS
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox,
                                size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'Nenhum pedido em produção',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Pedidos com pagamento recebido aparecem aqui',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF999999)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredOrders.length,
                        itemBuilder: (context, index) {
                          final order = _filteredOrders[index];
                          final isEmProducao = order.status == 'em_producao';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isEmProducao
                                    ? Colors.blue.shade300
                                    : Colors.grey.shade200,
                                width: isEmProducao ? 2 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Cabeçalho
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isEmProducao
                                                    ? Colors.blue
                                                        .withValues(alpha: 0.1)
                                                    : Colors.green
                                                        .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                isEmProducao
                                                    ? Icons.factory
                                                    : Icons.check_circle,
                                                color: isEmProducao
                                                    ? Colors.blue
                                                    : Colors.green,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    order.numero,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    order.clienteNome ??
                                                        'Cliente não informado',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isEmProducao
                                              ? Colors.blue
                                                  .withValues(alpha: 0.1)
                                              : Colors.green
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isEmProducao
                                              ? 'Em Produção'
                                              : 'Pagamento Recebido',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isEmProducao
                                                ? Colors.blue
                                                : Colors.green,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Detalhes
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildInfoChip(
                                          'Valor',
                                          'R\$ ${order.valorTotal.toStringAsFixed(2)}',
                                          Colors.blue,
                                        ),
                                      ),
                                      Expanded(
                                        child: _buildInfoChip(
                                          'Data',
                                          DateFormat('dd/MM/yyyy').format(
                                              DateTime.parse(
                                                  order.dataCriacao)),
                                          Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // AÇÕES
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (!isEmProducao)
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _iniciarProducao(order),
                                          icon: const Icon(Icons.play_arrow,
                                              size: 16),
                                          label: const Text('Iniciar'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            textStyle:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      if (isEmProducao) ...[
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _finalizarProducao(order),
                                          icon:
                                              const Icon(Icons.check, size: 16),
                                          label: const Text('Finalizar'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            textStyle:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _cancelarProducao(order),
                                          icon:
                                              const Icon(Icons.close, size: 16),
                                          label: const Text('Cancelar'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            textStyle:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
