import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';
import '../models/customer_model.dart';
import '../models/delivery_model.dart';
import '../models/erp_module_record.dart';
import '../models/financial_model.dart';
import '../models/order_model.dart';
import 'erp_module_repository.dart';
import 'financial_repository.dart';

class DeliveryRepository {
  static const _deliveryFeeMarker = '[ENTREGA_FRETE:';
  DeliveryRepository({ErpModuleRepository? records, AppDatabase? database})
      : _records = records ?? ErpModuleRepository(),
        _database = database ?? AppDatabase();

  final ErpModuleRepository _records;
  final AppDatabase _database;
  final FinancialRepository _financial = FinancialRepository();

  Future<List<DeliveryModel>> list() async {
    final records = await _records.list('entregas', recordType: 'delivery');
    return records.map(DeliveryModel.fromRecord).toList()
      ..sort((a, b) {
        final aTime = a.scheduledAt ?? a.record.updatedAt;
        final bTime = b.scheduledAt ?? b.record.updatedAt;
        return aTime.compareTo(bTime);
      });
  }

  /// Cria uma única ficha de expedição para cada OS finalizada na produção.
  /// O pedido e a ficha ficam independentes: mudar a entrega não reabre a OS.
  Future<List<DeliveryModel>> syncCompletedOrders(
      {String actor = 'Sistema'}) async {
    final db = await _database.database;
    final orders = (await db.query('orders',
            where: 'tipo = ? AND status = ?',
            whereArgs: const ['OS', 'entregue']))
        .map((row) => OrderModel.fromMap(row))
        .where((order) => order.id != null)
        .toList();
    final existing = await _records.list('entregas', recordType: 'delivery');
    final existingReferences = existing.map((item) => item.referenceId).toSet();
    final customerRows = await db.query('customers');
    final customers = {
      for (final row in customerRows)
        (row['id'] as num?)?.toInt(): CustomerModel.fromMap(row),
    };
    for (final order in orders) {
      final reference = 'order:${order.id}';
      if (existingReferences.contains(reference)) continue;
      final customer = customers[order.clienteId];
      const initialStatus = 'aguardando_agendamento';
      final now = DateTime.now();
      await _records.save(ErpModuleRecord(
        module: 'entregas',
        recordType: 'delivery',
        referenceId: reference,
        title: 'Pedido ${order.numero}',
        status: initialStatus,
        payload: {
          'order_id': order.id,
          'order_number': order.numero,
          'customer_name': order.clienteNome ?? customer?.name ?? '',
          'method': 'retirada_loja',
          'address': customer?.address ?? '',
          'contact': customer?.phone ?? '',
          'reference': '',
          'responsible': '',
          'delivery_fee': 0,
          'notes': '',
          'history': [
            DeliveryHistoryEntry(
              at: now,
              status: initialStatus,
              responsible: actor,
              note: 'Pedido finalizado importado da produção.',
            ).toMap()
          ],
        },
      ));
    }
    await refreshBalances();
    return list();
  }

  Future<List<DeliveryModel>> refreshBalances() async {
    final deliveries = await list();
    if (deliveries.isEmpty) return deliveries;
    final db = await _database.database;
    final balances = <int, ({double pending, double total})>{};
    if (db is SupabaseDatabase) {
      final raw = await db.rpc('matterdi_delivery_balances', {
        'p_order_ids': deliveries.map((item) => item.orderId).toList(),
      });
      for (final row in (raw as List? ?? const [])) {
        final map = Map<String, dynamic>.from(row as Map);
        balances[(map['order_id'] as num).toInt()] = (
          pending: (map['pending'] as num? ?? 0).toDouble(),
          total: (map['total'] as num? ?? 0).toDouble(),
        );
      }
    } else {
      final financial = (await db.query('financial'))
          .map((row) => FinancialModel.fromMap(row))
          .where((row) => row.type == 'receber' && row.status != 'cancelado');
      for (final delivery in deliveries) {
        final rows = financial.where((row) => row.orderId == delivery.orderId);
        balances[delivery.orderId] = (
          pending: rows
              .where((row) => !row.isPaid)
              .fold(0, (sum, row) => sum + row.amount),
          total: rows.fold(0, (sum, row) => sum + row.amount),
        );
      }
    }
    for (final delivery in deliveries) {
      final balance = balances[delivery.orderId] ?? (pending: 0.0, total: 0.0);
      if ((delivery.paymentPending - balance.pending).abs() < .001 &&
          (delivery.paymentTotal - balance.total).abs() < .001) {
        continue;
      }
      await _save(delivery.copyWith(
        paymentPending: balance.pending,
        paymentTotal: balance.total,
      ));
    }
    return list();
  }

  Future<DeliveryModel> save(DeliveryModel delivery,
      {String actor = 'Sistema'}) async {
    if (!DeliveryModel.methods.containsKey(delivery.method)) {
      throw ArgumentError('Selecione a modalidade de entrega ou retirada.');
    }
    if (!DeliveryModel.statuses.containsKey(delivery.status)) {
      throw ArgumentError('Selecione um status v?lido.');
    }
    if (delivery.isStoreDelivery && delivery.deliveryFee < 0) {
      throw ArgumentError('A taxa de entrega n?o pode ser negativa.');
    }
    final changed = delivery.history.isEmpty ||
        delivery.history.last.status != delivery.status ||
        delivery.history.last.responsible != actor;
    final history = changed
        ? [
            ...delivery.history,
            DeliveryHistoryEntry(
              at: DateTime.now(),
              status: delivery.status,
              responsible: actor,
              note: 'Dados da entrega atualizados.',
            )
          ]
        : delivery.history;
    final saved = await _save(delivery.copyWith(history: history));
    // A taxa s? ? criada depois que a venda j? possui contas financeiras.
    // Assim configurar a entrega n?o substitui a cobran?a do pedido.
    if (saved.hasFinancialEntry) {
      await _syncDeliveryFee(saved);
      await refreshBalances();
      return await _deliveryById(saved.record.id) ?? saved;
    }
    return saved;
  }

  /// Cria as contas a receber somente depois que a expedição foi configurada.
  /// Assim, o vencimento usa a data combinada de entrega ou retirada.
  Future<DeliveryModel> launchReceivable(DeliveryModel delivery,
      {String actor = 'Sistema'}) async {
    if (!delivery.deliveryDataReady) {
      throw StateError(
          'Preencha agendamento, responsável, contato e endereço antes de lançar para receber.');
    }
    if (delivery.hasFinancialEntry) return delivery;

    final db = await _database.database;
    final orders = await db.query('orders',
        where: 'id = ?', whereArgs: [delivery.orderId], limit: 1);
    if (orders.isEmpty) {
      throw StateError('Pedido da entrega não foi encontrado.');
    }
    final order = OrderModel.fromMap(orders.first).copyWith(
      dataEntrega: delivery.scheduledAt!.toIso8601String(),
    );
    if (!order.isAcceptedSale) {
      throw StateError(
          'Somente pedidos ativos podem ser lançados no financeiro.');
    }

    final hasOrderReceivable = db is SupabaseDatabase
        ? await _cloudHasReceivable(db, delivery.orderId)
        : (await _financial.getByOrderId(delivery.orderId)).any((row) =>
            row.status != 'cancelado' &&
            row.type == 'receber' &&
            !(row.notes ?? '').contains(_deliveryFeeMarker));
    if (!hasOrderReceivable) await _financial.createFromOrder(order);
    await _syncDeliveryFee(delivery, order: order);

    final saved = await save(
        delivery.copyWith(history: [
          ...delivery.history,
          DeliveryHistoryEntry(
              at: DateTime.now(),
              status: delivery.status,
              responsible: actor,
              note: 'Contas a receber lançadas após configurar a expedição.'),
        ]),
        actor: actor);
    await refreshBalances();
    return saved;
  }

  Future<DeliveryModel> conclude(DeliveryModel delivery,
      {String actor = 'Sistema'}) async {
    if (!delivery.deliveryDataReady) {
      throw StateError(
          'Configure agendamento, responsável, contato e endereço antes de concluir.');
    }
    if (!delivery.hasFinancialEntry) {
      throw StateError(
          'Lance o pedido para receber no financeiro antes de concluir a entrega.');
    }
    return save(delivery.copyWith(status: 'concluido'), actor: actor);
  }

  Future<List<FinancialModel>> pendingReceivables(int orderId) async {
    final db = await _database.database;
    final rows = await db.query('financial',
        where: 'order_id = ? AND type = ? AND is_paid = ? AND status != ?',
        whereArgs: [orderId, 'receber', 0, 'cancelado'],
        orderBy: 'due_date ASC');
    return rows
        .map(FinancialModel.fromMap)
        .where((row) => row.id != null && row.amount > 0)
        .toList();
  }

  Future<void> receivePayment({
    required int orderId,
    required int receivableId,
    required double amount,
    required DateTime receivedAt,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Informe um valor recebido maior que zero.');
    }
    final rows = await pendingReceivables(orderId);
    final matches = rows.where((row) => row.id == receivableId);
    if (matches.isEmpty) {
      throw StateError('A conta não está mais disponível para recebimento.');
    }
    final balance = matches.first.amount;
    final amountCents = (amount * 100).round();
    final balanceCents = (balance * 100).round();
    if ((amount * 100 - amountCents).abs() > .000001 ||
        amountCents > balanceCents) {
      throw ArgumentError('O valor supera o saldo da conta selecionada.');
    }
    // Valores antigos podem ter frações de centavo por cálculos em ponto
    // flutuante. Ao quitar o saldo exibido, use o valor exato armazenado.
    final settledAmount = amountCents == balanceCents ? balance : amount;
    await _financial.registrarPagamentoParcial(
        receivableId, settledAmount, receivedAt);
  }

  Future<DeliveryModel?> _deliveryById(int? recordId) async {
    if (recordId == null) return null;
    final deliveries = await list();
    for (final item in deliveries) {
      if (item.record.id == recordId) return item;
    }
    return null;
  }

  /// Mant?m a taxa de entrega em uma conta a receber identific?vel. Ela passa
  /// a compor o saldo do pedido, os recebimentos e o indicador "A receber".
  Future<void> _syncDeliveryFee(
    DeliveryModel delivery, {
    OrderModel? order,
  }) async {
    final desired = delivery.isStoreDelivery
        ? delivery.deliveryFee.clamp(0.0, double.infinity).toDouble()
        : 0.0;
    final database = await _database.database;
    final dueDate = delivery.scheduledAt ?? DateTime.now();
    if (database is SupabaseDatabase) {
      await database.rpc('matterdi_delivery_fee', {
        'p_order_id': delivery.orderId,
        'p_fee': desired,
        'p_due_date': dueDate.toIso8601String(),
      });
      return;
    }
    final marker = '$_deliveryFeeMarker${delivery.orderId}]';
    final rows = await _financial.getByOrderId(delivery.orderId);
    final feeRows =
        rows.where((row) => (row.notes ?? '').contains(marker)).toList();
    final active = feeRows
        .where((row) => row.status != 'cancelado' && !row.isPaid)
        .toList();

    if (desired <= .009) {
      for (final row in active) {
        await _financial.update(row.copyWith(
          status: 'cancelado',
          updatedAt: DateTime.now(),
        ));
      }
      return;
    }

    if (active.isNotEmpty) {
      await _financial.update(active.first.copyWith(
        description: 'Taxa de entrega - Pedido ${delivery.orderNumber}',
        amount: desired,
        dueDate: dueDate,
        customerName: delivery.customerName,
        updatedAt: DateTime.now(),
        status: 'pendente',
      ));
      for (final duplicate in active.skip(1)) {
        await _financial.update(duplicate.copyWith(
          status: 'cancelado',
          updatedAt: DateTime.now(),
        ));
      }
      return;
    }

    // Uma taxa j? recebida permanece no hist?rico; uma altera??o posterior
    // gera apenas o ajuste que ainda falta receber.
    final paidTotal = feeRows
        .where((row) => row.status != 'cancelado' && row.isPaid)
        .fold<double>(0, (sum, row) => sum + row.amount);
    final amount = (desired - paidTotal).clamp(0.0, double.infinity).toDouble();
    if (amount <= .009) return;
    final sale = order ?? await _orderFor(delivery.orderId);
    final now = DateTime.now();
    await _financial.create(FinancialModel(
      description: 'Taxa de entrega - Pedido ${delivery.orderNumber}',
      amount: amount,
      type: 'receber',
      dueDate: dueDate,
      isPaid: false,
      notes: '$marker Taxa de entrega lan?ada pela expedi??o.',
      orderId: delivery.orderId,
      customerId: sale?.clienteId,
      customerName: delivery.customerName,
      categoria: 'entrega',
      formaPagamento: sale?.formaPagamento ?? '',
      status: 'pendente',
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<bool> _cloudHasReceivable(
    SupabaseDatabase database,
    int orderId,
  ) async {
    final result = await database.rpc('matterdi_delivery_balances', {
      'p_order_ids': [orderId],
    });
    if (result is! List || result.isEmpty || result.first is! Map) {
      return false;
    }
    final total = (result.first as Map)['total'];
    return total is num && total > .009;
  }

  Future<OrderModel?> _orderFor(int orderId) async {
    final db = await _database.database;
    final rows = await db.query('orders',
        where: 'id = ?', whereArgs: [orderId], limit: 1);
    return rows.isEmpty ? null : OrderModel.fromMap(rows.first);
  }

  Future<DeliveryModel> _save(DeliveryModel delivery) async {
    final saved = await _records.save(ErpModuleRecord(
      id: delivery.record.id,
      module: 'entregas',
      recordType: 'delivery',
      referenceId: delivery.record.referenceId,
      title: delivery.record.title,
      status: delivery.status,
      createdAt: delivery.record.createdAt,
      payload: {
        'order_id': delivery.orderId,
        'order_number': delivery.orderNumber,
        'customer_name': delivery.customerName,
        'method': delivery.method,
        'scheduled_at': delivery.scheduledAt?.toIso8601String(),
        'responsible': delivery.responsible,
        'address': delivery.address,
        'reference': delivery.reference,
        'contact': delivery.contact,
        'delivery_fee': delivery.isStoreDelivery ? delivery.deliveryFee : 0,
        'notes': delivery.notes,
        'payment_pending': delivery.paymentPending,
        'payment_total': delivery.paymentTotal,
        'history': delivery.history.map((entry) => entry.toMap()).toList(),
      },
    ));
    return DeliveryModel.fromRecord(saved);
  }
}
