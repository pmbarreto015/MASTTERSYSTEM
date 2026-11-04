import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import '../../models/employee_model.dart';
import '../../models/ponto_model.dart';
import '../../models/holerite_model.dart';
import '../../services/employee_repository.dart';
import '../../services/ponto_repository.dart';
import '../../services/holerite_repository.dart';
import '../../services/folha_pagamento_service.dart';
import '../quote/preview_pdf_screen.dart';
import 'employee_ponto_report.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

// CORRIGIDO: TickerProviderStateMixin
class _EmployeesScreenState extends State<EmployeesScreen>
    with TickerProviderStateMixin, BackgroundRefreshMixin<EmployeesScreen> {
  final EmployeeRepository _repository = EmployeeRepository();
  final PontoRepository _pontoRepository = PontoRepository();
  final HoleriteRepository _holeriteRepository = HoleriteRepository();

  List<EmployeeModel> _employees = [];
  List<EmployeeModel> _filteredEmployees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showActiveOnly = true;
  late AnimationController _animationController;
  late TabController _rhTabController;
  int _rhSection = 0;
  int? _reportEmployeeId;
  int _reportSelectionVersion = 0;

  // Totais
  double get _totalSalarios =>
      _employees.fold(0.0, (sum, e) => sum + (e.salary ?? 0));
  int get _totalAtivos => _employees.where((e) => e.active).length;

  @override
  void initState() {
    super.initState();
    _rhTabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _loadEmployees();
  }

  @override
  void dispose() {
    _rhTabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadEmployees();

  Future<void> _loadEmployees() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final employees = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _applyEmployeeFilters();
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar funcionários: $e');
    }
  }

  void _filterEmployees(String query) {
    setState(() {
      _searchQuery = query;
      _applyEmployeeFilters();
    });
  }

  void _applyEmployeeFilters() {
    final query = _searchQuery.toLowerCase();
    _filteredEmployees = _employees.where((employee) {
      final matchesSearch = query.isEmpty ||
          employee.name.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query) ||
          employee.phone.contains(query) ||
          employee.position.toLowerCase().contains(query) ||
          employee.document.contains(query);
      return matchesSearch && (!_showActiveOnly || employee.active);
    }).toList();
  }

  void _openPontoReport(EmployeeModel employee) {
    setState(() {
      _reportEmployeeId = employee.id;
      _reportSelectionVersion++;
      _rhSection = 1;
    });
    _rhTabController.animateTo(1);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  // IMPRIMIR FOLHA DE PAGAMENTO
  Future<void> _imprimirFolhaPagamento() async {
    try {
      final mesRef = DateFormat('yyyy-MM').format(DateTime.now());
      final todosHolerites = <HoleriteModel>[];

      for (var emp in _employees) {
        final h =
            await _holeriteRepository.getByEmployeeAndMonth(emp.id!, mesRef);
        if (h != null) {
          todosHolerites.add(h);
        }
      }

      if (todosHolerites.isEmpty) {
        _showError('Nenhum holerite encontrado para o mês atual.');
        return;
      }

      final service = FolhaPagamentoService();
      await service.imprimirFolhaPagamento(_employees, todosHolerites, mesRef);

      _showSuccess('Folha de pagamento enviada para impressão!');
    } catch (e) {
      _showError('Erro ao imprimir folha: $e');
    }
  }

  // IMPRIMIR HOLERITE INDIVIDUAL
  Future<void> _imprimirHolerite(EmployeeModel employee) async {
    try {
      final mesRef = DateFormat('yyyy-MM').format(DateTime.now());
      final holerite = await _holeriteRepository.getByEmployeeAndMonth(
        employee.id!,
        mesRef,
      );

      if (holerite == null) {
        _showError('Nenhum holerite encontrado para este funcionário.');
        return;
      }

      final service = FolhaPagamentoService();
      await service.imprimirHolerite(employee, holerite);

      _showSuccess('Holerite enviado para impressão!');
    } catch (e) {
      _showError('Erro ao imprimir holerite: $e');
    }
  }

  // VISUALIZAR HOLERITE
  Future<void> _visualizarHolerite(EmployeeModel employee) async {
    try {
      final mesRef = DateFormat('yyyy-MM').format(DateTime.now());
      final holerite = await _holeriteRepository.getByEmployeeAndMonth(
        employee.id!,
        mesRef,
      );

      if (holerite == null) {
        _showError('Nenhum holerite encontrado para este funcionário.');
        return;
      }

      final service = FolhaPagamentoService();
      final bytes = await service.gerarHoleriteIndividual(employee, holerite);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPdfScreen(
            pdfBytes: bytes,
            titulo: 'Holerite - ${employee.name}',
          ),
        ),
      );
    } catch (e) {
      _showError('Erro ao visualizar holerite: $e');
    }
  }

  // GERAR HOLERITE COM CONFIRMAÇÃO
  Future<void> _gerarHolerite(EmployeeModel employee) async {
    final mesRef = DateFormat('yyyy-MM').format(DateTime.now());

    // Verificar se já existe holerite para este mês
    final existe = await _holeriteRepository.getByEmployeeAndMonth(
      employee.id!,
      mesRef,
    );

    if (existe != null) {
      // Se já existe, perguntar se quer gerar novamente
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Holerite já existe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Já existe um holerite para ${employee.name} no mês ${DateFormat('MMMM/yyyy').format(DateTime.now())}.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Deseja gerar um novo?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'O holerite existente será substituído.',
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
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Gerar Novamente'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    // Buscar pontos do funcionário no mês
    final pontos = await _pontoRepository.getByEmployeeAndMonth(
      employee.id!,
      mesRef,
    );

    // Calcular horas
    final totalHoras =
        pontos.fold<double>(0.0, (sum, p) => sum + p.horasTrabalhadas);
    final totalHorasExtras =
        pontos.fold<double>(0.0, (sum, p) => sum + p.horasExtras);

    final salarioBase = employee.salary ?? 0;
    final valorHora = salarioBase / 220;
    final valorHoraExtra = valorHora * 1.5;
    final totalHorasExtrasValor = totalHorasExtras * valorHoraExtra;
    final salarioBruto = salarioBase + totalHorasExtrasValor;

    final inss = salarioBruto * 0.11;
    final irrf = salarioBruto > 1903.98 ? (salarioBruto * 0.075) : 0.0;
    final descontos = inss + irrf;
    final salarioLiquido = salarioBruto - descontos;

    // Criar ou atualizar holerite
    if (existe != null) {
      // Atualizar holerite existente
      final holeriteAtualizado = existe.copyWith(
        salarioBase: salarioBase,
        horasTrabalhadas: totalHoras,
        horasExtras: totalHorasExtras,
        valorHora: valorHora,
        valorHoraExtra: valorHoraExtra,
        totalHorasExtras: totalHorasExtrasValor,
        salarioBruto: salarioBruto,
        descontos: descontos,
        inss: inss,
        irrf: irrf,
        salarioLiquido: salarioLiquido,
        pago: false,
        updatedAt: DateTime.now(),
      );

      await _holeriteRepository.update(holeriteAtualizado);
      _showSuccess('Holerite atualizado com sucesso!');
    } else {
      // Criar novo holerite
      final holerite = HoleriteModel(
        employeeId: employee.id!,
        employeeName: employee.name,
        mesReferencia: mesRef,
        salarioBase: salarioBase,
        horasTrabalhadas: totalHoras,
        horasExtras: totalHorasExtras,
        valorHora: valorHora,
        valorHoraExtra: valorHoraExtra,
        totalHorasExtras: totalHorasExtrasValor,
        salarioBruto: salarioBruto,
        descontos: descontos,
        inss: inss,
        irrf: irrf,
        salarioLiquido: salarioLiquido,
        pago: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _holeriteRepository.create(holerite);
      _showSuccess('Holerite gerado com sucesso!');
    }

    _loadEmployees();
  }

  // DIÁLOGO DE PONTO
  void _showPontoDialog(EmployeeModel employee) async {
    final hoje = DateTime.now();
    final ponto = await _pontoRepository.getTodayByEmployee(employee.id!);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.access_time,
                          color: Color(0xFF0F62AC)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ponto do Dia - ${employee.name}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            DateFormat('dd/MM/yyyy').format(hoje),
                            style: const TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),

                // Status do Ponto
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (ponto?.statusColor ?? Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ponto?.statusColor ?? Colors.grey,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ponto?.entrada1 == null
                            ? Icons.access_time
                            : ponto?.saida1 == null
                                ? Icons.work
                                : ponto?.entrada2 == null
                                    ? Icons.free_breakfast
                                    : Icons.check_circle,
                        color: ponto?.statusColor ?? Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ponto?.statusLabel ?? 'Aguardando registro',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: ponto?.statusColor ?? Colors.grey,
                              ),
                            ),
                            if (ponto != null)
                              Text(
                                'Horas trabalhadas: ${ponto.horasTrabalhadasFormatada}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Registros do dia
                _buildRegistroCard('Entrada 1', ponto?.entrada1),
                _buildRegistroCard('Saída 1', ponto?.saida1),
                _buildRegistroCard('Entrada 2', ponto?.entrada2),
                _buildRegistroCard('Saída 2', ponto?.saida2),

                const Spacer(),

                // Botão de Registrar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final agora = DateTime.now();
                      final novoPonto = ponto != null
                          ? await _registrarPonto(ponto, agora)
                          : await _criarPonto(employee, agora);

                      if (novoPonto != null) {
                        Navigator.pop(context);
                        _showSuccess('Ponto registrado com sucesso!');
                        _loadEmployees();
                      }
                    },
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(
                      ponto == null
                          ? 'Registrar Entrada 1'
                          : ponto.entrada1 == null
                              ? 'Registrar Entrada 1'
                              : ponto.saida1 == null
                                  ? 'Registrar Saída 1'
                                  : ponto.entrada2 == null
                                      ? 'Registrar Entrada 2'
                                      : ponto.saida2 == null
                                          ? 'Registrar Saída 2'
                                          : 'Dia Finalizado',
                      style: const TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F62AC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<PontoModel?> _criarPonto(
      EmployeeModel employee, DateTime agora) async {
    final ponto = PontoModel(
      employeeId: employee.id!,
      employeeName: employee.name,
      data: agora,
      entrada1: agora,
      createdAt: agora,
      updatedAt: agora,
    );
    return await _pontoRepository.create(ponto);
  }

  Future<PontoModel?> _registrarPonto(PontoModel ponto, DateTime agora) async {
    if (ponto.entrada1 == null) {
      ponto.entrada1 = agora;
    } else if (ponto.saida1 == null) {
      ponto.saida1 = agora;
      final diff = agora.difference(ponto.entrada1!);
      ponto.horasTrabalhadas += diff.inMinutes / 60;
    } else if (ponto.entrada2 == null) {
      ponto.entrada2 = agora;
    } else if (ponto.saida2 == null) {
      ponto.saida2 = agora;
      final diff = agora.difference(ponto.entrada2!);
      ponto.horasTrabalhadas += diff.inMinutes / 60;

      if (ponto.horasTrabalhadas > 8) {
        ponto.horasExtras = ponto.horasTrabalhadas - 8;
      }
    } else {
      return null;
    }
    ponto.updatedAt = agora;
    return await _pontoRepository.update(ponto);
  }

  Widget _buildRegistroCard(String label, DateTime? registro) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              registro != null
                  ? DateFormat('HH:mm:ss').format(registro)
                  : '---',
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    registro != null ? FontWeight.bold : FontWeight.normal,
                color: registro != null
                    ? const Color(0xFF0F62AC)
                    : Colors.grey.shade400,
              ),
            ),
          ),
          if (registro != null)
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
        ],
      ),
    );
  }

  // DIÁLOGO DE HOLERITE (Atualizado)
  void _showHoleriteDialog(EmployeeModel employee) async {
    final holerites = await _holeriteRepository.getByEmployeeId(employee.id!);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.description, color: Colors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Holerites - ${employee.name}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${holerites.length} holerite(s) disponível(eis)',
                            style: const TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),

                // BOTÃO GERAR HOLERITE
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _gerarHolerite(employee);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Gerar Novo Holerite'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F62AC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: holerites.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum holerite encontrado',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _gerarHolerite(employee);
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Gerar Holerite'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: holerites.length,
                          itemBuilder: (context, index) {
                            final h = holerites[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: h.pago
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    h.pago ? Icons.check_circle : Icons.pending,
                                    color:
                                        h.pago ? Colors.green : Colors.orange,
                                  ),
                                ),
                                title: Text(h.mesReferenciaFormatada),
                                subtitle: Text(h.salarioLiquidoFormatado),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: h.pago
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    h.pago ? 'Pago' : 'Pendente',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          h.pago ? Colors.green : Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                onTap: () => _showHoleriteDetalhe(h),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showHoleriteDetalhe(HoleriteModel holerite) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.description, color: Colors.green),
            ),
            const SizedBox(width: 12),
            Text('Holerite - ${holerite.mesReferenciaFormatada}'),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Funcionário: ${holerite.employeeName}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                _buildHoleriteItem(
                    'Salário Base', holerite.salarioBaseFormatado),
                _buildHoleriteItem('Horas Trabalhadas',
                    '${holerite.horasTrabalhadas.toStringAsFixed(2)}h'),
                _buildHoleriteItem('Horas Extras',
                    '${holerite.horasExtras.toStringAsFixed(2)}h'),
                _buildHoleriteItem(
                    'Valor Hora',
                    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                        .format(holerite.valorHora)),
                _buildHoleriteItem(
                    'Valor Hora Extra',
                    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                        .format(holerite.valorHoraExtra)),
                _buildHoleriteItem(
                    'Total Horas Extras',
                    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                        .format(holerite.totalHorasExtras)),
                const Divider(),
                _buildHoleriteItem(
                    'Salário Bruto', holerite.salarioBrutoFormatado,
                    bold: true),
                _buildHoleriteItem('INSS', holerite.inssFormatado),
                _buildHoleriteItem('IRRF', holerite.irrfFormatado),
                _buildHoleriteItem('Descontos', holerite.descontosFormatado),
                const Divider(),
                _buildHoleriteItem(
                    'Salário Líquido', holerite.salarioLiquidoFormatado,
                    bold: true, color: Colors.green),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          if (!holerite.pago)
            ElevatedButton.icon(
              onPressed: () async {
                await _holeriteRepository.marcarPago(holerite.id!);
                Navigator.pop(context);
                _showSuccess('Holerite marcado como pago!');
                _loadEmployees();
              },
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Marcar como Pago'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHoleriteItem(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  // FORMULÁRIO DE FUNCIONÁRIO
  Future<void> _showEmployeeForm({EmployeeModel? employee}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: employee?.name ?? '');
    final documentController =
        TextEditingController(text: employee?.document ?? '');
    final phoneController = TextEditingController(text: employee?.phone ?? '');
    final emailController = TextEditingController(text: employee?.email ?? '');
    final positionController =
        TextEditingController(text: employee?.position ?? '');
    final salaryController = TextEditingController(
      text:
          employee?.salary != null ? employee!.salary!.toStringAsFixed(2) : '',
    );
    final hireDateController = TextEditingController(
      text: employee?.hireDate != null
          ? DateFormat('dd/MM/yyyy').format(employee!.hireDate!)
          : '',
    );
    bool isActive = employee?.active ?? true;
    DateTime? hireDate = employee?.hireDate;

    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                employee == null ? Icons.person_add : Icons.edit,
                color: const Color(0xFF0F62AC),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              employee == null ? 'Novo Funcionário' : 'Editar Funcionário',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome Completo *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: documentController,
                  decoration: const InputDecoration(
                    labelText: 'CPF',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: positionController,
                  decoration: const InputDecoration(
                    labelText: 'Cargo *',
                    prefixIcon: Icon(Icons.work_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: salaryController,
                        decoration: const InputDecoration(
                          labelText: 'Salário (R\$))',
                          prefixIcon: Icon(Icons.monetization_on),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: hireDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            hireDate = date;
                            hireDateController.text =
                                DateFormat('dd/MM/yyyy').format(date);
                            setState(() {});
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data Admissão *',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            hireDateController.text.isEmpty
                                ? 'Selecione uma data'
                                : hireDateController.text,
                            style: TextStyle(
                              color: hireDateController.text.isEmpty
                                  ? Colors.grey
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Switch(
                      value: isActive,
                      onChanged: (value) => isActive = value,
                      activeThumbColor: const Color(0xFF0F62AC),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isActive ? 'Ativo' : 'Inativo',
                      style: TextStyle(
                        color: isActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final employeeData = employee != null
                    ? employee.copyWith(
                        name: nameController.text.trim(),
                        document: documentController.text.trim(),
                        phone: phoneController.text.trim(),
                        email: emailController.text.trim(),
                        position: positionController.text.trim(),
                        salary: double.tryParse(
                            salaryController.text.replaceAll(',', '.')),
                        hireDate: hireDate,
                        active: isActive,
                      )
                    : EmployeeModel.create(
                        name: nameController.text.trim(),
                        document: documentController.text.trim(),
                        phone: phoneController.text.trim(),
                        email: emailController.text.trim(),
                        position: positionController.text.trim(),
                        salary: double.tryParse(
                            salaryController.text.replaceAll(',', '.')),
                        hireDate: hireDate ?? DateTime.now(),
                        active: isActive,
                      );

                if (employee == null) {
                  await _repository.create(employeeData);
                } else {
                  await _repository.update(employeeData);
                }
                Navigator.pop(context, true);
                await _loadEmployees();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      employee == null
                          ? 'Funcionário criado com sucesso!'
                          : 'Funcionário atualizado com sucesso!',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F62AC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(employee == null ? 'Criar Funcionário' : 'Atualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployee(EmployeeModel employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${employee.name}"?'),
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
      await _repository.delete(employee.id!);
      await _loadEmployees();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Funcionário excluído com sucesso!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleActive(EmployeeModel employee) async {
    final updated = employee.copyWith(active: !employee.active);
    await _repository.update(updated);
    await _loadEmployees();
  }

  void _printPayroll() {
    _imprimirFolhaPagamento();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_outlined, color: Color(0xFF0F62AC)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recursos Humanos',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Text(
                            'Equipe, controle de ponto e folha de pagamento'),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loadEmployees,
                    tooltip: 'Atualizar funcionários',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildStatCard('Funcionários', '${_employees.length}',
                      Icons.people, Colors.blue),
                  _buildStatCard('Ativos', '$_totalAtivos', Icons.check_circle,
                      Colors.green),
                  _buildStatCard(
                      'Inativos',
                      '${_employees.length - _totalAtivos}',
                      Icons.cancel,
                      Colors.red),
                  _buildStatCard(
                      'Salários',
                      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                          .format(_totalSalarios),
                      Icons.attach_money,
                      Colors.orange),
                  OutlinedButton.icon(
                    onPressed: _employees.isEmpty ? null : _printPayroll,
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Folha do mês atual'),
                  ),
                ],
              ),
            ],
          ),
        ),
        TabBar(
          controller: _rhTabController,
          onTap: (index) => setState(() => _rhSection = index),
          tabs: const [
            Tab(icon: Icon(Icons.badge_outlined), text: 'Funcionários'),
            Tab(
                icon: Icon(Icons.fact_check_outlined),
                text: 'Relatórios de ponto'),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _rhSection,
            children: [
              _buildEmployees(context),
              EmployeePontoReport(
                employees: _employees,
                initialEmployeeId: _reportEmployeeId,
                selectionVersion: _reportSelectionVersion,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployees(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Barra de busca
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar funcionário...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: _filterEmployees,
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Ativos'),
                  selected: _showActiveOnly,
                  onSelected: (value) {
                    setState(() {
                      _showActiveOnly = value;
                      _applyEmployeeFilters();
                    });
                  },
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedColor: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                  checkmarkColor: const Color(0xFF0F62AC),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showEmployeeForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEmployees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum funcionário cadastrado'
                                  : 'Nenhum funcionário encontrado',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: () => _showEmployeeForm(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar Funcionário'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadEmployees,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredEmployees.length,
                          itemBuilder: (context, index) {
                            final employee = _filteredEmployees[index];
                            final isActive = employee.active;
                            final hireDate = employee.hireDate != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(employee.hireDate!)
                                : 'N/A';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isActive
                                      ? Colors.grey.shade200
                                      : Colors.red.shade300,
                                  width: isActive ? 1 : 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Avatar
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: isActive
                                              ? [
                                                  const Color(0xFF0F62AC),
                                                  const Color(0xFF4589FF)
                                                ]
                                              : [
                                                  Colors.grey.shade400,
                                                  Colors.grey.shade600
                                                ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          employee.name.isEmpty
                                              ? '?'
                                              : employee.name[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Informações
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                employee.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: isActive
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (!isActive)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: const Text(
                                                    'Inativo',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            employee.position,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'R\$ ${employee.salary?.toStringAsFixed(2) ?? '0,00'}',
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  hireDate,
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.orange,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Ações
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              _openPontoReport(employee),
                                          icon: const Icon(
                                              Icons.fact_check_outlined,
                                              size: 16),
                                          label:
                                              const Text('Relatório de ponto'),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.access_time,
                                                  size: 18,
                                                  color: Color(0xFF0F62AC)),
                                              onPressed: () =>
                                                  _showPontoDialog(employee),
                                              tooltip: 'Ponto',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.description,
                                                  size: 18,
                                                  color: Colors.green),
                                              onPressed: () =>
                                                  _showHoleriteDialog(employee),
                                              tooltip: 'Holerite',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.print,
                                                  size: 18, color: Colors.blue),
                                              onPressed: () =>
                                                  _imprimirHolerite(employee),
                                              tooltip: 'Imprimir Holerite',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.visibility,
                                                  size: 18,
                                                  color: Colors.purple),
                                              onPressed: () =>
                                                  _visualizarHolerite(employee),
                                              tooltip: 'Visualizar Holerite',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.toggle_on,
                                                color: isActive
                                                    ? Colors.green
                                                    : Colors.grey,
                                                size: 24,
                                              ),
                                              onPressed: () =>
                                                  _toggleActive(employee),
                                              tooltip: isActive
                                                  ? 'Desativar'
                                                  : 'Ativar',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.edit,
                                                  size: 16, color: Colors.grey),
                                              onPressed: () =>
                                                  _showEmployeeForm(
                                                      employee: employee),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
                                                  color: Colors.red),
                                              onPressed: () =>
                                                  _deleteEmployee(employee),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
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

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            ' $label',
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
