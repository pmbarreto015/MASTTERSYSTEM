import '../models/seller_model.dart';
import '../core/database/app_database.dart';

class SalesRepository {
  final AppDatabase _db = AppDatabase();

  Future<List<SellerModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'sellers',
      orderBy: 'name',
    );
    return result.map(SellerModel.fromMap).toList();
  }

  Future<SellerModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'sellers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return SellerModel.fromMap(result.first);
  }

  Future<SellerModel> create(SellerModel seller) async {
    final database = await _db.database;
    final map = seller.toMap();
    map.remove('id');
    final id = await database.insert('sellers', map);
    final created = await getById(id);
    return created!;
  }

  Future<SellerModel> update(SellerModel seller) async {
    final database = await _db.database;
    final map = seller.toMap();
    map.remove('id');
    map.remove('created_at');
    await database.update(
      'sellers',
      map,
      where: 'id = ?',
      whereArgs: [seller.id],
    );
    final updated = await getById(seller.id!);
    return updated!;
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'sellers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ATUALIZAR VENDAS DO VENDEDOR - SOMA TODOS OS PEDIDOS
  Future<void> atualizarVendasVendedor(int sellerId) async {
    final database = await _db.database;

    // Soma total das vendas do vendedor (apenas pedidos não cancelados)
    final result = await database.rawQuery('''
      SELECT 
        COALESCE(SUM(total), 0) as total_vendas,
        COUNT(id) as total_pedidos
      FROM orders 
      WHERE seller_id = ? AND tipo = 'OS' AND status != 'cancelado'
    ''', [sellerId]);

    final totalVendas = result.isNotEmpty
        ? (result.first['total_vendas'] as num).toDouble()
        : 0.0;

    // Atualiza o vendedor
    await database.update(
      'sellers',
      {'total_sales': totalVendas},
      where: 'id = ?',
      whereArgs: [sellerId],
    );
  }

  // ATUALIZAR TODOS OS VENDEDORES
  Future<void> atualizarTodosVendedores() async {
    final database = await _db.database;

    // Busca todos os vendedores
    final vendedores = await database.query('sellers');

    for (var v in vendedores) {
      final sellerId = v['id'] as int;

      // Soma as vendas de cada vendedor
      final result = await database.rawQuery('''
        SELECT 
          COALESCE(SUM(total), 0) as total_vendas
        FROM orders 
        WHERE seller_id = ? AND tipo = 'OS' AND status != 'cancelado'
      ''', [sellerId]);

      final totalVendas = result.isNotEmpty
          ? (result.first['total_vendas'] as num).toDouble()
          : 0.0;

      // Atualiza o vendedor
      await database.update(
        'sellers',
        {'total_sales': totalVendas},
        where: 'id = ?',
        whereArgs: [sellerId],
      );
    }
  }

  // BUSCAR VENDEDORES COM TOTAL DE VENDAS
  Future<List<Map<String, dynamic>>> getSalesBySeller() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT 
        s.id,
        s.name as vendedor,
        s.commission,
        s.total_sales as total_vendas,
        COALESCE(SUM(o.total * s.commission / 100), 0) as total_comissao,
        COUNT(o.id) as quantidade_pedidos
      FROM sellers s
      LEFT JOIN orders o ON o.seller_id = s.id AND o.tipo = 'OS' AND o.status != 'cancelado'
      GROUP BY s.id
      ORDER BY total_vendas DESC
    ''');
    return result;
  }

  // DASHBOARD DE VENDEDORES
  Future<Map<String, dynamic>> getDashboardVendedores() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_vendedores,
        SUM(total_sales) as total_vendas_geral,
        AVG(commission) as media_comissao,
        MAX(total_sales) as melhor_venda,
        (SELECT name FROM sellers ORDER BY total_sales DESC LIMIT 1) as melhor_vendedor
      FROM sellers
      WHERE active = 1
    ''');

    if (result.isEmpty) {
      return {
        'total_vendedores': 0,
        'total_vendas_geral': 0.0,
        'media_comissao': 0.0,
        'melhor_venda': 0.0,
        'melhor_vendedor': 'Nenhum',
      };
    }
    return result.first;
  }
}
