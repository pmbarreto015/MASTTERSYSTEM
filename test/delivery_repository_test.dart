import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/services/delivery_repository.dart';

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
  late Directory directory;
  late PathProviderPlatform previousPaths;
  late DeliveryRepository repository;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('matterdi-delivery-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    final database = await AppDatabase().database;
    final now = DateTime.now().toIso8601String();
    await database.insert('customers', {
      'id': 1,
      'uuid': 'delivery-customer',
      'name': 'Cliente da entrega',
      'phone': '11999998888',
      'address': 'Rua das Flores, 100',
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('orders', {
      'id': 1,
      'number': 'OS-ENT-1',
      'tipo': 'OS',
      'cliente_nome': 'Cliente da entrega',
      'customer_id': 1,
      'total': 180,
      'payment_method': 'Pix',
      'status': 'entregue',
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('orders', {
      'id': 2,
      'number': 'OS-AINDA-EM-PRODUCAO',
      'tipo': 'OS',
      'cliente_nome': 'Cliente da entrega',
      'customer_id': 1,
      'total': 50,
      'payment_method': 'Pix',
      'status': 'em_producao',
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('financial', {
      'description': 'Recebimento OS-ENT-1',
      'amount': 180,
      'type': 'receber',
      'due_date': now,
      'is_paid': 0,
      'order_id': 1,
      'status': 'pendente',
      'created_at': now,
      'updated_at': now,
    });
    repository = DeliveryRepository();
  });

  tearDownAll(() async {
    await AppDatabase().close();
    PathProviderPlatform.instance = previousPaths;
    if (!path.isWithin(Directory.systemTemp.resolveSymbolicLinksSync(),
            directory.resolveSymbolicLinksSync()) ||
        !path.basename(directory.path).startsWith('matterdi-delivery-')) {
      throw StateError('DiretÃ³rio de teste inesperado.');
    }
    await directory.delete(recursive: true);
  });

  test('importa somente pedidos finalizados uma vez e traz financeiro',
      () async {
    final first = await repository.syncCompletedOrders(actor: 'ExpediÃ§Ã£o');
    final second = await repository.syncCompletedOrders(actor: 'ExpediÃ§Ã£o');

    expect(first, hasLength(1));
    expect(second, hasLength(1));
    final delivery = second.single;
    expect(delivery.orderNumber, 'OS-ENT-1');
    expect(delivery.customerName, 'Cliente da entrega');
    expect(delivery.address, 'Rua das Flores, 100');
    expect(delivery.contact, '11999998888');
    expect(delivery.paymentPending, 180);
    expect(delivery.history.single.responsible, 'ExpediÃ§Ã£o');
  });

  test('registra modalidade, agendamento e histÃ³rico da entrega', () async {
    final original = (await repository.list()).single;
    final saved = await repository.save(
      original.copyWith(
        method: 'lalamove',
        status: 'saiu_para_entrega',
        scheduledAt: DateTime(2026, 10, 24, 15),
        responsible: 'Maria',
        reference: 'PortÃ£o azul',
      ),
      actor: 'Maria',
    );

    expect(saved.methodLabel, 'Lalamove');
    expect(saved.statusLabel, 'Saiu para entrega');
    expect(saved.responsible, 'Maria');
    expect(saved.history.last.status, 'saiu_para_entrega');
    expect(saved.history.last.responsible, 'Maria');
  });

  test('lanÃ§a para receber apÃ³s configurar e sÃ³ entÃ£o conclui', () async {
    final database = await AppDatabase().database;
    final now = DateTime.now().toIso8601String();
    await database.insert('orders', {
      'id': 3,
      'number': 'OS-ENT-SEM-FINANCEIRO',
      'tipo': 'OS',
      'cliente_nome': 'Cliente da entrega',
      'customer_id': 1,
      'total': 70,
      'payment_method': 'CartÃ£o',
      'status': 'entregue',
      'created_at': now,
      'updated_at': now,
    });
    final imported = await repository.syncCompletedOrders(actor: 'ExpediÃ§Ã£o');
    final delivery = imported.firstWhere((item) => item.orderId == 3);

    expect(delivery.hasFinancialEntry, isFalse);
    await expectLater(
        repository.conclude(delivery, actor: 'Maria'), throwsStateError);

    final configured = await repository.save(
      delivery.copyWith(
        method: 'entrega_loja',
        status: 'agendado',
        scheduledAt: DateTime(2026, 10, 25, 14),
        responsible: 'Maria',
        contact: '11999998888',
        address: 'Rua das Flores, 100',
      ),
      actor: 'Maria',
    );
    expect(configured.deliveryDataReady, isTrue);

    await repository.launchReceivable(configured, actor: 'Maria');
    final launched =
        (await repository.list()).firstWhere((item) => item.orderId == 3);
    expect(launched.hasFinancialEntry, isTrue);
    expect(launched.paymentPending, 70);

    final concluded = await repository.conclude(launched, actor: 'Maria');
    expect(concluded.status, 'concluido');
    expect(concluded.completedAt, isNotNull);
  });

  test('recebe o saldo do pedido no financeiro sem duplicar cobranÃ§a',
      () async {
    final rows = await repository.pendingReceivables(1);
    expect(rows, hasLength(1));
    final id = rows.single.id!;
    await repository.receivePayment(
        orderId: 1,
        receivableId: id,
        amount: 90,
        receivedAt: DateTime(2026, 10, 24));
    final partial = await repository.refreshBalances();
    final delivery = partial.firstWhere((item) => item.orderId == 1);
    expect(delivery.paymentTotal, 180);
    expect(delivery.paymentPending, 90);
    await expectLater(
        repository.receivePayment(
            orderId: 1,
            receivableId: id,
            amount: 91,
            receivedAt: DateTime.now()),
        throwsArgumentError);
    await repository.receivePayment(
        orderId: 1,
        receivableId: id,
        amount: 90,
        receivedAt: DateTime(2026, 10, 24));
    final settled = (await repository.refreshBalances())
        .firstWhere((item) => item.orderId == 1);
    expect(settled.paymentTotal, 180);
    expect(settled.paymentPending, 0);
    expect(settled.isPaidInFull, isTrue);
    expect(await repository.pendingReceivables(1), isEmpty);
    await expectLater(
        repository.receivePayment(
            orderId: 1,
            receivableId: id,
            amount: 90,
            receivedAt: DateTime.now()),
        throwsStateError);
  });

  test('quita o saldo exibido mesmo com imprecisÃ£o de ponto flutuante',
      () async {
    final database = await AppDatabase().database;
    final rows = await repository.pendingReceivables(3);
    final id = rows.single.id!;
    await database.update('financial', {'amount': 44.49999999999999},
        where: 'id = ?', whereArgs: [id]);
    await expectLater(
        repository.receivePayment(
            orderId: 3,
            receivableId: id,
            amount: 44.51,
            receivedAt: DateTime.now()),
        throwsArgumentError);
    await repository.receivePayment(
        orderId: 3,
        receivableId: id,
        amount: 44.50,
        receivedAt: DateTime.now());
    expect(await repository.pendingReceivables(3), isEmpty);
    final updated =
        await database.query('financial', where: 'id = ?', whereArgs: [id]);
    expect(updated.single['is_paid'], 1);
    expect(updated.single['amount'], 0);
  });

  test('inclui a taxa de entrega em uma conta a receber do pedido', () async {
    final database = await AppDatabase().database;
    final now = DateTime.now().toIso8601String();
    await database.insert('orders', {
      'id': 4,
      'number': 'OS-ENT-FRETE',
      'tipo': 'OS',
      'cliente_nome': 'Cliente da entrega',
      'customer_id': 1,
      'total': 100,
      'payment_method': 'Cart?o',
      'status': 'entregue',
      'created_at': now,
      'updated_at': now,
    });
    final imported = await repository.syncCompletedOrders(actor: 'Expedi??o');
    final delivery = imported.firstWhere((item) => item.orderId == 4);
    final configured = await repository.save(
      delivery.copyWith(
        method: 'entrega_loja',
        status: 'agendado',
        scheduledAt: DateTime(2026, 10, 28, 10),
        responsible: 'Maria',
        contact: '11999998888',
        address: 'Rua das Flores, 100',
        deliveryFee: 12,
      ),
      actor: 'Maria',
    );
    await repository.launchReceivable(configured, actor: 'Maria');
    final refreshed = await repository.refreshBalances();
    final launched = refreshed.firstWhere((item) => item.orderId == 4);
    expect(launched.paymentTotal, 112);
    expect(launched.paymentPending, 112);
    final rows = await repository.pendingReceivables(4);
    expect(rows.map((row) => row.amount), containsAll(<double>[100, 12]));
    expect(rows.any((row) => (row.notes ?? '').contains('[ENTREGA_FRETE:4]')),
        isTrue);
  });
}
