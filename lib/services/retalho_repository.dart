// lib/services/retalho_repository.dart

import 'package:sqflite/sqflite.dart';
import '../models/retalho_model.dart';
import '../core/database/app_database.dart';

class RetalhoRepository {
  final AppDatabase _db = AppDatabase();

  // ============================================================
  // CRUD BÁSICO
  // ============================================================

  /// Buscar todos os retalhos
  Future<List<RetalhoModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      orderBy: 'created_at DESC',
    );
    return result.map((map) => RetalhoModel.fromMap(map)).toList();
  }

  /// Buscar retalhos disponíveis
  Future<List<RetalhoModel>> getDisponiveis() async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      where: 'status = ?',
      whereArgs: ['disponivel'],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => RetalhoModel.fromMap(map)).toList();
  }

  /// Buscar retalhos por status
  Future<List<RetalhoModel>> getByStatus(String status) async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => RetalhoModel.fromMap(map)).toList();
  }

  /// Buscar retalho por ID
  Future<RetalhoModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return RetalhoModel.fromMap(result.first);
  }

  /// Buscar retalhos por material
  Future<List<RetalhoModel>> getByMaterial(int materialId) async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => RetalhoModel.fromMap(map)).toList();
  }

  /// Buscar retalhos (search)
  Future<List<RetalhoModel>> search(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      where: 'nome LIKE ? OR codigo LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => RetalhoModel.fromMap(map)).toList();
  }

  // ============================================================
  // CRIAR / ATUALIZAR / DELETAR
  // ============================================================

  /// Criar novo retalho
  Future<RetalhoModel> create(RetalhoModel retalho) async {
    final database = await _db.database;
    final map = retalho.toMap();
    map.remove('id');
    final id = await database.insert('retalhos', map);
    final created = await getById(id);
    return created!;
  }

  /// Atualizar retalho
  Future<RetalhoModel> update(RetalhoModel retalho) async {
    final database = await _db.database;
    final map = retalho.toMap();
    map.remove('id');
    await database.update(
      'retalhos',
      map,
      where: 'id = ?',
      whereArgs: [retalho.id],
    );
    final updated = await getById(retalho.id!);
    return updated!;
  }

  /// Deletar retalho
  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'retalhos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // AÇÕES ESPECÍFICAS
  // ============================================================

  /// Reservar retalho
  Future<void> reservar(int id) async {
    final database = await _db.database;
    await database.update(
      'retalhos',
      {'status': 'reservado'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Utilizar retalho
  Future<void> utilizar(int id) async {
    final database = await _db.database;
    await database.update(
      'retalhos',
      {'status': 'utilizado'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Descartar retalho
  Future<void> descartar(int id) async {
    final database = await _db.database;
    await database.update(
      'retalhos',
      {'status': 'descartado'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Liberar retalho (voltar para disponível)
  Future<void> liberar(int id) async {
    final database = await _db.database;
    await database.update(
      'retalhos',
      {'status': 'disponivel'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // ESTATÍSTICAS
  // ============================================================

  /// Total de retalhos
  Future<int> getTotal() async {
    final database = await _db.database;
    final result =
        await database.rawQuery('SELECT COUNT(*) as total FROM retalhos');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Total por status
  Future<Map<String, int>> getTotalPorStatus() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT status, COUNT(*) as total
      FROM retalhos
      GROUP BY status
    ''');
    final Map<String, int> totais = {};
    for (var row in result) {
      totais[row['status'] as String] = row['total'] as int;
    }
    return totais;
  }

  /// Área total de retalhos disponíveis
  Future<double> getAreaTotalDisponivel() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT SUM(area) as total
      FROM retalhos
      WHERE status = 'disponivel'
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Valor total de retalhos disponíveis
  Future<double> getValorTotalDisponivel() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT SUM(valor_estimado) as total
      FROM retalhos
      WHERE status = 'disponivel'
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Encontrar retalhos por área mínima
  Future<List<RetalhoModel>> findPorAreaMinima(double areaMinima) async {
    final database = await _db.database;
    final result = await database.query(
      'retalhos',
      where: 'area >= ? AND status = ?',
      whereArgs: [areaMinima, 'disponivel'],
      orderBy: 'area ASC',
    );
    return result.map((map) => RetalhoModel.fromMap(map)).toList();
  }

  /// Encontrar melhor retalho para uma área
  Future<RetalhoModel?> findMelhorRetalho(double areaNecessaria,
      {int? materialId}) async {
    final database = await _db.database;
    String where = 'area >= ? AND status = ?';
    List<dynamic> whereArgs = [areaNecessaria, 'disponivel'];

    if (materialId != null) {
      where += ' AND material_id = ?';
      whereArgs.add(materialId);
    }

    final result = await database.query(
      'retalhos',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'area ASC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return RetalhoModel.fromMap(result.first);
  }
}
