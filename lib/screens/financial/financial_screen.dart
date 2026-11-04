import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import '../../models/financial_model.dart';
import '../../services/financial_repository.dart';
import '../../constants/financial_categories.dart';
import '../../models/order_model.dart';
import '../../models/financial_summary.dart';
import '../../services/order_repository.dart';
import 'financial_overview.dart';

class FinancialScreen extends StatefulWidget {
  const FinancialScreen({super.key});

  @override
  State<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends State<FinancialScreen>
    with BackgroundRefreshMixin<FinancialScreen> {
  final FinancialRepository _repository = FinancialRepository();

  List<FinancialModel> _transactions = [];
  List<FinancialModel> _filteredTransactions = [];
  bool _isLoading = true;

  String _filterType = 'todos';
  String _filterStatus = 'todos';
  String _filterCategoria = 'todas';

  List<OrderModel> _orders = [];
  String _period = 'este_mes', _search = '';
  String? _loadError;
  int? _customerId;
  DateTime? _rangeStart = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _rangeEnd =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  Future<void> refreshInBackground() => _loadTransactions();

  @override
  Duration get backgroundRefreshInterval => const Duration(seconds: 30);

  Future<void> _loadTransactions() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final transactions = await _repository.getAll(includeCancelled: true);
      final orders = await OrderRepository().getAll();
      if (!mounted) return;
      setState(() {
        _transactions = transactions;
        _orders = orders;
        if (_customerId != null &&
            !orders.any((o) => o.clienteId == _customerId)) {
          _customerId = null;
        }
        if (_filterCategoria != 'todas' &&
            !transactions.any((t) => t.categoria == _filterCategoria)) {
          _filterCategoria = 'todas';
        }
        _loadError = null;
        _isLoading = false;
      });
      _filterTransactions();
    } catch (e) {
      if (!mounted) return;
      _loadError =
          'Não foi possível carregar os dados. Toque em Atualizar para tentar novamente.';
      setState(() => _isLoading = false);
      print('Erro ao carregar transações: $e');
    }
  }

  void _filterTransactions() {
    setState(() {
      _filteredTransactions = _periodTransactions.where((t) {
        final query = _search.trim().toLowerCase();
        if (query.isNotEmpty &&
            !('${t.description} ${t.customerName ?? ''} ${t.notes ?? ''}')
                .toLowerCase()
                .contains(query)) {
          return false;
        }
        if (_filterStatus == 'cancelado') {
          if (t.status != 'cancelado') return false;
        } else if (t.status == 'cancelado') return false;
        if (_filterType != 'todos' && t.type != _filterType) return false;
        if (_filterStatus != 'todos') {
          if (_filterStatus == 'pendente' && t.isPaid) return false;
          if (_filterStatus == 'pago' && !t.isPaid) return false;
          if (_filterStatus == 'vencido' &&
              !(!t.isPaid &&
                  DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day)
                      .isBefore(DateTime(DateTime.now().year,
                          DateTime.now().month, DateTime.now().day)))) {
            return false;
          }
        }
        if (_filterCategoria != 'todas' && t.categoria != _filterCategoria) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  void _showAddTransactionDialog() {
    final formKey = GlobalKey<FormState>();
    final valueController = TextEditingController();
    final descriptionController = TextEditingController();
    final documentController = TextEditingController();
    final customerNameController = TextEditingController();
    final valorBrutoController = TextEditingController();
    final taxaController = TextEditingController();
    var selectedType = 'receber';
    var selectedCategoria = 'vendas';
    var selectedFormaPagamento = 'PIX';
    var selectedDate = DateTime.now();
    bool isPaid = false;

    final List<String> formasPagamento = [
      'PIX',
      'Dinheiro',
      'Débito',
      'Crédito',
      'Boleto',
      'Transferência',
      'Outro',
    ];

    void calcularLiquido() {
      final bruto = double.tryParse(valorBrutoController.text) ?? 0;
      final taxa = double.tryParse(taxaController.text) ?? 0;
      if (bruto > 0 && taxa > 0) {
        final liquido = bruto - (bruto * taxa / 100);
        valueController.text = liquido.toStringAsFixed(2);
      }
    }

    showDialog(
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
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Nova Transação',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo *',
                      prefixIcon: Icon(Icons.swap_horiz),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'receber',
                        child: Row(children: [
                          Icon(Icons.arrow_downward, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Contas a Receber'),
                        ]),
                      ),
                      DropdownMenuItem(
                        value: 'pagar',
                        child: Row(children: [
                          Icon(Icons.arrow_upward, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Contas a Pagar'),
                        ]),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedType = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoria *',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                    items: FinancialCategories.getCategorias().map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Icon(
                              FinancialCategories.getIcon(cat),
                              color: FinancialCategories.getColor(cat),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(FinancialCategories.getLabel(cat)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => selectedCategoria = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição *',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: customerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Cliente (opcional)',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedFormaPagamento,
                    decoration: const InputDecoration(
                      labelText: 'Forma de Pagamento',
                      prefixIcon: Icon(Icons.payment),
                      border: OutlineInputBorder(),
                    ),
                    items: formasPagamento.map((f) {
                      return DropdownMenuItem(
                        value: f,
                        child: Text(f),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => selectedFormaPagamento = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: valorBrutoController,
                          decoration: const InputDecoration(
                            labelText: 'Valor Bruto',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => calcularLiquido(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: taxaController,
                          decoration: const InputDecoration(
                            labelText: 'Taxa (%)',
                            prefixIcon: Icon(Icons.percent),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => calcularLiquido(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: valueController,
                    decoration: const InputDecoration(
                      labelText: 'Valor Líquido *',
                      prefixIcon: Icon(Icons.monetization_on),
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data de Vencimento'),
                    subtitle:
                        Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (date != null) {
                        setState(() => selectedDate = date);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: documentController,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      prefixIcon: Icon(Icons.note),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: isPaid,
                        onChanged: (v) => setState(() => isPaid = v!),
                        activeColor: const Color(0xFF0F62AC),
                      ),
                      const Text(
                        'Marcar como pago',
                        style: TextStyle(fontSize: 12),
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
                final financial = FinancialModel(
                  description: descriptionController.text.trim(),
                  amount: double.parse(valueController.text),
                  type: selectedType,
                  dueDate: selectedDate,
                  isPaid: isPaid,
                  notes: documentController.text.trim(),
                  customerName: customerNameController.text.trim(),
                  categoria: selectedCategoria,
                  formaPagamento: selectedFormaPagamento,
                  valorBruto: double.tryParse(valorBrutoController.text) ?? 0,
                  taxa: double.tryParse(taxaController.text) ?? 0,
                  valorLiquido: double.tryParse(valueController.text) ?? 0,
                  status: isPaid ? 'pago' : 'pendente',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await _repository.create(financial);
                Navigator.pop(context);
                _loadTransactions();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transação adicionada com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F62AC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPartialPaymentDialog(FinancialModel transaction) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: transaction.amount.toString(),
    );
    final dateController = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
    );
    DateTime paymentDate = DateTime.now();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Registrar Pagamento Parcial'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Transação: ${transaction.description}'),
              const SizedBox(height: 8),
              Text(
                  'Valor original: R\$ ${transaction.amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Valor a pagar',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final val = double.tryParse(v ?? '0');
                  if (val == null || val <= 0) return 'Valor inválido';
                  if (val > transaction.amount) {
                    return 'Valor maior que o devido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: paymentDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    paymentDate = date;
                    dateController.text = DateFormat('dd/MM/yyyy').format(date);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data do pagamento',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(dateController.text),
                ),
              ),
            ],
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
                final valorPago = double.parse(amountController.text);

                await _repository.registrarPagamentoParcial(
                  transaction.id!,
                  valorPago,
                  paymentDate,
                );

                Navigator.pop(context);
                _loadTransactions();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pagamento parcial registrado!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Registrar Pagamento'),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsPaid(FinancialModel transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Pagamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja marcar como pago:'),
            const SizedBox(height: 8),
            Text(transaction.description),
            Text('R\$ ${transaction.amount.toStringAsFixed(2)}'),
            Text(DateFormat('dd/MM/yyyy').format(transaction.dueDate)),
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repository.markAsPaid(transaction.id!);
      _loadTransactions();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamento registrado!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteTransaction(FinancialModel transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir transação "${transaction.description}"?'),
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
      await _repository.delete(transaction.id!);
      _loadTransactions();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transação excluída!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<FinancialModel> get _periodTransactions => _transactions
      .where((t) =>
          inFinancialPeriod(t.dueDate, _rangeStart, _rangeEnd) &&
          (_customerId == null || t.customerId == _customerId))
      .toList();

  List<OrderModel> get _periodOrders => _orders
      .where((o) =>
          o.isAcceptedSale &&
          (_customerId == null || o.clienteId == _customerId) &&
          DateTime.tryParse(o.dataCriacao) != null &&
          inFinancialPeriod(
              DateTime.parse(o.dataCriacao), _rangeStart, _rangeEnd))
      .toList();

  Future<void> _selectPeriod(String value) async {
    final now = DateTime.now(),
        today = DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime? start, end;
    if (value == 'personalizado') {
      final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100, 12, 31),
          initialDateRange: DateTimeRange(
              start: _rangeStart ?? today, end: _rangeEnd ?? today),
          helpText: 'Selecione o período',
          saveText: 'Aplicar');
      if (picked == null || !mounted) return;
      start = picked.start;
      end = picked.end;
    } else if (value == 'hoje') {
      start = today;
      end = today;
    } else if (value == '7_dias') {
      start = today.subtract(const Duration(days: 6));
      end = today;
    } else if (value == '30_dias') {
      start = today.subtract(const Duration(days: 29));
      end = today;
    } else if (value == 'mes_anterior') {
      start = DateTime(now.year, now.month - 1);
      end = DateTime(now.year, now.month, 0);
    } else if (value == 'este_mes') {
      start = DateTime(now.year, now.month);
      end = DateTime(now.year, now.month + 1, 0);
    }
    setState(() {
      _period = value;
      _rangeStart = start;
      _rangeEnd = end;
    });
    _filterTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$'),
        date = DateFormat('dd/MM/yyyy');
    final customerNames = <int, String>{};
    for (final o in _orders) {
      if (o.clienteId != null) {
        customerNames[o.clienteId!] = o.clienteNome ?? 'Cliente';
      }
    }
    final customers = customerNames.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Scaffold(
      appBar: AppBar(
          title: const Text('Financeiro'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _isLoading ? null : _loadTransactions,
                icon: const Icon(Icons.refresh)),
          ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadError != null)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(_loadError!))),
                    Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(_period),
                                initialValue: _period,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Período',
                                    border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'este_mes',
                                      child: Text('Este mês')),
                                  DropdownMenuItem(
                                      value: 'mes_anterior',
                                      child: Text('Mês anterior')),
                                  DropdownMenuItem(
                                      value: 'hoje', child: Text('Hoje')),
                                  DropdownMenuItem(
                                      value: '7_dias',
                                      child: Text('Últimos 7 dias')),
                                  DropdownMenuItem(
                                      value: '30_dias',
                                      child: Text('Últimos 30 dias')),
                                  DropdownMenuItem(
                                      value: 'personalizado',
                                      child: Text('Escolher datas')),
                                  DropdownMenuItem(
                                      value: 'todos',
                                      child: Text('Todo o histórico')),
                                ],
                                onChanged: (v) {
                                  if (v != null) _selectPeriod(v);
                                },
                              )),
                          SizedBox(
                              width: 260,
                              child: DropdownButtonFormField<int>(
                                key: ValueKey(_customerId),
                                initialValue: _customerId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Cliente',
                                    border: OutlineInputBorder()),
                                items: [
                                  const DropdownMenuItem<int>(
                                      value: null,
                                      child: Text('Todos os clientes')),
                                  ...customers.map((c) => DropdownMenuItem(
                                      value: c.key,
                                      child: Text(c.value,
                                          overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (v) {
                                  setState(() => _customerId = v);
                                  _filterTransactions();
                                },
                              )),
                          OutlinedButton.icon(
                              onPressed: () => _selectPeriod('personalizado'),
                              icon: const Icon(Icons.date_range),
                              label: const Text('Datas')),
                          FilledButton.icon(
                              onPressed: _showAddTransactionDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Novo lançamento')),
                        ]),
                    const SizedBox(height: 10),
                    Text(_rangeStart == null
                        ? 'Todo o histórico'
                        : '${date.format(_rangeStart!)} a ${date.format(_rangeEnd!)}'),
                    const SizedBox(height: 16),
                    FinancialOverview(
                        summary: FinancialSummary(
                            _periodTransactions, _periodOrders)),
                    const SizedBox(height: 20),
                    Text('Lançamentos do período',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                        'O resumo acima segue período e cliente. Os filtros abaixo refinam somente a lista de lançamentos.'),
                    const SizedBox(height: 12),
                    TextField(
                        decoration: const InputDecoration(
                            labelText: 'Buscar descrição, cliente ou documento',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder()),
                        onChanged: (v) {
                          _search = v;
                          _filterTransactions();
                        }),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final type in const {
                        'todos': 'Todas as contas',
                        'receber': 'A receber',
                        'pagar': 'A pagar'
                      }.entries)
                        ChoiceChip(
                            label: Text(type.value),
                            selected: _filterType == type.key,
                            onSelected: (_) {
                              _filterType = type.key;
                              _filterTransactions();
                            }),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final status in const {
                        'todos': 'Todos os status',
                        'pendente': 'Em aberto',
                        'pago': 'Quitados',
                        'vencido': 'Vencidos',
                        'cancelado': 'Cancelados / histórico'
                      }.entries)
                        ChoiceChip(
                            label: Text(status.value),
                            selected: _filterStatus == status.key,
                            onSelected: (_) {
                              _filterStatus = status.key;
                              _filterTransactions();
                            }),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        key: ValueKey(_filterCategoria),
                        initialValue: _filterCategoria,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Categoria',
                            border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(
                              value: 'todas',
                              child: Text('Todas as categorias')),
                          ..._transactions.map((t) => t.categoria).toSet().map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                        ],
                        onChanged: (v) {
                          _filterCategoria = v ?? 'todas';
                          _filterTransactions();
                        }),
                    const SizedBox(height: 12),
                    Text('${_filteredTransactions.length} lançamentos encontrados'),
                    if (_filteredTransactions.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Nenhum lançamento para os filtros selecionados.'))
                    else
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: PaginatedDataTable(
                            key: ValueKey(
                                '$_period:$_rangeStart:$_rangeEnd:$_customerId:$_filterType:$_filterStatus:$_filterCategoria:$_search'),
                            rowsPerPage: _filteredTransactions.length < 10
                                ? _filteredTransactions.length
                                : 10,
                            showFirstLastButtons: true,
                            columns: const [
                              DataColumn(label: Text('Vencimento')),
                              DataColumn(label: Text('Descrição / cliente')),
                              DataColumn(label: Text('Tipo')),
                              DataColumn(label: Text('Categoria')),
                              DataColumn(label: Text('Valor')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Ações')),
                            ],
                            source: _FinancialLedgerSource(
                                _filteredTransactions,
                                (t) => DataRow(cells: [
                                      DataCell(Text(date.format(t.dueDate))),
                                      DataCell(SizedBox(
                                          width: 220,
                                          child: Text('${t.description}\n${t.customerName ?? ''}'))),
                                      DataCell(Text(t.type == 'receber'
                                          ? 'Receber'
                                          : 'Pagar')),
                                      DataCell(Text(t.categoria)),
                                      DataCell(Text(money.format(t.amount))),
                                      DataCell(Text(t.statusLabel,
                                          style:
                                              TextStyle(color: t.statusColor))),
                                      DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (t.status != 'cancelado' &&
                                                !t.isPaid &&
                                                t.type == 'receber')
                                              IconButton(
                                                  tooltip: 'Pagamento parcial',
                                                  onPressed: () =>
                                                      _showPartialPaymentDialog(
                                                          t),
                                                  icon: const Icon(
                                                      Icons.payments_outlined)),
                                            if (t.status != 'cancelado' &&
                                                !t.isPaid)
                                              IconButton(
                                                  tooltip: 'Marcar como pago',
                                                  onPressed: () =>
                                                      _markAsPaid(t),
                                                  icon: const Icon(Icons
                                                      .check_circle_outline)),
                                            IconButton(
                                                tooltip: 'Excluir lançamento',
                                                onPressed: () =>
                                                    _deleteTransaction(t),
                                                icon: const Icon(
                                                    Icons.delete_outline)),
                                          ])),
                                    ])),
                          )),
                    const SizedBox(height: 24),
                  ])),
    );
  }
}

class _FinancialLedgerSource extends DataTableSource {
  _FinancialLedgerSource(this.rows, this.build);
  final List<FinancialModel> rows;
  final DataRow Function(FinancialModel) build;
  @override
  DataRow? getRow(int i) => i < rows.length ? build(rows[i]) : null;
  @override
  int get rowCount => rows.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}
