// lib/services/maquina_repository.dart

import 'package:sqflite/sqflite.dart';
import '../models/maquina_model.dart';
import '../core/database/app_database.dart';

class MaquinaRepository {
  final AppDatabase _db = AppDatabase();

  // ============================================================
  // CRUD BÁSICO
  // ============================================================

  /// Buscar todas as máquinas
  Future<List<MaquinaModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'maquinas',
      orderBy: 'nome',
    );
    return result.map((map) => MaquinaModel.fromMap(map)).toList();
  }

  /// Buscar máquinas ativas
  Future<List<MaquinaModel>> getActive() async {
    final database = await _db.database;
    final result = await database.query(
      'maquinas',
      where: 'active = 1',
      orderBy: 'nome',
    );
    return result.map((map) => MaquinaModel.fromMap(map)).toList();
  }

  /// Buscar máquina por ID
  Future<MaquinaModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'maquinas',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return MaquinaModel.fromMap(result.first);
  }

  /// Buscar máquinas por tipo
  Future<List<MaquinaModel>> getByTipo(String tipo) async {
    final database = await _db.database;
    final result = await database.query(
      'maquinas',
      where: 'tipo = ?',
      whereArgs: [tipo],
      orderBy: 'nome',
    );
    return result.map((map) => MaquinaModel.fromMap(map)).toList();
  }

  /// Buscar máquinas (search)
  Future<List<MaquinaModel>> search(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'maquinas',
      where: 'nome LIKE ? OR modelo LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'nome',
    );
    return result.map((map) => MaquinaModel.fromMap(map)).toList();
  }

  // ============================================================
  // CRIAR / ATUALIZAR / DELETAR
  // ============================================================

  /// Criar nova máquina
  Future<MaquinaModel> create(MaquinaModel maquina) async {
    final database = await _db.database;
    maquina.recalcularCustos();
    final map = maquina.toMap();
    map.remove('id');
    final id = await database.insert('maquinas', map);
    final created = await getById(id);
    return created!;
  }

  /// Atualizar máquina
  Future<MaquinaModel> update(MaquinaModel maquina) async {
    final database = await _db.database;
    maquina.recalcularCustos();
    final map = maquina.toMap();
    map.remove('id');
    await database.update(
      'maquinas',
      map,
      where: 'id = ?',
      whereArgs: [maquina.id],
    );
    final updated = await getById(maquina.id!);
    return updated!;
  }

  /// Deletar máquina
  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'maquinas',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Desativar máquina
  Future<void> desativar(int id) async {
    final database = await _db.database;
    await database.update(
      'maquinas',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ativar máquina
  Future<void> ativar(int id) async {
    final database = await _db.database;
    await database.update(
      'maquinas',
      {'active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // ESTATÍSTICAS
  // ============================================================

  /// Total de máquinas
  Future<int> getTotal() async {
    final database = await _db.database;
    final result =
        await database.rawQuery('SELECT COUNT(*) as total FROM maquinas');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Total por tipo
  Future<Map<String, int>> getTotalPorTipo() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT tipo, COUNT(*) as total
      FROM maquinas
      WHERE active = 1
      GROUP BY tipo
    ''');
    final Map<String, int> totais = {};
    for (var row in result) {
      totais[row['tipo'] as String] = row['total'] as int;
    }
    return totais;
  }

  /// Custo total por hora de todas as máquinas
  Future<double> getCustoTotalHora() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT SUM(custo_total_hora) as total
      FROM maquinas
      WHERE active = 1
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
}
