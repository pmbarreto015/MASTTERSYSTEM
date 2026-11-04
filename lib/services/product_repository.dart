import '../models/product_model.dart';
import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';

class ProductRepository {
  final AppDatabase _db = AppDatabase();

  // BUSCAR PRODUTO POR ID - ADICIONADO
  Future<ProductModel?> getById(int id) async {
    try {
      final database = await _db.database;
      final result = await database.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (result.isEmpty) return null;
      return ProductModel.fromMap(result.first);
    } catch (e) {
      print('Erro ao buscar produto: $e');
      return null;
    }
  }

  // Buscar por termo
  Future<List<ProductModel>> search(String query) async {
    try {
      final database = await _db.database;
      final result = await database.query(
        'products',
        where: 'nome LIKE ? OR codigo LIKE ? OR categoria LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%'],
        orderBy: 'nome COLLATE NOCASE',
      );
      return result.map((map) => ProductModel.fromMap(map)).toList();
    } catch (e) {
      print('Erro no search: $e');
      return [];
    }
  }

  // Buscar por nome
  Future<List<ProductModel>> searchByName(String name) async {
    try {
      final database = await _db.database;
      final result = await database.query(
        'products',
        where: 'nome LIKE ?',
        whereArgs: ['%$name%'],
        orderBy: 'nome COLLATE NOCASE',
      );
      return result.map((map) => ProductModel.fromMap(map)).toList();
    } catch (e) {
      print('Erro no searchByName: $e');
      return [];
    }
  }

  // Buscar todos COM FALLBACK
  Future<List<ProductModel>> getAll() async {
    try {
      final database = await _db.database;
      final result = await database.query(
        'products',
        orderBy: 'nome COLLATE NOCASE',
      );

      if (result.isEmpty) {
        print('Tabela products vazia');
        return [];
      }

      return result.map((map) => ProductModel.fromMap(map)).toList();
    } catch (e) {
      print('Erro ao buscar produtos: $e');
      return [];
    }
  }

  // Inserir um produto
  Future<int> insert(ProductModel product) async {
    try {
      final database = await _db.database;
      final map = product.toMap()..remove('id');
      return await database.insert('products', map);
    } catch (e) {
      print('Erro ao inserir produto: $e');
      return -1;
    }
  }

  // Inserir múltiplos produtos (bulk insert)
  Future<void> bulkInsert(List<ProductModel> products) async {
    try {
      final database = await _db.database;
      if (database is SupabaseDatabase) {
        await database.rpc('matterdi_product_bulk_insert', {
          'p_rows':
              products.map((product) => product.toMap()..remove('id')).toList(),
        });
        return;
      }
      final batch = database.batch();

      for (final product in products) {
        final map = product.toMap()..remove('id');
        batch.insert('products', map);
      }

      await batch.commit(noResult: true);
    } catch (e) {
      print('Erro no bulkInsert: $e');
    }
  }

  // Atualizar um produto
  Future<int> update(ProductModel product) async {
    try {
      final database = await _db.database;
      final map = product.toMap()..remove('id');
      return await database.update(
        'products',
        map,
        where: 'id = ?',
        whereArgs: [product.id],
      );
    } catch (e) {
      print('Erro ao atualizar produto: $e');
      return -1;
    }
  }

  // Deletar um produto
  Future<int> delete(int id) async {
    try {
      final database = await _db.database;
      return await database.delete(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Erro ao deletar produto: $e');
      return -1;
    }
  }

  /// Exclui vários produtos em uma única transação.
  ///
  /// A transação evita uma exclusão parcial caso algum produto esteja ligado
  /// a um pedido já gravado e o SQLite bloqueie a operação.
  Future<int> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return 0;

    final database = await _db.database;
    if (database is SupabaseDatabase) {
      final result =
          await database.rpc('matterdi_product_delete_many', {'p_ids': ids});
      return (result as num).toInt();
    }
    return database.transaction((txn) async {
      var deleted = 0;
      for (final id in ids) {
        final compositions = await txn.query(
          'composicoes',
          columns: ['id'],
          where: 'produto_id = ?',
          whereArgs: [id],
        );
        for (final composition in compositions) {
          await txn.delete(
            'composicao_itens',
            where: 'composicao_id = ?',
            whereArgs: [composition['id']],
          );
        }
        await txn.delete(
          'composicoes',
          where: 'produto_id = ?',
          whereArgs: [id],
        );
        deleted += await txn.delete(
          'products',
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return deleted;
    });
  }
}
