// lib/services/material_repository.dart

import 'package:sqflite/sqflite.dart';
import '../models/material_model.dart';
import '../core/database/app_database.dart';

class MaterialRepository {
  final AppDatabase _db = AppDatabase();

  // ============================================================
  // CRUD BÁSICO
  // ============================================================

  /// Buscar todos os materiais
  Future<List<MaterialModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      orderBy: 'nome',
    );
    return result.map((map) => MaterialModel.fromMap(map)).toList();
  }

  /// Buscar materiais ativos
  Future<List<MaterialModel>> getActive() async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'active = 1',
      orderBy: 'nome',
    );
    return result.map((map) => MaterialModel.fromMap(map)).toList();
  }

  /// Buscar material por ID
  Future<MaterialModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return MaterialModel.fromMap(result.first);
  }

  /// Buscar material por código
  Future<MaterialModel?> getByCodigo(String codigo) async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'codigo = ?',
      whereArgs: [codigo],
    );
    if (result.isEmpty) return null;
    return MaterialModel.fromMap(result.first);
  }

  /// Buscar materiais por categoria
  Future<List<MaterialModel>> getByCategoria(String categoria) async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'categoria = ?',
      whereArgs: [categoria],
      orderBy: 'nome',
    );
    return result.map((map) => MaterialModel.fromMap(map)).toList();
  }

  /// Buscar materiais por tipo
  Future<List<MaterialModel>> getByTipo(String tipo) async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'tipo = ?',
      whereArgs: [tipo],
      orderBy: 'nome',
    );
    return result.map((map) => MaterialModel.fromMap(map)).toList();
  }

  /// Buscar materiais (search)
  Future<List<MaterialModel>> search(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'nome LIKE ? OR codigo LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'nome',
    );
    return result.map((map) => MaterialModel.fromMap(map)).toList();
  }

  // ============================================================
  // CRIAR / ATUALIZAR / DELETAR
  // ============================================================

  /// Criar novo material
  Future<MaterialModel> create(MaterialModel material) async {
    final database = await _db.database;
    final map = material.toMap();
    map.remove('id');
    final id = await database.insert('materiais', map);
    final created = await getById(id);
    return created!;
  }

  /// Atualizar material
  Future<MaterialModel> update(MaterialModel material) async {
    final database = await _db.database;
    final map = material.toMap();
    map.remove('id');
    await database.update(
      'materiais',
      map,
      where: 'id = ?',
      whereArgs: [material.id],
    );
    final updated = await getById(material.id!);
    return updated!;
  }

  /// Deletar material (hard delete)
  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'materiais',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Desativar material (soft delete)
  Future<void> desativar(int id) async {
    final database = await _db.database;
    await database.update(
      'materiais',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ativar material
  Future<void> ativar(int id) async {
    final database = await _db.database;
    await database.update(
      'materiais',
      {'active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // ESTOQUE
  // ============================================================

  /// Atualizar quantidade em estoque
  Future<void> atualizarEstoque(int id, double novaQuantidade) async {
    final database = await _db.database;
    await database.update(
      'materiais',
      {
        'quantidade_estoque': novaQuantidade,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Adicionar ao estoque
  Future<void> adicionarEstoque(int id, double quantidade) async {
    final material = await getById(id);
    if (material == null) return;
    final novaQuantidade = material.quantidadeEstoque + quantidade;
    await atualizarEstoque(id, novaQuantidade);
  }

  /// Remover do estoque
  Future<void> removerEstoque(int id, double quantidade) async {
    final material = await getById(id);
    if (material == null) return;
    final novaQuantidade = (material.quantidadeEstoque - quantidade)
        .clamp(0, double.infinity)
        .toDouble();
    await atualizarEstoque(id, novaQuantidade);
  }

  /// Verificar estoque baixo
  Future<List<MaterialModel>> getEstoqueBaixo() async {
    final database = await _db.database;
    final result = await database.query(
      'materiais',
      where: 'quantidade_estoque <= estoque_minimo AND active = 1',
      orderBy: 'quantidade_estoque',
    );
    return result.map((map) => MaterialModel.fromMap(map)).toList();
  }

  // ============================================================
  // ESTATÍSTICAS
  // ============================================================

  /// Total de materiais
  Future<int> getTotal() async {
    final database = await _db.database;
    final result =
        await database.rawQuery('SELECT COUNT(*) as total FROM materiais');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Total por categoria
  Future<Map<String, int>> getTotalPorCategoria() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT categoria, COUNT(*) as total
      FROM materiais
      WHERE active = 1
      GROUP BY categoria
    ''');
    final Map<String, int> totais = {};
    for (var row in result) {
      totais[row['categoria'] as String] = row['total'] as int;
    }
    return totais;
  }

  /// Valor total do estoque
  Future<double> getValorTotalEstoque() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT SUM(quantidade_estoque * preco_por_m2) as total
      FROM materiais
      WHERE active = 1
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
}
