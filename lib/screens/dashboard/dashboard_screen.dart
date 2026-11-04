import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Telas - imports diretos
import '../quote/quote_approval_screen.dart';
import '../production/production_screen.dart';
import '../agenda/agenda_screen.dart';
import '../order/orders_screen.dart';

// Repositories
import '../../services/order_repository.dart';
import '../../services/agenda_followup_repository.dart';

// Models
import '../../models/order_model.dart';

// Providers
import '../../providers/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigateToSection});

  final ValueChanged<int>? onNavigateToSection;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

// CORRIGIDO: TickerProviderStateMixin (suporte a múltiplos AnimationControllers)
class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, BackgroundRefreshMixin<DashboardScreen> {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Controlador para piscar o alerta
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  final OrderRepository _orderRepo = OrderRepository();
  final AgendaFollowupRepository _agendaRepo = AgendaFollowupRepository();

  // Dados do banco
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // Resumo
  int _pedidosProducao = 0;
  int _orcamentosPendentes = 0;
  int _agendaNotificacoes = 0;
  int _agendaAtrasados = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // ANIMAÇÃO DE PISCAR PARA O ALERTA
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _blinkAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _blinkController,
        curve: Curves.easeInOut,
      ),
    );
    _blinkController.repeat(reverse: true);

    _animationController.forward();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadDashboardData();

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final ordersFuture = _orderRepo.getAll();
      final agendaFuture = _agendaRepo.getAll();
      _orders = await ordersFuture;
      final agenda = await agendaFuture;

      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final today = DateTime(now.year, now.month, now.day);
      _agendaNotificacoes = agenda
          .where(
              (item) => !item.concluido && item.agendadoPara.isBefore(tomorrow))
          .length;
      _agendaAtrasados = agenda
          .where((item) => !item.concluido && item.agendadoPara.isBefore(today))
          .length;

      _processData();
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      print('Erro ao carregar dashboard: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao carregar dados: $e';
      });
    }
  }

  void _processData() {
    _orders.sort((a, b) => b.dataCriacao.compareTo(a.dataCriacao));
    _pedidosProducao = _orders
        .where((o) =>
            o.tipo == 'OS' &&
            (o.status == 'pagamento_recebido' ||
                o.status == 'em_producao' ||
                o.status == 'pronto'))
        .length;

    // Orçamentos são contabilizados separadamente das ordens de produção.
    _orcamentosPendentes = _orders
        .where(
          (o) => o.tipo == 'ORCAMENTO' && o.status == 'aguardando_pagamento',
        )
        .length;
  }

  void _navigateTo(
    BuildContext context,
    Widget screen, {
    required int sectionIndex,
  }) {
    final navigateInShell = widget.onNavigateToSection;
    if (navigateInShell != null) {
      navigateInShell(sectionIndex);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canAccessAgenda = auth.hasPermission('agenda');

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 64, color: Colors.orange),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage,
                              style: const TextStyle(color: Colors.orange),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadDashboardData,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F62AC),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            _buildWelcomeHeader(auth),
                            const SizedBox(height: 24),
                            _buildAlertaOrcamentos(),
                            if (canAccessAgenda && _agendaNotificacoes > 0) ...[
                              const SizedBox(height: 12),
                              _buildAlertaAgenda(),
                            ],
                            const SizedBox(height: 16),
                            _buildKPIGrid(canAccessAgenda: canAccessAgenda),
                            const SizedBox(height: 24),
                            _buildRecentOrders(),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertaAgenda() {
    if (_agendaNotificacoes == 0) return const SizedBox.shrink();

    final detail = _agendaAtrasados > 0
        ? '$_agendaAtrasados atrasado(s) e ${_agendaNotificacoes - _agendaAtrasados} para hoje'
        : '$_agendaNotificacoes compromisso(s) para hoje';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateTo(
          context,
          const AgendaScreen(),
          sectionIndex: 17,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _agendaAtrasados > 0
                ? const Color(0xFFD32F2F)
                : const Color(0xFF7B1FA2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_note, color: Colors.white, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AGENDA: $_agendaNotificacoes NOTIFICAÇÃO(ÕES)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$detail • Clique para abrir a Agenda',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  // ALERTA PISCANDO PARA ORÇAMENTOS PENDENTES
  Widget _buildAlertaOrcamentos() {
    if (_orcamentosPendentes == 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _blinkAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _blinkAnimation.value,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF4500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: InkWell(
              onTap: () => _navigateTo(
                context,
                const QuoteApprovalScreen(),
                sectionIndex: 15,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_active,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_orcamentosPendentes ORÇAMENTO(S) PENDENTE(S)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Clique aqui para aprovar ou visualizar',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Ver',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader(AuthProvider auth) {
    final userName = auth.currentUser?.fullName ?? 'Usuário';
    final notificationCount = _orcamentosPendentes +
        (auth.hasPermission('agenda') ? _agendaNotificacoes : 0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F62AC).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.print, size: 32, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, $userName!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        auth.isAdmin ? 'Administrador' : 'Usuário',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Sistema para Comunicação Visual',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                const Icon(Icons.notifications, color: Colors.white, size: 20),
                if (notificationCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$notificationCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 6,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // KPI GRID - APENAS PRODUÇÃO E ORÇAMENTOS
  Widget _buildKPIGrid({required bool canAccessAgenda}) {
    final kpis = [
      {
        'title': 'Em Produção',
        'value': '$_pedidosProducao',
        'icon': Icons.factory,
        'color': Colors.blue,
        'subtitle': 'Pedidos em andamento',
        'screen': const ProductionScreen(),
        'sectionIndex': 4,
      },
      {
        'title': 'Orçamentos Pendentes',
        'value': '$_orcamentosPendentes',
        'icon': Icons.receipt_long,
        'color': _orcamentosPendentes > 0 ? Colors.orange : Colors.grey,
        'subtitle': _orcamentosPendentes > 0
            ? '$_orcamentosPendentes aguardando aprovação'
            : 'Nenhum orçamento pendente',
        'screen': const QuoteApprovalScreen(),
        'sectionIndex': 15,
      },
      if (canAccessAgenda)
        {
          'title': 'Agenda',
          'value': '$_agendaNotificacoes',
          'icon': Icons.calendar_month,
          'color': _agendaAtrasados > 0 ? Colors.red : Colors.purple,
          'subtitle': _agendaNotificacoes > 0
              ? (_agendaAtrasados > 0
                  ? '$_agendaAtrasados atrasado(s); abra para acompanhar'
                  : 'Compromissos de hoje')
              : 'Nenhuma notificação para hoje',
          'screen': const AgendaScreen(),
          'sectionIndex': 17,
        },
    ];

    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: constraints.maxWidth < 700 ? 1 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: constraints.maxWidth < 700 ? 3.2 : 2.8,
        children: kpis.map((kpi) {
          return _buildKPICard(
            title: kpi['title'] as String,
            value: kpi['value'] as String,
            icon: kpi['icon'] as IconData,
            color: kpi['color'] as Color,
            subtitle: kpi['subtitle'] as String,
            onTap: () => _navigateTo(
              context,
              kpi['screen'] as Widget,
              sectionIndex: kpi['sectionIndex'] as int,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _orcamentosPendentes > 0 && title.contains('Orçamentos')
                    ? Colors.orange
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentOrders() {
    final recentOrders = _orders.where((order) => order.tipo == 'OS').take(5);
    if (recentOrders.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Nenhum pedido encontrado',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Últimos Pedidos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: () => _navigateTo(
                    context,
                    const OrdersScreen(),
                    sectionIndex: 18,
                  ),
                  child: const Text(
                    'Ver todos >',
                    style: TextStyle(color: Color(0xFF0F62AC)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        'Pedido',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Cliente',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Valor',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Status',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Data',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...recentOrders.map((order) {
              String formattedDate = 'Data inválida';
              try {
                formattedDate = DateFormat('dd/MM/yyyy')
                    .format(DateTime.parse(order.dataCriacao));
              } catch (_) {
                formattedDate = '—';
              }
              final status = _traduzirStatus(order.status);
              final statusColor = _getStatusColor(order.status);

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          order.numero,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          order.clienteNome ?? 'Não informado',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'R\$ ${order.valorTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          formattedDate,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _traduzirStatus(String status) {
    final traducoes = {
      'aguardando_pagamento': 'Pendente',
      'pagamento_recebido': 'Recebido',
      'em_producao': 'Em Produção',
      'pronto': 'Pronto',
      'entregue': 'Entregue',
      'cancelado': 'Cancelado',
    };
    return traducoes[status] ?? status;
  }

  Color _getStatusColor(String status) {
    final colors = {
      'aguardando_pagamento': Colors.orange,
      'pagamento_recebido': Colors.green,
      'em_producao': Colors.blue,
      'pronto': Colors.purple,
      'entregue': Colors.green,
      'cancelado': Colors.red,
    };
    return colors[status] ?? Colors.grey;
  }
}
