import '../models/product_model.dart';
import '../models/stock_movement_model.dart';
import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';

class StockRepository {
  final AppDatabase _db = AppDatabase();

  // REGISTRAR MOVIMENTAÇÃO
  Future<void> registrarMovimentacao(StockMovementModel movimento) async {
    final database = await _db.database;
    await database.insert('stock_movements', movimento.toMap());
  }

  // BUSCAR MOVIMENTAÇÕES DE UM PRODUTO
  Future<List<StockMovementModel>> getMovementsByProduct(int productId) async {
    final database = await _db.database;
    final result = await database.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => StockMovementModel.fromMap(map)).toList();
  }

  // BUSCAR TODAS MOVIMENTAÇÕES
  Future<List<StockMovementModel>> getAllMovements() async {
    final database = await _db.database;
    final result = await database.query(
      'stock_movements',
      orderBy: 'created_at DESC',
      limit: 100,
    );
    return result.map((map) => StockMovementModel.fromMap(map)).toList();
  }

  // BUSCAR MOVIMENTAÇÕES POR TIPO
  Future<List<StockMovementModel>> getMovementsByType(String type) async {
    final database = await _db.database;
    final result = await database.query(
      'stock_movements',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => StockMovementModel.fromMap(map)).toList();
  }

  // BUSCAR MOVIMENTAÇÕES POR PERÍODO
  Future<List<StockMovementModel>> getMovementsByPeriod(
    DateTime start,
    DateTime end,
  ) async {
    final database = await _db.database;
    final result = await database.query(
      'stock_movements',
      where: 'created_at BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => StockMovementModel.fromMap(map)).toList();
  }

  // ENTRADA DE ESTOQUE (Compra)
  Future<void> entradaEstoque({
    required ProductModel product,
    required double quantidade,
    required String motivo,
    int? supplierId,
    int? orderId,
  }) async {
    if (product.id == null) throw ArgumentError('Produto sem identificador.');
    if (quantidade <= 0) {
      throw ArgumentError('A quantidade de entrada deve ser maior que zero.');
    }
    final database = await _db.database;
    if (database is SupabaseDatabase) {
      await _cloudMove(database, product, quantidade, 'compra', motivo,
          supplierId: supplierId, orderId: orderId);
      return;
    }
    await database.transaction((transaction) async {
      final rows = await transaction.query('products',
          columns: ['estoque', 'nome'],
          where: 'id = ?',
          whereArgs: [product.id]);
      if (rows.isEmpty) throw StateError('Produto não encontrado.');
      final previousStock = (rows.first['estoque'] as num).toDouble();
      final newStock = previousStock + quantidade;
      final movement = StockMovementModel(
        productId: product.id!,
        productName: rows.first['nome'] as String,
        quantity: quantidade,
        type: 'compra',
        previousStock: previousStock,
        newStock: newStock,
        reason: motivo,
        supplierId: supplierId,
        orderId: orderId,
        createdAt: DateTime.now(),
      );
      await transaction.update(
        'products',
        {
          'estoque': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await transaction.insert('stock_movements', movement.toMap());
    });
  }

  // SAÍDA DE ESTOQUE (Venda)
  Future<void> saidaEstoque({
    required ProductModel product,
    required double quantidade,
    required String motivo,
    int? orderId,
  }) async {
    if (product.id == null) throw ArgumentError('Produto sem identificador.');
    if (quantidade <= 0) {
      throw ArgumentError('A quantidade de saída deve ser maior que zero.');
    }
    final database = await _db.database;
    if (database is SupabaseDatabase) {
      await _cloudMove(database, product, quantidade, 'venda', motivo,
          orderId: orderId);
      return;
    }
    await database.transaction((transaction) async {
      final rows = await transaction.query('products',
          columns: ['estoque', 'nome'],
          where: 'id = ?',
          whereArgs: [product.id]);
      if (rows.isEmpty) throw StateError('Produto não encontrado.');
      final previousStock = (rows.first['estoque'] as num).toDouble();
      final newStock = previousStock - quantidade;

      if (newStock < 0) {
        throw Exception('Estoque insuficiente! Disponível: $previousStock');
      }

      final movement = StockMovementModel(
        productId: product.id!,
        productName: rows.first['nome'] as String,
        quantity: quantidade,
        type: 'venda',
        previousStock: previousStock,
        newStock: newStock,
        reason: motivo,
        orderId: orderId,
        createdAt: DateTime.now(),
      );
      await transaction.update(
        'products',
        {
          'estoque': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await transaction.insert('stock_movements', movement.toMap());
    });
  }

  // AJUSTE MANUAL DE ESTOQUE
  Future<void> ajusteEstoque({
    required ProductModel product,
    required double novaQuantidade,
    required String motivo,
    int? userId,
  }) async {
    if (product.id == null) throw ArgumentError('Produto sem identificador.');
    if (novaQuantidade < 0) {
      throw ArgumentError('O estoque não pode ser negativo.');
    }
    final database = await _db.database;
    if (database is SupabaseDatabase) {
      await _cloudMove(database, product, novaQuantidade, 'ajuste', motivo,
          userId: userId);
      return;
    }
    await database.transaction((transaction) async {
      final rows = await transaction.query('products',
          columns: ['estoque', 'nome'],
          where: 'id = ?',
          whereArgs: [product.id]);
      if (rows.isEmpty) throw StateError('Produto não encontrado.');
      final previousStock = (rows.first['estoque'] as num).toDouble();
      final newStock = novaQuantidade;

      final movement = StockMovementModel(
        productId: product.id!,
        productName: rows.first['nome'] as String,
        quantity: (newStock - previousStock).abs(),
        type: 'ajuste',
        previousStock: previousStock,
        newStock: newStock,
        reason: motivo,
        userId: userId,
        createdAt: DateTime.now(),
      );
      await transaction.update(
        'products',
        {
          'estoque': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await transaction.insert('stock_movements', movement.toMap());
    });
  }

  // RESUMO DO ESTOQUE
  Future<void> _cloudMove(SupabaseDatabase database, ProductModel product,
      double quantity, String kind, String reason,
      {int? supplierId, int? orderId, int? userId}) async {
    await database.rpc('matterdi_stock_move', {
      'p_product_id': product.id,
      'p_quantity': quantity,
      'p_kind': kind,
      'p_reason': reason,
      'p_supplier_id': supplierId,
      'p_order_id': orderId,
      'p_user_id': userId,
      'p_created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> getResumoEstoque() async {
    final database = await _db.database;

    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_produtos,
        SUM(estoque) as total_estoque,
        SUM(estoque * preco) as valor_total_estoque,
        COUNT(CASE WHEN estoque <= 0 THEN 1 END) as produtos_esgotados,
        COUNT(CASE WHEN estoque < 10 AND estoque > 0 THEN 1 END) as produtos_baixo,
        COUNT(CASE WHEN estoque < 5 AND estoque > 0 THEN 1 END) as produtos_criticos
      FROM products
      WHERE ativo = 1
    ''');

    if (result.isEmpty) {
      return {
        'total_produtos': 0,
        'total_estoque': 0.0,
        'valor_total_estoque': 0.0,
        'produtos_esgotados': 0,
        'produtos_baixo': 0,
        'produtos_criticos': 0,
      };
    }
    return result.first;
  }
}
