import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../services/order_repository.dart';

class QuoteApprovalScreen extends StatefulWidget {
  const QuoteApprovalScreen({super.key});

  @override
  State<QuoteApprovalScreen> createState() => _QuoteApprovalScreenState();
}

class _QuoteApprovalScreenState extends State<QuoteApprovalScreen>
    with BackgroundRefreshMixin<QuoteApprovalScreen> {
  final OrderRepository _orderRepo = OrderRepository();

  List<OrderModel> _quotes = [];
  List<OrderModel> _filteredQuotes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'Todos';

  final List<String> _statusList = [
    'Todos',
    'aguardando_pagamento',
    'cancelado',
  ];

  final Map<String, String> _statusLabels = {
    'aguardando_pagamento': 'Pendente',
    'cancelado': 'Cancelado',
  };

  final Map<String, Color> _statusColors = {
    'aguardando_pagamento': Colors.orange,
    'cancelado': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  @override
  Future<void> refreshInBackground() => _loadQuotes();

  Future<void> _loadQuotes() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final quotes = await _orderRepo.getOrcamentos();
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _applyQuoteFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      print('Erro ao carregar orçamentos: $e');
    }
  }

  void _filterQuotes() {
    setState(_applyQuoteFilters);
  }

  void _applyQuoteFilters() {
    _filteredQuotes = _quotes.where((o) {
      final matchesSearch = _searchQuery.isEmpty ||
          (o.clienteNome?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          o.numero.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus =
          _filterStatus == 'Todos' || o.status == _filterStatus;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  Future<void> _approveQuote(OrderModel quote) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Aprovar Orçamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deseja aprovar o orçamento #${quote.numero}?'),
            const SizedBox(height: 8),
            Text('Cliente: ${quote.clienteNome ?? 'Não informado'}'),
            Text('Valor: R\$ ${quote.valorTotal.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            const Text(
              'Ao aprovar, este orçamento será enviado para:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const Text('Produção (como Ordem de Serviço)'),
            const Text('Financeiro (Contas a Receber)'),
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
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await _orderRepo.approveQuote(quote);

        await _loadQuotes();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Orçamento #${quote.numero} aprovado! Enviado para Produção e Financeiro.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aprovar orçamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelQuote(OrderModel quote) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Cancelar Orçamento'),
        content: Text('Deseja cancelar o orçamento #${quote.numero}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final updatedQuote = quote.copyWith(
          status: 'cancelado',
        );
        await _orderRepo.update(updatedQuote);
        await _loadQuotes();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Orçamento #${quote.numero} cancelado.'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int get _totalPendentes =>
      _quotes.where((o) => o.status == 'aguardando_pagamento').length;
  double get _totalValor => _quotes.fold(0.0, (sum, o) => sum + o.valorTotal);

  @override
  Widget build(BuildContext context) {
    // A tela também pode ser aberta diretamente por uma MaterialPageRoute.
    // O Material raiz garante o ancestral exigido por TextField, Dropdown e InkWell.
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                const Icon(Icons.pending_actions,
                    color: Color(0xFF0F62AC), size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Orçamentos Pendentes - Aprovação',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F62AC),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        '$_totalPendentes pendentes',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
                        'R\$ ${_totalValor.toStringAsFixed(2)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loadQuotes,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Atualizar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por cliente, número...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _filterQuotes();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _filterStatus,
                    decoration: InputDecoration(
                      labelText: 'Status',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    items: _statusList.map((status) {
                      final label = status == 'Todos'
                          ? 'Todos'
                          : (_statusLabels[status] ?? status);
                      return DropdownMenuItem(
                        value: status,
                        child: Text(label),
                      );
                    }).toList(),
                    onChanged: (v) {
                      _filterStatus = v!;
                      _filterQuotes();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredQuotes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.inbox,
                                size: 64, color: Color(0xFFE0E0E0)),
                            const SizedBox(height: 16),
                            const Text(
                              'Nenhum orçamento pendente',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _loadQuotes,
                              child: const Text('Atualizar'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadQuotes,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredQuotes.length,
                          itemBuilder: (context, index) {
                            final quote = _filteredQuotes[index];
                            final statusLabel =
                                _statusLabels[quote.status] ?? quote.status;
                            final statusColor =
                                _statusColors[quote.status] ?? Colors.grey;
                            final isCanceled = quote.status == 'cancelado';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isCanceled
                                      ? Colors.red.shade300
                                      : const Color(0xFFE0E0E0),
                                ),
                              ),
                              child: InkWell(
                                onTap: () {},
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: statusColor),
                                            ),
                                            child: Text(
                                              quote.numero,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: statusColor,
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
                                      const SizedBox(height: 8),
                                      Text(
                                        quote.clienteNome ??
                                            'Cliente não informado',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        quote.itens
                                            .map((i) => i.produtoNome)
                                            .join(', '),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        maxLines: 1,
                                      ),
                                      if (quote.itens.any(
                                          (item) => item.terceirizado)) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '${quote.itens.where((item) => item.terceirizado).length} item(ns) com terceirização • uso interno',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            DateFormat('dd/MM/yyyy').format(
                                                DateTime.parse(
                                                    quote.dataCriacao)),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                            'R\$ ${quote.valorTotal.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F62AC),
                                            ),
                                          ),
                                          const Spacer(),
                                          if (quote.dataEntrega != null)
                                            Text(
                                              'Entrega: ${quote.dataEntrega}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      if (!isCanceled)
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () =>
                                                    _approveQuote(quote),
                                                icon: const Icon(Icons.check,
                                                    size: 16),
                                                label: const Text('Aprovar'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _cancelQuote(quote),
                                                icon: const Icon(Icons.close,
                                                    size: 16),
                                                label: const Text('Cancelar'),
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(
                                                      color: Colors.red),
                                                  foregroundColor: Colors.red,
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 8),
                                                ),
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
}
