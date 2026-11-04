import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../tool/exportar_sqlite_supabase.dart' as exporter;

void main() {
  setUp(() => exitCode = 0);
  tearDown(() => exitCode = 0);

  test('refuses normalized source path as output even with force', () async {
    final directory = await Directory.systemTemp.createTemp('matterdi-export-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.db');
    await source.writeAsString('original database contents');
    final before = await source.readAsBytes();
    await exporter.main([
      '--database',
      source.path,
      '--output',
      '${directory.path}${Platform.pathSeparator}.${Platform.pathSeparator}source.db',
      '--force',
    ]);
    expect(exitCode, 64);
    expect(await source.readAsBytes(), before);
    expect(directory.listSync(), hasLength(1));
  });

  test('failed export preserves existing destination and cleans staging',
      () async {
    final directory = await Directory.systemTemp.createTemp('matterdi-export-');
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = '${directory.path}${Platform.pathSeparator}source.db';
    final output = File('${directory.path}${Platform.pathSeparator}import.sql');
    final database = sqlite3.open(databasePath);
    database.userVersion = 26;
    database.close();
    await output.writeAsString('previous export');
    await exporter.main([
      '--database',
      databasePath,
      '--output',
      output.path,
      '--force',
    ]);
    expect(exitCode, 65);
    expect(await output.readAsString(), 'previous export');
    expect(
        directory.listSync().where((file) => file.path.contains('.incoming-')),
        isEmpty);
  });

  test('exports application tables without local users or legacy columns',
      () async {
    final directory = await Directory.systemTemp.createTemp('matterdi-export-');
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = '${directory.path}${Platform.pathSeparator}source.db';
    final outputPath = '${directory.path}${Platform.pathSeparator}import.sql';
    final database = sqlite3.open(databasePath);
    addTearDown(database.close);
    database.userVersion = 28;

    const tables = [
      'customers',
      'products',
      'insumos',
      'sellers',
      'suppliers',
      'employees',
      'materiais',
      'maquinas',
      'orders',
      'order_items',
      'financial',
      'stock_movements',
      'pontos',
      'holerites',
      'retalhos',
      'composicoes',
      'composicao_itens',
      'agenda_followups',
      'erp_module_records',
      'system_users',
    ];
    for (final table in tables) {
      if (table == 'products') {
        database.execute(
          'CREATE TABLE products ('
          'id INTEGER PRIMARY KEY, nome TEXT, '
          'valor_minuto_maquina REAL, tempo_estimado REAL)',
        );
      } else if (table == 'system_users') {
        database.execute(
          'CREATE TABLE system_users ('
          'id INTEGER PRIMARY KEY, username TEXT, password TEXT)',
        );
      } else {
        database.execute('CREATE TABLE "$table" (id INTEGER PRIMARY KEY)');
      }
    }
    database.execute(
      "INSERT INTO products VALUES (7, 'Placa', 12.5, 30)",
    );
    database.execute(
      "INSERT INTO system_users VALUES (1, 'admin', 'segredo-local')",
    );

    await exporter.main([
      '--database',
      databasePath,
      '--output',
      outputPath,
    ]);

    final sql = await File(outputPath).readAsString();
    expect(sql, contains('BEGIN;'));
    expect(sql, contains('INSERT INTO public."products" ("id", "nome")'));
    expect(sql, contains('Placa'));
    expect(sql, isNot(contains('valor_minuto_maquina')));
    expect(sql, isNot(contains('tempo_estimado')));
    expect(sql, isNot(contains('segredo-local')));
    expect(sql, isNot(contains('INSERT INTO public."system_users"')));
    expect(sql, contains('COMMIT;'));
  });
}
