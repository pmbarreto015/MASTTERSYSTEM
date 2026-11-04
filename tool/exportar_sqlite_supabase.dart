import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;

const _tables = <String>[
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
];

const _ignoredColumns = <String, Set<String>>{
  // Essas colunas apareceram em bancos SQLite antigos, mas nunca foram usadas
  // pelos modelos atuais nem fazem parte do esquema PostgreSQL.
  'products': {'valor_minuto_maquina', 'tempo_estimado'},
};

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  if (options == null) {
    stderr.writeln(
      'Uso: dart run ../../tool/exportar_sqlite_supabase.dart '
      '--database CAMINHO.db --output importar_matterdi.sql [--force]',
    );
    exitCode = 64;
    return;
  }

  final databaseFile = File(options.database).absolute;
  final outputFile = File(options.output).absolute;
  final sourcePath = path.normalize(databaseFile.path).toLowerCase();
  final destinationPath = path.normalize(outputFile.path).toLowerCase();
  final sameExistingFile = databaseFile.existsSync() &&
      outputFile.existsSync() &&
      databaseFile.resolveSymbolicLinksSync().toLowerCase() ==
          outputFile.resolveSymbolicLinksSync().toLowerCase();
  if (sourcePath == destinationPath || sameExistingFile) {
    stderr.writeln('Escolha um arquivo de saída diferente do banco SQLite.');
    exitCode = 64;
    return;
  }
  final stagingFile = File(
      '${outputFile.path}.incoming-$pid-${DateTime.now().microsecondsSinceEpoch}');
  if (!databaseFile.existsSync()) {
    stderr.writeln('Banco SQLite não encontrado: ${databaseFile.path}');
    exitCode = 66;
    return;
  }
  if (outputFile.existsSync() && !options.force) {
    stderr.writeln(
      'O arquivo de saída já existe. Use outro nome ou acrescente --force.',
    );
    exitCode = 73;
    return;
  }

  Database? database;
  IOSink? sink;
  try {
    database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    database.execute('BEGIN');
    final version = database.userVersion;
    if (version != 28) {
      throw FormatException(
        'Abra este banco na versão atual do MatterdiSistem antes de exportar '
        '(versão encontrada: $version; esperada: 28).',
      );
    }
    final existingTables = database
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    final missing = _tables.where((table) => !existingTables.contains(table));
    if (missing.isNotEmpty || !existingTables.contains('system_users')) {
      throw FormatException(
        'O arquivo não é um banco completo do MatterdiSistem. '
        'Tabelas ausentes: ${missing.join(', ')}',
      );
    }

    final brokenReferences = database.select('PRAGMA foreign_key_check');
    if (brokenReferences.isNotEmpty) {
      throw FormatException(
          'O banco contém ${brokenReferences.length} referências inválidas. Corrija-as antes de importar no Supabase.');
    }
    outputFile.parent.createSync(recursive: true);
    sink = stagingFile.openWrite(mode: FileMode.writeOnly);
    sink.writeln('-- Importação gerada pelo MatterdiSistem.');
    sink.writeln('-- Aplique primeiro todas as migrations da pasta supabase.');
    sink.writeln('-- Senhas e system_users não são exportados.');
    sink.writeln('BEGIN;');
    sink.writeln("SET LOCAL statement_timeout = '15min';");

    var totalRows = 0;
    for (final table in _tables) {
      final columns = database
          .select('PRAGMA table_info("$table")')
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .where(
              (column) => !(_ignoredColumns[table]?.contains(column) ?? false))
          .toList(growable: false);
      if (columns.isEmpty) continue;

      final selectedColumns = columns.map(_quoteIdentifier).join(', ');
      final rows = database.select(
        'SELECT $selectedColumns FROM ${_quoteIdentifier(table)} ORDER BY id',
      );
      const chunkSize = 500;
      for (var offset = 0; offset < rows.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, rows.length);
        final values = <Map<String, Object?>>[];
        for (final row in rows.getRange(offset, end)) {
          values.add({
            for (final column in columns)
              column: _jsonValue(row[column], table: table, column: column),
          });
        }
        final json = jsonEncode(values);
        final tag = _dollarTag(json);
        sink.writeln(
          'INSERT INTO public.${_quoteIdentifier(table)} ($selectedColumns)',
        );
        sink.writeln(
          'SELECT $selectedColumns FROM jsonb_populate_recordset('
          'NULL::public.${_quoteIdentifier(table)}, $tag$json$tag::jsonb);',
        );
        totalRows += values.length;
      }
      sink.writeln(
        "SELECT setval(pg_get_serial_sequence('public.$table', 'id'), "
        'COALESCE((SELECT MAX(id) FROM public.${_quoteIdentifier(table)}), 1), '
        'EXISTS (SELECT 1 FROM public.${_quoteIdentifier(table)}));',
      );
    }
    sink.writeln('COMMIT;');
    sink.writeln('-- $totalRows registros exportados.');
    await sink.flush();
    await sink.close();
    sink = null;
    await stagingFile.rename(outputFile.path);
    stdout.writeln('$totalRows registros exportados para ${outputFile.path}');
    stdout.writeln(
      'Revise o arquivo e execute-o no SQL Editor do Supabase após as migrations.',
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } catch (error) {
    stderr.writeln('Não foi possível exportar: $error');
    exitCode = 1;
  } finally {
    await sink?.close();
    database?.close();
    if (await stagingFile.exists()) await stagingFile.delete();
  }
}

Object? _jsonValue(
  Object? value, {
  required String table,
  required String column,
}) {
  if (value == null || value is num || value is String) return value;
  if (value is Uint8List) {
    throw FormatException(
      'A coluna $table.$column contém dados binários não suportados.',
    );
  }
  return value.toString();
}

String _quoteIdentifier(String value) {
  if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(value)) {
    throw FormatException('Identificador inesperado no banco: $value');
  }
  return '"$value"';
}

String _dollarTag(String contents) {
  var suffix = 0;
  while (true) {
    final tag = suffix == 0 ? r'$matterdi_data$' : '\$matterdi_data_$suffix\$';
    if (!contents.contains(tag)) return tag;
    suffix++;
  }
}

_Options? _parseArguments(List<String> arguments) {
  String? database;
  String? output;
  var force = false;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--force') {
      force = true;
      continue;
    }
    if ((argument == '--database' || argument == '--output') &&
        index + 1 < arguments.length) {
      final value = arguments[++index];
      if (argument == '--database') {
        database = value;
      } else {
        output = value;
      }
      continue;
    }
    return null;
  }
  if (database == null || output == null) return null;
  return _Options(database, output, force);
}

class _Options {
  const _Options(this.database, this.output, this.force);

  final String database;
  final String output;
  final bool force;
}
