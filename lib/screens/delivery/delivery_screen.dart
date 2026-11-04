import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/background_refresh_mixin.dart';
import '../../models/delivery_model.dart';
import '../../models/financial_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/delivery_print_service.dart';
import '../../services/delivery_repository.dart';
import '../../services/order_repository.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen>
    with BackgroundRefreshMixin<DeliveryScreen> {
  final _repository = DeliveryRepository();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _date = DateFormat('dd/MM HH:mm');
  final _search = TextEditingController();
  List<DeliveryModel> _deliveries = const [];
  String _filter = 'pendentes';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Duration get backgroundRefreshInterval => const Duration(seconds: 30);

  @override
  Future<void> refreshInBackground() => _load(silent: true);

  String get _actor =>
      context.read<AuthProvider>().currentUser?.fullName ?? 'Usuário';

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final deliveries = await _repository.syncCompletedOrders(actor: _actor);
      if (!mounted) return;
      setState(() {
        _deliveries = deliveries;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível importar os pedidos finalizados. $error';
      });
    }
  }

  List<DeliveryModel> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _deliveries.where((delivery) {
      if (_filter == 'pendentes' &&
          const {'concluido', 'cancelado'}.contains(delivery.status)) {
        return false;
      }
      if (_filter == 'finalizados_mes') {
        final completed = delivery.completedAt;
        final now = DateTime.now();
        if (delivery.status != 'concluido' ||
            completed == null ||
            completed.year != now.year ||
            completed.month != now.month) {
          return false;
        }
      }
      if (_filter == 'atrasados' && !delivery.isLate) {
        return false;
      }
      if (_filter != 'todos' &&
          _filter != 'atrasados' &&
          _filter != 'pendentes' &&
          _filter != 'finalizados_mes' &&
          delivery.status != _filter) return false;
      return query.isEmpty ||
          '${delivery.orderNumber} ${delivery.customerName} ${delivery.methodLabel} ${delivery.responsible}'
              .toLowerCase()
              .contains(query);
    }).toList();
  }

  int get _ready => _deliveries
      .where((item) => !const {'concluido', 'cancelado'}.contains(item.status))
      .length;
  int get _late => _deliveries.where((item) => item.isLate).length;
  int get _complete => _deliveries.where((item) {
        final completed = item.completedAt;
        final now = DateTime.now();
        return item.status == 'concluido' &&
            completed != null &&
            completed.year == now.year &&
            completed.month == now.month;
      }).length;

  Future<void> _edit(DeliveryModel delivery) async {
    final result = await showDialog<DeliveryModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeliveryDialog(delivery: delivery),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repository.save(result, actor: _actor);
      await _load(silent: true);
      if (mounted) _message('Entrega atualizada.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _launchReceivable(DeliveryModel delivery) async {
    setState(() => _saving = true);
    try {
      await _repository.launchReceivable(delivery, actor: _actor);
      await _load(silent: true);
      if (mounted) _message('Conta a receber lançada no Financeiro.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printDelivery(DeliveryModel delivery) async {
    setState(() => _saving = true);
    try {
      final order = await OrderRepository().getById(delivery.orderId);
      if (order == null) {
        throw StateError('Pedido da entrega n?o foi encontrado.');
      }
      await DeliveryPrintService().print(delivery, order);
    } catch (error) {
      if (mounted) {
        _message('N?o foi poss?vel imprimir a entrega: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _conclude(DeliveryModel delivery) async {
    setState(() => _saving = true);
    try {
      await _repository.conclude(delivery, actor: _actor);
      await _load(silent: true);
      if (mounted)
        _message('Entrega concluída e movida para Finalizadas no mês.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _receivePayment(DeliveryModel delivery) async {
    if (!context.read<AuthProvider>().hasPermission('financeiro')) {
      _message('Seu usuário precisa de permissão para o Financeiro.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    List<FinancialModel> receivables;
    try {
      receivables = await _repository.pendingReceivables(delivery.orderId);
    } catch (error) {
      if (mounted)
        _message('Não foi possível consultar as contas: $error', error: true);
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (receivables.isEmpty) {
      _message('Não há contas em aberto para este pedido.');
      await _load(silent: true);
      return;
    }
    final receipt = await showDialog<_ReceiptResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ReceiptDialog(delivery: delivery, receivables: receivables));
    if (receipt == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repository.receivePayment(
          orderId: delivery.orderId,
          receivableId: receipt.receivableId,
          amount: receipt.amount,
          receivedAt: receipt.receivedAt);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _message('Não foi possível registrar o recebimento: $error',
            error: true);
      }
      return;
    }
    if (!mounted) return;
    _message('Recebimento registrado no Financeiro.');
    await _load(silent: true);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _openWhatsApp(DeliveryModel delivery) async {
    final phone = delivery.contact.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) {
      _message('Informe o contato do cliente antes de abrir o WhatsApp.',
          error: true);
      return;
    }
    final countryPhone = phone.startsWith('55') ? phone : '55$phone';
    final text = Uri.encodeComponent(
      'Olá, ${delivery.customerName}! O pedido ${delivery.orderNumber} está pronto. '
      '${delivery.method == 'retirada_loja' ? 'Aguardamos sua retirada na loja.' : 'Vamos confirmar a entrega.'}',
    );
    final uri = Uri.parse('https://wa.me/$countryPhone?text=$text');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _message('Não foi possível abrir o WhatsApp neste dispositivo.',
          error: true);
    }
  }

  void _message(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : Colors.teal.shade700,
      ));

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().hasPermission('entregas')) {
      return const Center(child: Text('Sem permissão para entregas.'));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            )
          ]),
        ),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          const Icon(Icons.local_shipping_outlined,
              color: Color(0xFF0F62AC), size: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Entregas e Retiradas',
                    style:
                        TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                Text(
                    'Configure, lance para receber e conclua a entrega ou retirada.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar pedidos finalizados',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.sync),
          )
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          _metric('Pedidos prontos', _ready, Icons.inventory_2_outlined,
              Colors.blue),
          _metric('Atrasados', _late, Icons.schedule_outlined, Colors.red),
          _metric('Finalizadas no mês', _complete, Icons.check_circle_outline,
              Colors.green),
          _metric(
              'Pagamento pendente',
              _deliveries.where((item) => item.paymentPending > 0.009).length,
              Icons.payments_outlined,
              Colors.orange),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Wrap(spacing: 12, runSpacing: 8, children: [
          _filterButton('Pendentes', 'pendentes', Icons.pending_actions),
          _filterButton(
              'Finalizadas no mês', 'finalizados_mes', Icons.task_alt_outlined),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar pedido ou cliente',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('delivery-filter-$_filter'),
              initialValue: _filter,
              decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                const DropdownMenuItem(value: 'todos', child: Text('Todos')),
                const DropdownMenuItem(
                    value: 'pendentes', child: Text('Pendentes')),
                const DropdownMenuItem(
                    value: 'finalizados_mes',
                    child: Text('Finalizadas no mês')),
                const DropdownMenuItem(
                    value: 'atrasados', child: Text('Atrasados')),
                ...DeliveryModel.statuses.entries.map((entry) =>
                    DropdownMenuItem(
                        value: entry.key, child: Text(entry.value))),
              ],
              onChanged: (value) => setState(() => _filter = value ?? 'todos'),
            ),
          )
        ]),
      ),
      Expanded(
        child: _visible.isEmpty
            ? const Center(
                child: Text(
                    'Nenhum pedido finalizado encontrado para este filtro.'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: _visible.length,
                  itemBuilder: (_, index) => _card(_visible[index]),
                ),
              ),
      )
    ]);
  }

  Widget _metric(String label, int value, IconData icon, Color color) => Card(
        child: SizedBox(
          width: 172,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$value',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(label, style: const TextStyle(fontSize: 11)),
                    ]),
              )
            ]),
          ),
        ),
      );

  Widget _filterButton(String label, String value, IconData icon) => ChoiceChip(
      selected: _filter == value,
      showCheckmark: false,
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => _filter = value));

  Widget _card(DeliveryModel delivery) {
    final color = delivery.isLate
        ? Colors.red
        : delivery.status == 'concluido'
            ? Colors.green
            : Colors.blue;
    final canConclude =
        delivery.deliveryDataReady && delivery.hasFinancialEntry;
    final active = !const {'concluido', 'cancelado'}.contains(delivery.status);
    return Card(
        child: Column(children: [
      ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(
              delivery.method == 'retirada_loja'
                  ? Icons.storefront_outlined
                  : Icons.local_shipping_outlined,
              color: color),
        ),
        title: Text('${delivery.orderNumber} • ${delivery.customerName}'),
        subtitle: Text(
          '${delivery.methodLabel} • ${delivery.statusLabel}'
          '${delivery.scheduledAt == null ? '' : ' • ${_date.format(delivery.scheduledAt!)}'}\n'
          '${_paymentText(delivery)}',
        ),
        trailing: Wrap(spacing: 2, children: [
          IconButton(
              tooltip: 'Avisar no WhatsApp',
              onPressed: _saving ? null : () => _openWhatsApp(delivery),
              icon: const Icon(Icons.chat_outlined)),
          IconButton(
              tooltip: 'Imprimir pedido de entrega A5',
              onPressed: _saving ? null : () => _printDelivery(delivery),
              icon: const Icon(Icons.print_outlined)),
          IconButton(
              tooltip: 'Detalhes e hist?rico',
              onPressed: _saving ? null : () => _edit(delivery),
              icon: const Icon(Icons.edit_outlined))
        ]),
        onTap: _saving ? null : () => _edit(delivery),
      ),
      if (active || delivery.paymentPending > .009)
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                      onPressed:
                          _saving ? null : () => _printDelivery(delivery),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Imprimir A5')),
                  if (active && !delivery.hasFinancialEntry)
                    OutlinedButton.icon(
                        onPressed: _saving || !delivery.deliveryDataReady
                            ? null
                            : () => _launchReceivable(delivery),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Lan?ar para receber')),
                  if (delivery.paymentPending > .009 &&
                      context.read<AuthProvider>().hasPermission('financeiro'))
                    FilledButton.icon(
                        onPressed:
                            _saving ? null : () => _receivePayment(delivery),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Receber pagamento')),
                  if (active)
                    FilledButton.icon(
                        onPressed: _saving || !canConclude
                            ? null
                            : () => _conclude(delivery),
                        icon: const Icon(Icons.task_alt_outlined),
                        label: const Text('Concluir')),
                ]))
    ]));
  }

  String _paymentText(DeliveryModel delivery) {
    if (!delivery.hasFinancialEntry) {
      return delivery.deliveryDataReady
          ? 'Financeiro: lançar para receber'
          : 'Financeiro: configure os dados para lançar a receber';
    }
    if (delivery.isPaidInFull) {
      return 'Financeiro: pago total • ${_money.format(delivery.paymentTotal)}';
    }
    return 'Financeiro: a receber ${_money.format(delivery.paymentPending)} de ${_money.format(delivery.paymentTotal)}';
  }
}

class _ReceiptResult {
  const _ReceiptResult(this.receivableId, this.amount, this.receivedAt);
  final int receivableId;
  final double amount;
  final DateTime receivedAt;
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({required this.delivery, required this.receivables});
  final DeliveryModel delivery;
  final List<FinancialModel> receivables;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  late FinancialModel _selected = widget.receivables.first;
  late final TextEditingController _amount = TextEditingController(
      text: _selected.amount.toStringAsFixed(2).replaceAll('.', ','));
  DateTime _receivedAt = DateTime.now();
  String? _error;
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final input = _amount.text.trim().replaceAll(' ', '');
    final normalized = input.contains(',')
        ? input.replaceAll('.', '').replaceAll(',', '.')
        : input;
    final value = double.tryParse(normalized);
    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        (value * 100).round() > (_selected.amount * 100).round() ||
        (value * 100 - (value * 100).round()).abs() > .000001) {
      setState(() => _error =
          'Informe um valor maior que zero, com até dois centavos decimais e que não ultrapasse ${_money.format(_selected.amount)}.');
      return;
    }
    Navigator.pop(context, _ReceiptResult(_selected.id!, value, _receivedAt));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Receber pagamento'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${widget.delivery.orderNumber} • ${widget.delivery.customerName}'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _selected.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Conta a receber',
                        border: OutlineInputBorder()),
                    items: widget.receivables
                        .map((row) => DropdownMenuItem(
                            value: row.id,
                            child: Text(
                                '${row.description} • ${_money.format(row.amount)}',
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        _selected = widget.receivables
                            .firstWhere((row) => row.id == id);
                        _amount.text = _selected.amount
                            .toStringAsFixed(2)
                            .replaceAll('.', ',');
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Saldo desta conta: ${_money.format(_selected.amount)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: 'Valor recebido (R\$)',
                        border: const OutlineInputBorder(),
                        errorText: _error),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                        'Recebido em ${DateFormat('dd/MM/yyyy').format(_receivedAt)}'),
                    onPressed: () async {
                      final date = await showDatePicker(
                          context: context,
                          initialDate: _receivedAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100));
                      if (date != null && mounted)
                        setState(() => _receivedAt = date);
                    },
                  ),
                  Text(
                      'O recebimento será registrado no Financeiro e abatido desta conta.',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _submit, child: const Text('Confirmar recebimento')),
        ],
      );
}

class _DeliveryDialog extends StatefulWidget {
  const _DeliveryDialog({required this.delivery});
  final DeliveryModel delivery;

  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  late String _method = widget.delivery.method;
  late String _status = widget.delivery.status;
  late DateTime? _schedule = widget.delivery.scheduledAt;
  late final TextEditingController _responsible =
      TextEditingController(text: widget.delivery.responsible);
  late final TextEditingController _address =
      TextEditingController(text: widget.delivery.address);
  late final TextEditingController _reference =
      TextEditingController(text: widget.delivery.reference);
  late final TextEditingController _contact =
      TextEditingController(text: widget.delivery.contact);
  late final TextEditingController _fee = TextEditingController(
      text: widget.delivery.deliveryFee == 0
          ? ''
          : widget.delivery.deliveryFee.toStringAsFixed(2));
  late final TextEditingController _notes =
      TextEditingController(text: widget.delivery.notes);

  @override
  void dispose() {
    _responsible.dispose();
    _address.dispose();
    _reference.dispose();
    _contact.dispose();
    _fee.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseSchedule() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _schedule ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_schedule ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    setState(() => _schedule =
        DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  void _save() {
    final fee = double.tryParse(_fee.text.replaceAll(',', '.')) ?? 0;
    if (fee < 0) return;
    Navigator.of(context).pop(widget.delivery.copyWith(
      method: _method,
      status: _status,
      scheduledAt: _schedule,
      responsible: _responsible.text.trim(),
      address: _address.text.trim(),
      reference: _reference.text.trim(),
      contact: _contact.text.trim(),
      deliveryFee: fee,
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            '${widget.delivery.orderNumber} — ${widget.delivery.customerName}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: _select('Modalidade', _method, DeliveryModel.methods,
                        (value) => setState(() => _method = value))),
                const SizedBox(width: 12),
                Expanded(
                    child: _select('Status', _status, _statusOptions,
                        (value) => setState(() => _status = value))),
              ]),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(_schedule == null
                    ? 'Definir agendamento'
                    : DateFormat('dd/MM/yyyy HH:mm').format(_schedule!)),
                trailing: TextButton(
                    onPressed: _chooseSchedule, child: const Text('Alterar')),
              ),
              _field(_responsible, 'Responsável pela liberação ou entrega'),
              _field(_contact, 'Contato do cliente',
                  keyboard: TextInputType.phone),
              _field(_address, 'Endereço de entrega'),
              _field(_reference, 'Referência do local'),
              if (_method == 'entrega_loja')
                _field(_fee, 'Taxa de entrega da loja',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true)),
              _field(_notes, 'Observações', maxLines: 3),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Financeiro: ${_financeText}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (widget.delivery.status != 'concluido')
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            'Salve os dados. Em seguida, use “Lançar para receber” e “Concluir” na ficha do pedido.',
                            style: TextStyle(fontSize: 12)))),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Histórico',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              ...widget.delivery.history.reversed.map((entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        DeliveryModel.statuses[entry.status] ?? entry.status),
                    subtitle: Text(
                        '${DateFormat('dd/MM/yyyy HH:mm').format(entry.at)} • ${entry.responsible}${entry.note.isEmpty ? '' : '\n${entry.note}'}'),
                  )),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
        ],
      );

  Map<String, String> get _statusOptions {
    final options = Map<String, String>.from(DeliveryModel.statuses);
    if (widget.delivery.status != 'concluido') options.remove('concluido');
    return options;
  }

  String get _financeText {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    if (!widget.delivery.hasFinancialEntry) return 'ainda não lançado';
    if (widget.delivery.isPaidInFull) {
      return 'pago total • ${money.format(widget.delivery.paymentTotal)}';
    }
    return 'a receber ${money.format(widget.delivery.paymentPending)} de ${money.format(widget.delivery.paymentTotal)}';
  }

  Widget _select(String label, String value, Map<String, String> options,
          ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: options.entries
            .map((entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)))
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      );

  Widget _field(TextEditingController controller, String label,
          {TextInputType? keyboard, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
