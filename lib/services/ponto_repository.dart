import '../models/ponto_model.dart';
import '../core/database/app_database.dart';

class PontoRepository {
  final AppDatabase _db = AppDatabase();

  Future<PontoModel> create(PontoModel ponto) async {
    final database = await _db.database;
    final map = ponto.toMap();
    map.remove('id');
    final id = await database.insert('pontos', map);
    final created = await getById(id);
    return created!;
  }

  Future<PontoModel> update(PontoModel ponto) async {
    final database = await _db.database;
    final map = ponto.toMap();
    map.remove('id');
    map.remove('created_at');
    await database.update(
      'pontos',
      map,
      where: 'id = ?',
      whereArgs: [ponto.id],
    );
    final updated = await getById(ponto.id!);
    return updated!;
  }

  Future<PontoModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'pontos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return PontoModel.fromMap(result.first);
  }

  Future<List<PontoModel>> getByEmployeeId(int employeeId) async {
    final database = await _db.database;
    final result = await database.query(
      'pontos',
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      orderBy: 'data DESC',
    );
    return result.map((map) => PontoModel.fromMap(map)).toList();
  }

  // CORRIGIDO - USAR ASPAS SIMPLES NO SQLITE
  Future<List<PontoModel>> getByEmployeeAndMonth(
      int employeeId, String mesReferencia) async {
    final database = await _db.database;
    // CORREÇÃO: usar aspas simples '%Y-%m' em vez de "%Y-%m"
    final result = await database.rawQuery(
      "SELECT * FROM pontos WHERE employee_id = ? AND strftime('%Y-%m', data) = ? ORDER BY data DESC",
      [employeeId, mesReferencia],
    );
    return result.map((map) => PontoModel.fromMap(map)).toList();
  }

  Future<PontoModel?> getTodayByEmployee(int employeeId) async {
    final database = await _db.database;
    final hoje = DateTime.now().toIso8601String().split('T')[0];
    final result = await database.query(
      'pontos',
      where: 'employee_id = ? AND date(data) = date(?)',
      whereArgs: [employeeId, hoje],
    );
    if (result.isEmpty) return null;
    return PontoModel.fromMap(result.first);
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'pontos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> getResumoMensal(
      int employeeId, String mesReferencia) async {
    final database = await _db.database;
    // CORREÇÃO: usar aspas simples '%Y-%m'
    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as dias_trabalhados,
        SUM(horas_trabalhadas) as total_horas,
        SUM(horas_extras) as total_horas_extras
      FROM pontos
      WHERE employee_id = ? AND strftime('%Y-%m', data) = ?
    ''', [employeeId, mesReferencia]);

    if (result.isEmpty) {
      return {
        'dias_trabalhados': 0,
        'total_horas': 0.0,
        'total_horas_extras': 0.0,
      };
    }
    return result.first;
  }
}
