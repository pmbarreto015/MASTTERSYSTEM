import '../core/database/app_database.dart';
import '../models/purchase_order_model.dart';

class PurchaseOrderRepository {
  final AppDatabase _db = AppDatabase();

  Future<List<PurchaseOrderModel>> getAll() async {
    final database = await _db.database;
    final rows = await database.query(
      'purchase_orders',
      orderBy: 'created_at DESC',
    );
    return rows.map(PurchaseOrderModel.fromMap).toList();
  }

  Future<PurchaseOrderModel> create(PurchaseOrderModel order) async {
    final database = await _db.database;
    final values = order.toMap()..remove('id');
    final id = await database.insert('purchase_orders', values);
    return order.copyWith(id: id);
  }

  Future<void> update(PurchaseOrderModel order) async {
    if (order.id == null) throw ArgumentError('Ordem de compra sem ID.');
    final database = await _db.database;
    final values = order.toMap()
      ..remove('id')
      ..remove('created_at');
    await database.update(
      'purchase_orders',
      values,
      where: 'id = ?',
      whereArgs: [order.id],
    );
  }
}
