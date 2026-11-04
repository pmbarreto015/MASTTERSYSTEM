import 'package:sqflite/sqflite.dart';
import '../models/order_model.dart';
import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';
import 'financial_repository.dart';

class OrderRepository {
  final AppDatabase _db = AppDatabase();
  final FinancialRepository _financialRepo = FinancialRepository();

  // BUSCAR POR ID
  Future<OrderModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    final order = OrderModel.fromMap(result.first);
    final items = await _getOrderItems(database, order.id!);
    return order.copyWith(itens: items);
  }

  // Buscar orçamentos (apenas ORCAMENTO)
  Future<List<OrderModel>> getOrcamentos() async {
    final database = await _db.database;
    final result = await database.query(
      'orders',
      where: 'tipo = ? AND status = ?',
      whereArgs: ['ORCAMENTO', 'aguardando_pagamento'],
      orderBy: 'created_at DESC',
    );
    return _ordersWithItems(database, result);
  }

  /// Converte um orçamento pendente em OS e gera o financeiro na mesma
  /// transação. Assim, o registro nunca fica aprovado apenas pela metade.
  Future<OrderModel> approveQuote(OrderModel quote) async {
    if (quote.id == null) {
      throw StateError('Orçamento sem identificador.');
    }

    final database = await _db.database;
    final approved = quote.copyWith(
      tipo: 'OS',
      status: 'pagamento_recebido',
      dataAtualizacao: DateTime.now().toIso8601String(),
    );

    if (database is SupabaseDatabase) {
      await database.rpc('matterdi_order_approve', {
        'p_order_id': quote.id,
        'p_order': approved.toMap()..remove('id'),
        'p_financials': _financialRows(approved),
      });
      return approved;
    }

    await database.transaction((transaction) async {
      final current = await transaction.query(
        'orders',
        columns: ['tipo', 'status', 'seller_id'],
        where: 'id = ?',
        whereArgs: [quote.id],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('Orçamento não encontrado.');
      }
      if (current.first['tipo'] != 'ORCAMENTO' ||
          current.first['status'] != 'aguardando_pagamento') {
        throw StateError('Este orçamento já foi processado.');
      }

      final changes = approved.toMap()..remove('id');
      final updated = await transaction.update(
        'orders',
        changes,
        where: 'id = ? AND tipo = ? AND status = ?',
        whereArgs: [quote.id, 'ORCAMENTO', 'aguardando_pagamento'],
      );
      if (updated != 1) {
        throw StateError('Não foi possível aprovar o orçamento.');
      }

      final existingFinancials = await transaction.query(
        'financial',
        columns: ['id'],
        where: 'order_id = ? AND status != ?',
        whereArgs: [quote.id, 'cancelado'],
        limit: 1,
      );
      if (existingFinancials.isEmpty) {
        await _financialRepo.createFromOrder(
          approved,
          executor: transaction,
        );
      }
      await _refreshSellerTotals(
          transaction, current.first['seller_id'] as int?);
      await _refreshSellerTotals(transaction, approved.sellerId);
    });

    return approved;
  }

  // Buscar por termo
  Future<List<OrderModel>> search(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'orders',
      where: 'number LIKE ? OR cliente_nome LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
    return _ordersWithItems(database, result);
  }

  // Buscar pedidos em produção (apenas OS)
  Future<List<OrderModel>> getProducao() async {
    final database = await _db.database;
    final result = await database.query(
      'orders',
      where: 'tipo = ? AND status IN (?, ?, ?, ?)',
      whereArgs: [
        'OS',
        'aguardando_pagamento',
        'pagamento_recebido',
        'em_producao',
        'pronto'
      ],
      orderBy: 'created_at DESC',
    );
    return _ordersWithItems(database, result);
  }

  // Buscar todos
  Future<List<OrderModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'orders',
      orderBy: 'created_at DESC',
    );
    return _ordersWithItems(database, result);
  }

  Future<List<OrderModel>> _ordersWithItems(
    Database database,
    List<Map<String, Object?>> orderMaps,
  ) async {
    if (orderMaps.isEmpty) return [];

    final orderIds =
        orderMaps.map((map) => map['id']).whereType<int>().toList();
    final itemsByOrder = await _getOrderItemsForOrders(database, orderIds);

    return orderMaps.map((map) {
      final order = OrderModel.fromMap(map);
      return order.copyWith(itens: itemsByOrder[order.id] ?? []);
    }).toList();
  }

  Future<Map<int, List<OrderItemModel>>> _getOrderItemsForOrders(
    Database database,
    List<int> orderIds,
  ) async {
    final itemsByOrder = <int, List<OrderItemModel>>{};

    // Limita cada consulta para manter compatibilidade com o SQLite.
    for (var start = 0; start < orderIds.length; start += 500) {
      final end = start + 500 > orderIds.length ? orderIds.length : start + 500;
      final ids = orderIds.sublist(start, end);
      final placeholders = List.filled(ids.length, '?').join(', ');
      final result = await database.rawQuery('''
        SELECT oi.*, p.nome AS produto_nome
        FROM order_items oi
        LEFT JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id IN ($placeholders)
      ''', ids);

      for (final map in result) {
        final orderId = map['order_id'] as int?;
        if (orderId != null) {
          itemsByOrder
              .putIfAbsent(orderId, () => [])
              .add(OrderItemModel.fromMap(map));
        }
      }
    }

    return itemsByOrder;
  }

  // Buscar itens de um pedido
  Future<List<OrderItemModel>> _getOrderItems(Database db, int orderId) async {
    final result = await db.rawQuery('''
      SELECT oi.*, p.nome AS produto_nome
      FROM order_items oi
      LEFT JOIN products p ON p.id = oi.product_id
      WHERE oi.order_id = ?
    ''', [orderId]);
    return result.map((map) => OrderItemModel.fromMap(map)).toList();
  }

  // CRIAR PEDIDO COM INTEGRAÇÃO FINANCEIRA
  Future<OrderModel> create(OrderModel order) async {
    if (order.clienteId == null) {
      throw ArgumentError(
        'Selecione um cliente cadastrado antes de salvar a venda.',
      );
    }
    if (order.itens.isEmpty) {
      throw ArgumentError('Adicione pelo menos um item antes de salvar.');
    }
    if (order.itens.any(
      (item) => item.produtoId == null || item.produtoId! <= 0,
    )) {
      throw ArgumentError(
        'Existe um produto sem cadastro válido. Remova o item e selecione-o novamente.',
      );
    }
    final database = await _db.database;

    if (!['OS', 'ORCAMENTO'].contains(order.tipo)) {
      throw ArgumentError('Tipo de documento inválido.');
    }
    if (order.tipo == 'ORCAMENTO' && order.status != 'cancelado') {
      order.status = 'aguardando_pagamento';
    }
    order.calcularTotal();
    final orderMap = order.toMap();
    orderMap.remove('id');
    if (database is SupabaseDatabase) {
      final id = await database.rpc('matterdi_order_create', {
        'p_order': orderMap,
        'p_items': _itemRows(order.itens),
        'p_financials': order.tipo == 'OS' ? _financialRows(order) : [],
      });
      return order.copyWith(id: (id as num).toInt());
    }
    return database.transaction((transaction) async {
      final id = await transaction.insert('orders', orderMap);
      await _insertOrderItems(transaction, id, order.itens);

      final createdOrder = order.copyWith(id: id);
      if (order.tipo == 'OS') {
        await _financialRepo.createFromOrder(
          createdOrder,
          executor: transaction,
        );
      }
      await _refreshSellerTotals(transaction, createdOrder.sellerId);
      return createdOrder;
    });
  }

  // ATUALIZAR PEDIDO
  Future<int> update(OrderModel order) async {
    if (order.id == null) throw ArgumentError('Pedido sem identificador.');
    final database = await _db.database;

    if (!['OS', 'ORCAMENTO'].contains(order.tipo)) {
      throw ArgumentError('Tipo de documento inválido.');
    }
    if (order.tipo == 'ORCAMENTO' && order.status != 'cancelado') {
      order.status = 'aguardando_pagamento';
    }
    order.calcularTotal();
    final orderMap = order.toMap();
    orderMap.remove('id');
    if (database is SupabaseDatabase) {
      final result = await database.rpc('matterdi_order_update', {
        'p_order_id': order.id,
        'p_order': orderMap,
        'p_items': _itemRows(order.itens),
        'p_financials': _financialRows(order),
      });
      return (result as num).toInt();
    }
    return database.transaction((transaction) async {
      final current = await transaction.query('orders',
          where: 'id = ?', whereArgs: [order.id], limit: 1);
      if (current.isEmpty) throw StateError('Pedido não encontrado.');
      if (order.tipo == 'ORCAMENTO' && current.first['tipo'] == 'OS') {
        final paid = await transaction.query('financial',
            where: 'order_id = ? AND is_paid = ? AND amount > ?',
            whereArgs: [order.id, 1, 0],
            limit: 1);
        if (paid.isNotEmpty) {
          throw StateError(
              'Esta OS possui recebimentos. Estorne os pagamentos antes de voltar para orçamento.');
        }
        await transaction.update(
            'financial',
            {
              'status': 'cancelado',
              'updated_at': DateTime.now().toIso8601String()
            },
            where: 'order_id = ?',
            whereArgs: [order.id]);
      }
      final result = await transaction.update(
        'orders',
        orderMap,
        where: 'id = ?',
        whereArgs: [order.id],
      );
      if (result != 1) throw StateError('Pedido não encontrado.');

      await transaction.delete(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [order.id],
      );
      await _insertOrderItems(transaction, order.id!, order.itens);

      if (order.isAcceptedSale) {
        final existing = await transaction.query(
          'financial',
          columns: ['id'],
          where: 'order_id = ? AND status != ?',
          whereArgs: [order.id, 'cancelado'],
          limit: 1,
        );
        if (existing.isEmpty) {
          await _financialRepo.createFromOrder(order, executor: transaction);
        }
      }
      await _refreshSellerTotals(
          transaction, current.first['seller_id'] as int?);
      await _refreshSellerTotals(transaction, order.sellerId);
      return result;
    });
  }

  Future<void> _insertOrderItems(
    DatabaseExecutor executor,
    int orderId,
    List<OrderItemModel> items,
  ) async {
    for (final item in items) {
      await executor.insert('order_items', {
        'order_id': orderId,
        'product_id': item.produtoId ?? 0,
        'quantity': item.quantidade,
        'unit_price': item.precoUnitario,
        'subtotal': item.subtotal,
        'specifications': item.especificacoes,
        'largura': item.largura,
        'altura': item.altura,
        'custo_unitario': item.custoUnitario,
        'detalhes_custo': item.detalhesCusto,
        'terceirizado': item.terceirizado ? 1 : 0,
      });
    }
  }

  List<Map<String, dynamic>> _financialRows(OrderModel order) => _financialRepo
      .planFromOrder(order)
      .map((financial) => financial.toMap()..remove('id'))
      .toList();

  List<Map<String, dynamic>> _itemRows(List<OrderItemModel> items) => items
      .map((item) => <String, dynamic>{
            'product_id': item.produtoId,
            'quantity': item.quantidade,
            'unit_price': item.precoUnitario,
            'subtotal': item.subtotal,
            'specifications': item.especificacoes,
            'largura': item.largura,
            'altura': item.altura,
            'custo_unitario': item.custoUnitario,
            'detalhes_custo': item.detalhesCusto,
            'terceirizado': item.terceirizado ? 1 : 0,
          })
      .toList();

  Future<void> _refreshSellerTotals(
      DatabaseExecutor executor, int? sellerId) async {
    if (sellerId == null) return;
    final rows = await executor.query('orders',
        columns: ['total'],
        where: 'seller_id = ? AND tipo = ? AND status != ?',
        whereArgs: [sellerId, 'OS', 'cancelado']);
    final total = rows.fold<double>(
        0, (sum, row) => sum + (row['total'] as num).toDouble());
    await executor.update('sellers', {'total_sales': total},
        where: 'id = ?', whereArgs: [sellerId]);
  }

  // Deletar
  Future<int> delete(int id) async {
    final database = await _db.database;
    if (database is SupabaseDatabase) {
      final result =
          await database.rpc('matterdi_order_delete', {'p_order_id': id});
      return (result as num).toInt();
    }
    return database.transaction((transaction) async {
      final orderRows = await transaction.query(
        'orders',
        columns: ['seller_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final sellerId =
          orderRows.isEmpty ? null : orderRows.first['seller_id'] as int?;

      // Uma composição pode estar ligada tanto a um pedido/OS quanto a um
      // orçamento. Seus itens precisam ser removidos antes da composição em
      // bancos antigos que ainda não possuem a cascata habilitada.
      final compositions = await transaction.query(
        'composicoes',
        columns: ['id'],
        where: 'pedido_id = ? OR orcamento_id = ?',
        whereArgs: [id, id],
      );
      final compositionIds =
          compositions.map((row) => row['id']).whereType<int>().toList();
      for (final compositionId in compositionIds) {
        await transaction.delete(
          'composicao_itens',
          where: 'composicao_id = ?',
          whereArgs: [compositionId],
        );
      }
      await transaction.delete(
        'composicoes',
        where: 'pedido_id = ? OR orcamento_id = ?',
        whereArgs: [id, id],
      );

      await transaction.delete(
        'financial',
        where: 'order_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'stock_movements',
        where: 'order_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'retalhos',
        where: 'pedido_origem_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [id],
      );
      final deleted = await transaction.delete(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (sellerId != null) {
        await transaction.rawUpdate('''
          UPDATE sellers
          SET total_sales = COALESCE((
            SELECT SUM(total)
            FROM orders
            WHERE seller_id = ? AND tipo = 'OS' AND status != 'cancelado'
          ), 0),
          updated_at = ?
          WHERE id = ?
        ''', [sellerId, DateTime.now().toIso8601String(), sellerId]);
      }
      return deleted;
    });
  }

  /// Recoloca um documento finalizado/cancelado no fluxo operacional.
  /// Orçamentos voltam para aprovação e pedidos/OS voltam para a etapa
  /// posterior ao recebimento do pagamento.
  Future<OrderModel> reopen(OrderModel order) async {
    if (order.id == null) throw ArgumentError('Pedido sem identificador.');
    if (order.status != 'entregue' && order.status != 'cancelado') {
      throw StateError(
          'Somente pedidos entregues ou cancelados podem ser reabertos.');
    }

    final reopened = order.copyWith(
      status: order.tipo == 'ORCAMENTO'
          ? 'aguardando_pagamento'
          : 'pagamento_recebido',
      dataAtualizacao: DateTime.now().toIso8601String(),
    );
    await update(reopened);
    return reopened;
  }
}
