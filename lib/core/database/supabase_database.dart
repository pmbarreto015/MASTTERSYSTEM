import 'dart:typed_data';

import 'package:sqflite/sqlite_api.dart';

import '../supabase/supabase_service.dart';

typedef SupabaseRpcCall = Future<dynamic> Function(
  String name,
  Map<String, Object?> params, {
  bool requireSession,
});

/// Adapta as operações simples do sqflite à API segura do Supabase.
///
/// O cliente envia filtros estruturados e nomes de relatórios conhecidos. Ele
/// nunca envia SQL ao PostgreSQL. Fluxos que precisam de atomicidade devem
/// usar uma RPC de domínio, pois uma callback [transaction] não pode atravessar
/// várias requisições HTTP com segurança.
class SupabaseDatabase extends _SupabaseExecutor implements Database {
  SupabaseDatabase._({
    required SupabaseRpcCall rpcCall,
    required String path,
  })  : _rpcCall = rpcCall,
        _path = path;

  static const int schemaVersion = 29;

  final SupabaseRpcCall _rpcCall;
  final String _path;
  final _SerialQueue _queue = _SerialQueue();
  bool _open = true;

  static Future<SupabaseDatabase> connect({
    required SupabaseService service,
  }) async {
    return SupabaseDatabase._(
      path: service.baseUrl,
      rpcCall: service.rpc,
    );
  }

  /// Constructor used by unit tests without opening a network connection.
  static SupabaseDatabase forTesting({
    required SupabaseRpcCall rpcCall,
    String path = 'https://test.supabase.co',
  }) =>
      SupabaseDatabase._(rpcCall: rpcCall, path: path);

  @override
  SupabaseDatabase get _supabaseDatabase => this;

  @override
  String get path => _path;

  @override
  bool get isOpen => _open;

  Future<dynamic> rpc(
    String name,
    Map<String, Object?> params, {
    bool requireSession = true,
  }) {
    _checkOpen();
    final snapshot = _copyMap(params);
    return _queue.run(
      () => _rpcCall(name, snapshot, requireSession: requireSession),
    );
  }

  @override
  Future<Object?> _invokeData(Map<String, Object?> payload) {
    _checkOpen();
    final snapshot = _copyMap(payload);
    return _queue.run(
      () => _rpcCall(
        'matterdi_data',
        {'payload': snapshot},
        requireSession: true,
      ),
    );
  }

  @override
  Future<Object?> _invokeReport(String name, List<Object?> arguments) {
    _checkOpen();
    final snapshot = List<Object?>.from(_copy(arguments) as List);
    return _queue.run(
      () => _rpcCall(
        'matterdi_report',
        {'report_name': name, 'arguments': snapshot},
        requireSession: true,
      ),
    );
  }

  Future<List<Object?>> _invokeBatch(
    List<Map<String, Object?>> operations, {
    required bool noResult,
    required bool continueOnError,
  }) {
    _checkOpen();
    final snapshot = (_copy(operations) as List)
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
    return _queue.run(() async {
      final value = await _rpcCall(
        'matterdi_batch',
        {
          'operations': snapshot,
          'no_result': noResult,
          'continue_on_error': continueOnError,
        },
        requireSession: true,
      );
      if (value is! List) {
        throw SupabaseDatabaseException(
          'O Supabase retornou um lote inválido.',
        );
      }
      return value.map<Object?>((item) {
        if (item is Map && item['error'] is String) {
          return SupabaseDatabaseException(item['error'] as String);
        }
        return item;
      }).toList();
    });
  }

  void _checkOpen() {
    if (!_open) {
      throw SupabaseDatabaseException(
        'A conexão com o Supabase está fechada. Conecte novamente.',
      );
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    _checkOpen();
    throw UnsupportedError(
      'Transações por callback não estão disponíveis no Supabase. '
      'Use uma RPC de negócio para executar toda a alteração em uma única '
      'transação PostgreSQL.',
    );
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await _queue.done;
  }
}

class SupabaseDatabaseException extends DatabaseException {
  SupabaseDatabaseException(this.message) : super(message);

  final String message;

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;

  @override
  String toString() => message;
}

abstract class _SupabaseExecutor implements DatabaseExecutor {
  SupabaseDatabase get _supabaseDatabase;

  Future<Object?> _invokeData(Map<String, Object?> payload);

  Future<Object?> _invokeReport(String name, List<Object?> arguments);

  @override
  Database get database => _supabaseDatabase;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    throw UnsupportedError(
      'Comandos SQL livres não são aceitos pelo Supabase.',
    );
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    throw UnsupportedError(
      'INSERT em SQL livre não é aceito pelo Supabase. Use insert().',
    );
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    throw UnsupportedError(
      'DELETE em SQL livre não é aceito pelo Supabase. Use delete().',
    );
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    final payload = _rawUpdatePayload(sql, arguments ?? const []);
    return _integer(await _invokeData(payload));
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final report = _reportFor(sql, arguments ?? const []);
    return _rows(await _invokeReport(report.name, report.arguments));
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (nullColumnHack != null) {
      throw UnsupportedError('nullColumnHack não está disponível no Supabase.');
    }
    if (conflictAlgorithm != null &&
        conflictAlgorithm != ConflictAlgorithm.abort) {
      throw UnsupportedError(
        'Este algoritmo de conflito não está disponível no Supabase.',
      );
    }
    return _integer(await _invokeData(_insertPayload(table, values)));
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (conflictAlgorithm != null &&
        conflictAlgorithm != ConflictAlgorithm.abort) {
      throw UnsupportedError(
        'Este algoritmo de conflito não está disponível no Supabase.',
      );
    }
    return _integer(await _invokeData(
      _updatePayload(table, values, where, whereArgs ?? const []),
    ));
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async =>
      _integer(await _invokeData(
        _deletePayload(table, where, whereArgs ?? const []),
      ));

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
  }) async {
    final payload = _queryPayload(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs ?? const [],
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    if (limit != null) return _rows(await _invokeData(payload));

    // Each RPC has a server-side limit. Fetch every page rather than silently
    // returning only the first 10000 rows of a query without an explicit limit.
    // A unique tie-breaker keeps equal sort values in a stable order.
    payload['order'] = _paginationOrder(
      payload['order']! as List<Map<String, Object?>>,
      distinct: distinct ?? false,
      columns: columns,
    );
    const pageSize = 1000;
    payload['limit'] = pageSize;
    var pageOffset = offset ?? 0;
    final result = <Map<String, Object?>>[];
    while (true) {
      payload['offset'] = pageOffset;
      final page = _rows(await _invokeData(payload));
      if (page.length > pageSize) {
        throw SupabaseDatabaseException(
          'O Supabase retornou uma página maior que o limite solicitado.',
        );
      }
      result.addAll(page);
      if (page.length < pageSize) return result;
      pageOffset += page.length;
    }
  }

  Future<int> getVersion() async => SupabaseDatabase.schemaVersion;

  @override
  Batch batch() => _SupabaseBatch(_supabaseDatabase);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'Esta operação não está disponível no Supabase '
        '(${invocation.memberName}).',
      );
}

class _SupabaseBatch implements Batch {
  _SupabaseBatch(this._database);

  final SupabaseDatabase _database;
  final List<Map<String, Object?>> _operations = [];
  bool _submitted = false;

  void _add(Map<String, Object?> operation) {
    if (_submitted) {
      throw StateError('Este lote de operações já foi enviado ao Supabase.');
    }
    _operations.add(_copyMap(operation));
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
        noResult: noResult ?? false,
        continueOnError: continueOnError ?? false,
      );

  @override
  Future<List<Object?>> apply({
    bool? noResult,
    bool? continueOnError,
  }) =>
      _submit(
        noResult: noResult ?? false,
        continueOnError: continueOnError ?? false,
      );

  Future<List<Object?>> _submit({
    required bool noResult,
    required bool continueOnError,
  }) async {
    if (_submitted) {
      throw StateError('Este lote de operações já foi enviado ao Supabase.');
    }
    _submitted = true;
    return _database._invokeBatch(
      _operations,
      noResult: noResult,
      continueOnError: continueOnError,
    );
  }

  @override
  void execute(String sql, [List<Object?>? arguments]) {
    throw UnsupportedError(
        'Comandos SQL livres não são aceitos pelo Supabase.');
  }

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) {
    throw UnsupportedError('INSERT em SQL livre não é aceito pelo Supabase.');
  }

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) {
    throw UnsupportedError('DELETE em SQL livre não é aceito pelo Supabase.');
  }

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) => _add({
        'kind': 'data',
        'payload': _rawUpdatePayload(sql, arguments ?? const []),
      });

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) {
    final report = _reportFor(sql, arguments ?? const []);
    _add({
      'kind': 'report',
      'report_name': report.name,
      'arguments': report.arguments,
    });
  }

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    if (nullColumnHack != null ||
        (conflictAlgorithm != null &&
            conflictAlgorithm != ConflictAlgorithm.abort)) {
      throw UnsupportedError('Opção de INSERT não disponível no Supabase.');
    }
    _add({'kind': 'data', 'payload': _insertPayload(table, values)});
  }

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    if (conflictAlgorithm != null &&
        conflictAlgorithm != ConflictAlgorithm.abort) {
      throw UnsupportedError('Opção de UPDATE não disponível no Supabase.');
    }
    _add({
      'kind': 'data',
      'payload': _updatePayload(table, values, where, whereArgs ?? const []),
    });
  }

  @override
  void delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) =>
      _add({
        'kind': 'data',
        'payload': _deletePayload(table, where, whereArgs ?? const []),
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
  }) {
    if (limit == null) {
      throw UnsupportedError(
        'Consultas em lote no Supabase precisam de um limite explícito. '
        'Use query() fora do lote para consultar todos os registros.',
      );
    }
    _add({
      'kind': 'data',
      'payload': _queryPayload(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs ?? const [],
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      ),
    });
  }
}

List<Map<String, Object?>> _paginationOrder(
  List<Map<String, Object?>> order, {
  required bool distinct,
  required List<String>? columns,
}) {
  final result = order.map(Map<String, Object?>.from).toList();
  // DISTINCT may select only a subset of columns. PostgreSQL requires every
  // ORDER BY column to belong to that projection, whose complete tuple is the
  // unique tie-breaker for the distinct result.
  final tieBreakers = distinct && columns != null && columns.isNotEmpty
      ? columns
      : const ['id'];
  for (final column in tieBreakers) {
    if (!result
        .any((entry) => entry['column'] == column && entry['nocase'] != true)) {
      result.add({'column': column, 'direction': 'asc'});
    }
  }
  return result;
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

const _allowedTables = <String>{
  'customers',
  'products',
  'insumos',
  'sellers',
  'suppliers',
  'employees',
  'orders',
  'order_items',
  'financial',
  'stock_movements',
  'pontos',
  'holerites',
  'materiais',
  'maquinas',
  'retalhos',
  'composicoes',
  'composicao_itens',
  'agenda_followups',
  'system_users',
  'erp_module_records',
  'purchase_orders',
};

Map<String, Object?> _queryPayload(
  String table, {
  bool? distinct,
  List<String>? columns,
  String? where,
  required List<Object?> whereArgs,
  String? groupBy,
  String? having,
  String? orderBy,
  int? limit,
  int? offset,
}) {
  _checkTable(table);
  if (columns != null) {
    for (final column in columns) {
      _checkIdentifier(column, 'coluna');
    }
  }
  if (groupBy != null || having != null) {
    throw UnsupportedError('GROUP BY e HAVING não estão disponíveis aqui.');
  }
  if (limit != null && limit < 1) {
    throw ArgumentError.value(limit, 'limit', 'deve ser maior que zero');
  }
  if (offset != null && offset < 0) {
    throw ArgumentError.value(offset, 'offset', 'não pode ser negativo');
  }
  return {
    'operation': 'query',
    'table': table,
    'distinct': distinct ?? false,
    if (columns != null) 'columns': List<String>.from(columns),
    'filters': _parseWhere(where, whereArgs),
    'order': _parseOrder(table, orderBy),
    if (limit != null) 'limit': limit,
    if (offset != null) 'offset': offset,
  };
}

Map<String, Object?> _insertPayload(
  String table,
  Map<String, Object?> values,
) {
  _checkTable(table);
  _checkValues(values);
  return {
    'operation': 'insert',
    'table': table,
    'values': _copyMap(values),
  };
}

Map<String, Object?> _updatePayload(
  String table,
  Map<String, Object?> values,
  String? where,
  List<Object?> whereArgs,
) {
  _checkTable(table);
  _checkValues(values);
  final filters = _parseWhere(where, whereArgs);
  if (filters.isEmpty) {
    throw ArgumentError('UPDATE sem filtro não é permitido no Supabase.');
  }
  return {
    'operation': 'update',
    'table': table,
    'values': _copyMap(values),
    'filters': filters,
  };
}

Map<String, Object?> _deletePayload(
  String table,
  String? where,
  List<Object?> whereArgs,
) {
  _checkTable(table);
  final filters = _parseWhere(where, whereArgs);
  if (filters.isEmpty) {
    throw ArgumentError('DELETE sem filtro não é permitido no Supabase.');
  }
  return {
    'operation': 'delete',
    'table': table,
    'filters': filters,
  };
}

void _checkTable(String table) {
  if (!_allowedTables.contains(table)) {
    throw ArgumentError.value(table, 'table', 'tabela não permitida');
  }
}

void _checkValues(Map<String, Object?> values) {
  if (values.isEmpty) throw ArgumentError('Informe ao menos um valor.');
  for (final key in values.keys) {
    _checkIdentifier(key, 'coluna');
  }
}

void _checkIdentifier(String value, String label) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError.value(value, label, 'identificador inválido');
  }
}

List<Map<String, Object?>> _parseWhere(
  String? where,
  List<Object?> arguments,
) {
  if (where == null || where.trim().isEmpty) {
    if (arguments.isNotEmpty) {
      throw ArgumentError('Há argumentos sem filtro correspondente.');
    }
    return const [];
  }
  final source = where.trim().replaceAll(RegExp(r'\s+'), ' ');
  final result = <Map<String, Object?>>[];
  var position = 0;
  var argumentIndex = 0;
  var connector = 'and';

  Object? nextArgument() {
    if (argumentIndex >= arguments.length) {
      throw ArgumentError('Faltam argumentos para o filtro informado.');
    }
    final value = arguments[argumentIndex++];
    if (value == null ||
        value is Map ||
        value is Iterable && value is! String) {
      throw ArgumentError('Tipo de argumento de filtro não permitido.');
    }
    return value;
  }

  Match? match(RegExp expression) => expression.matchAsPrefix(source, position);

  while (position < source.length) {
    if (result.isNotEmpty) {
      final join = match(RegExp(r'(AND|OR)\s+', caseSensitive: false));
      if (join == null) {
        throw ArgumentError('Filtro não permitido: $where');
      }
      connector = join.group(1)!.toLowerCase();
      position = join.end;
    }

    Match? found;
    Map<String, Object?>? filter;

    found = match(RegExp(
      r'([a-z][a-z0-9_]*)\s+BETWEEN\s+\?\s+AND\s+\?',
      caseSensitive: false,
    ));
    if (found != null) {
      filter = {
        'column': found.group(1)!.toLowerCase(),
        'operator': 'between',
        'values': [nextArgument(), nextArgument()],
      };
    }

    found ??= match(RegExp(
      r'LOWER\(([a-z][a-z0-9_]*)\)\s*=\s*LOWER\(\?\)',
      caseSensitive: false,
    ));
    if (filter == null && found != null) {
      filter = {
        'column': found.group(1)!.toLowerCase(),
        'operator': 'ieq',
        'value': nextArgument(),
      };
    }

    if (filter == null) {
      found = match(RegExp(
        r'date\(([a-z][a-z0-9_]*)\)\s*=\s*date\(\?\)',
        caseSensitive: false,
      ));
      if (found != null) {
        filter = {
          'column': found.group(1)!.toLowerCase(),
          'operator': 'date_eq',
          'value': nextArgument(),
        };
      }
    }

    if (filter == null) {
      found = match(RegExp(
        r'([a-z][a-z0-9_]*)\s+IS\s+(NOT\s+)?NULL',
        caseSensitive: false,
      ));
      if (found != null) {
        filter = {
          'column': found.group(1)!.toLowerCase(),
          'operator': found.group(2) == null ? 'is_null' : 'is_not_null',
        };
      }
    }

    if (filter == null) {
      found = match(RegExp(
        r'([a-z][a-z0-9_]*)\s+IN\s*\((\?(?:\s*,\s*\?)*)\)',
        caseSensitive: false,
      ));
      if (found != null) {
        final count = '?'.allMatches(found.group(2)!).length;
        filter = {
          'column': found.group(1)!.toLowerCase(),
          'operator': 'in',
          'values': List<Object?>.generate(count, (_) => nextArgument()),
        };
      }
    }

    if (filter == null) {
      found = match(RegExp(
        r'([a-z][a-z0-9_]*)\s*(LIKE|=|!=|<>|>=|<=|>|<)\s*\?',
        caseSensitive: false,
      ));
      if (found != null) {
        filter = {
          'column': found.group(1)!.toLowerCase(),
          'operator': _operatorName(found.group(2)!),
          'value': nextArgument(),
        };
      }
    }

    if (filter == null) {
      found = match(RegExp(
        r'([a-z][a-z0-9_]*)\s*<=\s*([a-z][a-z0-9_]*)',
        caseSensitive: false,
      ));
      if (found != null) {
        filter = {
          'column': found.group(1)!.toLowerCase(),
          'operator': 'column_lte',
          'rhs_column': found.group(2)!.toLowerCase(),
        };
      }
    }

    if (filter == null) {
      found = match(RegExp(
        r'([a-z][a-z0-9_]*)\s*(=|!=|<>|>=|<=|>|<)\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ));
      if (found != null) {
        filter = {
          'column': found.group(1)!.toLowerCase(),
          'operator': _operatorName(found.group(2)!),
          'value': num.parse(found.group(3)!),
        };
      }
    }

    if (filter == null || found == null) {
      throw ArgumentError('Filtro não permitido: $where');
    }
    _checkIdentifier(filter['column']! as String, 'coluna');
    if (filter['rhs_column'] case final String rhs) {
      _checkIdentifier(rhs, 'coluna');
    }
    result.add({'connector': connector, ...filter});
    position = found.end;
    if (position < source.length && source[position] == ' ') position++;
  }

  if (argumentIndex != arguments.length) {
    throw ArgumentError('Há argumentos sem filtro correspondente.');
  }
  return result;
}

String _operatorName(String source) {
  switch (source.toUpperCase()) {
    case '=':
      return 'eq';
    case '!=':
    case '<>':
      return 'ne';
    case '>':
      return 'gt';
    case '>=':
      return 'gte';
    case '<':
      return 'lt';
    case '<=':
      return 'lte';
    case 'LIKE':
      return 'ilike';
  }
  throw ArgumentError('Operador não permitido.');
}

List<Map<String, Object?>> _parseOrder(String table, String? orderBy) {
  if (orderBy == null || orderBy.trim().isEmpty) return const [];
  final normalized = orderBy.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.toLowerCase() ==
      "case when status = 'concluido' then 1 else 0 end, agendado_para asc") {
    if (table != 'agenda_followups') {
      throw ArgumentError('Ordenação especial inválida para esta tabela.');
    }
    return const [
      {'expression': 'agenda_status', 'direction': 'asc'},
      {'column': 'agendado_para', 'direction': 'asc'},
    ];
  }

  return normalized.split(',').map((part) {
    final match = RegExp(
      r'^([a-z][a-z0-9_]*)(?:\s+COLLATE\s+NOCASE)?(?:\s+(ASC|DESC))?$',
      caseSensitive: false,
    ).firstMatch(part.trim());
    if (match == null) {
      throw ArgumentError('Ordenação não permitida: $orderBy');
    }
    final column = match.group(1)!.toLowerCase();
    _checkIdentifier(column, 'coluna');
    return <String, Object?>{
      'column': column,
      'direction': (match.group(2) ?? 'ASC').toLowerCase(),
      'nocase':
          RegExp(r'\sCOLLATE\s+NOCASE', caseSensitive: false).hasMatch(part),
    };
  }).toList();
}

Map<String, Object?> _rawUpdatePayload(
  String sql,
  List<Object?> arguments,
) {
  final normalized = _normalizeSql(sql);
  if (normalized ==
      'update customers set total_purchases = total_purchases + ? where id = ?') {
    _expectArguments(arguments, 2);
    return {
      'operation': 'customer_add_purchase',
      'amount': arguments[0],
      'id': arguments[1],
    };
  }
  if (normalized ==
      'update sellers set total_sales = coalesce(( select sum(total) from orders where seller_id = ? and tipo = \'OS\' and status != \'cancelado\' ), 0), updated_at = ? where id = ?') {
    _expectArguments(arguments, 3);
    return {
      'operation': 'seller_refresh_sales',
      'seller_id': arguments[0],
      'updated_at': arguments[1],
      'target_id': arguments[2],
    };
  }
  throw UnsupportedError(
    'Esta atualização SQL não está na lista segura do Supabase.',
  );
}

_ReportCall _reportFor(String sql, List<Object?> arguments) {
  final normalized = _normalizeSql(sql);
  final fixed = _fixedReports[normalized];
  if (fixed != null) return _ReportCall(fixed, List<Object?>.from(arguments));

  if (RegExp(
    r'^select oi\.\*, p\.nome as produto_nome from order_items oi left join products p on p\.id = oi\.product_id where oi\.order_id in \(\?(?:, \?)*\)$',
  ).hasMatch(normalized)) {
    if (arguments.isEmpty) {
      throw ArgumentError('Informe ao menos um pedido.');
    }
    return _ReportCall('order_items_for_orders', List<Object?>.from(arguments));
  }
  throw UnsupportedError(
    'Esta consulta SQL não está na lista segura do Supabase.',
  );
}

final _fixedReports = <String, String>{
  _normalizeSql('''
    SELECT COUNT(*) as total_transacoes,
      SUM(CASE WHEN type = 'receber' AND is_paid = 0 THEN amount ELSE 0 END) as total_aberto,
      SUM(CASE WHEN type = 'receber' AND is_paid = 1 THEN amount ELSE 0 END) as total_pago,
      SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date < date('now') THEN amount ELSE 0 END) as total_vencido,
      SUM(CASE WHEN type = 'receber' THEN amount ELSE 0 END) as total_comprado
    FROM (SELECT * FROM financial f WHERE f.status != 'cancelado' AND (f.order_id IS NULL OR f.order_id IN (SELECT id FROM orders WHERE tipo = 'OS' AND status != 'cancelado'))) financial WHERE customer_id = ?
  '''): 'financial_customer_summary',
  _normalizeSql('''
    SELECT SUM(CASE WHEN type = 'receber' AND is_paid = 0 THEN amount ELSE 0 END) as a_receber,
      SUM(CASE WHEN type = 'receber' AND is_paid = 1 THEN amount ELSE 0 END) as recebido,
      SUM(CASE WHEN type = 'pagar' AND is_paid = 0 THEN amount ELSE 0 END) as a_pagar,
      SUM(CASE WHEN type = 'pagar' AND is_paid = 1 THEN amount ELSE 0 END) as pago,
      COUNT(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date < date('now') THEN 1 END) as vencidos_qtde,
      SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date < date('now') THEN amount ELSE 0 END) as vencidos_valor
    FROM (SELECT * FROM financial f WHERE f.status != 'cancelado' AND (f.order_id IS NULL OR f.order_id IN (SELECT id FROM orders WHERE tipo = 'OS' AND status != 'cancelado'))) financial
  '''): 'financial_dashboard',
  _normalizeSql('''
    SELECT SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date BETWEEN ? AND ? THEN amount ELSE 0 END) as a_receber_projetado,
      SUM(CASE WHEN type = 'pagar' AND is_paid = 0 AND due_date BETWEEN ? AND ? THEN amount ELSE 0 END) as a_pagar_projetado
    FROM (SELECT * FROM financial f WHERE f.status != 'cancelado' AND (f.order_id IS NULL OR f.order_id IN (SELECT id FROM orders WHERE tipo = 'OS' AND status != 'cancelado'))) financial
  '''): 'financial_projection',
  _normalizeSql('''
    SELECT COUNT(*) as total_produtos, SUM(estoque) as total_estoque,
      SUM(estoque * preco) as valor_total_estoque,
      COUNT(CASE WHEN estoque <= 0 THEN 1 END) as produtos_esgotados,
      COUNT(CASE WHEN estoque < 10 AND estoque > 0 THEN 1 END) as produtos_baixo,
      COUNT(CASE WHEN estoque < 5 AND estoque > 0 THEN 1 END) as produtos_criticos
    FROM products WHERE ativo = 1
  '''): 'stock_summary',
  _normalizeSql('''SELECT COALESCE(SUM(total), 0) as total_vendas,
    COUNT(id) as total_pedidos FROM orders
    WHERE seller_id = ? AND tipo = 'OS' AND status != 'cancelado' '''):
      'seller_totals',
  _normalizeSql('''SELECT COALESCE(SUM(total), 0) as total_vendas FROM orders
    WHERE seller_id = ? AND tipo = 'OS' AND status != 'cancelado' '''):
      'seller_sales_total',
  _normalizeSql('''SELECT s.id, s.name as vendedor, s.commission,
    s.total_sales as total_vendas,
    COALESCE(SUM(o.total * s.commission / 100), 0) as total_comissao,
    COUNT(o.id) as quantidade_pedidos FROM sellers s
    LEFT JOIN orders o ON o.seller_id = s.id AND o.tipo = 'OS' AND o.status != 'cancelado'
    GROUP BY s.id ORDER BY total_vendas DESC'''): 'sales_by_seller',
  _normalizeSql('''SELECT COUNT(*) as total_vendedores,
    SUM(total_sales) as total_vendas_geral, AVG(commission) as media_comissao,
    MAX(total_sales) as melhor_venda,
    (SELECT name FROM sellers ORDER BY total_sales DESC LIMIT 1) as melhor_vendedor
    FROM sellers WHERE active = 1'''): 'sales_dashboard',
  _normalizeSql('SELECT COUNT(*) as total FROM retalhos'): 'retalhos_count',
  _normalizeSql(
          'SELECT status, COUNT(*) as total FROM retalhos GROUP BY status'):
      'retalhos_by_status',
  _normalizeSql(
          "SELECT SUM(area) as total FROM retalhos WHERE status = 'disponivel'"):
      'retalhos_available_area',
  _normalizeSql(
          "SELECT SUM(valor_estimado) as total FROM retalhos WHERE status = 'disponivel'"):
      'retalhos_available_value',
  _normalizeSql('SELECT COUNT(*) as total FROM materiais'): 'materiais_count',
  _normalizeSql(
          'SELECT categoria, COUNT(*) as total FROM materiais WHERE active = 1 GROUP BY categoria'):
      'materiais_by_category',
  _normalizeSql(
          'SELECT SUM(quantidade_estoque * preco_por_m2) as total FROM materiais WHERE active = 1'):
      'materiais_stock_value',
  _normalizeSql('SELECT COUNT(*) as total FROM maquinas'): 'maquinas_count',
  _normalizeSql(
          'SELECT tipo, COUNT(*) as total FROM maquinas WHERE active = 1 GROUP BY tipo'):
      'maquinas_by_type',
  _normalizeSql(
          'SELECT SUM(custo_total_hora) as total FROM maquinas WHERE active = 1'):
      'maquinas_hour_cost',
  _normalizeSql(
          'SELECT categoria, SUM(quantidade) as total FROM insumos WHERE active = 1 GROUP BY categoria'):
      'insumos_by_category',
  _normalizeSql('''SELECT COUNT(*) as total_itens,
    SUM(quantidade) as total_quantidade,
    SUM(quantidade * preco_unitario) as valor_total,
    COUNT(CASE WHEN quantidade <= estoque_minimo THEN 1 END) as itens_baixos,
    COUNT(CASE WHEN quantidade <= 0 THEN 1 END) as itens_esgotados
    FROM insumos WHERE active = 1'''): 'insumos_totals',
  _normalizeSql(
          "SELECT * FROM pontos WHERE employee_id = ? AND strftime('%Y-%m', data) = ? ORDER BY data DESC"):
      'pontos_employee_month',
  _normalizeSql('''SELECT COUNT(*) as dias_trabalhados,
    SUM(horas_trabalhadas) as total_horas,
    SUM(horas_extras) as total_horas_extras FROM pontos
    WHERE employee_id = ? AND strftime('%Y-%m', data) = ?'''):
      'pontos_month_summary',
  _normalizeSql('''SELECT oi.*, p.nome AS produto_nome FROM order_items oi
    LEFT JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?'''):
      'order_items_for_orders',
  _normalizeSql('''SELECT COUNT(*) as total_funcionarios,
    SUM(salario_liquido) as total_pagar,
    COUNT(CASE WHEN pago = 1 THEN 1 END) as pagos,
    COUNT(CASE WHEN pago = 0 THEN 1 END) as pendentes
    FROM holerites WHERE mes_referencia = ?'''): 'holerites_month_summary',
  _normalizeSql('SELECT COUNT(*) as total FROM composicoes'):
      'composicoes_count',
  _normalizeSql('SELECT AVG(margem_lucro) as media FROM composicoes'):
      'composicoes_margin_average',
  _normalizeSql('SELECT SUM(custo_total) as total FROM composicoes'):
      'composicoes_cost_total',
  _normalizeSql('SELECT SUM(preco_venda) as total FROM composicoes'):
      'composicoes_sales_total',
};

class _ReportCall {
  const _ReportCall(this.name, this.arguments);

  final String name;
  final List<Object?> arguments;
}

String _normalizeSql(String sql) => sql
    .trim()
    .replaceAll(RegExp(r';+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

void _expectArguments(List<Object?> arguments, int count) {
  if (arguments.length != count) {
    throw ArgumentError('Quantidade de argumentos SQL inválida.');
  }
}

int _integer(Object? result) {
  if (result is int) return result;
  if (result is num) return result.toInt();
  throw SupabaseDatabaseException('O Supabase retornou um número inválido.');
}

List<Map<String, Object?>> _rows(Object? result) {
  if (result is! List || result.any((row) => row is! Map)) {
    throw SupabaseDatabaseException(
      'O Supabase retornou dados de consulta inválidos.',
    );
  }
  return result.map((row) => Map<String, Object?>.from(row as Map)).toList();
}

Map<String, Object?> _copyMap(Map<String, Object?> source) =>
    Map<String, Object?>.from(_copy(source) as Map);

Object? _copy(Object? value) {
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', _copy(item)));
  }
  if (value is Iterable) return value.map(_copy).toList();
  return value;
}
