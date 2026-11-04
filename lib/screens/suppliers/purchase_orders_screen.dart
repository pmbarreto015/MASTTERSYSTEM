import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/background_refresh_mixin.dart';
import '../../models/purchase_order_model.dart';
import '../../models/supplier_model.dart';
import '../../services/purchase_order_repository.dart';
import '../../services/purchase_order_print_service.dart';
import '../../services/supplier_repository.dart';

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen>
    with BackgroundRefreshMixin<PurchaseOrdersScreen> {
  final _purchaseRepository = PurchaseOrderRepository();
  final _printService = PurchaseOrderPrintService();
  final _supplierRepository = SupplierRepository();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  List<PurchaseOrderModel> _orders = [];
  List<SupplierModel> _suppliers = [];
  bool _loading = true;

  static const _statuses = {
    'solicitado': 'Solicitado',
    'aprovado': 'Aprovado',
    'recebido': 'Recebido',
    'cancelado': 'Cancelado',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> refreshInBackground() => _load(showLoading: false);

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _purchaseRepository.getAll(),
        _supplierRepository.getAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] as List<PurchaseOrderModel>;
        _suppliers = results[1] as List<SupplierModel>;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível carregar as compras: $error')),
        );
      }
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  double _number(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (cleaned.contains(',')) {
      return double.tryParse(
              cleaned.replaceAll('.', '').replaceAll(',', '.')) ??
          0;
    }
    return double.tryParse(cleaned) ?? 0;
  }

  double _draftTotal(List<_PurchaseItemDraft> drafts) => drafts.fold(
        0,
        (total, item) =>
            total +
            (_number(item.quantity.text) * _number(item.unitValue.text)),
      );

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  Future<void> _newPurchaseOrder() async {
    final activeSuppliers = _suppliers.where((item) => item.active).toList();
    SupplierModel? supplier =
        activeSuppliers.isEmpty ? null : activeSuppliers.first;
    final itemDrafts = <_PurchaseItemDraft>[_PurchaseItemDraft()];
    final notes = TextEditingController();
    DateTime? expectedDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nova ordem de compra'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Solicite materiais, insumos, serviços ou qualquer item necessário para a empresa.',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<SupplierModel>(
                    initialValue: supplier,
                    decoration: const InputDecoration(
                      labelText: 'Fornecedor',
                      border: OutlineInputBorder(),
                    ),
                    items: _suppliers
                        .where((item) => item.active)
                        .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => supplier = value),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Itens da compra',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(itemDrafts.length, (index) {
                    final item = itemDrafts[index];
                    final itemTotal = _number(item.quantity.text) *
                        _number(item.unitValue.text);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: item.description,
                                      onChanged: (_) => setDialogState(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Item ${index + 1}',
                                        hintText: 'Ex.: Lona 440g',
                                        isDense: true,
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remover item',
                                    onPressed: itemDrafts.length == 1
                                        ? null
                                        : () => setDialogState(() {
                                              final removed =
                                                  itemDrafts.removeAt(index);
                                              removed.dispose();
                                            }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: item.quantity,
                                      onChanged: (_) => setDialogState(() {}),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Quantidade',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: item.unit,
                                      onChanged: (_) => setDialogState(() {}),
                                      decoration: const InputDecoration(
                                        labelText: 'Unidade',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: item.unitValue,
                                      onChanged: (_) => setDialogState(() {}),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Valor unitário',
                                        prefixText: 'R\$ ',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Text(
                                    'Total do item: ${_money.format(itemTotal)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => setDialogState(
                        () => itemDrafts.add(_PurchaseItemDraft()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar item'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Valor total estimado',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _money.format(_draftTotal(itemDrafts)),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(expectedDate == null
                        ? 'Previsão de recebimento'
                        : 'Receber até ${DateFormat('dd/MM/yyyy').format(expectedDate!)}'),
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: expectedDate ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 1)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (selected != null) {
                        setDialogState(() => expectedDate = selected);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      hintText:
                          'Entrega, forma de pagamento, urgência, referência...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final requestedItems = itemDrafts
                    .where((item) => item.description.text.trim().isNotEmpty)
                    .map(
                      (item) => PurchaseOrderItem(
                        description: item.description.text.trim(),
                        quantity: _number(item.quantity.text) > 0
                            ? _number(item.quantity.text)
                            : 1,
                        unit: item.unit.text.trim().isEmpty
                            ? 'un.'
                            : item.unit.text.trim(),
                        unitValue: _number(item.unitValue.text),
                      ),
                    )
                    .toList();
                if (supplier == null || requestedItems.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Informe o fornecedor e pelo menos um item.'),
                  ));
                  return;
                }
                await _purchaseRepository.create(PurchaseOrderModel(
                  supplierId: supplier!.id,
                  supplierName: supplier!.name,
                  expectedDate: expectedDate == null
                      ? null
                      : DateFormat('yyyy-MM-dd').format(expectedDate!),
                  items: requestedItems,
                  notes: notes.text.trim(),
                  total: requestedItems.fold(
                    0,
                    (sum, item) => sum + item.total,
                  ),
                ));
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Registrar solicitação'),
            ),
          ],
        ),
      ),
    );
    for (final item in itemDrafts) {
      item.dispose();
    }
    notes.dispose();
    if (saved == true) await _load();
  }

  Future<void> _changeStatus(PurchaseOrderModel order, String status) async {
    await _purchaseRepository.update(order.copyWith(status: status));
    await _load(showLoading: false);
  }

  Future<void> _print(PurchaseOrderModel order) async {
    try {
      await _printService.print(order);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível imprimir a ordem: $error')),
        );
      }
    }
  }

  Color _statusColor(String status) => switch (status) {
        'aprovado' => Colors.blue,
        'recebido' => Colors.teal,
        'cancelado' => Colors.red,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Ordens de compra'),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newPurchaseOrder,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Nova solicitação'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma ordem de compra registrada.\nCrie uma solicitação para comprar insumos, materiais ou serviços.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final order = _orders[index];
                        final color = _statusColor(order.status);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.shopping_bag_outlined,
                                        color: color),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(order.number,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    IconButton(
                                      tooltip: 'Imprimir ordem de compra',
                                      onPressed: () => _print(order),
                                      icon: const Icon(Icons.print_outlined),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Alterar status',
                                      onSelected: (status) =>
                                          _changeStatus(order, status),
                                      itemBuilder: (_) => _statuses.entries
                                          .map((entry) => PopupMenuItem(
                                                value: entry.key,
                                                child: Text(entry.value),
                                              ))
                                          .toList(),
                                      child: Chip(
                                        label: Text(_statuses[order.status] ??
                                            order.status),
                                        labelStyle: TextStyle(color: color),
                                        backgroundColor:
                                            color.withValues(alpha: .12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(order.supplierName,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 6),
                                ...order.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      '• ${_quantity(item.quantity)} ${item.unit} — ${item.description}'
                                      '${item.unitValue > 0 ? '  |  ${_money.format(item.unitValue)} cada  |  ${_money.format(item.total)}' : ''}',
                                    ),
                                  ),
                                ),
                                if (order.expectedDate != null ||
                                    order.total > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '${order.expectedDate == null ? '' : 'Previsão: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(order.expectedDate!))}'}${order.expectedDate != null && order.total > 0 ? '  •  ' : ''}${order.total > 0 ? 'Estimativa: ${_money.format(order.total)}' : ''}',
                                    ),
                                  ),
                                if (order.notes.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text('Obs.: ${order.notes}'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      );
}

class _PurchaseItemDraft {
  _PurchaseItemDraft()
      : description = TextEditingController(),
        quantity = TextEditingController(text: '1'),
        unit = TextEditingController(text: 'un.'),
        unitValue = TextEditingController(text: '0,00');

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController unitValue;

  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    unitValue.dispose();
  }
}
