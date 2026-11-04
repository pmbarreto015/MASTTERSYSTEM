import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masttersystem/services/database_rpc_server.dart';

/// Servidor independente para um banco existente, inclusive em uma VPS.
/// A chave é lida do ambiente ou de um arquivo, nunca da linha de comando.
Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length ||
        !const ['--database', '--port', '--bind', '--token-file']
            .contains(arguments[index])) {
      stderr.writeln('Uso: dart run tool/servidor_banco.dart '
          '--database CAMINHO.db [--port 8080] [--bind 127.0.0.1] '
          '[--token-file chave.txt]');
      exitCode = 64;
      return;
    }
    options[arguments[index]] = arguments[index + 1];
  }
  Database? database;
  DatabaseRpcServer? server;
  try {
    final file = File(options['--database'] ?? '');
    if (options['--database'] == null || !await file.exists()) {
      throw const FormatException(
          'Informe um arquivo .db existente do PC principal.');
    }
    final tokenFile = options['--token-file'];
    final token = (tokenFile == null
            ? Platform.environment['MATTERDI_DATABASE_TOKEN'] ?? ''
            : await File(tokenFile).readAsString())
        .trim();
    if (token.length < 24) {
      throw const FormatException('Configure MATTERDI_DATABASE_TOKEN ou '
          '--token-file com uma chave de pelo menos 24 caracteres.');
    }
    final port = int.tryParse(options['--port'] ?? '8080');
    if (port == null || port < 1024 || port > 65535) {
      throw const FormatException('A porta precisa estar entre 1024 e 65535.');
    }
    final bind = InternetAddress.tryParse(options['--bind'] ?? '127.0.0.1');
    if (bind == null) {
      throw const FormatException('Informe um IP válido em --bind.');
    }
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      file.absolute.path,
      options: OpenDatabaseOptions(onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA busy_timeout = 10000');
      }),
    );
    if (await database.getVersion() != 28) {
      throw const FormatException('Atualize o banco no aplicativo do PC antes '
          'de iniciar este servidor (versão esperada: 28).');
    }
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('customers','products','orders','system_users')",
    );
    if (tables.length != 4) {
      throw const FormatException(
          'O arquivo não é um banco completo do MatterdiSistem.');
    }
    server = DatabaseRpcServer(database: database, token: token);
    await server.start(address: bind, port: port);
    stdout.writeln('Servidor de dados ativo em ${bind.address}:$port.');
    stdout.writeln('Banco: ${file.absolute.path}');
    stdout.writeln('Pressione Ctrl+C para encerrar.');
    final stopped = Completer<void>();
    final subscriptions = <StreamSubscription<ProcessSignal>>[];
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm
    ]) {
      subscriptions.add(signal.watch().listen((_) {
        if (!stopped.isCompleted) stopped.complete();
      }));
    }
    await stopped.future;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  } catch (error) {
    stderr.writeln('Não foi possível executar o servidor: $error');
    exitCode = 1;
  } finally {
    await server?.stop();
    await database?.close();
  }
}
