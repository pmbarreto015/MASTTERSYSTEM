import 'package:sqflite/sqflite.dart';
import '../models/financial_model.dart';
import '../models/order_model.dart';
import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';

class FinancialRepository {
  final AppDatabase _db = AppDatabase();

  // CRIAR TRANSAÇÃO
  Future<FinancialModel> create(FinancialModel financial) async {
    final database = await _db.database;
    return _createWithExecutor(database, financial);
  }

  Future<FinancialModel> _createWithExecutor(
    DatabaseExecutor executor,
    FinancialModel financial,
  ) async {
    final map = financial.toMap();
    map.remove('id');

    final id = await executor.insert('financial', map);
    return financial.copyWith(id: id);
  }

  // BUSCAR TODAS AS TRANSAÇÕES
  Future<List<FinancialModel>> getAll({bool includeCancelled = false}) async {
    final database = await _db.database;
    final result = await database.query('financial', orderBy: 'due_date DESC');
    final orders =
        await database.query('orders', columns: ['id', 'tipo', 'status']);
    final acceptedIds = orders
        .where((o) => o['tipo'] == 'OS' && o['status'] != 'cancelado')
        .map((o) => o['id'])
        .toSet();
    return result
        .where((row) =>
            (includeCancelled || row['status'] != 'cancelado') &&
            (row['order_id'] == null ||
                acceptedIds.contains(row['order_id']) ||
                (includeCancelled && row['status'] == 'cancelado')))
        .map((row) => FinancialModel.fromMap(row))
        .toList();
  }

  // BUSCAR POR ID
  Future<FinancialModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'financial',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return FinancialModel.fromMap(result.first);
  }

  // ATUALIZAR TRANSAÇÃO
  Future<FinancialModel> update(FinancialModel financial) async {
    final database = await _db.database;
    final map = financial.toMap();
    map.remove('id');
    map.remove('created_at');

    await database.update(
      'financial',
      map,
      where: 'id = ?',
      whereArgs: [financial.id],
    );
    return financial;
  }

  // MARCAR COMO PAGO
  Future<void> markAsPaid(int id) async {
    final database = await _db.database;
    await database.update(
      'financial',
      {
        'is_paid': 1,
        'status': 'pago',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // EXCLUIR TRANSAÇÃO
  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'financial',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // REGISTRAR PAGAMENTO PARCIAL
  Future<FinancialModel> registrarPagamentoParcial(
    int transactionId,
    double valorPago,
    DateTime dataPagamento,
  ) async {
    if (!valorPago.isFinite || valorPago <= 0) {
      throw ArgumentError('O valor pago deve ser maior que zero.');
    }

    final database = await _db.database;
    if (database is SupabaseDatabase) {
      final result = await database.rpc('matterdi_financial_partial', {
        'p_id': transactionId,
        'p_paid': valorPago,
        'p_date': dataPagamento.toIso8601String(),
      });
      return FinancialModel.fromMap(Map<String, dynamic>.from(result as Map));
    }
    return database.transaction((executor) async {
      final rows = await executor.query(
        'financial',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Transação não encontrada.');

      final transaction = FinancialModel.fromMap(rows.first);
      if (transaction.isPaid || transaction.amount <= 0) {
        throw StateError('Esta transação já está quitada.');
      }
      if (valorPago > transaction.amount) {
        throw ArgumentError(
          'O pagamento não pode ser maior que o saldo em aberto.',
        );
      }

      final restante = transaction.amount - valorPago;
      final pagamento = FinancialModel(
        description: 'Parcial - ${transaction.description}',
        amount: valorPago,
        type: 'receber',
        dueDate: dataPagamento,
        isPaid: true,
        notes: 'Pagamento parcial de ${transaction.valorFormatado}',
        orderId: transaction.orderId,
        customerId: transaction.customerId,
        customerName: transaction.customerName,
        categoria: transaction.categoria,
        formaPagamento: transaction.formaPagamento,
        status: 'pago',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _createWithExecutor(executor, pagamento);

      final updated = transaction.copyWith(
        amount: restante,
        isPaid: restante == 0,
        status: restante == 0 ? 'pago' : 'parcial',
        updatedAt: DateTime.now(),
      );
      final map = updated.toMap()
        ..remove('id')
        ..remove('created_at');
      await executor.update(
        'financial',
        map,
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      return updated;
    });
  }

  // CRIAR A PARTIR DE UM PEDIDO
  Future<List<FinancialModel>> createFromOrder(
    OrderModel order, {
    DatabaseExecutor? executor,
  }) async {
    final target = executor ?? await _db.database;
    final planned = planFromOrder(order);
    if (target is SupabaseDatabase) {
      final rows = await target.rpc('matterdi_financial_from_order', {
        'p_order_id': order.id,
        'p_rows': planned.map((item) => item.toMap()..remove('id')).toList(),
      });
      return (rows as List)
          .map((row) =>
              FinancialModel.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
    }
    final inserted = <FinancialModel>[];
    for (final financial in planned) {
      inserted.add(await _createWithExecutor(target, financial));
    }
    return inserted;
  }

  /// Calcula as parcelas sem gravar, para enviá-las com o pedido em uma RPC.
  List<FinancialModel> planFromOrder(OrderModel order) {
    if (!order.isAcceptedSale) return [];
    final created = <FinancialModel>[];

    // Se for 50% + 50%, cria duas transações
    if (order.formaPagamento == '50% no ato + 50% na entrega') {
      // 1ª Transação: Entrada (já paga no ato)
      if (order.entrada > 0) {
        final entrada = FinancialModel(
          description:
              'Entrada - Pedido ${order.numero} - ${order.clienteNome}',
          amount: order.entrada,
          type: 'receber',
          dueDate: DateTime.now(),
          isPaid: true,
          notes: 'Pedido #${order.numero} - Entrada',
          orderId: order.id,
          customerId: order.clienteId,
          customerName: order.clienteNome,
          categoria: 'vendas',
          formaPagamento: order.formaPagamento,
          status: 'pago',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        created.add(entrada);
      }

      // 2ª Transação: Restante (a receber na entrega)
      final restante = FinancialModel(
        description: 'Restante - Pedido ${order.numero} - ${order.clienteNome}',
        amount: (order.valorTotal - order.entrada)
            .clamp(0.0, double.infinity)
            .toDouble(),
        type: 'receber',
        dueDate: order.dataEntrega != null
            ? DateTime.parse(order.dataEntrega!)
            : DateTime.now().add(const Duration(days: 30)),
        isPaid: false,
        notes: 'Pedido #${order.numero} - Restante na entrega',
        orderId: order.id,
        customerId: order.clienteId,
        customerName: order.clienteNome,
        categoria: 'vendas',
        formaPagamento: order.formaPagamento,
        status: 'pendente',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      created.add(restante);
      return created;
    }

    // Parcelado Loja
    if (order.formaPagamento == 'Parcelado Loja' && order.parcelas.isNotEmpty) {
      // Entrada
      if (order.entrada > 0) {
        final entrada = FinancialModel(
          description:
              'Entrada - Pedido ${order.numero} - ${order.clienteNome}',
          amount: order.entrada,
          type: 'receber',
          dueDate: DateTime.now(),
          isPaid: true,
          notes: 'Pedido #${order.numero} - Entrada',
          orderId: order.id,
          customerId: order.clienteId,
          customerName: order.clienteNome,
          categoria: 'vendas',
          formaPagamento: order.formaPagamento,
          status: 'pago',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        created.add(entrada);
      }

      // Parcelas
      for (var i = 0; i < order.parcelas.length; i++) {
        final dataParcela =
            i < order.parcelasDatas.length && order.parcelasDatas[i].isNotEmpty
                ? DateTime.parse(order.parcelasDatas[i])
                : DateTime.now().add(Duration(days: (i + 1) * 30));

        final parcela = FinancialModel(
          description:
              '${(i + 1).toString().padLeft(2, '0')}ª Parcela - Pedido ${order.numero} - ${order.clienteNome}',
          amount: order.parcelas[i],
          type: 'receber',
          dueDate: dataParcela,
          isPaid: false,
          notes:
              'Pedido #${order.numero} - Parcela ${i + 1}/${order.parcelas.length}',
          orderId: order.id,
          customerId: order.clienteId,
          customerName: order.clienteNome,
          categoria: 'vendas',
          formaPagamento: order.formaPagamento,
          parcela: i + 1,
          totalParcelas: order.parcelas.length,
          status: 'pendente',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        created.add(parcela);
      }
      return created;
    }

    // À Vista - Cria uma única transação
    if (order.entrada > 0) {
      final entrada = order.entrada.clamp(0.0, order.valorTotal).toDouble();
      created.add(FinancialModel(
        description: 'Entrada - Pedido ${order.numero} - ${order.clienteNome}',
        amount: entrada,
        type: 'receber',
        dueDate: DateTime.now(),
        isPaid: true,
        notes: 'Pedido #${order.numero} - Entrada',
        orderId: order.id,
        customerId: order.clienteId,
        customerName: order.clienteNome,
        categoria: 'vendas',
        formaPagamento: order.formaPagamento,
        status: 'pago',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      final restante = (order.valorTotal - entrada).clamp(0.0, double.infinity);
      if (restante > 0) {
        created.add(FinancialModel(
          description: 'Pedido ${order.numero} - ${order.clienteNome}',
          amount: restante,
          type: 'receber',
          dueDate: order.dataEntrega != null
              ? DateTime.parse(order.dataEntrega!)
              : DateTime.now().add(const Duration(days: 30)),
          isPaid: false,
          notes: 'Pedido #${order.numero} - ${order.formaPagamento}',
          orderId: order.id,
          customerId: order.clienteId,
          customerName: order.clienteNome,
          categoria: 'vendas',
          formaPagamento: order.formaPagamento,
          status: 'pendente',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
      return created;
    }

    final financial = FinancialModel(
      description: 'Pedido ${order.numero} - ${order.clienteNome}',
      amount: order.valorTotal,
      type: 'receber',
      dueDate: order.dataEntrega != null
          ? DateTime.parse(order.dataEntrega!)
          : DateTime.now().add(const Duration(days: 30)),
      isPaid:
          order.formaPagamento == 'À Vista' || order.formaPagamento == 'PIX',
      notes: 'Pedido #${order.numero} - ${order.formaPagamento}',
      orderId: order.id,
      customerId: order.clienteId,
      customerName: order.clienteNome,
      categoria: 'vendas',
      formaPagamento: order.formaPagamento,
      status:
          (order.formaPagamento == 'À Vista' || order.formaPagamento == 'PIX')
              ? 'pago'
              : 'pendente',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    created.add(financial);
    return created;
  }

  // BUSCAR POR PEDIDO
  Future<List<FinancialModel>> getByOrderId(int orderId) async {
    final database = await _db.database;
    final result = await database.query(
      'financial',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    return result.map((row) => FinancialModel.fromMap(row)).toList();
  }

  // BUSCAR POR CLIENTE
  Future<List<FinancialModel>> getByCustomerId(int customerId) async {
    final database = await _db.database;
    final result = await database.query(
      'financial',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'due_date DESC',
    );
    return result.map((row) => FinancialModel.fromMap(row)).toList();
  }

  // RESUMO DO CLIENTE
  Future<Map<String, dynamic>> getCustomerSummary(int customerId) async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_transacoes,
        SUM(CASE WHEN type = 'receber' AND is_paid = 0 THEN amount ELSE 0 END) as total_aberto,
        SUM(CASE WHEN type = 'receber' AND is_paid = 1 THEN amount ELSE 0 END) as total_pago,
        SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date < date('now') THEN amount ELSE 0 END) as total_vencido,
        SUM(CASE WHEN type = 'receber' THEN amount ELSE 0 END) as total_comprado
      FROM (SELECT * FROM financial f WHERE f.status != 'cancelado' AND (f.order_id IS NULL OR f.order_id IN (SELECT id FROM orders WHERE tipo = 'OS' AND status != 'cancelado'))) financial
      WHERE customer_id = ?
    ''', [customerId]);

    if (result.isEmpty) {
      return {
        'total_transacoes': 0,
        'total_aberto': 0.0,
        'total_pago': 0.0,
        'total_vencido': 0.0,
        'total_comprado': 0.0,
      };
    }
    return result.first;
  }

  // BUSCAR POR CATEGORIA
  Future<List<FinancialModel>> getByCategoria(String categoria) async {
    final database = await _db.database;
    final result = await database.query(
      'financial',
      where: 'categoria = ?',
      whereArgs: [categoria],
      orderBy: 'due_date DESC',
    );
    return result.map((row) => FinancialModel.fromMap(row)).toList();
  }

  // DASHBOARD COMPLETO
  Future<Map<String, dynamic>> getDashboard() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'receber' AND is_paid = 0 THEN amount ELSE 0 END) as a_receber,
        SUM(CASE WHEN type = 'receber' AND is_paid = 1 THEN amount ELSE 0 END) as recebido,
        SUM(CASE WHEN type = 'pagar' AND is_paid = 0 THEN amount ELSE 0 END) as a_pagar,
        SUM(CASE WHEN type = 'pagar' AND is_paid = 1 THEN amount ELSE 0 END) as pago,
        COUNT(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date < date('now') THEN 1 END) as vencidos_qtde,
        SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date < date('now') THEN amount ELSE 0 END) as vencidos_valor
      FROM (SELECT * FROM financial f WHERE f.status != 'cancelado' AND (f.order_id IS NULL OR f.order_id IN (SELECT id FROM orders WHERE tipo = 'OS' AND status != 'cancelado'))) financial
    ''');

    if (result.isEmpty) {
      return {
        'a_receber': 0.0,
        'recebido': 0.0,
        'a_pagar': 0.0,
        'pago': 0.0,
        'vencidos_qtde': 0,
        'vencidos_valor': 0.0,
      };
    }
    return result.first;
  }

  // FLUXO DE CAIXA PROJETADO
  Future<Map<String, dynamic>> getProjecaoCaixa() async {
    final database = await _db.database;
    final hoje = DateTime.now().toIso8601String();
    final limite =
        DateTime.now().add(const Duration(days: 30)).toIso8601String();

    final result = await database.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date BETWEEN ? AND ? THEN amount ELSE 0 END) as a_receber_projetado,
        SUM(CASE WHEN type = 'pagar' AND is_paid = 0 AND due_date BETWEEN ? AND ? THEN amount ELSE 0 END) as a_pagar_projetado
      FROM (SELECT * FROM financial f WHERE f.status != 'cancelado' AND (f.order_id IS NULL OR f.order_id IN (SELECT id FROM orders WHERE tipo = 'OS' AND status != 'cancelado'))) financial
    ''', [hoje, limite, hoje, limite]);

    if (result.isEmpty) {
      return {
        'a_receber_projetado': 0.0,
        'a_pagar_projetado': 0.0,
      };
    }
    return result.first;
  }
}
