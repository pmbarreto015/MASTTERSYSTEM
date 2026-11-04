import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../models/employee_model.dart';
import '../../models/ponto_model.dart';
import '../../models/ponto_report.dart';
import '../../services/ponto_report_pdf_service.dart';
import '../../services/ponto_repository.dart';

class EmployeePontoReport extends StatefulWidget {
  const EmployeePontoReport({
    super.key,
    required this.employees,
    this.initialEmployeeId,
    this.selectionVersion = 0,
    this.loadPontos,
  });

  final List<EmployeeModel> employees;
  final int? initialEmployeeId;
  final int selectionVersion;
  final Future<List<PontoModel>> Function(int employeeId)? loadPontos;

  @override
  State<EmployeePontoReport> createState() => _EmployeePontoReportState();
}

class _EmployeePontoReportState extends State<EmployeePontoReport> {
  final _repository = PontoRepository();
  final _dateFormat = DateFormat('dd/MM/yyyy');
  int? _employeeId;
  late DateTimeRange _period;
  PontoReport? _report;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  int _request = 0;

  EmployeeModel? get _employee {
    for (final employee in widget.employees) {
      if (employee.id == _employeeId) return employee;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = DateTimeRange(
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _employeeId = widget.initialEmployeeId;
    if (_employeeId != null) _load();
  }

  @override
  void didUpdateWidget(covariant EmployeePontoReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.initialEmployeeId != widget.initialEmployeeId ||
            oldWidget.selectionVersion != widget.selectionVersion) &&
        widget.initialEmployeeId != null) {
      _employeeId = widget.initialEmployeeId;
      _load();
    } else if (_employeeId != null && _employee == null) {
      _request++;
      _employeeId = null;
      _report = null;
      _loading = false;
      _error = null;
    }
  }

  Future<void> _load() async {
    final employeeId = _employeeId;
    if (employeeId == null) return;
    final request = ++_request;
    final period = _period;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final pontos =
          await (widget.loadPontos ?? _repository.getByEmployeeId)(employeeId);
      if (!mounted || request != _request) return;
      setState(() {
        _report = PontoReport(
          employeeId: employeeId,
          start: period.start,
          end: period.end,
          records: pontos,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error =
            'Não foi possível carregar os pontos. Tente atualizar o relatório.';
      });
    }
  }

  Future<void> _choosePeriod() async {
    final period = await showDateRangePicker(
      context: context,
      initialDateRange: _period,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      helpText: 'Período do relatório de ponto',
      saveText: 'Aplicar',
    );
    if (period == null || !mounted) return;
    setState(() => _period = period);
    await _load();
  }

  Future<void> _export() async {
    final report = _report;
    final employee = _employee;
    if (report == null || employee == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await PontoReportPdfService().generate(employee, report);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PontoPdfPreview(
          bytes: bytes,
          employee: employee,
          report: report,
        ),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível gerar o PDF do relatório de ponto.'),
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Relatório individual de ponto',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                      'Consulte as batidas e os totais registrados de cada funcionário.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth - 32)
                            .clamp(0, 300)
                            .toDouble(),
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(_employeeId),
                          initialValue: _employeeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Funcionário',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: widget.employees
                              .where((employee) => employee.id != null)
                              .map(
                                (employee) => DropdownMenuItem<int>(
                                  value: employee.id,
                                  child: Text(
                                      '${employee.name}${employee.active ? '' : ' (inativo)'}',
                                      overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (id) {
                            setState(() => _employeeId = id);
                            _load();
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _choosePeriod,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                            '${_dateFormat.format(_period.start)} a ${_dateFormat.format(_period.end)}'),
                      ),
                      IconButton(
                        onPressed:
                            _employeeId == null || _loading ? null : _load,
                        tooltip: 'Atualizar relatório',
                        icon: const Icon(Icons.refresh),
                      ),
                      FilledButton.icon(
                        onPressed: report == null || _loading || _exporting
                            ? null
                            : _export,
                        icon: Icon(_exporting
                            ? Icons.hourglass_empty
                            : Icons.picture_as_pdf),
                        label: const Text('PDF / Imprimir'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (report != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 10, runSpacing: 8, children: [
                  _summary('Dias com registro', '${report.diasRegistrados}',
                      Icons.calendar_today),
                  _summary(
                      'Horas trabalhadas',
                      PontoReport.formatHours(report.totalHoras),
                      Icons.schedule),
                  _summary(
                      'Horas extras',
                      PontoReport.formatHours(report.totalExtras),
                      Icons.more_time),
                  _summary('Registros em aberto', '${report.registrosAbertos}',
                      Icons.pending_actions),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Totais conforme os registros salvos. Batidas ausentes aparecem como "-".'),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!)))
                      : report == null
                          ? Center(
                              child: Text(widget.employees.isEmpty
                                  ? 'Cadastre um funcionário para consultar os pontos.'
                                  : 'Selecione um funcionário para consultar o período.'))
                          : report.pontos.isEmpty
                              ? const Center(
                                  child: Text(
                                      'Nenhum ponto registrado neste período.'))
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      columns: const [
                                        DataColumn(label: Text('Data')),
                                        DataColumn(label: Text('Entrada 1')),
                                        DataColumn(label: Text('Saída 1')),
                                        DataColumn(label: Text('Entrada 2')),
                                        DataColumn(label: Text('Saída 2')),
                                        DataColumn(label: Text('Horas')),
                                        DataColumn(label: Text('Extras')),
                                        DataColumn(label: Text('Situação')),
                                        DataColumn(label: Text('Observações')),
                                      ],
                                      rows: report.pontos
                                          .map((ponto) => DataRow(cells: [
                                                DataCell(Text(_dateFormat
                                                    .format(ponto.data))),
                                                DataCell(Text(
                                                    ponto.entrada1Formatada)),
                                                DataCell(Text(
                                                    ponto.saida1Formatada)),
                                                DataCell(Text(
                                                    ponto.entrada2Formatada)),
                                                DataCell(Text(
                                                    ponto.saida2Formatada)),
                                                DataCell(Text(PontoReport
                                                    .formatHours(ponto
                                                        .horasTrabalhadas))),
                                                DataCell(Text(
                                                    PontoReport.formatHours(
                                                        ponto.horasExtras))),
                                                DataCell(
                                                    Text(ponto.statusLabel)),
                                                DataCell(ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                          maxWidth: 260),
                                                  child: Text(
                                                      ponto.observacoes.isEmpty
                                                          ? '-'
                                                          : ponto.observacoes),
                                                )),
                                              ]))
                                          .toList(),
                                    ),
                                  ),
                                ),
            ),
          ],
        ),
      );
    });
  }

  Widget _summary(String label, String value, IconData icon) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _PontoPdfPreview extends StatelessWidget {
  const _PontoPdfPreview({
    required this.bytes,
    required this.employee,
    required this.report,
  });

  final Uint8List bytes;
  final EmployeeModel employee;
  final PontoReport report;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyyMMdd');
    return Scaffold(
      appBar: AppBar(title: Text('Relatório de ponto - ${employee.name}')),
      body: PdfPreview(
        build: (_) => bytes,
        pdfFileName:
            'ponto_${employee.id}_${date.format(report.start)}_${date.format(report.end)}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}
