import '../models/insumo_model.dart';
import '../core/database/app_database.dart';

class InsumoRepository {
  final AppDatabase _db = AppDatabase();

  Future<List<InsumoModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'insumos',
      orderBy: 'nome',
    );
    return result.map((map) => InsumoModel.fromMap(map)).toList();
  }

  Future<List<InsumoModel>> getByCategoria(String categoria) async {
    final database = await _db.database;
    final result = await database.query(
      'insumos',
      where: 'categoria = ?',
      whereArgs: [categoria],
      orderBy: 'nome',
    );
    return result.map((map) => InsumoModel.fromMap(map)).toList();
  }

  Future<List<InsumoModel>> search(String query) async {
    final database = await _db.database;
    final result = await database.query(
      'insumos',
      where: 'nome LIKE ? OR codigo LIKE ? OR categoria LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'nome',
    );
    return result.map((map) => InsumoModel.fromMap(map)).toList();
  }

  Future<InsumoModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'insumos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return InsumoModel.fromMap(result.first);
  }

  Future<InsumoModel> create(InsumoModel insumo) async {
    final database = await _db.database;
    final map = insumo.toMap();
    map.remove('id');
    final id = await database.insert('insumos', map);
    final created = await getById(id);
    return created!;
  }

  Future<InsumoModel> update(InsumoModel insumo) async {
    final database = await _db.database;
    final map = insumo.toMap();
    map.remove('id');
    map.remove('created_at');
    await database.update(
      'insumos',
      map,
      where: 'id = ?',
      whereArgs: [insumo.id],
    );
    final updated = await getById(insumo.id!);
    return updated!;
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'insumos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // AJUSTAR QUANTIDADE
  Future<void> ajustarQuantidade(int id, double novaQuantidade) async {
    final database = await _db.database;
    await database.update(
      'insumos',
      {
        'quantidade': novaQuantidade,
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // RESUMO POR CATEGORIA
  Future<Map<String, double>> getResumoPorCategoria() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT categoria, SUM(quantidade) as total
      FROM insumos
      WHERE active = 1
      GROUP BY categoria
    ''');

    final Map<String, double> resumo = {};
    for (var row in result) {
      resumo[row['categoria'] as String] = (row['total'] as num).toDouble();
    }
    return resumo;
  }

  // TOTAL DE INSUMOS
  Future<Map<String, dynamic>> getTotais() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_itens,
        SUM(quantidade) as total_quantidade,
        SUM(quantidade * preco_unitario) as valor_total,
        COUNT(CASE WHEN quantidade <= estoque_minimo THEN 1 END) as itens_baixos,
        COUNT(CASE WHEN quantidade <= 0 THEN 1 END) as itens_esgotados
      FROM insumos
      WHERE active = 1
    ''');

    if (result.isEmpty) {
      return {
        'total_itens': 0,
        'total_quantidade': 0.0,
        'valor_total': 0.0,
        'itens_baixos': 0,
        'itens_esgotados': 0,
      };
    }
    return result.first;
  }

  // CATEGORIAS DISPONÍVEIS
  List<String> getCategorias() {
    return [
      'Materiais',
      'Impressão',
      'Tintas',
      'Papelaria',
      'Ferramentas',
      'Embalagens',
      'Costura',
      'Adesivos',
      'Corte',
      'Outros'
    ];
  }

  List<String> getUnidades() {
    return ['un', 'm²', 'L', 'kg', 'g', 'cm', 'm', 'rolo', 'caixa', 'pacote'];
  }
}
