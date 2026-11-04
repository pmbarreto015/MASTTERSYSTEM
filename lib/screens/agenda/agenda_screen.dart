import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/agenda_followup_model.dart';
import '../../services/agenda_followup_repository.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen>
    with BackgroundRefreshMixin<AgendaScreen> {
  final AgendaFollowupRepository _repository = AgendaFollowupRepository();
  final TextEditingController _searchController = TextEditingController();

  List<AgendaFollowupModel> _items = [];
  List<AgendaFollowupModel> _filteredItems = [];
  bool _loading = true;
  String _periodFilter = 'hoje';
  String _statusFilter = 'todos';
  String _search = '';

  static const _statusLabels = {
    'responder': 'Responder',
    'sem_resposta': 'Sem resposta',
    'aguardando_cliente': 'Aguardando cliente',
    'concluido': 'Concluído',
  };

  static const _periodicityLabels = {
    'unico': 'Somente esta vez',
    'diario': 'Diariamente',
    'semanal': 'Semanalmente',
  };

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadItems();

  Future<void> _loadItems() async {
    if (!isRefreshingInBackground) setState(() => _loading = true);
    try {
      final items = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Erro ao carregar a agenda: $e', isError: true);
    }
  }

  DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _isToday(DateTime value) =>
      _dayStart(value) == _dayStart(DateTime.now());

  bool _isThisWeek(DateTime value) {
    final today = _dayStart(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return !value.isBefore(monday) && value.isBefore(nextMonday);
  }

  bool _isOverdue(AgendaFollowupModel item) =>
      !item.concluido && item.agendadoPara.isBefore(DateTime.now());

  void _applyFilters() {
    final query = _search.toLowerCase().trim();
    setState(() {
      _filteredItems = _items.where((item) {
        final matchesSearch = query.isEmpty ||
            item.clienteNome.toLowerCase().contains(query) ||
            item.assunto.toLowerCase().contains(query) ||
            item.telefone.contains(query) ||
            item.observacoes.toLowerCase().contains(query);
        final matchesStatus =
            _statusFilter == 'todos' || item.status == _statusFilter;
        final matchesPeriod = switch (_periodFilter) {
          'hoje' => _isToday(item.agendadoPara) && !item.concluido,
          'semana' => _isThisWeek(item.agendadoPara) && !item.concluido,
          'atrasados' => _isOverdue(item),
          'concluidos' => item.concluido,
          _ => true,
        };
        return matchesSearch && matchesStatus && matchesPeriod;
      }).toList();
    });
  }

  Color _statusColor(String status) => switch (status) {
        'sem_resposta' => Colors.red,
        'aguardando_cliente' => Colors.orange,
        'concluido' => Colors.green,
        _ => const Color(0xFF0F62AC),
      };

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _openEditor({AgendaFollowupModel? item}) async {
    final formKey = GlobalKey<FormState>();
    final clientController =
        TextEditingController(text: item?.clienteNome ?? '');
    final phoneController = TextEditingController(text: item?.telefone ?? '');
    final subjectController = TextEditingController(text: item?.assunto ?? '');
    final notesController =
        TextEditingController(text: item?.observacoes ?? '');
    var selectedStatus = item?.status ?? 'responder';
    var selectedPeriodicity = item?.periodicidade ?? 'unico';
    var selectedDate =
        item?.agendadoPara ?? DateTime.now().add(const Duration(hours: 1));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Row(
            children: [
              const Icon(Icons.event_note, color: Color(0xFF0F62AC)),
              const SizedBox(width: 10),
              Text(item == null
                  ? 'Novo acompanhamento'
                  : 'Editar acompanhamento'),
            ],
          ),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48)
                .clamp(0, 560)
                .toDouble(),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final clientField = TextFormField(
                          controller: clientController,
                          decoration: const InputDecoration(
                            labelText: 'Cliente ou contato *',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Informe o cliente ou contato'
                                  : null,
                        );
                        final phoneField = TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(
                            labelText: 'WhatsApp/telefone',
                            prefixIcon: Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(),
                          ),
                        );
                        if (constraints.maxWidth < 520) {
                          return Column(
                            children: [
                              clientField,
                              const SizedBox(height: 12),
                              phoneField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: clientField),
                            const SizedBox(width: 10),
                            Expanded(child: phoneField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Assunto ou pendência *',
                        hintText: 'Ex.: Responder orçamento enviado',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Informe o assunto'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        hintText: 'Última mensagem, combinado com o cliente...',
                        prefixIcon: Icon(Icons.notes),
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedStatus,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Situação',
                              border: OutlineInputBorder(),
                            ),
                            items: _statusLabels.entries
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) selectedStatus = value;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedPeriodicity,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Repetição',
                              border: OutlineInputBorder(),
                            ),
                            items: _periodicityLabels.entries
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) selectedPeriodicity = value;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDate),
                        );
                        if (time == null) return;
                        setDialogState(() {
                          selectedDate = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Próximo contato',
                          prefixIcon: Icon(Icons.schedule),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(selectedDate),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final updated = AgendaFollowupModel(
                    id: item?.id,
                    clienteNome: clientController.text.trim(),
                    telefone: phoneController.text.trim(),
                    assunto: subjectController.text.trim(),
                    observacoes: notesController.text.trim(),
                    status: selectedStatus,
                    periodicidade: selectedPeriodicity,
                    agendadoPara: selectedDate,
                    concluidoEm: selectedStatus == 'concluido'
                        ? (item?.concluidoEm ?? DateTime.now())
                        : null,
                    criadoEm: item?.criadoEm,
                  );
                  if (item == null) {
                    await _repository.create(updated);
                  } else {
                    await _repository.update(updated);
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (e) {
                  if (mounted) {
                    _showMessage('Erro ao salvar: $e', isError: true);
                  }
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    clientController.dispose();
    phoneController.dispose();
    subjectController.dispose();
    notesController.dispose();
    if (saved == true) {
      await _loadItems();
      if (mounted) _showMessage('Acompanhamento salvo.');
    }
  }

  Future<void> _openWhatsApp(AgendaFollowupModel item) async {
    var digits = item.telefone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 || digits.length == 11) digits = '55$digits';
    if (digits.isEmpty) {
      _showMessage('Cadastre o telefone do cliente.', isError: true);
      return;
    }
    final uri = Uri.https('wa.me', '/$digits', {
      'text': 'Olá, ${item.clienteNome}. ${item.assunto}',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage('Não foi possível abrir o WhatsApp.', isError: true);
    }
  }

  Future<void> _toggleCompleted(AgendaFollowupModel item) async {
    if (item.concluido) {
      await _repository.setCompleted(item, false);
    } else {
      await _repository.completeAndScheduleNext(item);
    }
    await _loadItems();
  }

  Future<void> _delete(AgendaFollowupModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir acompanhamento?'),
        content: Text('${item.clienteNome} — ${item.assunto}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.delete(item.id!);
    await _loadItems();
  }

  int get _todayCount => _items
      .where((item) => _isToday(item.agendadoPara) && !item.concluido)
      .length;
  int get _weekCount => _items
      .where((item) => _isThisWeek(item.agendadoPara) && !item.concluido)
      .length;
  int get _overdueCount => _items.where(_isOverdue).length;
  int get _waitingCount =>
      _items.where((item) => item.status == 'aguardando_cliente').length;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            _buildHeader(),
            _buildToolbar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredItems.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadItems,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) =>
                                _buildFollowupCard(_filteredItems[index]),
                          ),
                        ),
            ),
          ],
        ),
      );

  Widget _buildHeader() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final title = Row(
            children: [
              const Icon(Icons.calendar_month, color: Color(0xFF0F62AC)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agenda de Acompanhamentos',
                      style: TextStyle(
                        fontSize: compact ? 17 : 19,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Text(
                      'Mensagens, retornos e conversas que precisam de aten\u00e7\u00e3o',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          );
          final newButton = FilledButton.icon(
            onPressed: _openEditor,
            icon: const Icon(Icons.add),
            label: const Text('Novo acompanhamento'),
          );
          final cards = [
            _summaryCard('Hoje', _todayCount, Icons.today, Colors.blue, 'hoje'),
            _summaryCard(
              'Esta semana',
              _weekCount,
              Icons.date_range,
              Colors.indigo,
              'semana',
            ),
            _summaryCard(
              'Atrasados',
              _overdueCount,
              Icons.warning_amber,
              Colors.red,
              'atrasados',
            ),
            _summaryCard(
              'Aguardando cliente',
              _waitingCount,
              Icons.hourglass_top,
              Colors.orange,
              'todos',
              status: 'aguardando_cliente',
            ),
          ];

          return Container(
            color: Theme.of(context).colorScheme.surface,
            padding: EdgeInsets.fromLTRB(16, compact ? 10 : 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) ...[
                  title,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: newButton),
                ] else
                  Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      newButton,
                    ],
                  ),
                const SizedBox(height: 12),
                if (compact)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final card in cards)
                        SizedBox(
                          width: (constraints.maxWidth - 40) / 2,
                          child: card,
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      for (final card in cards) Expanded(child: card),
                    ],
                  ),
              ],
            ),
          );
        },
      );

  Widget _summaryCard(
    String label,
    int count,
    IconData icon,
    Color color,
    String period, {
    String status = 'todos',
  }) =>
      InkWell(
        onTap: () {
          _periodFilter = period;
          _statusFilter = status;
          _applyFilters();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildToolbar() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final search = TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText:
                  'Buscar cliente, assunto, telefone ou observa\u00e7\u00e3o...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: (value) {
              _search = value;
              _applyFilters();
            },
          );
          final period = DropdownButtonFormField<String>(
            initialValue: _periodFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
              DropdownMenuItem(value: 'semana', child: Text('Esta semana')),
              DropdownMenuItem(value: 'atrasados', child: Text('Atrasados')),
              DropdownMenuItem(value: 'todos', child: Text('Todos')),
              DropdownMenuItem(
                value: 'concluidos',
                child: Text('Conclu\u00eddos'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _periodFilter = value;
              _applyFilters();
            },
          );
          final status = DropdownButtonFormField<String>(
            initialValue: _statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'todos', child: Text('Todas situa\u00e7\u00f5es')),
              DropdownMenuItem(value: 'responder', child: Text('Responder')),
              DropdownMenuItem(
                value: 'sem_resposta',
                child: Text('Sem resposta'),
              ),
              DropdownMenuItem(
                value: 'aguardando_cliente',
                child: Text('Aguardando cliente'),
              ),
              DropdownMenuItem(
                  value: 'concluido', child: Text('Conclu\u00eddo')),
            ],
            onChanged: (value) {
              if (value == null) return;
              _statusFilter = value;
              _applyFilters();
            },
          );
          final refresh = IconButton(
            onPressed: _loadItems,
            icon: const Icon(Icons.refresh, color: Color(0xFF0F62AC)),
            tooltip: 'Atualizar',
          );

          return Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: compact
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 4),
                          refresh,
                        ],
                      ),
                      const SizedBox(height: 8),
                      period,
                      const SizedBox(height: 8),
                      status,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 10),
                      SizedBox(width: 180, child: period),
                      const SizedBox(width: 10),
                      SizedBox(width: 220, child: status),
                      refresh,
                    ],
                  ),
          );
        },
      );

  Widget _buildFollowupCard(AgendaFollowupModel item) {
    final color = _statusColor(item.status);
    final overdue = _isOverdue(item);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: overdue ? Colors.red.shade300 : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Checkbox(
              value: item.concluido,
              onChanged: (_) => _toggleCompleted(item),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.clienteNome,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            decoration: item.concluido
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusLabels[item.status] ?? item.status,
                          style: TextStyle(color: color, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(item.assunto, style: const TextStyle(fontSize: 13)),
                  if (item.observacoes.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.observacoes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _meta(
                        overdue ? Icons.warning_amber : Icons.schedule,
                        DateFormat('dd/MM/yyyy HH:mm')
                            .format(item.agendadoPara),
                        overdue ? Colors.red : Colors.grey,
                      ),
                      if (item.telefone.isNotEmpty)
                        _meta(
                            Icons.phone_outlined, item.telefone, Colors.green),
                      if (item.periodicidade != 'unico')
                        _meta(
                          Icons.repeat,
                          _periodicityLabels[item.periodicidade] ??
                              item.periodicidade,
                          Colors.indigo,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (item.telefone.isNotEmpty)
              IconButton(
                onPressed: () => _openWhatsApp(item),
                icon: const Icon(Icons.chat, color: Colors.green),
                tooltip: 'Abrir WhatsApp',
              ),
            IconButton(
              onPressed: () => _openEditor(item: item),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
            ),
            IconButton(
              onPressed: () => _delete(item),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Excluir',
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      );

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'Nenhum acompanhamento neste período',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('Registrar acompanhamento'),
            ),
          ],
        ),
      );
}
