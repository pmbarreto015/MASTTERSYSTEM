import '../core/database/app_database.dart';
import '../models/erp_module_record.dart';

class ErpModuleRepository {
  ErpModuleRepository({AppDatabase? database})
      : _db = database ?? AppDatabase();
  final AppDatabase _db;

  Future<List<ErpModuleRecord>> list(String module,
      {String? recordType}) async {
    _validateModule(module);
    if (recordType != null) _validateType(recordType);
    final db = await _db.database;
    final rows = await db.query(
      'erp_module_records',
      where:
          recordType == null ? 'module = ?' : 'module = ? AND record_type = ?',
      whereArgs: [module, if (recordType != null) recordType],
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(ErpModuleRecord.fromMap).toList();
  }

  Future<List<ErpModuleRecord>> getAll(
          {required String module, String? recordType}) =>
      list(module, recordType: recordType);

  Future<ErpModuleRecord?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('erp_module_records',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ErpModuleRecord.fromMap(rows.single);
  }

  Future<ErpModuleRecord> save(ErpModuleRecord record) async {
    _validateModule(record.module);
    _validateType(record.recordType);
    if (record.title.trim().isEmpty)
      throw ArgumentError('Informe o título do registro.');
    if (record.status.trim().isEmpty)
      throw ArgumentError('Informe a situação do registro.');
    final db = await _db.database;
    final saved =
        record.copyWith(title: record.title.trim(), updatedAt: DateTime.now());
    final map = saved.toMap()..remove('id');
    if (record.id == null) {
      final id = await db.insert('erp_module_records', map);
      return saved.copyWith(id: id);
    }
    map.remove('created_at');
    final count = await db.update('erp_module_records', map,
        where: 'id = ? AND module = ? AND record_type = ?',
        whereArgs: [record.id, record.module, record.recordType]);
    if (count != 1)
      throw StateError(
          'Registro não encontrado ou sem permissão de alteração.');
    return saved;
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    final count =
        await db.delete('erp_module_records', where: 'id = ?', whereArgs: [id]);
    if (count != 1)
      throw StateError('Registro não encontrado ou sem permissão de exclusão.');
  }

  static void _validateModule(String module) {
    if (!const {'financeiro', 'rh', 'entregas'}.contains(module)) {
      throw ArgumentError('Módulo inválido.');
    }
  }

  static void _validateType(String type) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,59}$').hasMatch(type)) {
      throw ArgumentError('Tipo de registro inválido.');
    }
  }
}
