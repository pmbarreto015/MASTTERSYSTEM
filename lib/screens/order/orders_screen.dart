import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/background_refresh_mixin.dart';
import '../../models/customer_model.dart';
import '../../models/order_model.dart';
import '../../models/seller_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/customer_repository.dart';
import '../../services/impressao_service.dart';
import '../../services/order_repository.dart';
import '../../services/sales_repository.dart';
import '../../services/system_user_repository.dart';
import '../quote/preview_pdf_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with BackgroundRefreshMixin<OrdersScreen> {
  static const _blue = Color(0xFF0F62AC);
  static const _statuses = <String, String>{
    'aguardando_pagamento': 'Aguardando pagamento',
    'pagamento_recebido': 'Pagamento recebido',
    'em_producao': 'Em produção',
    'pronto': 'Pronto',
    'entregue': 'Entregue',
    'cancelado': 'Cancelado',
  };

  static const _filterStatuses = <String, String>{
    'aguardando_pagamento': 'Aguardando pagamento',
    'pagamento_recebido': 'Pagamento recebido',
    'em_producao': 'Em produção',
    'entregue': 'Entregue',
    'cancelado': 'Cancelado',
  };

  String _orderStatusLabel(OrderModel order) =>
      _statuses[order.orderStatusGroup] ?? order.orderStatusGroup;

  final OrderRepository _repository = OrderRepository();
  final CustomerRepository _customerRepository = CustomerRepository();
  final SalesRepository _salesRepository = SalesRepository();
  final SystemUserRepository _userRepository = SystemUserRepository();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currency =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _date = DateFormat('dd/MM/yyyy');

  List<OrderModel> _orders = [];
  List<CustomerModel> _customers = [];
  bool _loading = true;
  String? _error;
  String _typeFilter = 'TODOS';
  String _statusFilter = 'todos';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadData(showLoading: false);

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _repository.getAll(),
        _customerRepository.getAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] as List<OrderModel>;
        _customers = results[1] as List<CustomerModel>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os pedidos: $error';
      });
    }
  }

  List<OrderModel> get _filteredOrders {
    final query = _searchController.text.trim().toLowerCase();
    return _orders.where((order) {
      final matchesQuery = query.isEmpty ||
          order.numero.toLowerCase().contains(query) ||
          (order.clienteNome ?? '').toLowerCase().contains(query);
      final matchesType = _typeFilter == 'TODOS' || order.tipo == _typeFilter;
      final matchesStatus =
          _statusFilter == 'todos' || order.orderStatusGroup == _statusFilter;
      return matchesQuery && matchesType && matchesStatus;
    }).toList();
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _formatDate(String? value) {
    final parsed = _parseDate(value);
    return parsed == null ? '—' : _date.format(parsed);
  }

  bool _isOverdue(OrderModel order) {
    if (!order.isAcceptedSale || order.status == 'entregue') return false;
    final delivery = _parseDate(order.dataEntrega);
    if (delivery == null) return false;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final deliveryOnly = DateTime(delivery.year, delivery.month, delivery.day);
    return deliveryOnly.isBefore(todayOnly);
  }

  Widget _datesCell(OrderModel order) {
    final overdue = _isOverdue(order);
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(order.dataCriacao),
            style: const TextStyle(fontSize: 12),
          ),
          if (order.dataEntrega != null)
            Text(
              'Entrega ${_formatDate(order.dataEntrega)}',
              style: TextStyle(
                fontSize: 10,
                color: overdue ? Colors.red : Colors.grey,
                fontWeight: overdue ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'aguardando_pagamento' => Colors.orange,
        'pagamento_recebido' => Colors.blue,
        'em_producao' => Colors.deepPurple,
        'pronto' => Colors.teal,
        'entregue' => Colors.green,
        'cancelado' => Colors.red,
        _ => Colors.grey,
      };

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<bool> _requestAuthorization({
    required String permission,
    required String action,
  }) async {
    final currentUser =
        Provider.of<AuthProvider>(context, listen: false).currentUser;
    final usernameController =
        TextEditingController(text: currentUser?.username ?? '');
    final passwordController = TextEditingController();
    var obscurePassword = true;
    var validating = false;
    String? errorText;

    final authorized = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.lock_outline, color: _blue),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Autorizar $action')),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informe as credenciais de um usuário autorizado para continuar.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: usernameController,
                      enabled: !validating,
                      autofocus: usernameController.text.isEmpty,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      enabled: !validating,
                      autofocus: usernameController.text.isNotEmpty,
                      obscureText: obscurePassword,
                      onSubmitted: validating
                          ? null
                          : (_) async {
                              await _validateAuthorization(
                                dialogContext: dialogContext,
                                setDialogState: setDialogState,
                                usernameController: usernameController,
                                passwordController: passwordController,
                                permission: permission,
                                setValidating: (value) => validating = value,
                                setError: (value) => errorText = value,
                              );
                            },
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          onPressed: validating
                              ? null
                              : () => setDialogState(
                                  () => obscurePassword = !obscurePassword),
                          icon: Icon(obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(errorText!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: validating
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: validating
                      ? null
                      : () => _validateAuthorization(
                            dialogContext: dialogContext,
                            setDialogState: setDialogState,
                            usernameController: usernameController,
                            passwordController: passwordController,
                            permission: permission,
                            setValidating: (value) => validating = value,
                            setError: (value) => errorText = value,
                          ),
                  icon: validating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(validating ? 'Verificando...' : 'Autorizar'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    usernameController.dispose();
    passwordController.dispose();
    return authorized;
  }

  Future<void> _validateAuthorization({
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
    required String permission,
    required ValueChanged<bool> setValidating,
    required ValueChanged<String?> setError,
  }) async {
    if (usernameController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      setDialogState(() => setError('Informe o usuário e a senha.'));
      return;
    }

    setDialogState(() {
      setValidating(true);
      setError(null);
    });
    try {
      final user = await _userRepository.authenticate(
        usernameController.text,
        passwordController.text,
      );
      if (!dialogContext.mounted) return;
      if (user == null) {
        setDialogState(() {
          setValidating(false);
          setError('Usuário ou senha incorretos.');
        });
        return;
      }
      if (!user.can(permission)) {
        setDialogState(() {
          setValidating(false);
          setError('Este usuário não possui permissão para esta ação.');
        });
        return;
      }
      Navigator.pop(dialogContext, true);
    } catch (error) {
      debugPrint('Falha ao validar autorização: $error');
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setValidating(false);
        setError(
          'Não foi possível validar as credenciais. Tente novamente.',
        );
      });
    }
  }

  Future<void> _authorizeAndEdit(OrderModel order) async {
    final authorized = await _requestAuthorization(
      permission: 'pedidos_alterar',
      action: 'alteração do pedido',
    );
    if (authorized && mounted) await _editOrder(order);
  }

  Future<void> _openPrintDocuments(OrderModel order) async {
    _showMessage('Preparando os documentos do pedido...');
    try {
      final current = order.id == null
          ? order
          : (await _repository.getById(order.id!) ?? order);

      CustomerModel? customer;
      if (current.clienteId != null) {
        customer = await _customerRepository.getById(current.clienteId!);
      }
      customer ??= CustomerModel.create(
        name: current.clienteNome ?? 'Cliente não informado',
        phone: '',
      );

      SellerModel? seller;
      if (current.sellerId != null) {
        seller = await _salesRepository.getById(current.sellerId!);
      }
      seller ??= SellerModel.create(
        name: 'Vendedor não informado',
        phone: '',
        email: '',
        commission: 0,
      );

      final printingService = ImpressaoService();
      final customerBytes =
          await printingService.gerarPdfBytes(current, customer, seller);
      final productionBytes = current.tipo == 'OS'
          ? await printingService.gerarPdfProducaoBytes(
              current,
              customer,
              seller,
            )
          : null;

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewPdfScreen(
            pdfBytes: customerBytes,
            productionPdfBytes: productionBytes,
            titulo: 'Via do cliente • Pedido #${current.numero}',
            productionTitle: 'Ordem de produção #${current.numero}',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Falha ao gerar documentos do pedido: $error');
      _showMessage(
        'Não foi possível gerar os documentos. Confira os dados do cliente e dos itens.',
        error: true,
      );
    }
  }

  String _technicalDetails(OrderItemModel item) {
    if (item.detalhesCusto.trim().isEmpty) return '';
    return item.detalhesCusto
        .split('\n')
        .map((line) => line
            .replaceAll(
              RegExp(r'\s*\|\s*Custo\s+R\$\s*[\d.,]+', caseSensitive: false),
              '',
            )
            .replaceAll(
              RegExp(r'\s*\|\s*Venda\s+R\$\s*[\d.,]+', caseSensitive: false),
              '',
            )
            .trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  Future<void> _showDetails(OrderModel order) async {
    final current = order.id == null
        ? order
        : (await _repository.getById(order.id!) ?? order);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogHeader(
                icon: Icons.receipt_long,
                title: 'Pedido ${current.numero}',
                onClose: () => Navigator.pop(context),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 28,
                        runSpacing: 18,
                        children: [
                          _detail(
                              'Cliente', current.clienteNome ?? 'Sem cliente'),
                          _detail(
                              'Documento',
                              current.tipo == 'OS'
                                  ? 'Pedido / OS'
                                  : 'Orçamento'),
                          _detail('Status', _orderStatusLabel(current)),
                          if (current.tipo == 'OS' &&
                              current.orderStatusGroup == 'em_producao')
                            _detail('Etapa de produção',
                                current.productionStatusLabel),
                          _detail(
                              'Criado em', _formatDate(current.dataCriacao)),
                          _detail('Entrega', _formatDate(current.dataEntrega)),
                          _detail('Pagamento', current.formaPagamento),
                          _detail(
                              'Prioridade', _priorityLabel(current.prioridade)),
                          _detail(
                              'Total', _currency.format(current.valorTotal)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Itens (${current.itens.length})',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                      const SizedBox(height: 10),
                      if (current.itens.isEmpty)
                        const Text('Nenhum item cadastrado.')
                      else
                        ...current.itens.map(
                          (item) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: .45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.produtoNome,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      if (item.especificacoes.isNotEmpty)
                                        Text(item.especificacoes,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                      if (item.largura > 0 && item.altura > 0)
                                        Text(
                                          'Medidas: ${item.largura.toStringAsFixed(0)} x ${item.altura.toStringAsFixed(0)} mm',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      if (_technicalDetails(item).isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Composição:\n${_technicalDetails(item)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: Colors.teal),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text('${item.quantidade} x '
                                    '${_currency.format(item.precoUnitario)}'),
                                const SizedBox(width: 24),
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    _currency.format(item.subtotal),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (current.observacoes.trim().isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('Observações',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(current.observacoes),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _openPrintDocuments(current);
                      },
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Imprimir documentos'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _authorizeAndEdit(current);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Alterar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogHeader({
    required IconData icon,
    required String title,
    required VoidCallback onClose,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  List<OrderItemModel> _copyItems(List<OrderItemModel> items) =>
      items.map((item) => OrderItemModel.fromMap(item.toMap())).toList();

  Future<void> _editOrder(OrderModel order) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isClosed = order.status == 'entregue' || order.status == 'cancelado';
    final canReopen = auth.hasPermission('pedidos_reabrir');
    var customerId = order.clienteId;
    if (!_customers.any((customer) => customer.id == customerId)) {
      customerId = null;
    }
    var documentType = order.tipo;
    var status = _statuses.containsKey(order.status)
        ? order.status
        : 'aguardando_pagamento';
    var priority = ['baixa', 'normal', 'alta', 'urgente']
            .contains(order.prioridade.toLowerCase())
        ? order.prioridade.toLowerCase()
        : 'normal';
    var deliveryDate = _parseDate(order.dataEntrega);
    final paymentController = TextEditingController(text: order.formaPagamento);
    final notesController = TextEditingController(text: order.observacoes);
    final items = _copyItems(order.itens);
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogHeader(
                  icon: Icons.edit_note,
                  title: 'Alterar pedido ${order.numero}',
                  onClose: saving ? () {} : () => Navigator.pop(context, false),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 650;
                            final fields = [
                              DropdownButtonFormField<String>(
                                initialValue: documentType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Tipo do documento',
                                    border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'ORCAMENTO',
                                      child:
                                          Text('Orçamento — aguarda aceite')),
                                  DropdownMenuItem(
                                      value: 'OS',
                                      child: Text('OS — venda aceita')),
                                ],
                                onChanged: saving || (isClosed && !canReopen)
                                    ? null
                                    : (value) => setDialogState(() {
                                          documentType = value!;
                                          status = 'aguardando_pagamento';
                                        }),
                              ),
                              DropdownButtonFormField<int>(
                                initialValue: customerId,
                                decoration: const InputDecoration(
                                  labelText: 'Cliente',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: _customers
                                    .where((customer) => customer.id != null)
                                    .map((customer) => DropdownMenuItem(
                                          value: customer.id!,
                                          child: Text(customer.name,
                                              overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: saving
                                    ? null
                                    : (value) => setDialogState(
                                        () => customerId = value),
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: status,
                                decoration: InputDecoration(
                                  labelText: documentType == 'OS'
                                      ? 'Etapa da produção'
                                      : 'Status do fluxo',
                                  helperText: isClosed && !canReopen
                                      ? 'Somente um usuário autorizado pode reabrir este pedido'
                                      : null,
                                  border: const OutlineInputBorder(),
                                ),
                                items: (documentType == 'OS'
                                        ? {
                                            ...OrderModel.productionStatuses,
                                            'cancelado': 'Cancelado',
                                          }
                                        : _statuses)
                                    .entries
                                    .map((entry) => DropdownMenuItem(
                                          value: entry.key,
                                          child: Text(entry.value),
                                        ))
                                    .toList(),
                                onChanged: saving ||
                                        documentType == 'ORCAMENTO' ||
                                        (isClosed && !canReopen)
                                    ? null
                                    : (value) => setDialogState(
                                        () => status = value ?? status),
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: priority,
                                decoration: const InputDecoration(
                                  labelText: 'Prioridade',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'baixa', child: Text('Baixa')),
                                  DropdownMenuItem(
                                      value: 'normal', child: Text('Normal')),
                                  DropdownMenuItem(
                                      value: 'alta', child: Text('Alta')),
                                  DropdownMenuItem(
                                      value: 'urgente', child: Text('Urgente')),
                                ],
                                onChanged: saving
                                    ? null
                                    : (value) => setDialogState(
                                        () => priority = value ?? priority),
                              ),
                              TextFormField(
                                controller: paymentController,
                                enabled: !saving,
                                decoration: const InputDecoration(
                                  labelText: 'Forma de pagamento',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ];
                            if (compact) {
                              return Column(
                                children: fields
                                    .map((field) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: field,
                                        ))
                                    .toList(),
                              );
                            }
                            return GridView.count(
                              crossAxisCount: 2,
                              childAspectRatio: 4.7,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: fields,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: saving
                              ? null
                              : () async {
                                  final selected = await showDatePicker(
                                    context: context,
                                    initialDate: deliveryDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 3650)),
                                  );
                                  if (selected != null) {
                                    setDialogState(
                                        () => deliveryDate = selected);
                                  }
                                },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Data de entrega',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_month),
                            ),
                            child: Text(deliveryDate == null
                                ? 'Não informada'
                                : _date.format(deliveryDate!)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Itens do pedido',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 8),
                        ...items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(item.produtoNome,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 82,
                                    child: TextFormField(
                                      initialValue: item.quantidade.toString(),
                                      enabled: !saving,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Qtd.',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (value) {
                                        final quantity = int.tryParse(value);
                                        if (quantity != null && quantity > 0) {
                                          item.quantidade = quantity;
                                          item.subtotal =
                                              item.precoUnitario * quantity;
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 120,
                                    child: TextFormField(
                                      initialValue:
                                          item.precoUnitario.toStringAsFixed(2),
                                      enabled: !saving,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Valor unit.',
                                        prefixText: 'R\$ ',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (value) {
                                        final price = double.tryParse(
                                            value.replaceAll(',', '.'));
                                        if (price != null && price >= 0) {
                                          item.precoUnitario = price;
                                          item.subtotal =
                                              price * item.quantidade;
                                        }
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: saving
                                        ? null
                                        : () => setDialogState(
                                            () => items.removeAt(index)),
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: 'Remover item',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        TextFormField(
                          controller: notesController,
                          enabled: !saving,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                if (customerId == null) {
                                  _showMessage('Selecione um cliente.',
                                      error: true);
                                  return;
                                }
                                if (items.isEmpty) {
                                  _showMessage(
                                      'O pedido deve possuir pelo menos um item.',
                                      error: true);
                                  return;
                                }
                                if (documentType != order.tipo) {
                                  final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                            title: Text(documentType == 'OS'
                                                ? 'Aceitar orçamento e gerar OS?'
                                                : 'Voltar para orçamento?'),
                                            content: Text(documentType == 'OS'
                                                ? 'Ao confirmar, esta venda entra no financeiro, nos totais e no fluxo de entrega.'
                                                : 'A OS deixa os totais e as entregas. Títulos em aberto serão cancelados e preservados no histórico. OS com pagamentos recebidos precisam de estorno primeiro.'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c, false),
                                                  child:
                                                      const Text('Cancelar')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c, true),
                                                  child:
                                                      const Text('Confirmar')),
                                            ],
                                          ));
                                  if (confirmed != true ||
                                      !dialogContext.mounted) {
                                    return;
                                  }
                                }
                                setDialogState(() => saving = true);
                                try {
                                  final customer = _customers.firstWhere(
                                      (item) => item.id == customerId);
                                  final updated = order.copyWith(
                                    tipo: documentType,
                                    clienteId: customerId,
                                    clienteNome: customer.name,
                                    itens: items,
                                    status: status,
                                    prioridade: priority,
                                    formaPagamento:
                                        paymentController.text.trim(),
                                    observacoes: notesController.text.trim(),
                                    dataEntrega:
                                        deliveryDate?.toIso8601String(),
                                    dataAtualizacao:
                                        DateTime.now().toIso8601String(),
                                  );
                                  await _repository.update(updated);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext, true);
                                  }
                                } catch (error) {
                                  setDialogState(() => saving = false);
                                  _showMessage(
                                      'Não foi possível alterar o pedido: $error',
                                      error: true);
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label:
                            Text(saving ? 'Salvando...' : 'Salvar alterações'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    paymentController.dispose();
    notesController.dispose();
    if (saved == true) {
      await _loadData(showLoading: false);
      _showMessage('Pedido alterado com sucesso.');
    }
  }

  Future<void> _deleteOrder(OrderModel order) async {
    final authorized = await _requestAuthorization(
      permission: 'pedidos_excluir',
      action: 'exclusão do pedido',
    );
    if (!authorized || !mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir pedido?'),
            content: Text(
              'O pedido ${order.numero}, seus itens e os lançamentos financeiros vinculados serão excluídos. Esta ação não pode ser desfeita.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || order.id == null) return;

    try {
      await _repository.delete(order.id!);
      await _loadData(showLoading: false);
      _showMessage('Pedido ${order.numero} excluído.');
    } catch (error) {
      _showMessage('Não foi possível excluir o pedido: $error', error: true);
    }
  }

  Future<void> _reopenOrder(OrderModel order) async {
    if (order.status != 'entregue' && order.status != 'cancelado') return;
    final authorized = await _requestAuthorization(
      permission: 'pedidos_reabrir',
      action: 'reabertura do pedido',
    );
    if (!authorized || !mounted) return;

    final destination = order.tipo == 'ORCAMENTO'
        ? 'Aguardando pagamento'
        : 'Pagamento recebido';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reabrir pedido?'),
            content: Text(
              'O pedido ${order.numero} voltará para o status "$destination" e poderá seguir novamente pelo fluxo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.lock_open),
                label: const Text('Reabrir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await _repository.reopen(order);
      await _loadData(showLoading: false);
      _showMessage('Pedido ${order.numero} reaberto com sucesso.');
    } catch (error) {
      _showMessage('Não foi possível reabrir o pedido: $error', error: true);
    }
  }

  String _priorityLabel(String value) => switch (value.toLowerCase()) {
        'baixa' => 'Baixa',
        'alta' => 'Alta',
        'urgente' => 'Urgente',
        _ => 'Normal',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _buildContent(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: _blue, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedidos',
                    style: TextStyle(
                        color: _blue,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                Text('Visualize, altere e exclua pedidos do fluxo comercial',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 52),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final orders = _filteredOrders;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        _buildSummary(),
        const SizedBox(height: 16),
        _buildFilters(),
        const SizedBox(height: 16),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 64),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.search_off, color: Colors.grey, size: 48),
                SizedBox(height: 12),
                Text('Nenhum pedido encontrado.'),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 900
                ? Column(
                    children: orders.map(_buildOrderCard).toList(),
                  )
                : _buildTable(orders),
          ),
      ],
    );
  }

  Widget _buildSummary() {
    final osCount = _orders.where((order) => order.tipo == 'OS').length;
    final productionCount = _orders
        .where((order) =>
            order.tipo == 'OS' && order.orderStatusGroup == 'em_producao')
        .length;
    final overdueCount = _orders.where(_isOverdue).length;
    final total = _orders
        .where((order) => order.isAcceptedSale)
        .fold<double>(0, (sum, order) => sum + order.valorTotal);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 520
            ? (constraints.maxWidth - 12) / 2
            : 210.0;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard(
              'Total de registros',
              _orders.length.toString(),
              Icons.list_alt,
              _blue,
              width: cardWidth,
            ),
            _summaryCard(
              'Pedidos / OS',
              osCount.toString(),
              Icons.receipt,
              Colors.teal,
              width: cardWidth,
            ),
            _summaryCard(
              'Em produ\u00e7\u00e3o',
              productionCount.toString(),
              Icons.factory,
              Colors.deepPurple,
              width: cardWidth,
            ),
            _summaryCard(
              'Entregas atrasadas',
              overdueCount.toString(),
              Icons.warning_amber_rounded,
              overdueCount > 0 ? Colors.red : Colors.grey,
              width: cardWidth,
            ),
            _summaryCard(
              'Valor ativo',
              _currency.format(total),
              Icons.attach_money,
              Colors.green,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                Text(label,
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Buscar por número ou cliente',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        );
        final type = DropdownButtonFormField<String>(
          initialValue: _typeFilter,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Tipo',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
            DropdownMenuItem(value: 'OS', child: Text('Pedidos / OS')),
            DropdownMenuItem(value: 'ORCAMENTO', child: Text('Orçamentos')),
          ],
          onChanged: (value) => setState(() => _typeFilter = value ?? 'TODOS'),
        );
        final status = DropdownButtonFormField<String>(
          initialValue: _statusFilter,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Status',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: 'todos', child: Text('Todos')),
            ..._filterStatuses.entries.map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (value) =>
              setState(() => _statusFilter = value ?? 'todos'),
        );
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              search,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: type),
                  const SizedBox(width: 10),
                  Expanded(child: status),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            SizedBox(width: 170, child: type),
            const SizedBox(width: 12),
            SizedBox(width: 205, child: status),
          ],
        );
      },
    );
  }

  Widget _buildTable(List<OrderModel> orders) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 10,
              horizontalMargin: 12,
              headingRowColor: WidgetStatePropertyAll(
                _blue.withValues(alpha: .08),
              ),
              columns: const [
                DataColumn(label: Text('Número')),
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Tipo')),
                DataColumn(label: Text('Datas')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Pagamento')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('Ações')),
              ],
              rows: orders.map((order) {
                final color = _statusColor(order.orderStatusGroup);
                return DataRow(cells: [
                  DataCell(Text(order.numero,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(SizedBox(
                    width: 105,
                    child: Text(order.clienteNome ?? 'Sem cliente',
                        overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(
                      Text(order.tipo == 'OS' ? 'Pedido / OS' : 'Orçamento')),
                  DataCell(_datesCell(order)),
                  DataCell(_statusBadge(order, color)),
                  DataCell(SizedBox(
                    width: 82,
                    child: Text(
                      order.formaPagamento,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                  DataCell(Text(_currency.format(order.valorTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(_actions(order, compact: true)),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final color = _statusColor(order.orderStatusGroup);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.numero,
                      style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                _statusBadge(order, color),
              ],
            ),
            const SizedBox(height: 8),
            Text(order.clienteNome ?? 'Sem cliente',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.tipo == 'OS' ? 'Pedido / OS' : 'Orçamento'} • ${_formatDate(order.dataCriacao)}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        'Pagamento: ${order.formaPagamento}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      if (order.dataEntrega != null)
                        Text(
                          'Entrega: ${_formatDate(order.dataEntrega)}'
                          '${_isOverdue(order) ? ' • ATRASADA' : ''}',
                          style: TextStyle(
                            color: _isOverdue(order) ? Colors.red : Colors.grey,
                            fontSize: 11,
                            fontWeight: _isOverdue(order)
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(_currency.format(order.valorTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            Align(alignment: Alignment.centerRight, child: _actions(order)),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(OrderModel order, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _orderStatusLabel(order),
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _actions(OrderModel order, {bool compact = false}) {
    final isClosed = order.status == 'entregue' || order.status == 'cancelado';
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(4),
            onPressed: () => _showDetails(order),
            icon: const Icon(Icons.visibility_outlined, size: 20),
            color: _blue,
            tooltip: 'Visualizar',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(4),
            onPressed: () => _openPrintDocuments(order),
            icon: const Icon(Icons.print_outlined, size: 20),
            color: Colors.blueGrey,
            tooltip: 'Imprimir pedido do cliente ou ordem de produção',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(4),
            onPressed: () => _authorizeAndEdit(order),
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: Colors.orange,
            tooltip: 'Alterar',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(4),
            onPressed: () => _deleteOrder(order),
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Colors.red,
            tooltip: 'Excluir pedido e dados relacionados',
          ),
          if (isClosed)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
              onPressed: () => _reopenOrder(order),
              icon: const Icon(Icons.lock_open, size: 20),
              color: Colors.green,
              tooltip: 'Reabrir pedido',
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _showDetails(order),
          icon: const Icon(Icons.visibility_outlined),
          color: _blue,
          tooltip: 'Visualizar',
        ),
        IconButton(
          onPressed: () => _openPrintDocuments(order),
          icon: const Icon(Icons.print_outlined),
          color: Colors.blueGrey,
          tooltip: 'Imprimir pedido do cliente ou ordem de produção',
        ),
        IconButton(
          onPressed: () => _authorizeAndEdit(order),
          icon: const Icon(Icons.edit_outlined),
          color: Colors.orange.shade800,
          tooltip: 'Alterar',
        ),
        if (isClosed)
          IconButton(
            onPressed: () => _reopenOrder(order),
            icon: const Icon(Icons.lock_open),
            color: Colors.green,
            tooltip: 'Reabrir pedido',
          ),
        IconButton(
          onPressed: () => _deleteOrder(order),
          icon: const Icon(Icons.delete_outline),
          color: Colors.red,
          tooltip: 'Excluir pedido e dados relacionados',
        ),
      ],
    );
  }
}
