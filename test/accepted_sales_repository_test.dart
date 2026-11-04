import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/models/order_model.dart';
import 'package:masttersystem/services/order_repository.dart';
import 'package:masttersystem/services/financial_repository.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

void main() {
  late Directory temp;
  late PathProviderPlatform previous;
  late Database db;
  var sequence = 0;
  final repository = OrderRepository(), financial = FinancialRepository();
  OrderModel document(String type, {String payment = 'Boleto'}) => OrderModel(
        numero: 'TEST-${sequence++}',
        tipo: type,
        clienteId: 1,
        clienteNome: 'Cliente',
        sellerId: 1,
        formaPagamento: payment,
        itens: [
          OrderItemModel(
              produtoId: 1,
              produtoNome: 'Produto',
              quantidade: 1,
              precoUnitario: 100,
              subtotal: 100)
        ],
      );
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('matterdi-accepted-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    db = await AppDatabase().database;
    final now = DateTime.now().toIso8601String();
    await db.insert('customers',
        {'id': 1, 'name': 'Cliente', 'created_at': now, 'updated_at': now});
    await db.insert('products', {
      'id': 1,
      'codigo': 'TEST',
      'nome': 'Produto',
      'categoria': 'Teste',
      'preco': 100,
      'created_at': now,
      'updated_at': now
    });
    await db.insert('sellers',
        {'id': 1, 'name': 'Vendedor', 'created_at': now, 'updated_at': now});
  });
  setUp(() async {
    await db.delete('financial');
    await db.delete('order_items');
    await db.delete('orders');
    await db.update('sellers', {'total_sales': 0});
  });
  tearDownAll(() async {
    await AppDatabase().close();
    PathProviderPlatform.instance = previous;
    if (!path.isWithin(Directory.systemTemp.resolveSymbolicLinksSync(),
            temp.resolveSymbolicLinksSync()) ||
        !path.basename(temp.path).startsWith('matterdi-accepted-')) {
      throw StateError('Diretório inesperado');
    }
    await temp.delete(recursive: true);
  });
  test('orçamento não entra no financeiro, produção ou totais de vendedor',
      () async {
    final quote =
        await repository.create(document('ORCAMENTO')..status = 'em_producao');
    expect(quote.status, 'aguardando_pagamento');
    expect(await financial.getAll(), isEmpty);
    expect(await repository.getProducao(), isEmpty);
    expect((await db.query('sellers')).first['total_sales'], 0);
  });
  test('aceite gera financeiro uma vez e atualiza vendas do vendedor',
      () async {
    final quote = await repository.create(document('ORCAMENTO'));
    final accepted = await repository.approveQuote(quote);
    expect(accepted.tipo, 'OS');
    expect((await financial.getAll()).length, 1);
    expect((await db.query('sellers')).first['total_sales'], 100);
    await expectLater(repository.approveQuote(quote), throwsStateError);
    expect((await financial.getAll()).length, 1);
  });
  test(
      'retorno para orçamento preserva títulos cancelados; novo aceite não duplica ativos',
      () async {
    final os = await repository.create(document('OS'));
    final quote = os.copyWith(tipo: 'ORCAMENTO');
    await repository.update(quote);
    expect(await financial.getAll(), isEmpty);
    final history = await financial.getAll(includeCancelled: true);
    expect(history.length, 1);
    expect(history.first.status, 'cancelado');
    expect((await db.query('sellers')).first['total_sales'], 0);
    await repository.update(quote.copyWith(tipo: 'OS'));
    expect((await financial.getAll()).length, 1);
    expect((await financial.getAll(includeCancelled: true)).length, 2);
    expect((await db.query('sellers')).first['total_sales'], 100);
  });
  test('OS paga não volta para orçamento nem perde itens ou recebimentos',
      () async {
    final os = await repository.create(document('OS', payment: 'À Vista'));
    await expectLater(
        repository.update(os.copyWith(tipo: 'ORCAMENTO')), throwsStateError);
    expect((await repository.getById(os.id!))!.tipo, 'OS');
    expect((await db.query('order_items')).length, 1);
    expect((await db.query('financial')).length, 1);
    expect((await financial.getAll()).first.isPaid, isTrue);
  });

  test('cada etapa escolhida para a venda mantém o financeiro independente',
      () async {
    for (final status in OrderModel.productionStatuses.keys) {
      final order = document('OS')..status = status;
      final saved = await repository.create(order);
      expect(saved.status, status);
      expect((await repository.getById(saved.id!))!.status, status);
      final titles = (await financial.getAll())
          .where((title) => title.orderId == saved.id)
          .toList();
      expect(titles, hasLength(1));
      expect(titles.single.isPaid, isFalse);
      expect(titles.single.amount, 100);
    }
  });

  test('alterar a etapa preserva especificações dos pedidos antigos', () async {
    final order = document('OS');
    order.itens.single.especificacoes =
        'Tamanho: P | Cor: Branca | Material: Algodão | Arte aprovada';
    final saved = await repository.create(order);
    await repository.update(saved.copyWith(status: 'pronto'));
    final reloaded = await repository.getById(saved.id!);
    expect(reloaded!.itens.single.especificacoes,
        order.itens.single.especificacoes);
    expect(reloaded.status, 'pronto');
  });

  test('entrada de valor zero não é tratada como recebimento', () async {
    final os = await repository
        .create(document('OS', payment: '50% no ato + 50% na entrega'));
    await repository.update(os.copyWith(tipo: 'ORCAMENTO'));
    expect(await financial.getAll(), isEmpty);
    final history = await financial.getAll(includeCancelled: true);
    expect(history.length, 1);
    expect(history.every((t) => t.status == 'cancelado'), isTrue);
  });
}
