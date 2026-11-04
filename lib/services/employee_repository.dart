import '../models/employee_model.dart';
import '../core/database/app_database.dart';

class EmployeeRepository {
  final AppDatabase _db = AppDatabase();

  Future<List<EmployeeModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'employees',
      orderBy: 'name',
    );
    return result.map(EmployeeModel.fromMap).toList();
  }

  Future<EmployeeModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'employees',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return EmployeeModel.fromMap(result.first);
  }

  Future<EmployeeModel> create(EmployeeModel employee) async {
    final database = await _db.database;
    final map = employee.toMap();
    map.remove('id');
    final id = await database.insert('employees', map);
    final created = await getById(id);
    return created!;
  }

  Future<EmployeeModel> update(EmployeeModel employee) async {
    final database = await _db.database;
    final map = employee.toMap();
    map.remove('id');
    map.remove('created_at');
    await database.update(
      'employees',
      map,
      where: 'id = ?',
      whereArgs: [employee.id],
    );
    final updated = await getById(employee.id!);
    return updated!;
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'employees',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<EmployeeModel>> getActive() async {
    final database = await _db.database;
    final result = await database.query(
      'employees',
      where: 'active = 1',
      orderBy: 'name',
    );
    return result.map(EmployeeModel.fromMap).toList();
  }
}
