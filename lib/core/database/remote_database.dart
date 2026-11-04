import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqlite_api.dart';

/// A sqflite-compatible connection to the database served by the PC.
///
/// Requests are never retried: after a lost response, an INSERT or COMMIT may
/// already have been applied by the server.
class RemoteDatabase extends _RemoteExecutor implements Database {
  RemoteDatabase._(this._serverUri, this._token, this._client);

  static const _requestTimeout = Duration(seconds: 15);
  static const _schemaVersion = 29;
  final Uri _serverUri;
  final String _token;
  final http.Client _client;
  final _SerialQueue _queue = _SerialQueue();
  bool _open = true;

  static Future<RemoteDatabase> connect({
    required String serverUrl,
    required String token,
  }) async {
    final normalizedUrl = normalizeServerUrl(serverUrl);
    final normalizedToken = token.trim();
    if (normalizedToken.length < 24 ||
        normalizedToken.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError(
          'A chave de acesso deve ter pelo menos 24 caracteres.');
    }

    final connection = RemoteDatabase._(
      Uri.parse(normalizedUrl),
      normalizedToken,
      http.Client(),
    );
    try {
      final health = await connection._send('GET', 'health');
      if (health is! Map ||
          health['service'] != 'matterdi-database' ||
          health['protocol'] != 1) {
        throw RemoteDatabaseException(
          'O endereço informado não é um servidor de banco Matterdi compatível.',
        );
      }
      if (health['version'] != _schemaVersion) {
        throw RemoteDatabaseException(
          'O banco do servidor está na versão ${health['version']}. '
          'Atualize o sistema do PC para a versão de banco $_schemaVersion.',
        );
      }
      return connection;
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  /// Accepts a LAN IP or an HTTPS address, optionally with a path prefix.
  static String normalizeServerUrl(String serverUrl) {
    var value = serverUrl.trim();
    if (value.isEmpty) {
      throw ArgumentError('Informe o endereço do servidor de banco de dados.');
    }
    if (!value.contains('://')) value = 'http://$value';
    Uri uri;
    try {
      uri = Uri.parse(value);
    } on FormatException {
      throw ArgumentError('O endereço do servidor é inválido.');
    }
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw ArgumentError('Informe um endereço HTTP ou HTTPS válido.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError(
        'O endereço não pode conter usuário, senha, parâmetros ou fragmentos.',
      );
    }
    if (uri.port < 1 || uri.port > 65535) {
      throw ArgumentError('A porta do servidor deve estar entre 1 e 65535.');
    }
    final localHost = _isPrivateHost(uri.host);
    if (uri.scheme == 'http' && !localHost) {
      throw ArgumentError(
        'Use HTTPS para hospedagem na internet. Na rede local, informe o IP '
        'privado do PC, por exemplo 192.168.1.10:8080.',
      );
    }
    if (uri.scheme == 'http' && localHost && !uri.hasPort) {
      uri = uri.replace(port: 8080);
    }
    uri = uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
    return uri.toString();
  }

  static bool _isPrivateHost(String host) {
    if (host.toLowerCase() == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    return address.isLoopback ||
        (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  @override
  RemoteDatabase get _remoteDatabase => this;

  @override
  String get path => _serverUri.toString();

  @override
  bool get isOpen => _open;

  @override
  Future<Object?> _invoke(String method, Map<String, Object?> params) {
    _checkOpen();
    final snapshot = _copyParams(params);
    return _queue.run(() => _request(method, snapshot));
  }

  void _checkOpen() {
    if (!_open) {
      throw RemoteDatabaseException(
        'A conexão com o banco remoto está fechada. Conecte novamente.',
      );
    }
  }

  Future<Object?> _send(
    String verb,
    String endpoint, [
    Map<String, Object?>? payload,
  ]) async {
    _checkOpen();
    final request = http.Request(
      verb,
      _serverUri.replace(path: '${_serverUri.path}/$endpoint'),
    )
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['Accept'] = 'application/json';
    if (payload != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(_encodeValue(payload));
    }
    http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })()
          .timeout(_requestTimeout);
    } on TimeoutException {
      await close();
      throw RemoteDatabaseException(
        'O servidor não respondeu em 15 segundos. Confira a rede e conecte '
        'novamente. Se estava salvando dados, confira o resultado antes de repetir.',
      );
    } on http.ClientException {
      await close();
      throw RemoteDatabaseException(
        'Não foi possível comunicar com o banco do PC. Confira o endereço, '
        'a rede e se o servidor está ligado. Se estava salvando dados, confira '
        'o resultado antes de repetir.',
      );
    } on IOException {
      await close();
      throw RemoteDatabaseException(
        'A conexão com o banco do PC foi perdida. Conecte novamente e confira '
        'o resultado antes de repetir uma gravação.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw RemoteDatabaseException(
          'A chave de acesso ao servidor é inválida.');
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw RemoteDatabaseException(
        'O servidor redirecionou a conexão. Informe o endereço final do servidor.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw RemoteDatabaseException(
        'O servidor retornou uma resposta inválida '
        '(HTTP ${response.statusCode}).',
      );
    }
    if (decoded is Map && decoded['error'] is String) {
      throw RemoteDatabaseException(decoded['error'] as String);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteDatabaseException(
        'O servidor recusou a operação (HTTP ${response.statusCode}).',
      );
    }
    try {
      return _decodeValue(decoded);
    } on FormatException {
      throw RemoteDatabaseException(
        'O servidor retornou dados binários inválidos.',
      );
    }
  }

  Future<Object?> _request(
    String method,
    Map<String, Object?> params, {
    String? transactionId,
  }) async {
    final response = await _send('POST', 'database', {
      'method': method,
      'params': params,
      if (transactionId != null) 'transactionId': transactionId,
    });
    if (response is! Map || !response.containsKey('result')) {
      throw RemoteDatabaseException(
          'O servidor retornou um resultado inválido.');
    }
    return response['result'];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    _checkOpen();
    return _queue.run(() async {
      final id = await _request('begin', {'exclusive': exclusive});
      if (id is! String || id.isEmpty) {
        throw RemoteDatabaseException('O servidor não iniciou a transação.');
      }
      final transaction = _RemoteTransaction(this, id);
      try {
        final result = await action(transaction);
        await transaction._finish();
        await _request('commit', {}, transactionId: id);
        return result;
      } catch (_) {
        await transaction._finish();
        try {
          await _request('rollback', {}, transactionId: id);
        } catch (_) {
          // Preserve the original failure. The server expires abandoned
          // transactions when the connection cannot deliver a rollback.
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _client.close();
  }
}

/// Keeps sqflite's constraint inspection methods available to callers.
class RemoteDatabaseException extends DatabaseException {
  RemoteDatabaseException(this.message) : super(message);

  final String message;

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;

  @override
  String toString() => message;
}

abstract class _RemoteExecutor implements DatabaseExecutor {
  RemoteDatabase get _remoteDatabase;
  Future<Object?> _invoke(String method, Map<String, Object?> params);

  @override
  Database get database => _remoteDatabase;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _invoke('execute', _sqlParams(sql, arguments));
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async =>
      _integer(await _invoke('rawInsert', _sqlParams(sql, arguments)));

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async =>
      _integer(await _invoke('rawUpdate', _sqlParams(sql, arguments)));

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async =>
      _integer(await _invoke('rawDelete', _sqlParams(sql, arguments)));

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async =>
      _rows(await _invoke('rawQuery', _sqlParams(sql, arguments)));

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async =>
      _integer(await _invoke('insert', {
        'table': table,
        'values': values,
        'nullColumnHack': nullColumnHack,
        'conflictAlgorithm': conflictAlgorithm?.index,
      }));

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async =>
      _integer(await _invoke('update', {
        'table': table,
        'values': values,
        'where': where,
        'whereArgs': whereArgs,
        'conflictAlgorithm': conflictAlgorithm?.index,
      }));

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async =>
      _integer(await _invoke('delete', {
        'table': table,
        'where': where,
        'whereArgs': whereArgs,
      }));

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async =>
      _rows(await _invoke(
          'query',
          _queryParams(
            table,
            distinct: distinct,
            columns: columns,
            where: where,
            whereArgs: whereArgs,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          )));

  Future<int> getVersion() async => _integer(await _invoke('getVersion', {}));

  @override
  Batch batch() => _RemoteBatch(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'Esta operação do banco não está disponível na conexão remota '
        '(${invocation.memberName}).',
      );
}

class _RemoteTransaction extends _RemoteExecutor implements Transaction {
  _RemoteTransaction(this._remoteDatabase, this._id);

  @override
  final RemoteDatabase _remoteDatabase;
  final String _id;
  final _SerialQueue _queue = _SerialQueue();
  bool _active = true;

  @override
  Future<Object?> _invoke(String method, Map<String, Object?> params) {
    if (!_active) {
      throw RemoteDatabaseException('A transação remota já foi encerrada.');
    }
    final snapshot = _copyParams(params);
    return _queue.run(() => _remoteDatabase._request(
          method,
          snapshot,
          transactionId: _id,
        ));
  }

  Future<void> _finish() async {
    _active = false;
    await _queue.done;
  }
}

class _RemoteBatch implements Batch {
  _RemoteBatch(this._executor);

  final _RemoteExecutor _executor;
  final List<Map<String, Object?>> _operations = [];
  bool _submitted = false;

  void _add(String method, Map<String, Object?> params) {
    if (_submitted) {
      throw StateError('Este lote de operações já foi enviado ao servidor.');
    }
    // Match sqflite: changing values after adding an operation must not change
    // the operation queued in the batch.
    _operations.add({
      'method': method,
      'params': _copyParams(params),
    });
  }

  @override
  int get length => _operations.length;

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) =>
      _submit(
        exclusive: exclusive,
        noResult: noResult,
        continueOnError: continueOnError,
        atomic: true,
      );

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) =>
      _submit(
        noResult: noResult,
        continueOnError: continueOnError,
        atomic: false,
      );

  Future<List<Object?>> _submit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
    required bool atomic,
  }) async {
    if (_submitted) {
      throw StateError('Este lote de operações já foi enviado ao servidor.');
    }
    _submitted = true;
    final result = await _executor._invoke('batch', {
      'operations': _operations,
      'exclusive': exclusive,
      'noResult': noResult,
      'continueOnError': continueOnError,
      'atomic': atomic,
    });
    if (result is! List) {
      throw RemoteDatabaseException('O servidor retornou um lote inválido.');
    }
    return result.map<Object?>((value) {
      if (value is Map && value['error'] is String) {
        return RemoteDatabaseException(value['error'] as String);
      }
      return value;
    }).toList();
  }

  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _add('execute', _sqlParams(sql, arguments));

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _add('rawInsert', _sqlParams(sql, arguments));

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _add('rawUpdate', _sqlParams(sql, arguments));

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _add('rawDelete', _sqlParams(sql, arguments));

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _add('rawQuery', _sqlParams(sql, arguments));

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _add('insert', {
        'table': table,
        'values': values,
        'nullColumnHack': nullColumnHack,
        'conflictAlgorithm': conflictAlgorithm?.index,
      });

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _add('update', {
        'table': table,
        'values': values,
        'where': where,
        'whereArgs': whereArgs,
        'conflictAlgorithm': conflictAlgorithm?.index,
      });

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _add('delete', {
        'table': table,
        'where': where,
        'whereArgs': whereArgs,
      });

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _add(
          'query',
          _queryParams(
            table,
            distinct: distinct,
            columns: columns,
            where: where,
            whereArgs: whereArgs,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          ));
}

class _SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> get done => _tail;

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

Map<String, Object?> _sqlParams(String sql, List<Object?>? arguments) => {
      'sql': sql,
      'arguments': arguments,
    };

Map<String, Object?> _queryParams(
  String table, {
  bool? distinct,
  List<String>? columns,
  String? where,
  List<Object?>? whereArgs,
  String? groupBy,
  String? having,
  String? orderBy,
  int? limit,
  int? offset,
}) =>
    {
      'table': table,
      'distinct': distinct,
      'columns': columns,
      'where': where,
      'whereArgs': whereArgs,
      'groupBy': groupBy,
      'having': having,
      'orderBy': orderBy,
      'limit': limit,
      'offset': offset,
    };

int _integer(Object? result) {
  if (result is int) return result;
  throw RemoteDatabaseException('O servidor retornou um número inválido.');
}

List<Map<String, Object?>> _rows(Object? result) {
  if (result is! List || result.any((row) => row is! Map)) {
    throw RemoteDatabaseException(
        'O servidor retornou dados de consulta inválidos.');
  }
  return result.map((row) => Map<String, Object?>.from(row as Map)).toList();
}

Object? _encodeValue(Object? value) {
  if (value is Uint8List) {
    return {'__matterdi_blob': base64Encode(value)};
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _encodeValue(value)));
  }
  if (value is List) return value.map(_encodeValue).toList();
  return value;
}

Map<String, Object?> _copyParams(Map<String, Object?> params) =>
    Map<String, Object?>.from(_decodeValue(_encodeValue(params)) as Map);

Object? _decodeValue(Object? value) {
  if (value is Map) {
    if (value.length == 1 && value['__matterdi_blob'] is String) {
      return base64Decode(value['__matterdi_blob'] as String);
    }
    return value.map((key, value) => MapEntry(key, _decodeValue(value)));
  }
  if (value is List) return value.map(_decodeValue).toList();
  return value;
}
