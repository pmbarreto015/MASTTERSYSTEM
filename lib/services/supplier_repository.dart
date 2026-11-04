import '../models/supplier_model.dart';
import '../core/database/app_database.dart';

class SupplierRepository {
  final AppDatabase _db = AppDatabase();

  Future<List<SupplierModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'suppliers',
      orderBy: 'name',
    );
    return result.map(SupplierModel.fromMap).toList();
  }

  Future<SupplierModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return SupplierModel.fromMap(result.first);
  }

  Future<SupplierModel> create(SupplierModel supplier) async {
    final database = await _db.database;
    final map = supplier.toMap();
    map.remove('id');
    final id = await database.insert('suppliers', map);

    // CORREÇÃO: Buscar o fornecedor criado e retornar com o ID
    final created = await getById(id);
    return created!;
  }

  Future<SupplierModel> update(SupplierModel supplier) async {
    final database = await _db.database;
    final map = supplier.toMap();
    map.remove('id');
    map.remove('created_at');
    await database.update(
      'suppliers',
      map,
      where: 'id = ?',
      whereArgs: [supplier.id],
    );

    // Buscar o fornecedor atualizado
    final updated = await getById(supplier.id!);
    return updated!;
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SupplierModel>> search(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'suppliers',
      where: 'name LIKE ? OR product LIKE ? OR document LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'name',
    );
    return result.map(SupplierModel.fromMap).toList();
  }
}
