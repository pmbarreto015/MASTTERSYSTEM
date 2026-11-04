import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../core/background_refresh_mixin.dart';
import '../../models/employee_model.dart';
import '../../models/erp_module_record.dart';
import '../../models/holerite_model.dart';
import '../../models/hr_module.dart';
import '../../providers/auth_provider.dart';
import '../../services/employee_repository.dart';
import '../../services/folha_pagamento_service.dart';
import '../../services/holerite_repository.dart';
import '../../services/hr_management_service.dart';
import '../../widgets/horizontal_wheel_scroll.dart';
import '../quote/preview_pdf_screen.dart';
import 'employee_ponto_report.dart';

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});

  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrFilter {
  String query = '';
  String status = 'Todos';
  int? employeeId;
  DateTimeRange? period;
}

class _HrScreenState extends State<HrScreen>
    with BackgroundRefreshMixin<HrScreen> {
  final _service = HrManagementService();
  final _employeeRepository = EmployeeRepository();
  final _holeriteRepository = HoleriteRepository();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _date = DateFormat('dd/MM/yyyy');
  final _filters = <String, _HrFilter>{};
  final _visited = <String>{'dashboard'};
  List<ErpModuleRecord> _records = [];
  List<EmployeeModel> _employees = [];
  String _section = 'dashboard';
  String? _error;
  bool _loading = true;
  bool _working = false;
  int? _portalEmployeeId;
  String _portalCompetence = DateFormat('yyyy-MM').format(DateTime.now());
  HoleriteModel? _portalHolerite;
  int _portalRequest = 0;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _canAccess =>
      context.read<AuthProvider>().hasPermission('funcionarios');
  bool get _canFinance =>
      context.read<AuthProvider>().hasPermission('financeiro');
  String get _actor =>
      context.read<AuthProvider>().currentUser?.fullName ?? 'RH';

  EmployeeModel? get _portalOwnEmployee {
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin) return null;
    final email = auth.currentUser?.email.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;
    for (final employee in _employees) {
      if (employee.email.trim().toLowerCase() == email) return employee;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _canAccess) _load();
    });
  }

  @override
  Future<void> refreshInBackground() async {
    if (_canAccess) await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final employees = await _employeeRepository.getAll();
      final records = await _service.list();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _records = records;
        _loading = false;
        _error = null;
        final own = _portalOwnEmployee;
        if (own != null) {
          _portalEmployeeId = own.id;
          _filters.putIfAbsent('portal', _HrFilter.new).employeeId = own.id;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível atualizar o RH. $error';
      });
    }
  }

  void _navigate(String key) => setState(() {
        _section = key;
        _visited.add(key);
      });

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : Colors.teal.shade700,
    ));
  }

  EmployeeModel? _employee(dynamic id) {
    for (final employee in _employees) {
      if (employee.id == id) return employee;
    }
    return null;
  }

  bool _isDone(ErpModuleRecord r) => const [
        'Concluído',
        'Atendido',
        'Cancelado',
        'Recusado',
        'Reprovado',
        'Inativo',
        'Arquivado'
      ].contains(r.status);

  DateTime? _recordDate(ErpModuleRecord r) {
    for (final key in [
      'start_date',
      'event_date',
      'evaluation_date',
      'request_date',
      'document_date',
      'termination_date',
      'due_date',
      'interview_date'
    ]) {
      final date = DateTime.tryParse('${r.payload[key]}');
      if (date != null) return date;
    }
    return r.createdAt;
  }

  List<ErpModuleRecord> _filtered(HrModule module) {
    final filter = _filters.putIfAbsent(module.key, _HrFilter.new);
    final query = filter.query.trim().toLowerCase();
    return _records.where((r) {
      if (r.recordType != module.key) return false;
      if (module.key == 'portal' &&
          _portalOwnEmployee != null &&
          r.payload['employee_id'] != _portalOwnEmployee!.id) return false;
      if (filter.status != 'Todos' && r.status != filter.status) return false;
      if (filter.employeeId != null &&
          r.payload['employee_id'] != filter.employeeId) return false;
      final date = _recordDate(r);
      if (filter.period != null &&
          (date == null ||
              date.isBefore(filter.period!.start) ||
              date.isAfter(filter.period!.end
                  .add(const Duration(days: 1))
                  .subtract(const Duration(microseconds: 1))))) return false;
      return query.isEmpty ||
          '${r.title} ${r.status} ${_employee(r.payload['employee_id'])?.name ?? ''} ${r.payload['department'] ?? ''}'
              .toLowerCase()
              .contains(query);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.hasPermission('funcionarios')) {
      return const Center(
          child: Text('Seu usuário não possui permissão para acessar o RH.'));
    }
    final current = HrModule.byKey(_section);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14)),
                child:
                    const Icon(Icons.people_alt_outlined, color: Colors.teal)),
            const SizedBox(width: 12),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('RH e Departamento Pessoal',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                  Text('Pessoas, rotinas e histórico em um só lugar',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
            IconButton(
                tooltip: 'Atualizar dados',
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.refresh)),
          ])),
      SizedBox(height: 54, child: _topModuleMenu()),
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text(current.description,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)))),
      if (_error != null)
        MaterialBanner(content: Text(_error!), actions: [
          TextButton(
              onPressed: () => _load(), child: const Text('Tentar novamente'))
        ]),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
          child: IndexedStack(
        index: HrModule.modules.indexOf(current),
        children: [
          for (final module in HrModule.modules)
            _visited.contains(module.key)
                ? TickerMode(
                    enabled: _section == module.key,
                    child: ExcludeFocus(
                        excluding: _section != module.key,
                        child: _moduleBody(module)))
                : const SizedBox.shrink(),
        ],
      )),
    ]);
  }

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
              key: const PageStorageKey('rh-module-menu'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: HrModule.modules.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final module = HrModule.modules[index];
                return ChoiceChip(
                    selected: _section == module.key,
                    showCheckmark: false,
                    avatar: Icon(_moduleIcon(module.key), size: 17),
                    label: Text(
                        '${(index + 1).toString().padLeft(2, '0')}  ${module.title}'),
                    onSelected: (_) => _navigate(module.key));
              })));

  IconData _moduleIcon(String key) => switch (key) {
        'dashboard' => Icons.dashboard_outlined,
        'colaboradores' => Icons.badge_outlined,
        'ponto' => Icons.fingerprint,
        'ferias' => Icons.beach_access_outlined,
        'folha' => Icons.receipt_long_outlined,
        'relatorios' => Icons.assessment_outlined,
        _ => Icons.folder_outlined,
      };

  Widget _moduleBody(HrModule module) => switch (module.key) {
        'dashboard' => _dashboard(),
        'colaboradores' => _collaboratorsOverview(),
        'ponto' => EmployeePontoReport(employees: _employees),
        'relatorios' => _reports(),
        _ => _recordWorkspace(module),
      };

  Widget _collaboratorsOverview() => ListView(
          key: const PageStorageKey('rh-collaborators-overview'),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Icon(Icons.badge_outlined, color: Colors.teal),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Colaboradores cadastrados',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                                'Cadastros e dados existentes permanecem neste RH.',
                                style: TextStyle(fontSize: 12))
                          ])),
                      TextButton.icon(
                          onPressed: () => _navigate('ponto'),
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Controle de ponto')),
                    ]))),
            const SizedBox(height: 10),
            if (_employees.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum colaborador cadastrado.')))
            else
              ..._employees.map((employee) => Card(
                  child: ListTile(
                      leading: CircleAvatar(
                          child: Text(employee.name.isEmpty
                              ? '?'
                              : employee.name[0].toUpperCase())),
                      title: Text(employee.name),
                      subtitle: Text(
                          '${employee.position.isEmpty ? 'Sem cargo informado' : employee.position} • ${employee.active ? 'Ativo' : 'Inativo'}'),
                      trailing: IconButton(
                          tooltip: 'Relatório de ponto',
                          onPressed: () => _navigate('ponto'),
                          icon: const Icon(Icons.query_stats_outlined))))),
          ]);

  Widget _metric(String label, String value, IconData icon, Color color) =>
      SizedBox(
          width: 215,
          child: Card(
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(value,
                            style: const TextStyle(
                                fontSize: 23, fontWeight: FontWeight.bold)),
                        Text(label, style: const TextStyle(fontSize: 12)),
                      ])),
                ])),
          ));

  Widget _dashboard() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final active = _employees.where((e) => e.active).length;
    final vacations = _records.where((r) =>
        r.recordType == 'ferias' &&
        ['Aprovado', 'Em férias'].contains(r.status));
    final onVacation = vacations.where((r) {
      final start = DateTime.tryParse('${r.payload['start_date']}');
      final end = DateTime.tryParse('${r.payload['end_date']}');
      return start != null &&
          end != null &&
          !today.isBefore(start) &&
          !today.isAfter(end);
    }).length;
    final pending = _records
        .where((r) =>
            r.recordType != 'auditoria' &&
            !_isDone(r) &&
            ![
              'Ativo',
              'Aprovado',
              'Enviado ao financeiro',
              'Configurado internamente'
            ].contains(r.status))
        .toList();
    final expiry = _records
        .where((r) =>
            ['sst', 'treinamentos'].contains(r.recordType) &&
            r.status != 'Cancelado' &&
            DateTime.tryParse('${r.payload['expiry_date']}')
                    ?.isBefore(today.add(const Duration(days: 30))) ==
                true)
        .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 8, children: [
        _metric('Colaboradores ativos', '$active', Icons.badge_outlined,
            Colors.teal),
        _metric('Em férias hoje', '$onVacation', Icons.beach_access_outlined,
            Colors.blue),
        _metric('Pendências do RH', '${pending.length}',
            Icons.notifications_active_outlined, Colors.orange),
        _metric('Exames / cursos até 30 dias', '${expiry.length}',
            Icons.health_and_safety_outlined, Colors.redAccent),
      ]),
      const SizedBox(height: 16),
      _vacationCalendar(),
      const SizedBox(height: 16),
      const Text('Acesso aos módulos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 1; i < HrModule.modules.length; i++)
          SizedBox(
              width: 270,
              child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      onTap: () => _navigate(HrModule.modules[i].key),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${(i + 1).toString().padLeft(2, '0')}  ${HrModule.modules[i].title}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 5),
                                Text(HrModule.modules[i].description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                              ])))))
      ]),
      const SizedBox(height: 20),
      const Text('Alertas e próximas ações',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (pending.isEmpty && expiry.isEmpty)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhuma pendência registrada.')),
      for (final record in [...expiry, ...pending].toSet().take(12))
        Card(
            child: ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: Text(record.title),
          subtitle: Text(
              '${HrModule.byKey(record.recordType).title} • ${record.status}'),
          trailing: _recordDate(record) == null
              ? null
              : Text(_date.format(_recordDate(record)!)),
          onTap: () => _navigate(record.recordType),
        )),
    ]);
  }

  Widget _vacationCalendar() {
    final start = _calendarMonth;
    final end = DateTime(start.year, start.month + 1, 0);
    final vacations = _records.where((r) {
      if (r.recordType != 'ferias' ||
          !['Aprovado', 'Em férias', 'Concluído'].contains(r.status))
        return false;
      final from = DateTime.tryParse('${r.payload['start_date']}');
      final to = DateTime.tryParse('${r.payload['end_date']}');
      return from != null &&
          to != null &&
          !from.isAfter(end) &&
          !to.isBefore(start);
    }).toList();
    final offset = start.weekday % 7;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                    child: Text('Calendário de férias',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                    tooltip: 'Mês anterior',
                    onPressed: () => setState(() =>
                        _calendarMonth = DateTime(start.year, start.month - 1)),
                    icon: const Icon(Icons.chevron_left)),
                Text(DateFormat('MM/yyyy').format(start)),
                IconButton(
                    tooltip: 'Próximo mês',
                    onPressed: () => setState(() =>
                        _calendarMonth = DateTime(start.year, start.month + 1)),
                    icon: const Icon(Icons.chevron_right)),
              ]),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, constraints) {
                final width = (constraints.maxWidth / 7).floorToDouble();
                return Wrap(children: [
                  for (final day in [
                    'Dom',
                    'Seg',
                    'Ter',
                    'Qua',
                    'Qui',
                    'Sex',
                    'Sáb'
                  ])
                    SizedBox(
                        width: width,
                        child: Center(
                            child: Text(day,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)))),
                  for (var i = 0; i < offset + end.day; i++)
                    SizedBox(
                        width: width,
                        height: 38,
                        child: i < offset
                            ? null
                            : Builder(builder: (context) {
                                final day = DateTime(
                                    start.year, start.month, i - offset + 1);
                                final scheduled = vacations
                                    .where((r) =>
                                        !day.isBefore(DateTime.parse(
                                            '${r.payload['start_date']}')) &&
                                        !day.isAfter(DateTime.parse(
                                            '${r.payload['end_date']}')))
                                    .toList();
                                return Tooltip(
                                    message: scheduled.isEmpty
                                        ? 'Sem férias'
                                        : scheduled
                                            .map((r) =>
                                                _employee(r
                                                        .payload['employee_id'])
                                                    ?.name ??
                                                r.title)
                                            .join('\n'),
                                    child: Container(
                                        margin: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                            color: scheduled.isEmpty
                                                ? null
                                                : Colors.teal
                                                    .withValues(alpha: .18),
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        child: Center(
                                            child: Text(
                                                '${day.day}${scheduled.isEmpty ? '' : ' •'}'))));
                              })),
                ]);
              }),
              for (final record in vacations.take(8))
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${_employee(record.payload['employee_id'])?.name ?? record.title}: ${_date.format(DateTime.parse('${record.payload['start_date']}'))} a ${_date.format(DateTime.parse('${record.payload['end_date']}'))}')),
              if (vacations.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Nenhuma férias aprovada neste mês.')),
            ])));
  }

  Widget _recordWorkspace(HrModule module) {
    final filter = _filters.putIfAbsent(module.key, _HrFilter.new);
    final records = _filtered(module);
    return Column(children: [
      if (module.key == 'portal') _portalSummary(),
      if (module.key == 'folha')
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                  child: Text(
                      'Valores aprovados pelo RH. Holerites e cálculos já existentes continuam no cadastro.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12))),
              TextButton.icon(
                  onPressed: () => _navigate('colaboradores'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Holerites')),
            ])),
      if (module.key == 'configuracoes')
        const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
                'Eventos eSocial são preparados como rascunho. A transmissão exige provedor oficial, credenciais e certificado configurados externamente. Não informe senhas neste cadastro.',
                style: TextStyle(fontSize: 12))),
      if (module.key == 'documentos')
        const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
                'Anexe contratos e comprovantes de assinatura de um provedor externo. O cadastro não executa uma assinatura eletrônica.',
                style: TextStyle(fontSize: 12))),
      Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 245,
                    child: TextFormField(
                        key: ValueKey('search-${module.key}'),
                        initialValue: filter.query,
                        decoration: const InputDecoration(
                            labelText: 'Buscar registro ou colaborador',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search)),
                        onChanged: (value) =>
                            setState(() => filter.query = value))),
                SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                        initialValue: filter.status,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Situação',
                            border: OutlineInputBorder()),
                        items: ['Todos', ...module.statuses]
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child:
                                    Text(s, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => filter.status = value ?? 'Todos'))),
                if (module.fields.any((f) => f.kind == HrFieldKind.employee))
                  SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<int>(
                          key: ValueKey(
                              'rh-filter-${module.key}-${filter.employeeId}'),
                          initialValue: filter.employeeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Colaborador',
                              border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Todos os colaboradores')),
                            for (final employee in _employees)
                              DropdownMenuItem(
                                  value: employee.id,
                                  child: Text(employee.name,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: module.key == 'portal' &&
                                  _portalOwnEmployee != null
                              ? null
                              : (value) =>
                                  setState(() => filter.employeeId = value))),
                OutlinedButton.icon(
                    onPressed: () async {
                      final period = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(1990),
                          lastDate: DateTime(2100),
                          initialDateRange: filter.period);
                      if (period != null && mounted)
                        setState(() => filter.period = period);
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(filter.period == null
                        ? 'Período'
                        : '${_date.format(filter.period!.start)} – ${_date.format(filter.period!.end)}')),
                if (filter.period != null)
                  IconButton(
                      tooltip: 'Limpar período',
                      onPressed: () => setState(() => filter.period = null),
                      icon: const Icon(Icons.clear)),
                FilledButton.icon(
                    onPressed: _working ? null : () => _edit(module),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo registro')),
                OutlinedButton.icon(
                    onPressed: records.isEmpty
                        ? null
                        : () => _exportRecords(module, records),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Exportar JSON')),
              ])),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${records.length} registro(s)',
                  style: const TextStyle(color: Colors.grey)))),
      Expanded(
          child: records.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.folder_open_outlined,
                      size: 46, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text('Nenhum registro com os filtros selecionados.'),
                  TextButton(
                      onPressed: () => _edit(module),
                      child: const Text('Cadastrar primeiro registro')),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  itemCount: records.length,
                  itemBuilder: (context, index) =>
                      _recordCard(module, records[index]))),
      if (module.key == 'configuracoes')
        SizedBox(height: 130, child: _auditList()),
    ]);
  }

  Widget _recordCard(HrModule module, ErpModuleRecord record) {
    final employee = _employee(record.payload['employee_id']);
    final date = _recordDate(record);
    return Card(
        child: ExpansionTile(
      leading: CircleAvatar(
          backgroundColor: Colors.teal.withValues(alpha: .12),
          child: Icon(
              module.financial
                  ? Icons.payments_outlined
                  : Icons.description_outlined,
              color: Colors.teal)),
      title: Text(record.title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([
        if (employee != null) employee.name,
        record.status,
        if (date != null) _date.format(date),
        if (record.payload['amount'] is num)
          _money.format(record.payload['amount'])
      ].join(' • ')),
      children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              for (final field in module.fields)
                if (record.payload[field.key] != null &&
                    field.kind != HrFieldKind.attachment)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                          '${field.label}: ${_display(field, record.payload[field.key])}')),
              if (record.payload['financial_id'] != null)
                Text(
                    'Conta a pagar vinculada: #${record.payload['financial_id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                OutlinedButton.icon(
                    onPressed:
                        _working ? null : () => _edit(module, previous: record),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar')),
                if (record.payload['attachment'] is Map)
                  OutlinedButton.icon(
                      onPressed: () => _downloadAttachment(record),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(
                          '${(record.payload['attachment'] as Map)['name']}')),
                if (module.financial && _canFinance)
                  FilledButton.icon(
                      onPressed: _working ||
                              record.payload['financial_id'] != null ||
                              record.status != 'Aprovado'
                          ? null
                          : () => _sendFinancial(record),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(record.payload['financial_id'] != null
                          ? 'Já vinculado ao financeiro'
                          : 'Gerar conta a pagar')),
                if (module.financial && !_canFinance)
                  const Chip(
                      label: Text(
                          'Envio ao financeiro exige permissão Financeiro')),
                TextButton.icon(
                    onPressed: _working ? null : () => _delete(record),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    label: const Text('Excluir')),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Atualizado em ${DateFormat('dd/MM/yyyy HH:mm').format(record.updatedAt)} por ${record.payload['updated_by'] ?? record.payload['created_by'] ?? 'RH'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]))
      ],
    ));
  }

  String _display(HrField field, dynamic value) {
    if (field.kind == HrFieldKind.employee)
      return _employee(value)?.name ?? 'Colaborador #$value';
    if (field.kind == HrFieldKind.money && value is num)
      return _money.format(value);
    if (field.kind == HrFieldKind.date)
      return DateTime.tryParse('$value') == null
          ? '$value'
          : _date.format(DateTime.parse('$value'));
    return '$value';
  }

  Future<void> _edit(HrModule module, {ErpModuleRecord? previous}) async {
    final result = await showDialog<_HrEditResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HrRecordEditor(
            module: module,
            employees: _employees,
            previous: previous,
            lockedEmployeeId:
                module.key == 'portal' ? _portalOwnEmployee?.id : null,
            onSave: (result) async {
              if (!_canAccess)
                throw StateError('Você não possui acesso ao RH.');
              await _service.save(
                  module: module,
                  title: result.title,
                  status: result.status,
                  payload: result.payload,
                  actor: _actor,
                  previous: previous);
              await _load(silent: true);
            }));
    if (result != null && mounted) _message('Registro salvo.');
  }

  Future<void> _delete(ErpModuleRecord record) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Excluir registro?'),
              content: Text(
                  'O registro “${record.title}” será excluído. A ação ficará no histórico do RH.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Excluir'))
              ],
            ));
    if (accepted != true || !mounted || !_canAccess) return;
    setState(() => _working = true);
    try {
      await _service.delete(record, _actor);
      await _load(silent: true);
      _message('Registro excluído.');
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sendFinancial(ErpModuleRecord record) async {
    if (!_canAccess || !_canFinance) return;
    final employee = _employee(record.payload['employee_id']);
    if (employee == null) {
      _message('Vincule um colaborador válido ao registro.', error: true);
      return;
    }
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Gerar conta a pagar'),
              content: Text(
                  'Gerar ${_money.format(record.payload['amount'] ?? 0)} para ${employee.name}? A conta será criada como pendente. A baixa será realizada no Financeiro.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Gerar conta'))
              ],
            ));
    if (confirm != true || !mounted || !_canFinance) return;
    setState(() => _working = true);
    try {
      final financial =
          await _service.sendToFinancial(record, employee, _actor);
      await _load(silent: true);
      _message('Conta a pagar #${financial.id} vinculada ao registro.');
    } catch (error) {
      _message('Não foi possível gerar a conta: $error', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _portalSummary() => Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Consulta individual pelo RH',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                'Área restrita à permissão Funcionários. Selecione um colaborador para consultar seu holerite e suas solicitações.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<int>(
                          key:
                              ValueKey('portal-colaborador-$_portalEmployeeId'),
                          initialValue: _portalEmployeeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Colaborador',
                              border: OutlineInputBorder()),
                          items: [
                            for (final employee in _employees)
                              DropdownMenuItem(
                                  value: employee.id,
                                  child: Text(employee.name,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: _portalOwnEmployee != null
                              ? null
                              : (id) {
                                  setState(() {
                                    _portalEmployeeId = id;
                                    _filters
                                        .putIfAbsent('portal', _HrFilter.new)
                                        .employeeId = id;
                                  });
                                  _loadPortalHolerite();
                                })),
                  SizedBox(
                      width: 150,
                      child: TextFormField(
                          initialValue: _portalCompetence,
                          decoration: const InputDecoration(
                              labelText: 'AAAA-MM',
                              border: OutlineInputBorder()),
                          onChanged: (value) {
                            _portalCompetence = value;
                            _loadPortalHolerite();
                          })),
                  OutlinedButton.icon(
                      onPressed:
                          _portalHolerite == null ? null : _viewPortalHolerite,
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Consultar holerite')),
                  if (_portalEmployeeId != null)
                    Text(_portalHolerite == null
                        ? 'Sem holerite nesta competência.'
                        : 'Líquido: ${_money.format(_portalHolerite!.salarioLiquido)}'),
                ]),
          ])));

  Future<void> _loadPortalHolerite() async {
    final request = ++_portalRequest;
    if (_portalEmployeeId == null ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(_portalCompetence)) {
      setState(() => _portalHolerite = null);
      return;
    }
    try {
      final receipt = await _holeriteRepository.getByEmployeeAndMonth(
          _portalEmployeeId!, _portalCompetence);
      if (mounted && request == _portalRequest)
        setState(() => _portalHolerite = receipt);
    } catch (error) {
      if (mounted && request == _portalRequest) {
        setState(() => _portalHolerite = null);
        _message('Não foi possível consultar o holerite: $error', error: true);
      }
    }
  }

  Future<void> _viewPortalHolerite() async {
    final receipt = _portalHolerite;
    final employee = _employee(_portalEmployeeId);
    if (receipt == null || employee == null || !_canAccess) return;
    try {
      final bytes = await FolhaPagamentoService()
          .gerarHoleriteIndividual(employee, receipt);
      if (mounted)
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PreviewPdfScreen(
                    pdfBytes: bytes, titulo: 'Holerite • ${employee.name}')));
    } catch (error) {
      _message('Não foi possível abrir o holerite: $error', error: true);
    }
  }

  Widget _auditList() {
    final events = _records.where((r) => r.recordType == 'auditoria').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Histórico de operações do RH',
              style: TextStyle(fontWeight: FontWeight.bold))),
      Expanded(
          child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, index) {
                final e = events[index];
                return ListTile(
                    dense: true,
                    title: Text(e.title),
                    subtitle: Text(
                        '${e.payload['actor']} • ${DateFormat('dd/MM/yyyy HH:mm').format(e.createdAt)}'));
              })),
    ]);
  }

  List<List<String>> _reportRows() {
    final records = _records.where((r) => r.recordType != 'auditoria').toList();
    return [
      for (final e in _employees)
        [
          e.name,
          e.position,
          e.active ? 'Ativo' : 'Inativo',
          _money.format(e.salary ?? 0),
          '${records.where((r) => r.payload['employee_id'] == e.id && r.recordType == 'afastamentos' && r.status != 'Recusado').length}',
          '${records.where((r) => r.payload['employee_id'] == e.id && r.recordType == 'treinamentos' && r.status == 'Concluído').length}',
          _money.format(records
              .where((r) =>
                  r.payload['employee_id'] == e.id &&
                  ['folha', 'beneficios', 'rescisoes', 'ferias']
                      .contains(r.recordType) &&
                  ['Aprovado', 'Enviado ao financeiro', 'Concluído']
                      .contains(r.status))
              .fold<double>(
                  0,
                  (sum, r) =>
                      sum + ((r.payload['amount'] as num?)?.toDouble() ?? 0))),
        ]
    ];
  }

  Widget _reports() {
    final active = _employees.where((e) => e.active).toList();
    final salaries = active.fold<double>(0, (sum, e) => sum + (e.salary ?? 0));
    final now = DateTime.now();
    final hired = _employees
        .where((e) =>
            e.hireDate?.year == now.year && e.hireDate?.month == now.month)
        .length;
    final departed = _records
        .where((r) =>
            r.recordType == 'rescisoes' &&
            r.status == 'Concluído' &&
            DateTime.tryParse('${r.payload['termination_date']}')?.year ==
                now.year &&
            DateTime.tryParse('${r.payload['termination_date']}')?.month ==
                now.month)
        .length;
    final base = _employees.isEmpty
        ? 0.0
        : ((hired + departed) / 2) / _employees.length * 100;
    final positions = <String, int>{};
    for (final e in active) {
      positions[e.position.isEmpty ? 'Sem cargo' : e.position] =
          (positions[e.position.isEmpty ? 'Sem cargo' : e.position] ?? 0) + 1;
    }
    final maxCount = positions.values.fold<int>(1, (a, b) => a > b ? a : b);
    final rows = _reportRows();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _metric('Salários base dos ativos', _money.format(salaries),
            Icons.payments_outlined, Colors.teal),
        _metric(
            'Admissões no mês', '$hired', Icons.person_add_alt, Colors.blue),
        _metric('Desligamentos concluídos / mês', '$departed',
            Icons.person_remove_outlined, Colors.orange),
        _metric('Rotatividade no mês¹', '${base.toStringAsFixed(1)}%',
            Icons.swap_horiz, Colors.purple),
      ]),
      const SizedBox(height: 8),
      const Text(
          '¹ (Admissões + desligamentos) ÷ 2 ÷ colaboradores cadastrados. Valores de registros aprovados refletem todo o histórico cadastrado.',
          style: TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 18),
      const Text('Colaboradores ativos por cargo',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      for (final entry in positions.entries)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(
                  width: 150,
                  child: Text(entry.key, overflow: TextOverflow.ellipsis)),
              Expanded(
                  child: LinearProgressIndicator(
                      value: entry.value / maxCount,
                      minHeight: 14,
                      borderRadius: BorderRadius.circular(4))),
              SizedBox(
                  width: 40,
                  child: Text('${entry.value}', textAlign: TextAlign.end)),
            ])),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: rows.isEmpty ? null : _exportReportCsv,
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Exportar CSV')),
        OutlinedButton.icon(
            onPressed: rows.isEmpty ? null : _exportReportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Relatório PDF')),
        OutlinedButton.icon(
            onPressed: () => _navigate('ponto'),
            icon: const Icon(Icons.schedule),
            label: const Text('Horas, extras e faltas por colaborador')),
      ]),
      const SizedBox(height: 14),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: [
            for (final title in _reportHeaders) DataColumn(label: Text(title))
          ], rows: [
            for (final row in rows)
              DataRow(cells: [for (final cell in row) DataCell(Text(cell))])
          ])),
    ]);
  }

  static const _reportHeaders = [
    'Colaborador',
    'Cargo',
    'Situação',
    'Salário base',
    'Afastamentos',
    'Cursos concluídos',
    'Valores aprovados'
  ];

  Future<void> _exportReportCsv() async {
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    final text = [_reportHeaders, ..._reportRows()]
        .map((r) => r.map(cell).join(';'))
        .join('\r\n');
    await _saveFile(
        'relatorio_rh_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(text)]),
        ['csv']);
  }

  Future<void> _exportReportPdf() async {
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (_) => [
                pw.Text('MastterSystem • Relatório de RH',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text(
                    'Emitido em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}. Registros aprovados: todo o histórico.'),
                pw.SizedBox(height: 12),
                pw.TableHelper.fromTextArray(
                    headers: _reportHeaders,
                    data: _reportRows(),
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    headerStyle: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ]));
      final bytes = await pdf.save();
      if (mounted)
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PreviewPdfScreen(
                    pdfBytes: bytes, titulo: 'Relatório de RH')));
    } catch (error) {
      _message('Não foi possível gerar o relatório: $error', error: true);
    }
  }

  Future<void> _exportRecords(
      HrModule module, List<ErpModuleRecord> records) async {
    final data = {
      'system': 'MastterSystem',
      'module': module.title,
      'exported_at': DateTime.now().toIso8601String(),
      'exported_by': _actor,
      if (module.key == 'configuracoes')
        'integration_state': 'draft_only_not_transmitted',
      'records': records
          .map((r) => {
                'id': r.id,
                'title': r.title,
                'status': r.status,
                'payload': r.payload,
                'created_at': r.createdAt.toIso8601String(),
                'updated_at': r.updatedAt.toIso8601String()
              })
          .toList()
    };
    await _saveFile(
        'rh_${module.key}_${DateFormat('yyyyMMdd').format(DateTime.now())}.json',
        Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data))),
        ['json']);
  }

  Future<void> _downloadAttachment(ErpModuleRecord record) async {
    try {
      final attachment =
          Map<String, dynamic>.from(record.payload['attachment'] as Map);
      final bytes = base64Decode(attachment['base64'] as String);
      if (sha256.convert(bytes).toString() != attachment['sha256'])
        throw StateError(
            'O arquivo não passou pela verificação de integridade.');
      final name =
          '${attachment['name']}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      await _saveFile(
          name, bytes, [name.contains('.') ? name.split('.').last : 'bin']);
    } catch (error) {
      _message('Não foi possível baixar o documento: $error', error: true);
    }
  }

  Future<void> _saveFile(
      String name, Uint8List bytes, List<String> extensions) async {
    if (!_canAccess) return;
    try {
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar arquivo do RH',
          fileName: name,
          type: FileType.custom,
          allowedExtensions: extensions,
          bytes: bytes);
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS)
        await File(path).writeAsBytes(bytes, flush: true);
      _message('Arquivo salvo.');
    } catch (error) {
      _message('Não foi possível salvar o arquivo: $error', error: true);
    }
  }
}

class _HrEditResult {
  const _HrEditResult(this.title, this.status, this.payload);
  final String title;
  final String status;
  final Map<String, dynamic> payload;
}

class _HrRecordEditor extends StatefulWidget {
  const _HrRecordEditor(
      {required this.module,
      required this.employees,
      required this.onSave,
      this.previous,
      this.lockedEmployeeId});
  final HrModule module;
  final List<EmployeeModel> employees;
  final ErpModuleRecord? previous;
  final int? lockedEmployeeId;
  final Future<void> Function(_HrEditResult) onSave;
  @override
  State<_HrRecordEditor> createState() => _HrRecordEditorState();
}

class _HrRecordEditorState extends State<_HrRecordEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _controllers = <String, TextEditingController>{};
  late Map<String, dynamic> _payload;
  late String _status;
  bool _attaching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _payload = Map.of(widget.previous?.payload ?? {});
    if (widget.lockedEmployeeId != null)
      _payload['employee_id'] = widget.lockedEmployeeId;
    _title.text = widget.previous?.title ?? '';
    _status = widget.previous?.status ?? widget.module.statuses.first;
    for (final field in widget.module.fields) {
      final value = _payload[field.key];
      if (!const [
        HrFieldKind.attachment,
        HrFieldKind.employee,
        HrFieldKind.choice
      ].contains(field.kind)) {
        _controllers[field.key] = TextEditingController(
            text: value == null
                ? ''
                : (field.kind == HrFieldKind.money && value is num
                    ? value.toStringAsFixed(2).replaceAll('.', ',')
                    : '$value'));
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  num? _number(String value) {
    var normalized = value.trim().replaceAll(RegExp(r'\s|R\$'), '');
    if (normalized.contains(','))
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    return num.tryParse(normalized);
  }

  void _sync() {
    for (final field in widget.module.fields) {
      final controller = _controllers[field.key];
      if (controller == null) continue;
      final text = controller.text.trim();
      if (text.isEmpty) {
        _payload.remove(field.key);
        continue;
      }
      _payload[field.key] =
          const [HrFieldKind.money, HrFieldKind.number].contains(field.kind)
              ? (_number(text) ?? text)
              : text;
    }
  }

  Future<void> _submit() async {
    _sync();
    final valid = _form.currentState!.validate();
    final errors = widget.module.validate(_payload);
    if (!valid || errors.isNotEmpty) {
      setState(() => _error = errors.isEmpty
          ? 'Confira os campos destacados.'
          : errors.values.first);
      return;
    }
    if (widget.module.key == 'documentos' &&
        _status == 'Assinatura comprovada pelo provedor' &&
        ('${_payload['signature_provider'] ?? ''}'.trim().isEmpty ||
            '${_payload['signature_protocol'] ?? ''}'.trim().isEmpty)) {
      setState(() =>
          _error = 'Informe o provedor externo e o protocolo da assinatura.');
      return;
    }
    final result = _HrEditResult(_title.text.trim(), _status, _payload);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(result);
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível salvar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            '${widget.previous == null ? 'Novo registro' : 'Editar'} • ${widget.module.title}'),
        content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: _title,
                          decoration: const InputDecoration(
                              labelText: 'Título / identificação *',
                              border: OutlineInputBorder()),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Informe o título.'
                              : null),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                          initialValue: _status,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Situação',
                              border: OutlineInputBorder()),
                          items: widget.module.statuses
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _status = value);
                          }),
                      for (final field in widget.module.fields)
                        Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _field(field)),
                      if (widget.module.financial)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                                'Informe valores conferidos pelo responsável. A conta a pagar é gerada somente pela ação “Gerar conta a pagar”, após aprovação.',
                                style: TextStyle(fontSize: 12))),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_error!,
                                style:
                                    const TextStyle(color: Colors.redAccent))),
                    ])))),
        actions: [
          TextButton(
              onPressed:
                  _attaching || _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _attaching || _saving ? null : _submit,
              child: Text(_saving ? 'Salvando...' : 'Salvar'))
        ],
      );

  Widget _field(HrField field) {
    final label = '${field.label}${field.required ? ' *' : ''}';
    if (field.kind == HrFieldKind.attachment) {
      final attachment = _payload[field.key] as Map?;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label),
        const SizedBox(height: 6),
        Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                  onPressed: _attaching ? null : () => _attach(field),
                  icon: const Icon(Icons.attach_file),
                  label: Text(_attaching
                      ? 'Carregando...'
                      : 'Anexar arquivo (até 1 MB)')),
              if (attachment != null) Text('${attachment['name']}'),
              if (attachment != null)
                IconButton(
                    tooltip: 'Remover anexo',
                    onPressed: () => setState(() => _payload.remove(field.key)),
                    icon: const Icon(Icons.close)),
            ]),
      ]);
    }
    if (field.kind == HrFieldKind.employee) {
      final selected = _payload[field.key] as int?;
      return DropdownButtonFormField<int>(
          initialValue:
              widget.employees.any((e) => e.id == selected) ? selected : null,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: [
            for (final employee in widget.employees)
              DropdownMenuItem(
                  value: employee.id,
                  child: Text(
                      '${employee.name}${employee.active ? '' : ' (inativo)'}',
                      overflow: TextOverflow.ellipsis))
          ],
          onChanged: widget.lockedEmployeeId != null
              ? null
              : (value) => setState(() => _payload[field.key] = value),
          validator: (v) =>
              field.required && v == null ? 'Selecione o colaborador.' : null);
    }
    if (field.kind == HrFieldKind.choice) {
      return DropdownButtonFormField<String>(
          initialValue: field.options.contains(_payload[field.key])
              ? _payload[field.key] as String?
              : null,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (value) => setState(() => _payload[field.key] = value),
          validator: (v) =>
              field.required && v == null ? 'Selecione uma opção.' : null);
    }
    final controller = _controllers[field.key]!;
    return TextFormField(
      controller: controller,
      readOnly: field.kind == HrFieldKind.date,
      maxLines: field.kind == HrFieldKind.notes ? 3 : 1,
      keyboardType:
          const [HrFieldKind.money, HrFieldKind.number].contains(field.kind)
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
      decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          hintText: field.kind == HrFieldKind.date ? 'AAAA-MM-DD' : null,
          suffixIcon: field.kind == HrFieldKind.date
              ? IconButton(
                  tooltip: 'Escolher data',
                  icon: const Icon(Icons.event_outlined),
                  onPressed: () => _chooseDate(field))
              : null),
      onTap: field.kind == HrFieldKind.date ? () => _chooseDate(field) : null,
      validator: (value) {
        if (field.required && (value == null || value.trim().isEmpty))
          return 'Campo obrigatório.';
        if (value == null || value.trim().isEmpty) return null;
        if (const [HrFieldKind.money, HrFieldKind.number]
            .contains(field.kind)) {
          final number = _number(value);
          if (number == null || !number.isFinite || number < 0)
            return 'Informe um valor válido, maior ou igual a zero.';
        }
        return null;
      },
    );
  }

  Future<void> _chooseDate(HrField field) async {
    final controller = _controllers[field.key]!;
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100));
    if (date != null && mounted)
      setState(() => controller.text = DateFormat('yyyy-MM-dd').format(date));
  }

  Future<void> _attach(HrField field) async {
    setState(() {
      _attaching = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 1024 * 1024)
        throw StateError('Selecione um arquivo de até 1 MB.');
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw StateError('Não foi possível ler o arquivo.');
      if (bytes.length > 1024 * 1024)
        throw StateError('Selecione um arquivo de até 1 MB.');
      if (mounted)
        setState(() => _payload[field.key] = {
              'name': file.name,
              'size': bytes.length,
              'base64': base64Encode(bytes),
              'sha256': sha256.convert(bytes).toString(),
              'attached_at': DateTime.now().toIso8601String()
            });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }
}
