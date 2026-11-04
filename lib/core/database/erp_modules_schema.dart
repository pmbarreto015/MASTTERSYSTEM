import 'package:sqflite/sqflite.dart';

Future<void> createErpModulesSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS erp_module_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      module TEXT NOT NULL CHECK (module IN ('financeiro', 'rh', 'entregas')),
      record_type TEXT NOT NULL,
      title TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'ativo',
      payload TEXT NOT NULL DEFAULT '{}',
      reference_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(module, record_type, reference_id)
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_erp_module_type ON erp_module_records(module, record_type)');
}
