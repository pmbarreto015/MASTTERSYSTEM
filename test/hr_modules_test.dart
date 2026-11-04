import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/core/database/erp_modules_schema.dart';
import 'package:masttersystem/models/employee_model.dart';
import 'package:masttersystem/models/hr_module.dart';
import 'package:masttersystem/services/erp_module_repository.dart';
import 'package:masttersystem/services/hr_management_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemoryAppDatabase implements AppDatabase {
  _MemoryAppDatabase(this.db);
  final Database db;
  @override
  Future<Database> get database async => db;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> payroll({double amount = 2000}) => {
      'employee_id': 1,
      'competence': '2026-10',
      'gross': 2200.0,
      'deductions': 200.0,
      'amount': amount,
      'due_date': '2026-11-05',
    };

void main() {
  test('catálogo mantém dezoito módulos com identificadores únicos', () {
    expect(HrModule.modules.length, 18);
    expect(HrModule.modules.map((m) => m.key).toSet().length, 18);
  });

  test(
      'férias rejeitam períodos invertidos sem descartar erros dos outros campos',
      () {
    final errors = HrModule.byKey('ferias').validate({
      'employee_id': 1,
      'acquisition_start': '2026-05-01',
      'acquisition_end': '2025-05-01',
      'start_date': '2026-12-20',
      'end_date': '2026-12-10',
      'amount': 0,
      'due_date': '2026-12-15',
    });
    expect(errors.keys, containsAll(['acquisition_end', 'end_date']));
  });

  test('folha recusa competência, datas inexistentes e valores não finitos',
      () {
    final errors = HrModule.byKey('folha').validate({
      ...payroll(),
      'competence': '2026-13',
      'amount': double.nan,
      'due_date': '2026-02-31',
    });
    expect(errors.keys, containsAll(['competence', 'amount', 'due_date']));
  });

  test('avaliacao exige colaborador válido e nota até dez', () {
    final errors = HrModule.byKey('desempenho').validate({
      'employee_id': -1,
      'evaluation_date': '2026-10-24',
      'evaluator': 'Gestora',
      'target': 'Entregas no prazo',
      'score': 11,
    });
    expect(errors.keys, containsAll(['employee_id', 'score']));
  });

  group('persistência e integração financeira local', () {
    late Database db;
    late ErpModuleRepository records;
    late HrManagementService service;
    final employee = EmployeeModel.create(
            name: 'Colaboradora teste',
            document: '',
            phone: '',
            email: '',
            position: 'Produção')
        .copyWith(id: 1);

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      await createErpModulesSchema(db);
      await db.execute('''CREATE TABLE financial (
        id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT NOT NULL,
        amount REAL NOT NULL, type TEXT NOT NULL, due_date TEXT NOT NULL,
        is_paid INTEGER, notes TEXT, order_id INTEGER, customer_id INTEGER,
        customer_name TEXT, categoria TEXT, forma_pagamento TEXT,
        parcela INTEGER, total_parcelas INTEGER, valor_bruto REAL, taxa REAL,
        valor_liquido REAL, status TEXT, pagamentos TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''');
      final app = _MemoryAppDatabase(db);
      records = ErpModuleRepository(database: app);
      service = HrManagementService(records: records, database: app);
    });
    tearDown(() async => db.close());

    test('salva registro e mantém auditoria sem expor documentos no evento',
        () async {
      final saved = await service.save(
          module: HrModule.byKey('folha'),
          title: 'Folha outubro',
          status: 'Rascunho',
          payload: payroll(),
          actor: 'Gestora');
      final all = await service.list();
      expect(all.where((r) => r.recordType == 'folha').single.id, saved.id);
      final audit = all.where((r) => r.recordType == 'auditoria').single;
      expect(audit.payload['actor'], 'Gestora');
      expect(audit.payload.containsKey('amount'), false);
    });

    test('conta a pagar e vínculo são atômicos e reenvio não duplica',
        () async {
      final saved = await service.save(
          module: HrModule.byKey('folha'),
          title: 'Folha outubro',
          status: 'Aprovado',
          payload: payroll(),
          actor: 'Gestora');
      final first = await service.sendToFinancial(saved, employee, 'Gestora');
      final second = await service.sendToFinancial(saved, employee, 'Gestora');
      expect(first.id, second.id);
      expect((await db.query('financial')).length, 1);
      final linked = (await records.getById(saved.id!))!;
      expect(linked.payload['financial_id'], first.id);
      expect(linked.status, 'Enviado ao financeiro');
      expect(first.type, 'pagar');
      expect(first.isPaid, false);
      expect(first.amount, 2000);
    });

    test('rascunho não gera conta e registro vinculado não pode ser excluído',
        () async {
      var saved = await service.save(
          module: HrModule.byKey('folha'),
          title: 'Folha outubro',
          status: 'Rascunho',
          payload: payroll(),
          actor: 'Gestora');
      await expectLater(service.sendToFinancial(saved, employee, 'Gestora'),
          throwsStateError);
      expect(await db.query('financial'), isEmpty);
      saved = await service.save(
          module: HrModule.byKey('folha'),
          title: saved.title,
          status: 'Aprovado',
          payload: saved.payload,
          actor: 'Gestora',
          previous: saved);
      await service.sendToFinancial(saved, employee, 'Gestora');
      final linked = (await records.getById(saved.id!))!;
      await expectLater(service.delete(linked, 'Gestora'), throwsStateError);
    });

    test('falha de gravação do vínculo desfaz conta a pagar', () async {
      final saved = await service.save(
          module: HrModule.byKey('folha'),
          title: 'Folha outubro',
          status: 'Aprovado',
          payload: payroll(),
          actor: 'Gestora');
      await db.execute(
          "CREATE TRIGGER fail_link BEFORE UPDATE ON erp_module_records WHEN NEW.record_type = 'folha' BEGIN SELECT RAISE(ABORT, 'falha simulada'); END");
      await expectLater(service.sendToFinancial(saved, employee, 'Gestora'),
          throwsA(anything));
      expect(await db.query('financial'), isEmpty);
      expect(
          (await records.getById(saved.id!))!.payload['financial_id'], isNull);
    });
  });
}
