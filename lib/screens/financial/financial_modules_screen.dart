import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/background_refresh_mixin.dart';
import '../../models/erp_module_record.dart';
import '../../models/financial_model.dart';
import '../../models/order_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/finance_calculations.dart';
import '../../services/finance_report_service.dart';
import '../../services/finance_workspace_service.dart';
import '../../services/order_repository.dart';
import '../../widgets/horizontal_wheel_scroll.dart';
import 'finance_form_dialog.dart';
import 'finance_table.dart';
import 'financial_screen.dart';

part 'finance_module_views.dart';
part 'finance_module_actions.dart';

class FinancialModulesScreen extends StatefulWidget {
  const FinancialModulesScreen({super.key});
  @override
  State<FinancialModulesScreen> createState() => _FinancialModulesScreenState();
}

class _FinanceModule {
  const _FinanceModule(this.title, this.description, this.icon);
  final String title, description;
  final IconData icon;
}

const _modules = [
  _FinanceModule(
      'Dashboard Financeiro', 'Indicadores, saldo e alertas', Icons.insights),
  _FinanceModule(
      'Contas a Receber', 'Clientes, parcelas e baixas', Icons.south_west),
  _FinanceModule('Contas a Pagar', 'Fornecedores, despesas e vencimentos',
      Icons.north_east),
  _FinanceModule(
      'Fluxo de Caixa', 'Entradas, saídas e projeções', Icons.waterfall_chart),
  _FinanceModule('Bancos e Contas', 'Contas, caixas e transferências',
      Icons.account_balance),
  _FinanceModule('Conciliação Bancária', 'Importação OFX e conferência',
      Icons.compare_arrows),
  _FinanceModule('Controle de Despesas', 'Despesas recorrentes e categorias',
      Icons.receipt_long),
  _FinanceModule('DRE e Lucratividade',
      'Receitas, despesas e resultado gerencial', Icons.query_stats),
  _FinanceModule('Cartões e Parcelamentos', 'Taxas, recebíveis e antecipações',
      Icons.credit_card),
  _FinanceModule('Cobranças e Inadimplência', 'Lembretes, acordos e histórico',
      Icons.notifications_active),
  _FinanceModule('Comissões', 'Regras, apuração e pagamentos', Icons.percent),
  _FinanceModule(
      'Centro de Custos', 'Resultados por setor e unidade', Icons.account_tree),
  _FinanceModule('Financeiro por Pedido', 'Custos, pagamentos e margens',
      Icons.inventory_2),
  _FinanceModule('Relatórios Financeiros',
      'Filtros e exportação PDF, CSV e Excel', Icons.summarize),
  _FinanceModule('Configurações e Auditoria',
      'Categorias, regras, logs e fechamento', Icons.admin_panel_settings),
];

class _FinancialModulesScreenState extends State<FinancialModulesScreen>
    with BackgroundRefreshMixin<FinancialModulesScreen> {
  final _service = FinanceWorkspaceService();
  final _search = TextEditingController();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _date = DateFormat('dd/MM/yyyy');
  List<FinancialModel> _rows = [];
  List<OrderModel> _orders = [];
  List<ErpModuleRecord> _records = [];
  int _selected = 0;
  bool _loading = true, _busy = false;
  String? _error;
  String _status = 'todos';
  DateTimeRange? _range = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month),
    end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
  );
  String _reportType = 'lancamentos';

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

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        _service.financial.getAll(includeCancelled: true),
        _service.load(),
        OrderRepository().getAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<FinancialModel>;
        _records = results[1] as List<ErpModuleRecord>;
        _orders = results[2] as List<OrderModel>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar o financeiro: $error';
      });
    }
  }

  bool _inRange(DateTime date, DateTimeRange? range) {
    if (range == null) return true;
    final day = DateTime(date.year, date.month, date.day);
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool _inPeriod(DateTime date) => _inRange(date, _range);

  bool _matches(String value) =>
      value.toLowerCase().contains(_search.text.trim().toLowerCase());
  List<FinancialModel> get _periodRows => _rows
      .where((t) =>
          t.status != 'cancelado' &&
          _inPeriod(t.dueDate) &&
          _matches('${t.description} ${t.customerName ?? ''} ${t.categoria}') &&
          (_status == 'todos' ||
              (_status == 'pago' && t.isPaid) ||
              (_status == 'pendente' && !t.isPaid) ||
              (_status == 'vencido' && t.isOverdue)))
      .toList();

  List<FinancialModel> get _salesRows => _rows
      .where((t) =>
          t.type == 'receber' &&
          t.status != 'cancelado' &&
          _matches('${t.description} ${t.customerName ?? ''} ${t.categoria}'))
      .toList();

  double _salesFor(DateTimeRange range) => _salesRows
      .where((t) => _inRange(t.createdAt, range))
      .fold<double>(0, (total, t) => total + t.amount);

  DateTimeRange _dayRange(DateTime day) => DateTimeRange(
      start: DateTime(day.year, day.month, day.day),
      end: DateTime(day.year, day.month, day.day));

  DateTimeRange _monthRange(DateTime day) => DateTimeRange(
      start: DateTime(day.year, day.month),
      end: DateTime(day.year, day.month + 1, 0));

  DateTimeRange _yearRange(DateTime day) =>
      DateTimeRange(start: DateTime(day.year), end: DateTime(day.year, 12, 31));

  void _setPeriod(DateTimeRange range) => setState(() => _range = range);

  void _updateFinanceView(VoidCallback update) {
    if (mounted) setState(update);
  }

  bool _isSelectedRange(DateTimeRange candidate) =>
      _range?.start == candidate.start && _range?.end == candidate.end;
  List<ErpModuleRecord> _type(String type, {bool activeOnly = false}) =>
      _records
          .where((r) =>
              r.recordType == type && (!activeOnly || r.status == 'ativo'))
          .toList();
  List<ErpModuleRecord> _searchType(String type) => _type(type)
      .where((r) => _matches('${r.title} ${r.payload.values.join(' ')}'))
      .toList();
  ErpModuleRecord? _meta(int? id) => _type('transaction_meta')
      .where((r) => r.payload['financialId'] == id)
      .firstOrNull;
  String _recordName(int? id, [String fallback = 'Não vinculado']) =>
      _records.where((r) => r.id == id).firstOrNull?.title ?? fallback;
  String _displayDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—' : _date.format(date);
  }

  String get _periodLabel => _range == null
      ? 'Todo o histórico'
      : '${_date.format(_range!.start)} a ${_date.format(_range!.end)}';
  Map<String, String> _options(String type) => {
        for (final r in _type(type, activeOnly: true)) '${r.id}': r.title,
      };
  Map<String, String> get _categories => {
        'vendas': 'Vendas',
        'materiais': 'Materiais',
        'operacional': 'Operacional',
        'terceirizacao': 'Terceirização',
        'pessoal': 'Pessoal',
        'marketing': 'Marketing',
        'entrega': 'Entrega',
        'outros': 'Outros',
        for (final r in _type('category', activeOnly: true)) r.title: r.title,
      };
  double _number(dynamic value) => (value as num? ?? 0).toDouble();

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = context.read<AuthProvider>().currentUser;
      _service.actor = user?.fullName ?? 'Usuário';
      _service.actorId = user?.id;
      await action();
      if (!mounted) return;
      await _load(silent: true);
      if (success != null && mounted) _message(success);
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : Colors.teal.shade700));

  Future<Map<String, dynamic>?> _form(String title, List<FinanceField> fields,
          {Map<String, dynamic> initial = const {}, String? description}) =>
      showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FinanceFormDialog(
              title: title,
              fields: fields,
              initial: initial,
              description: description));

  Widget _button(String text, IconData icon, VoidCallback action) =>
      FilledButton.icon(
          onPressed: _busy ? null : action,
          icon: Icon(icon, size: 18),
          label: Text(text));
  Widget _section(String title,
          {String? description,
          List<Widget> actions = const [],
          required List<Widget> children}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (description != null)
                  SizedBox(
                      width: 520,
                      child: Text(description,
                          style: Theme.of(context).textTheme.bodySmall)),
              ]),
              ...actions
            ]),
        const SizedBox(height: 16),
        ...children
      ]);

  Widget _metric(String label, double value, IconData icon, Color color) =>
      SizedBox(
          width: 205,
          child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label))
                        ]),
                        const SizedBox(height: 12),
                        Text(_money.format(value),
                            style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                color: color))
                      ]))));

  Widget _tag(String text, [Color color = Colors.blue]) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)));
  DataCell _cell(String text) => DataCell(ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis)));
  DataCell _actions(List<Widget> actions) =>
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: actions));
  Widget _icon(String tooltip, IconData icon, VoidCallback action) =>
      IconButton(
          tooltip: tooltip,
          onPressed: _busy ? null : action,
          icon: Icon(icon, size: 19));

  Future<void> _pickPeriod() async {
    final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _range);
    if (range != null && mounted) setState(() => _range = range);
  }

  Widget _filters() => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 285,
                    child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Buscar no módulo',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true))),
                OutlinedButton.icon(
                    onPressed: _pickPeriod,
                    icon: const Icon(Icons.date_range),
                    label: Text(_periodLabel)),
                Wrap(spacing: 4, children: [
                  ChoiceChip(
                      label: const Text('Hoje'),
                      selected: _isSelectedRange(_dayRange(DateTime.now())),
                      onSelected: (_) => _setPeriod(_dayRange(DateTime.now()))),
                  ChoiceChip(
                      label: const Text('Mês'),
                      selected: _isSelectedRange(_monthRange(DateTime.now())),
                      onSelected: (_) =>
                          _setPeriod(_monthRange(DateTime.now()))),
                  ChoiceChip(
                      label: const Text('Ano'),
                      selected: _isSelectedRange(_yearRange(DateTime.now())),
                      onSelected: (_) =>
                          _setPeriod(_yearRange(DateTime.now()))),
                ]),
                TextButton(
                    onPressed: () => setState(() => _range = null),
                    child: const Text('Todo o histórico')),
                SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                            labelText: 'Lançamentos',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: const [
                          DropdownMenuItem(
                              value: 'todos', child: Text('Todos')),
                          DropdownMenuItem(
                              value: 'pendente', child: Text('Em aberto')),
                          DropdownMenuItem(value: 'pago', child: Text('Pagos')),
                          DropdownMenuItem(
                              value: 'vencido', child: Text('Vencidos'))
                        ],
                        onChanged: (value) =>
                            setState(() => _status = value ?? 'todos'))),
              ])));

  Widget _topModuleMenu() => Container(
      decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: .45),
          border: Border(
              bottom: BorderSide(
                  color:
                      Theme.of(context).dividerColor.withValues(alpha: .5)))),
      child: HorizontalWheelScroll(
          builder: (context, controller) => ListView.separated(
              controller: controller,
              key: const PageStorageKey('finance-module-menu'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: _modules.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ChoiceChip(
                  selected: _selected == i,
                  showCheckmark: false,
                  avatar: Icon(_modules[i].icon, size: 17),
                  label: Text(
                      '${(i + 1).toString().padLeft(2, '0')}  ${_modules[i].title}'),
                  onSelected: (_) => setState(() => _selected = i)))));

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF112E4A), Color(0xFF166D91)])),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet,
                  color: Colors.white, size: 30),
              const SizedBox(width: 14),
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Financeiro',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.bold)),
                    Text('15 módulos integrados ao ERP',
                        style: TextStyle(color: Colors.white70))
                  ])),
              IconButton(
                  tooltip: 'Atualizar dados',
                  onPressed: _busy ? null : () => _load(),
                  icon: const Icon(Icons.refresh, color: Colors.white)),
              PopupMenuButton<String>(
                  tooltip: 'Mais opções',
                  iconColor: Colors.white,
                  onSelected: (_) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              const Scaffold(body: FinancialScreen()))),
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'legacy',
                            child: Text('Resumo e lançamentos tradicionais'))
                      ]),
            ])),
        if (_busy) const LinearProgressIndicator(minHeight: 3),
        SizedBox(height: 54, child: _topModuleMenu()),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    key: const PageStorageKey('financial-modules-scroll'),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null)
                            Card(
                                color: Colors.red.shade50,
                                child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Colors.red.shade800)))),
                          _filters(),
                          const SizedBox(height: 18),
                          _moduleBody(),
                        ]))),
      ]);
}
