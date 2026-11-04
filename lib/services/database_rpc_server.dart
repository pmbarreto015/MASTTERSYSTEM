import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqflite/sqlite_api.dart';

/// Expõe o banco já aberto pelo PC, preservando as transações do SQLite.
class DatabaseRpcServer {
  DatabaseRpcServer({
    required Database database,
    required String token,
    Duration transactionIdleTimeout = const Duration(seconds: 30),
  })  : _database = database,
        _token = token.trim(),
        _idleTimeout = transactionIdleTimeout {
    if (token.trim().length < 24 || token.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError(
          'A chave de acesso precisa ter pelo menos 24 caracteres.');
    }
    if (transactionIdleTimeout <= Duration.zero) {
      throw ArgumentError('O prazo da transação deve ser maior que zero.');
    }
  }

  static const _maximumBodyBytes = 2 * 1024 * 1024;
  final Duration _idleTimeout;
  final Database _database;
  final String _token;
  final Map<String, _TransactionSession> _sessions = {};
  final Random _random = Random.secure();
  HttpServer? _server;
  int? _schemaVersion;
  bool _stopping = false;

  bool get isRunning => _server != null && !_stopping;
  int? get port => _server?.port;

  Future<void> start({InternetAddress? address, int port = 8080}) async {
    if (isRunning) return;
    if (_stopping) {
      throw StateError('O servidor de dados está sendo encerrado.');
    }
    if (!_database.isOpen) {
      throw StateError('Abra o banco de dados antes de iniciar o servidor.');
    }
    final version = await _database.getVersion();
    if (version != 29) {
      throw StateError(
          'Atualize o banco do PC para a versão 29 antes de iniciar o servidor.');
    }
    _schemaVersion = version;
    final server =
        await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (_) {},
      onDone: () {
        if (identical(_server, server)) _server = null;
      },
    );
  }

  Future<void> stop() async {
    _stopping = true;
    final server = _server;
    _server = null;
    try {
      // Rollback também encerra sessões que aguardam o bloqueio do SQLite.
      final sessions = _sessions.values.toList();
      for (final session in sessions) {
        _requestFinish(session, commit: false);
      }
      await server?.close(force: true);
      await Future.wait(sessions.map((session) => session.finished.future));
    } finally {
      _stopping = false;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    String? transactionId;
    // Um erro de socket durante a operação libera a transação do cliente.
    unawaited(request.response.done.then<void>((_) {}, onError: (Object _) {
      final session = _sessions[transactionId];
      if (session != null) _requestFinish(session, commit: false);
    }));
    try {
      if (!_authenticated(
          request.headers.value(HttpHeaders.authorizationHeader))) {
        throw const _RpcError(
            'Chave de acesso ausente ou inválida.', HttpStatus.unauthorized);
      }
      if (!isRunning) {
        throw const _RpcError('O servidor de dados está indisponível.',
            HttpStatus.serviceUnavailable);
      }
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _respond(request, HttpStatus.ok, {
          'service': 'matterdi-database',
          'protocol': 1,
          'version': _schemaVersion,
        });
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/database') {
        throw const _RpcError(
            'Endereço ou método não disponível.', HttpStatus.notFound);
      }
      final body = await _readBody(request);
      final method = _requiredString(body, 'method');
      final params = _map(
          _decodeValues(body['params'] ?? const <String, Object?>{}), 'params');
      transactionId = _optionalString(body, 'transactionId');
      Object? result;
      if (method == 'begin') {
        if (transactionId != null) {
          throw const _RpcError(
              'Não é possível iniciar uma transação dentro de outra.');
        }
        final session =
            _beginSession(exclusive: _optionalBool(params, 'exclusive'));
        transactionId = session.id;
        await session.ready.future;
        result = session.id;
      } else if (method == 'commit' || method == 'rollback') {
        final session = _getSession(transactionId);
        final command = _requestFinish(session, commit: method == 'commit');
        await command.result.future;
      } else if (transactionId != null) {
        final session = _getSession(transactionId);
        final command = _TransactionCommand(method, params);
        session.commands.add(command);
        _refreshTimeout(session);
        result = await command.result.future;
      } else {
        result = await _execute(_database, method, params);
      }
      await _respond(request, HttpStatus.ok, {'result': result});
    } catch (error) {
      if (error is SocketException || error is HttpException) {
        final session = _sessions[transactionId];
        if (session != null) _requestFinish(session, commit: false);
      }
      final failure = _publicError(error);
      try {
        await _respond(request, failure.status, {'error': failure.message});
      } catch (_) {
        final session = _sessions[transactionId];
        if (session != null) _requestFinish(session, commit: false);
      }
    }
  }

  bool _authenticated(String? authorization) {
    final expected = 'Bearer $_token';
    if (authorization == null || authorization.length != expected.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= authorization.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<Map<String, Object?>> _readBody(HttpRequest request) async {
    if (request.contentLength > _maximumBodyBytes) {
      throw const _RpcError('A requisição excede o limite de 2 MB.',
          HttpStatus.requestEntityTooLarge);
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > _maximumBodyBytes) {
        throw const _RpcError('A requisição excede o limite de 2 MB.',
            HttpStatus.requestEntityTooLarge);
      }
      bytes.addAll(chunk);
    }
    try {
      return _map(jsonDecode(utf8.decode(bytes)), 'requisição');
    } on FormatException {
      throw const _RpcError('Envie uma requisição JSON válida.');
    }
  }

  Future<void> _respond(
      HttpRequest request, int status, Map<String, Object?> body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.write(jsonEncode(_encodeValues(body)));
    await request.response.close();
  }

  _TransactionSession _beginSession({bool? exclusive}) {
    if (_sessions.length >= 64) {
      throw const _RpcError(
          'Há muitas transações em andamento. Tente novamente.',
          HttpStatus.serviceUnavailable);
    }
    final id =
        base64Url.encode(List<int>.generate(32, (_) => _random.nextInt(256)));
    final session = _TransactionSession(id);
    _sessions[id] = session;
    _refreshTimeout(session);
    unawaited(_runSession(session, exclusive: exclusive));
    return session;
  }

  Future<void> _runSession(_TransactionSession session,
      {bool? exclusive}) async {
    Object? failure;
    try {
      await _database.transaction((transaction) async {
        if (session.closing) throw const _Rollback();
        if (!session.ready.isCompleted) session.ready.complete();
        await for (final command in session.commands.stream) {
          if (command.method == 'commit') {
            if (session.rollbackRequested) throw const _Rollback();
            return;
          }
          if (command.method == 'rollback') throw const _Rollback();
          session.timeout?.cancel();
          try {
            command.result.complete(
                await _execute(transaction, command.method, command.params));
          } catch (error, stack) {
            command.result.completeError(_publicError(error), stack);
          } finally {
            if (!session.closing) _refreshTimeout(session);
          }
        }
        throw const _Rollback();
      }, exclusive: exclusive);
    } on _Rollback {
      // Lançar dentro do callback garante o rollback real do sqflite.
    } catch (error) {
      failure = _publicError(error);
    } finally {
      session.timeout?.cancel();
      _sessions.remove(session.id);
      if (!session.ready.isCompleted) {
        session.ready.completeError(failure ??
            const _RpcError('Não foi possível iniciar a transação.'));
      }
      final finishCommand = session.finishCommand;
      if (finishCommand != null && !finishCommand.result.isCompleted) {
        if (failure == null &&
            finishCommand.method == 'commit' &&
            session.rollbackRequested) {
          finishCommand.result.completeError(const _RpcError(
            'A transação foi interrompida. Confira os dados antes de repetir.',
            HttpStatus.conflict,
          ));
        } else if (failure == null) {
          finishCommand.result.complete();
        } else {
          finishCommand.result.completeError(failure);
        }
      }
      session.finished.complete();
      unawaited(session.commands.close());
    }
  }

  _TransactionSession _getSession(String? id) {
    final session = _sessions[id];
    if (session == null || session.closing) {
      throw const _RpcError(
          'A transação expirou ou já foi encerrada. Tente novamente.',
          HttpStatus.conflict);
    }
    return session;
  }

  void _refreshTimeout(_TransactionSession session) {
    session.timeout?.cancel();
    session.timeout =
        Timer(_idleTimeout, () => _requestFinish(session, commit: false));
  }

  _TransactionCommand _requestFinish(_TransactionSession session,
      {required bool commit}) {
    if (!commit) session.rollbackRequested = true;
    if (session.finishCommand != null) return session.finishCommand!;
    session.closing = true;
    session.timeout?.cancel();
    final command =
        _TransactionCommand(commit ? 'commit' : 'rollback', const {});
    session.finishCommand = command;
    // Encerramentos automáticos também observam eventuais erros de commit.
    unawaited(command.result.future.then<void>((_) {}, onError: (Object _) {}));
    session.commands.add(command);
    return command;
  }

  Future<Object?> _execute(DatabaseExecutor executor, String method,
      Map<String, Object?> params) async {
    switch (method) {
      case 'query':
        _validateQuery(params);
        return executor.query(
          _identifier(params, 'table'),
          distinct: _optionalBool(params, 'distinct'),
          columns: _columns(params),
          where: _optionalString(params, 'where'),
          whereArgs: _arguments(params, 'whereArgs'),
          groupBy: _optionalString(params, 'groupBy'),
          having: _optionalString(params, 'having'),
          orderBy: _optionalString(params, 'orderBy'),
          limit: _optionalInt(params, 'limit'),
          offset: _optionalInt(params, 'offset'),
        );
      case 'insert':
        return executor.insert(
          _identifier(params, 'table'),
          _values(params),
          nullColumnHack: _nullableIdentifier(params, 'nullColumnHack'),
          conflictAlgorithm: _conflictAlgorithm(params),
        );
      case 'update':
        _validateFragment(_optionalString(params, 'where'));
        return executor.update(
          _identifier(params, 'table'),
          _values(params),
          where: _optionalString(params, 'where'),
          whereArgs: _arguments(params, 'whereArgs'),
          conflictAlgorithm: _conflictAlgorithm(params),
        );
      case 'delete':
        _validateFragment(_optionalString(params, 'where'));
        return executor.delete(
          _identifier(params, 'table'),
          where: _optionalString(params, 'where'),
          whereArgs: _arguments(params, 'whereArgs'),
        );
      case 'rawQuery':
      case 'rawInsert':
      case 'rawUpdate':
      case 'rawDelete':
      case 'execute':
        final sql = _requiredString(params, 'sql');
        _validateSql(sql, method);
        final arguments = _arguments(params, 'arguments');
        switch (method) {
          case 'rawQuery':
            return executor.rawQuery(sql, arguments);
          case 'rawInsert':
            return executor.rawInsert(sql, arguments);
          case 'rawUpdate':
            return executor.rawUpdate(sql, arguments);
          case 'rawDelete':
            return executor.rawDelete(sql, arguments);
          default:
            await executor.execute(sql, arguments);
            return null;
        }
      case 'getVersion':
        return executor.getVersion();
      case 'batch':
        final operations = params['operations'];
        if (operations is! List) {
          throw const _RpcError('Informe a lista de operações do lote.');
        }
        final batch = executor.batch();
        for (final item in operations) {
          final operation = _map(item, 'operação');
          _addBatchOperation(batch, _requiredString(operation, 'method'),
              _map(operation['params'] ?? const <String, Object?>{}, 'params'));
        }
        final atomic = _optionalBool(params, 'atomic') ?? true;
        final results = atomic
            ? await batch.commit(
                exclusive: _optionalBool(params, 'exclusive'),
                noResult: _optionalBool(params, 'noResult'),
                continueOnError: _optionalBool(params, 'continueOnError'),
              )
            : await batch.apply(
                noResult: _optionalBool(params, 'noResult'),
                continueOnError: _optionalBool(params, 'continueOnError'),
              );
        return results
            .map((result) => result is DatabaseException
                ? <String, Object?>{'error': _publicError(result).message}
                : result)
            .toList();
      default:
        throw const _RpcError('Operação de banco não disponível.');
    }
  }

  void _addBatchOperation(
      Batch batch, String method, Map<String, Object?> params) {
    switch (method) {
      case 'query':
        _validateQuery(params);
        batch.query(_identifier(params, 'table'),
            distinct: _optionalBool(params, 'distinct'),
            columns: _columns(params),
            where: _optionalString(params, 'where'),
            whereArgs: _arguments(params, 'whereArgs'),
            groupBy: _optionalString(params, 'groupBy'),
            having: _optionalString(params, 'having'),
            orderBy: _optionalString(params, 'orderBy'),
            limit: _optionalInt(params, 'limit'),
            offset: _optionalInt(params, 'offset'));
        break;
      case 'insert':
        batch.insert(_identifier(params, 'table'), _values(params),
            nullColumnHack: _nullableIdentifier(params, 'nullColumnHack'),
            conflictAlgorithm: _conflictAlgorithm(params));
        break;
      case 'update':
        _validateFragment(_optionalString(params, 'where'));
        batch.update(_identifier(params, 'table'), _values(params),
            where: _optionalString(params, 'where'),
            whereArgs: _arguments(params, 'whereArgs'),
            conflictAlgorithm: _conflictAlgorithm(params));
        break;
      case 'delete':
        _validateFragment(_optionalString(params, 'where'));
        batch.delete(_identifier(params, 'table'),
            where: _optionalString(params, 'where'),
            whereArgs: _arguments(params, 'whereArgs'));
        break;
      case 'rawQuery':
      case 'rawInsert':
      case 'rawUpdate':
      case 'rawDelete':
      case 'execute':
        final sql = _requiredString(params, 'sql');
        _validateSql(sql, method);
        final arguments = _arguments(params, 'arguments');
        switch (method) {
          case 'rawQuery':
            batch.rawQuery(sql, arguments);
            break;
          case 'rawInsert':
            batch.rawInsert(sql, arguments);
            break;
          case 'rawUpdate':
            batch.rawUpdate(sql, arguments);
            break;
          case 'rawDelete':
            batch.rawDelete(sql, arguments);
            break;
          default:
            batch.execute(sql, arguments);
        }
        break;
      default:
        throw const _RpcError('Operação não permitida dentro do lote.');
    }
  }

  static Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw _RpcError('O campo $name deve ser um objeto JSON.');
    }
    return Map<String, Object?>.from(value);
  }

  static String _requiredString(Map<String, Object?> params, String key) {
    final value = _optionalString(params, key);
    if (value == null || value.trim().isEmpty) {
      throw _RpcError('Informe o campo $key.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value != null && value is! String) {
      throw _RpcError('O campo $key deve ser um texto.');
    }
    return value as String?;
  }

  static bool? _optionalBool(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value != null && value is! bool) {
      throw _RpcError('O campo $key deve ser verdadeiro ou falso.');
    }
    return value as bool?;
  }

  static int? _optionalInt(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value != null && value is! int) {
      throw _RpcError('O campo $key deve ser inteiro.');
    }
    return value as int?;
  }

  static List<Object?>? _arguments(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value == null) return null;
    if (value is! List || value.any((item) => !_sqliteValue(item))) {
      throw _RpcError('O campo $key deve ser uma lista de valores simples.');
    }
    return List<Object?>.from(value);
  }

  static bool _sqliteValue(Object? value) =>
      value == null || value is String || value is num || value is Uint8List;

  static Object? _decodeValues(Object? value) {
    if (value is List) return value.map(_decodeValues).toList();
    if (value is Map) {
      if (value.length == 1 && value['__matterdi_blob'] is String) {
        try {
          return base64Decode(value['__matterdi_blob'] as String);
        } on FormatException {
          throw const _RpcError('O conteúdo binário da requisição é inválido.');
        }
      }
      return value.map((key, item) => MapEntry(key, _decodeValues(item)));
    }
    return value;
  }

  static Object? _encodeValues(Object? value) {
    if (value is Uint8List) return {'__matterdi_blob': base64Encode(value)};
    if (value is List) return value.map(_encodeValues).toList();
    if (value is Map) {
      return value.map((key, item) => MapEntry(key, _encodeValues(item)));
    }
    return value;
  }

  static Map<String, Object?> _values(Map<String, Object?> params) {
    final values = _map(params['values'], 'values');
    for (final entry in values.entries) {
      _checkIdentifier(entry.key);
      if (!_sqliteValue(entry.value)) {
        throw const _RpcError(
            'Os valores do registro devem ser textos, números ou nulos.');
      }
    }
    return values;
  }

  static String _identifier(Map<String, Object?> params, String key) {
    final value = _requiredString(params, key);
    _checkIdentifier(value);
    if (key == 'table' && value.toLowerCase().startsWith('sqlite_')) {
      throw const _RpcError(
          'O acesso às tabelas internas não está disponível.');
    }
    return value;
  }

  static String? _nullableIdentifier(Map<String, Object?> params, String key) {
    final value = _optionalString(params, key);
    if (value != null) _checkIdentifier(value);
    return value;
  }

  static void _checkIdentifier(String value) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
      throw const _RpcError('Nome de tabela ou coluna inválido.');
    }
  }

  static List<String>? _columns(Map<String, Object?> params) {
    final value = params['columns'];
    if (value == null) return null;
    if (value is! List || value.any((column) => column is! String)) {
      throw const _RpcError('As colunas devem ser uma lista de textos.');
    }
    return List<String>.from(value);
  }

  static ConflictAlgorithm? _conflictAlgorithm(Map<String, Object?> params) {
    final value = _optionalInt(params, 'conflictAlgorithm');
    if (value == null) return null;
    if (value < 0 || value >= ConflictAlgorithm.values.length) {
      throw const _RpcError('Algoritmo de conflito inválido.');
    }
    return ConflictAlgorithm.values[value];
  }

  static void _validateQuery(Map<String, Object?> params) {
    for (final key in ['where', 'groupBy', 'having', 'orderBy']) {
      _validateFragment(_optionalString(params, key));
    }
    for (final column in _columns(params) ?? const <String>[]) {
      _validateFragment(column);
    }
  }

  static void _validateFragment(String? fragment) {
    if (fragment == null) return;
    final scrubbed = _scrubSql(fragment);
    if (scrubbed.contains(';') || _forbiddenSql.hasMatch(scrubbed)) {
      throw const _RpcError(
          'O trecho de consulta contém uma operação não permitida.');
    }
  }

  static final _forbiddenSql = RegExp(
    r'\b(?:PRAGMA|ATTACH|DETACH|VACUUM|CREATE|ALTER|DROP|REINDEX|BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|LOAD_EXTENSION|READFILE|WRITEFILE)\b',
    caseSensitive: false,
  );

  static void _validateSql(String sql, String method) {
    final scrubbed = _scrubSql(sql).trim();
    final statement = scrubbed.endsWith(';')
        ? scrubbed.substring(0, scrubbed.length - 1).trimRight()
        : scrubbed;
    final verb = RegExp(r'^([A-Za-z]+)\b')
        .firstMatch(statement)
        ?.group(1)
        ?.toUpperCase();
    final allowed = switch (method) {
      'rawQuery' => const ['SELECT'],
      'rawInsert' => const ['INSERT'],
      'rawUpdate' => const ['UPDATE'],
      'rawDelete' => const ['DELETE'],
      _ => const ['INSERT', 'UPDATE', 'DELETE'],
    };
    if (!allowed.contains(verb) ||
        statement.contains(';') ||
        _forbiddenSql.hasMatch(statement)) {
      throw const _RpcError(
          'O servidor aceita apenas consultas e alterações de registros.');
    }
    if (verb != 'SELECT' &&
        RegExp(r'\bsqlite_[A-Za-z0-9_]*\b', caseSensitive: false)
            .hasMatch(statement)) {
      throw const _RpcError(
          'Alterações em tabelas internas não são permitidas.');
    }
  }

  /// Remove literais e comentários antes de conferir verbos e separadores.
  static String _scrubSql(String sql) {
    final output = StringBuffer();
    var index = 0;
    while (index < sql.length) {
      final char = sql[index];
      if (char == "'" || char == '"' || char == '`' || char == '[') {
        final end = char == '[' ? ']' : char;
        final identifier = StringBuffer();
        index++;
        var closed = false;
        while (index < sql.length) {
          if (sql[index] == end) {
            if (char != '[' &&
                index + 1 < sql.length &&
                sql[index + 1] == end) {
              if (char != "'") identifier.write(end);
              index += 2;
              continue;
            }
            index++;
            closed = true;
            break;
          }
          if (char != "'") identifier.write(sql[index]);
          index++;
        }
        if (!closed) {
          throw const _RpcError('A consulta contém um texto sem fechamento.');
        }
        output.write(char == "'" ? ' ' : ' ${identifier.toString()} ');
      } else if (char == '-' &&
          index + 1 < sql.length &&
          sql[index + 1] == '-') {
        while (index < sql.length && sql[index] != '\n') {
          index++;
        }
        output.write(' ');
      } else if (char == '/' &&
          index + 1 < sql.length &&
          sql[index + 1] == '*') {
        final end = sql.indexOf('*/', index + 2);
        if (end < 0) {
          throw const _RpcError(
              'A consulta contém um comentário sem fechamento.');
        }
        index = end + 2;
        output.write(' ');
      } else {
        output.write(char);
        index++;
      }
    }
    return output.toString();
  }

  static _RpcError _publicError(Object error) {
    if (error is _RpcError) return error;
    if (error is DatabaseException) {
      if (error.isUniqueConstraintError()) {
        return const _RpcError(
            'Já existe um registro com esses dados.', HttpStatus.conflict);
      }
      final description = error.toString().toLowerCase();
      if (description.contains('foreign key')) {
        return const _RpcError(
            'O registro depende de outro cadastro ou está em uso.',
            HttpStatus.conflict);
      }
      if (description.contains('locked') || description.contains('busy')) {
        return const _RpcError(
            'O banco está ocupado. Tente novamente.', HttpStatus.conflict);
      }
      if (description.contains('readonly') ||
          description.contains('read-only')) {
        return const _RpcError(
            'O banco do servidor está disponível apenas para leitura.',
            HttpStatus.conflict);
      }
      return const _RpcError(
          'Não foi possível executar a operação no banco de dados.',
          HttpStatus.conflict);
    }
    if (error is FormatException ||
        error is TypeError ||
        error is ArgumentError) {
      return const _RpcError('Os parâmetros da operação são inválidos.');
    }
    return const _RpcError('Não foi possível concluir a operação no servidor.',
        HttpStatus.internalServerError);
  }
}

class _TransactionSession {
  _TransactionSession(this.id);
  final String id;
  final ready = Completer<void>();
  final finished = Completer<void>();
  final commands = StreamController<_TransactionCommand>();
  Timer? timeout;
  bool closing = false;
  bool rollbackRequested = false;
  _TransactionCommand? finishCommand;
}

class _TransactionCommand {
  _TransactionCommand(this.method, this.params);
  final String method;
  final Map<String, Object?> params;
  final result = Completer<Object?>();
}

class _Rollback implements Exception {
  const _Rollback();
}

class _RpcError implements Exception {
  const _RpcError(this.message, [this.status = HttpStatus.badRequest]);
  final String message;
  final int status;
}
