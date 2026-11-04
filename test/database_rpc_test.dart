import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/core/database/remote_database.dart';
import 'package:masttersystem/services/database_rpc_server.dart';
import 'package:masttersystem/services/stock_repository.dart';
import 'package:masttersystem/models/product_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Estes testes de integração usam o servidor SQLite real no loopback.
  HttpOverrides.global = null;
  const token = 'test-access-token-with-at-least-32-characters';
  late Database database;
  late DatabaseRpcServer server;
  late RemoteDatabase remote;
  late String url;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 29,
        singleInstance: false,
        onCreate: (db, _) => db.execute('CREATE TABLE records ('
            'id INTEGER PRIMARY KEY, name TEXT UNIQUE, value INTEGER, data BLOB)'),
      ),
    );
    server = DatabaseRpcServer(
        database: database,
        token: token,
        transactionIdleTimeout: const Duration(milliseconds: 500));
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    url = 'http://127.0.0.1:${server.port}';
    remote = await RemoteDatabase.connect(serverUrl: url, token: token);
  });

  tearDown(() async {
    await AppDatabase().close();
    await remote.close();
    await server.stop();
    await database.close();
  });

  test('IP privado recebe porta padrão e hospedagem exige HTTPS', () {
    expect(RemoteDatabase.normalizeServerUrl('192.168.1.10'),
        'http://192.168.1.10:8080');
    expect(RemoteDatabase.normalizeServerUrl('https://example.com/erp/'),
        'https://example.com/erp');
    expect(() => RemoteDatabase.normalizeServerUrl('http://8.8.8.8'),
        throwsArgumentError);
    expect(
        () =>
            RemoteDatabase.normalizeServerUrl('https://user:pass@example.com'),
        throwsArgumentError);
  });

  test('PC e dois clientes leem e gravam os mesmos registros e blobs',
      () async {
    await database.insert('records', {'name': 'criado no PC', 'value': 10});
    expect((await remote.query('records')).single['name'], 'criado no PC');
    final id = await remote.insert('records', {
      'name': 'criado no celular',
      'value': 20,
      'data': Uint8List.fromList([0, 128, 255]),
    });
    expect(
        (await database.query('records', where: 'id = ?', whereArgs: [id]))
            .single['name'],
        'criado no celular');
    final second = await RemoteDatabase.connect(serverUrl: url, token: token);
    try {
      await second.rawUpdate(
          'UPDATE records SET value = value + ? WHERE id = ?', [5, id]);
      final row =
          (await remote.query('records', where: 'id = ?', whereArgs: [id]))
              .single;
      expect(row['value'], 25);
      expect(row['data'], [0, 128, 255]);
      await second.delete('records', where: 'id = ?', whereArgs: [id]);
      expect(await database.query('records'), hasLength(1));
    } finally {
      await second.close();
    }
    expect(await remote.getVersion(), 29);
  });

  test('token inválido e ausência de autenticação são recusados', () async {
    final response = await http.get(Uri.parse('$url/health'));
    expect(response.statusCode, 401);
    await expectLater(
        RemoteDatabase.connect(
            serverUrl: url,
            token: 'wrong-access-token-with-at-least-32-characters'),
        throwsA(isA<RemoteDatabaseException>()));
    expect(await database.query('records'), isEmpty);
  });

  test('commit grava e exceção no callback reverte todas as alterações',
      () async {
    await remote.transaction((txn) async {
      await txn.insert('records', {'name': 'confirmado', 'value': 1});
      final batch = txn.batch()
        ..insert('records', {'name': 'lote na transação', 'value': 2});
      await batch.commit(noResult: true);
    });
    await expectLater(remote.transaction((txn) async {
      await txn.insert('records', {'name': 'cancelado', 'value': 3});
      await txn.update('records', {'value': 99},
          where: 'name = ?', whereArgs: ['confirmado']);
      throw StateError('cancelar operação');
    }), throwsStateError);
    final rows = await database.query('records', orderBy: 'id');
    expect(rows.map((row) => row['name']), ['confirmado', 'lote na transação']);
    expect(rows.first['value'], 1);
  });

  test('transações concorrentes não perdem alterações de saldo', () async {
    await database.insert('records', {'name': 'saldo', 'value': 0});
    final second = await RemoteDatabase.connect(serverUrl: url, token: token);
    Future<void> increment(RemoteDatabase connection) =>
        connection.transaction((txn) async {
          final row = (await txn.query('records')).single;
          await txn.update('records', {'value': (row['value'] as int) + 1},
              where: 'id = ?', whereArgs: [row['id']]);
        });
    try {
      await Future.wait([increment(remote), increment(second)]);
      expect((await database.query('records')).single['value'], 2);
    } finally {
      await second.close();
    }
  });

  test('lote é atômico e suporta continueOnError', () async {
    final batch = remote.batch()
      ..insert('records', {'name': 'duplicado', 'value': 1})
      ..insert('records', {'name': 'duplicado', 'value': 2});
    await expectLater(batch.commit(), throwsA(isA<RemoteDatabaseException>()));
    expect(await database.query('records'), isEmpty);
    final partial = remote.batch()
      ..insert('records', {'name': 'duplicado', 'value': 1})
      ..insert('records', {'name': 'duplicado', 'value': 2})
      ..insert('records', {'name': 'outro', 'value': 3});
    final results = await partial.commit(continueOnError: true);
    expect(results[1], isA<DatabaseException>());
    expect(await database.query('records'), hasLength(2));
  });

  Future<http.Response> rpc(String method,
          [Map<String, Object?> params = const {}, String? id]) =>
      http.post(
        Uri.parse('$url/database'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'method': method,
          'params': params,
          if (id != null) 'transactionId': id
        }),
      );

  test('transação abandonada expira e libera o banco com rollback', () async {
    final begin = await rpc('begin');
    final id = (jsonDecode(begin.body) as Map)['result'] as String;
    final inserted = await rpc(
        'insert',
        {
          'table': 'records',
          'values': {'name': 'abandonado', 'value': 1}
        },
        id);
    expect(inserted.statusCode, 200);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(await database.query('records'), isEmpty);
    expect((await rpc('commit', {}, id)).statusCode, 409);
    await remote.insert('records', {'name': 'após expirar', 'value': 2});
    expect(await database.query('records'), hasLength(1));
  });

  test('encerrar servidor reverte uma transação ainda aberta', () async {
    final id =
        (jsonDecode((await rpc('begin')).body) as Map)['result'] as String;
    await rpc(
        'insert',
        {
          'table': 'records',
          'values': {'name': 'não confirmado'}
        },
        id);
    await server.stop();
    expect(await database.query('records'), isEmpty);
  });

  test('DDL e controle de arquivo não são expostos aos clientes', () async {
    await expectLater(remote.execute('DROP TABLE records'),
        throwsA(isA<RemoteDatabaseException>()));
    await expectLater(remote.rawQuery('PRAGMA writable_schema = ON'),
        throwsA(isA<RemoteDatabaseException>()));
    await expectLater(remote.rawQuery('SELECT load_extension(?)', ['invalid']),
        throwsA(isA<RemoteDatabaseException>()));
    await remote.insert(
        'records', {'name': "texto; DROP TABLE records --", 'value': 1});
    expect(await database.query('records'), hasLength(1));
  });

  test('configuração remota persiste sem fallback e preserva config após erro',
      () async {
    await AppDatabase().configureRemoteDatabase(serverUrl: url, token: token);
    expect(await AppDatabase().database, isA<RemoteDatabase>());
    await expectLater(AppDatabase().getDatabasePath(), throwsStateError);
    await expectLater(
        AppDatabase().configureRemoteDatabase(
            serverUrl: url,
            token: 'wrong-access-token-with-at-least-32-characters'),
        throwsA(isA<RemoteDatabaseException>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppDatabase.databaseServerUrlKey), url);
    expect(
        prefs.getString(AppDatabase.databaseModeKey), AppDatabase.remoteMode);
    expect((await AppDatabase().database).isOpen, isTrue);
  });

  test('estoque remoto usa saldo atual mesmo com produto desatualizado na tela',
      () async {
    await remote.close();
    await server.stop();
    await database.close();
    final temporary =
        await Directory.systemTemp.createTemp('matterdi-stock-network-');
    final databaseFile =
        File('${temporary.path}${Platform.pathSeparator}stock.db');
    await databaseFile.create();
    addTearDown(() async {
      await AppDatabase().close();
      await remote.close();
      await server.stop();
      await database.close();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({
      AppDatabase.databaseModeKey: AppDatabase.sharedMode,
      AppDatabase.databasePathKey: databaseFile.path,
    });
    final initial = await AppDatabase().database;
    final product = ProductModel(codigo: 'TEST', nome: 'Produto', estoque: 10);
    product.id = await initial.insert('products', product.toMap());
    await AppDatabase().close();
    database = await databaseFactoryFfi.openDatabase(databaseFile.path,
        options: OpenDatabaseOptions(singleInstance: false));
    server = DatabaseRpcServer(database: database, token: token);
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    url = 'http://127.0.0.1:${server.port}';
    remote = await RemoteDatabase.connect(serverUrl: url, token: token);
    await AppDatabase().configureRemoteDatabase(serverUrl: url, token: token);
    await database.update('products', {'estoque': 25},
        where: 'id = ?', whereArgs: [product.id]);
    final stock = StockRepository();
    await stock.entradaEstoque(
        product: product, quantidade: 10, motivo: 'compra');
    await Future.wait([
      stock.saidaEstoque(product: product, quantidade: 10, motivo: 'venda PC'),
      stock.saidaEstoque(
          product: product, quantidade: 10, motivo: 'venda celular'),
    ]);
    expect((await database.query('products')).single['estoque'], 15);
    final movements = await database.query('stock_movements', orderBy: 'id');
    expect(movements.map((row) => row['previous_stock']), [25, 35, 25]);
    await expectLater(
        stock.saidaEstoque(
            product: product, quantidade: 20, motivo: 'sem saldo'),
        throwsA(isA<Exception>()));
    expect((await database.query('products')).single['estoque'], 15);
    expect(await database.query('stock_movements'), hasLength(3));
  });
}
