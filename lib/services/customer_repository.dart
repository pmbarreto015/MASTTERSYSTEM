import '../models/customer_model.dart';
import '../core/database/app_database.dart';

class CustomerRepository {
  final AppDatabase _db = AppDatabase();

  // Buscar todos os clientes
  Future<List<CustomerModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'customers',
      where: 'deleted_at IS NULL',
      orderBy: 'name',
    );
    return result.map(CustomerModel.fromMap).toList();
  }

  // Buscar cliente por ID
  Future<CustomerModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'customers',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return CustomerModel.fromMap(result.first);
  }

  // Buscar cliente por UUID
  Future<CustomerModel?> getByUuid(String uuid) async {
    final database = await _db.database;
    final result = await database.query(
      'customers',
      where: 'uuid = ? AND deleted_at IS NULL',
      whereArgs: [uuid],
    );
    if (result.isEmpty) return null;
    return CustomerModel.fromMap(result.first);
  }

  // Buscar clientes por nome
  Future<List<CustomerModel>> searchByName(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'customers',
      where: 'name LIKE ? AND deleted_at IS NULL',
      whereArgs: ['%$query%'],
      orderBy: 'name',
    );
    return result.map(CustomerModel.fromMap).toList();
  }

  // Criar novo cliente
  Future<CustomerModel> create(CustomerModel customer) async {
    final database = await _db.database;
    final map = customer.toMap();
    map.remove('id'); // Remove id para auto increment
    final id = await database.insert('customers', map);
    return customer.copyWith(id: id);
  }

  // Atualizar cliente
  Future<CustomerModel> update(CustomerModel customer) async {
    final database = await _db.database;
    final map = customer.toMap();
    map.remove('id');
    map.remove('created_at');
    await database.update(
      'customers',
      map,
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    return customer;
  }

  // Deletar cliente (soft delete)
  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.update(
      'customers',
      {
        'deleted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Adicionar compra ao cliente
  Future<void> addPurchase(int customerId, double value) async {
    final database = await _db.database;
    await database.rawUpdate(
      'UPDATE customers SET total_purchases = total_purchases + ? WHERE id = ?',
      [value, customerId],
    );
  }

  // Buscar clientes VIP (total compras > 3000)
  Future<List<CustomerModel>> getVipCustomers() async {
    final database = await _db.database;
    final result = await database.query(
      'customers',
      where: 'total_purchases > 3000 AND deleted_at IS NULL',
      orderBy: 'total_purchases DESC',
    );
    return result.map(CustomerModel.fromMap).toList();
  }
}
