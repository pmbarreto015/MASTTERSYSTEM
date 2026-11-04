import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../models/customer_model.dart';
import '../../models/seller_model.dart';
import '../../services/order_repository.dart';
import '../../services/impressao_service.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

// CORRIGIDO: TickerProviderStateMixin
class _ProductionScreenState extends State<ProductionScreen>
    with TickerProviderStateMixin, BackgroundRefreshMixin<ProductionScreen> {
  final OrderRepository _repository = OrderRepository();
  List<OrderModel> _orders = [];
  List<OrderModel> _filteredOrders = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'Todos';
  late AnimationController _animationController;

  final List<String> _statusList = [
    'Todos',
    'aguardando_pagamento',
    'pagamento_recebido',
    'em_producao',
    'pronto',
    'entregue',
    'cancelado'
  ];

  final Map<String, String> _statusLabels = {
    'aguardando_pagamento': 'Arte',
    'pagamento_recebido': 'Impressão',
    'em_producao': 'Acabamento',
    'pronto': 'Qualidade',
    'entregue': 'Finalizado',
    'cancelado': 'Cancelado',
  };

  final Map<String, Color> _statusColors = {
    'aguardando_pagamento': Colors.blue,
    'pagamento_recebido': Colors.orange,
    'em_producao': Colors.purple,
    'pronto': Colors.teal,
    'entregue': Colors.green,
    'cancelado': Colors.red,
  };

  final Map<String, int> _statusProgress = {
    'aguardando_pagamento': 20,
    'pagamento_recebido': 40,
    'em_producao': 60,
    'pronto': 80,
    'entregue': 100,
  };

  final Map<String, String> _priorityLabels = {
    'normal': 'Normal',
    'media': 'Média',
    'alta': 'Alta',
  };

  final Map<String, Color> _priorityColors = {
    'normal': Colors.green,
    'media': Colors.orange,
    'alta': Colors.red,
  };

  // Estatísticas
  int get _totalEmProducao => _orders
      .where((o) =>
          o.status == 'pagamento_recebido' ||
          o.status == 'em_producao' ||
          o.status == 'pronto')
      .length;
  int get _totalPendentes =>
      _orders.where((o) => o.status == 'aguardando_pagamento').length;
  int get _totalEntregues =>
      _orders.where((o) => o.status == 'entregue').length;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _loadOrders();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadOrders();

  Future<void> _loadOrders() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final orders = await _repository.getProducao();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _applyOrderFilters();
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      print('Erro ao carregar pedidos: $e');
    }
  }

  void _filterOrders() {
    setState(_applyOrderFilters);
  }

  void _applyOrderFilters() {
    _filteredOrders = _orders.where((o) {
      final matchesSearch = _searchQuery.isEmpty ||
          (o.clienteNome?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          o.numero.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus =
          _filterStatus == 'Todos' || o.status == _filterStatus;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  Future<void> _advanceStatus(OrderModel order) async {
    final current = order.status;
    String newStatus = current;

    switch (current) {
      case 'aguardando_pagamento':
        newStatus = 'pagamento_recebido';
        break;
      case 'pagamento_recebido':
        newStatus = 'em_producao';
        break;
      case 'em_producao':
        newStatus = 'pronto';
        break;
      case 'pronto':
        newStatus = 'entregue';
        break;
      default:
        return;
    }

    final updated = order.copyWith(status: newStatus);
    await _repository.update(updated);
    if (!mounted) return;
    _loadOrders();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(
                'Status alterado para: ${_statusLabels[newStatus] ?? newStatus}'),
          ],
        ),
        backgroundColor: _statusColors[newStatus] ?? Colors.green,
      ),
    );
  }

  Future<void> _regressStatus(OrderModel order) async {
    final current = order.status;
    String newStatus = current;

    switch (current) {
      case 'pagamento_recebido':
        newStatus = 'aguardando_pagamento';
        break;
      case 'em_producao':
        newStatus = 'pagamento_recebido';
        break;
      case 'pronto':
        newStatus = 'em_producao';
        break;
      case 'entregue':
        newStatus = 'pronto';
        break;
      default:
        return;
    }

    final updated = order.copyWith(status: newStatus);
    await _repository.update(updated);
    if (!mounted) return;
    _loadOrders();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.arrow_back, color: Colors.white),
            const SizedBox(width: 8),
            Text('Voltou para: ${_statusLabels[newStatus] ?? newStatus}'),
          ],
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _changePriority(OrderModel order, String newPriority) async {
    final updated = order.copyWith(prioridade: newPriority);
    await _repository.update(updated);
    if (!mounted) return;
    _loadOrders();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.priority_high, color: Colors.white),
            const SizedBox(width: 8),
            Text(
                'Prioridade alterada para: ${_priorityLabels[newPriority] ?? newPriority}'),
          ],
        ),
        backgroundColor: _priorityColors[newPriority] ?? Colors.blue,
      ),
    );
  }

  void _showOrderDetails(OrderModel order) {
    final displayStatus = _statusLabels[order.status] ?? order.status;
    final statusColor = _statusColors[order.status] ?? Colors.grey;
    final priorityLabel = _priorityLabels[order.prioridade] ?? 'Normal';
    final priorityColor = _priorityColors[order.prioridade] ?? Colors.green;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    statusColor,
                                    statusColor.withValues(alpha: 0.6)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.print,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'OS #${order.numero}',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                ),
                                Text(
                                  'Cliente: ${order.clienteNome ?? 'Não informado'}',
                                  style: const TextStyle(
                                      fontSize: 14, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Grid de Informações
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            'Data Criação',
                            DateFormat('dd/MM/yyyy HH:mm')
                                .format(DateTime.parse(order.dataCriacao)),
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            'Entrega',
                            order.dataEntrega != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(DateTime.parse(order.dataEntrega!))
                                : 'Não definida',
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            'Status',
                            displayStatus,
                            statusColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            'Prioridade',
                            priorityLabel,
                            priorityColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Observações
                    if (order.observacoes.isNotEmpty) ...[
                      const Text(
                        'Observações',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          order.observacoes,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Produtos
                    const Text(
                      'Produtos:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ...order.itens.map(_buildProductionProductCard),

                    const SizedBox(height: 16),

                    // Timeline de Produção
                    _buildProductionTimeline(order),

                    const SizedBox(height: 24),

                    // Botões de Ação
                    Row(
                      children: [
                        if (order.status != 'aguardando_pagamento' &&
                            order.status != 'entregue' &&
                            order.status != 'cancelado')
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _regressStatus(order);
                              },
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('Voltar'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                side: const BorderSide(color: Colors.orange),
                                foregroundColor: Colors.orange,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        if (order.status != 'aguardando_pagamento' &&
                            order.status != 'entregue' &&
                            order.status != 'cancelado')
                          const SizedBox(width: 8),
                        if (order.status != 'entregue' &&
                            order.status != 'cancelado')
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _advanceStatus(order);
                              },
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: Text(
                                  'Avançar para ${_statusLabels[_getNextStatus(order.status)] ?? 'Próximo'}'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F62AC),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: order.prioridade,
                            decoration: const InputDecoration(
                              labelText: 'Prioridade',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'normal', child: Text('Normal')),
                              DropdownMenuItem(
                                  value: 'media', child: Text('Média')),
                              DropdownMenuItem(
                                  value: 'alta', child: Text('Alta')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                Navigator.pop(context);
                                _changePriority(order, v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Botão Reimprimir
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          final cliente = CustomerModel.create(
                            name: order.clienteNome ?? 'Cliente',
                            phone: '',
                          );

                          final vendedor = SellerModel.create(
                            name: order.clienteNome ?? 'Vendedor',
                            phone: '',
                            email: '',
                            commission: 0,
                          );

                          try {
                            final bytes =
                                await ImpressaoService().gerarPdfProducaoBytes(
                              order,
                              cliente,
                              vendedor,
                            );
                            await ImpressaoService().imprimirPdf(bytes);
                          } catch (_) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Não foi possível gerar a ordem de produção.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('Reimprimir Pedido',
                            style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F62AC),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProductionProductCard(OrderItemModel item) {
    final hasDimensions = item.largura > 0 && item.altura > 0;
    final technicalDetails = _technicalDetails(item);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: () => _showProductDetails(item),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F62AC).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF0F62AC),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.produtoNome,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Quantidade: ${item.quantidade}'
                      '${hasDimensions ? '  •  ${item.largura.toStringAsFixed(0)} x ${item.altura.toStringAsFixed(0)} mm' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (item.especificacoes.trim().isNotEmpty)
                      Text(
                        item.especificacoes.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    if (technicalDetails.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Possui composição de materiais',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (item.terceirizado)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'TERCEIRIZADO',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProductDetails(OrderItemModel item) async {
    final technicalDetails = _technicalDetails(item);
    final hasDimensions = item.largura > 0 && item.altura > 0;
    final area = hasDimensions
        ? (item.largura * item.altura / 1000000) * item.quantidade
        : 0.0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                color: const Color(0xFF0F62AC),
                child: Row(
                  children: [
                    const Icon(Icons.precision_manufacturing_outlined,
                        color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.produtoNome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _productionDetail(
                            'Quantidade',
                            item.quantidade.toString(),
                            Icons.numbers,
                          ),
                          _productionDetail(
                            'Medidas',
                            hasDimensions
                                ? '${item.largura.toStringAsFixed(0)} x ${item.altura.toStringAsFixed(0)} mm'
                                : 'Não informadas',
                            Icons.straighten,
                          ),
                          if (area > 0)
                            _productionDetail(
                              'Área total',
                              '${area.toStringAsFixed(3)} m²',
                              Icons.square_foot,
                            ),
                          _productionDetail(
                            'Execução',
                            item.terceirizado ? 'Terceirizada' : 'Interna',
                            item.terceirizado
                                ? Icons.outbox_outlined
                                : Icons.factory_outlined,
                          ),
                        ],
                      ),
                      if (item.especificacoes.trim().isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Especificações, cores e acabamento',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blue.withValues(alpha: .25)),
                          ),
                          child: SelectableText(item.especificacoes.trim()),
                        ),
                      ],
                      if (technicalDetails.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Materiais da composição',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.teal.withValues(alpha: .25)),
                          ),
                          child: SelectableText(
                            technicalDetails,
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Fechar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productionDetail(String label, String value, IconData icon) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFF0F62AC)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _technicalDetails(OrderItemModel item) {
    if (item.detalhesCusto.trim().isEmpty) return '';
    return item.detalhesCusto
        .split('\n')
        .map((line) => line
            .replaceAll(
              RegExp(r'\s*\|\s*Custo\s+R\$\s*[\d.,]+', caseSensitive: false),
              '',
            )
            .replaceAll(
              RegExp(r'\s*\|\s*Venda\s+R\$\s*[\d.,]+', caseSensitive: false),
              '',
            )
            .trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  Widget _buildInfoCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getNextStatus(String current) {
    switch (current) {
      case 'aguardando_pagamento':
        return 'pagamento_recebido';
      case 'pagamento_recebido':
        return 'em_producao';
      case 'em_producao':
        return 'pronto';
      case 'pronto':
        return 'entregue';
      default:
        return current;
    }
  }

  Widget _buildProductionTimeline(OrderModel order) {
    final stages = [
      'aguardando_pagamento',
      'pagamento_recebido',
      'em_producao',
      'pronto',
      'entregue'
    ];
    final currentIndex = stages.indexOf(order.status);
    final statusColor = _statusColors[order.status] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progresso da Produção',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stages.length,
              separatorBuilder: (context, index) => SizedBox(
                width: 24,
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: index < currentIndex
                      ? const Color(0xFF0F62AC)
                      : Colors.grey.shade300,
                ),
              ),
              itemBuilder: (context, index) {
                final isComplete = index <= currentIndex;
                final isCurrent = index == currentIndex;
                final statusKey = stages[index];
                final statusLabel = _statusLabels[statusKey] ?? statusKey;
                final statusColorStage =
                    _statusColors[statusKey] ?? Colors.grey;

                return Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isComplete
                            ? statusColorStage
                            : Colors.grey.shade200,
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFF0F62AC)
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: isComplete
                          ? const Icon(
                              Icons.check,
                              size: 22,
                              color: Colors.white,
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusLabel
                          .replaceAll('', '')
                          .replaceAll('', '')
                          .replaceAll('', '')
                          .replaceAll('', '')
                          .replaceAll('', '')
                          .replaceAll('', ''),
                      style: TextStyle(
                        fontSize: 9,
                        color: isComplete
                            ? statusColorStage
                            : Colors.grey.shade500,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                Container(
                  width: (_statusProgress[order.status] ?? 0) *
                      MediaQuery.of(context).size.width /
                      100 *
                      0.85,
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_statusProgress[order.status]}% concluído',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Status: ${_statusLabels[order.status] ?? order.status}',
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // BARRA DE TÍTULO COM BOTÃO VOLTAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F62AC),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Voltar',
                ),
                const SizedBox(width: 8),
                const Icon(Icons.factory, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Ordens de Serviço - Produção',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Cards de estatísticas
                _buildStatCard('$_totalPendentes', 'Pendentes', Colors.orange),
                const SizedBox(width: 8),
                _buildStatCard('$_totalEmProducao', 'Em Produção', Colors.blue),
                const SizedBox(width: 8),
                _buildStatCard('$_totalEntregues', 'Finalizados', Colors.green),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loadOrders,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Atualizar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: const Color(0xFF0F62AC),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Barra de Busca e Filtros
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Buscar por cliente, número...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          onChanged: (v) {
                            _searchQuery = v;
                            _filterOrders();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        initialValue: _filterStatus,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        items: _statusList.map((status) {
                          final label = status == 'Todos'
                              ? 'Todos'
                              : (_statusLabels[status] ?? status);
                          return DropdownMenuItem(
                            value: status,
                            child: Text(label,
                                style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (v) {
                          _filterStatus = v!;
                          _filterOrders();
                        },
                      ),
                    ),
                  ],
                ),
                if (_filterStatus != 'Todos' || _searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_filteredOrders.length} resultado(s) encontrado(s)',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _filterStatus = 'Todos';
                              _filterOrders();
                            });
                          },
                          child: const Text('Limpar filtros',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Lista de Pedidos
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'Nenhum pedido em produção',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _loadOrders,
                              child: const Text('Atualizar'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = _filteredOrders[index];
                            final statusLabel =
                                _statusLabels[order.status] ?? order.status;
                            final statusColor =
                                _statusColors[order.status] ?? Colors.grey;
                            final progress = _statusProgress[order.status] ?? 0;
                            final priorityLabel =
                                _priorityLabels[order.prioridade] ?? 'Normal';
                            final priorityColor =
                                _priorityColors[order.prioridade] ??
                                    Colors.green;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () => _showOrderDetails(order),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Linha 1: Número, Prioridade, Status
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: statusColor),
                                            ),
                                            child: Text(
                                              order.numero,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: statusColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: priorityColor.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              priorityLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: priorityColor,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  statusLabel,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: statusColor,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Linha 2: Cliente e Produtos
                                      Text(
                                        order.clienteNome ??
                                            'Cliente não informado',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        order.itens
                                            .map((i) => i.produtoNome)
                                            .join(', '),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 10),

                                      // Linha 3: Data e Entrega
                                      Row(
                                        children: [
                                          Text(
                                            DateFormat('dd/MM/yyyy').format(
                                                DateTime.parse(
                                                    order.dataCriacao)),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (order.dataEntrega != null)
                                            Text(
                                              'Entrega: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(order.dataEntrega!))}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Barra de Progresso
                                      Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: (progress / 100) *
                                                  MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.9,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF0F62AC),
                                                    Color(0xFF4589FF)
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '$progress% concluído',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          if (order.status == 'entregue')
                                            const Text(
                                              'Finalizado!',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.green,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
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

  Widget _buildStatCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
