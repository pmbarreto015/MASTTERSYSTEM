import 'dart:convert';

import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';
import '../models/employee_model.dart';
import '../models/erp_module_record.dart';
import '../models/financial_model.dart';
import '../models/hr_module.dart';
import 'erp_module_repository.dart';

class HrManagementService {
  HrManagementService({ErpModuleRepository? records, AppDatabase? database})
      : _records = records ?? ErpModuleRepository(),
        _database = database ?? AppDatabase();

  final ErpModuleRepository _records;
  final AppDatabase _database;
  static final Set<int> _financialInFlight = {};

  Future<List<ErpModuleRecord>> list() => _records.list('rh');

  Future<ErpModuleRecord> save(
      {required HrModule module,
      required String title,
      required String status,
      required Map<String, dynamic> payload,
      required String actor,
      ErpModuleRecord? previous}) async {
    if (title.trim().isEmpty)
      throw ArgumentError('Informe o título do registro.');
    if (!module.statuses.contains(status))
      throw ArgumentError('Situação inválida.');
    final errors = module.validate(payload);
    if (errors.isNotEmpty) throw ArgumentError(errors.values.first);
    if (previous?.id != null) {
      final latest = await _records.getById(previous!.id!);
      if (latest == null || latest.updatedAt != previous.updatedAt) {
        throw StateError(
            'Este registro foi alterado em outra tela ou dispositivo. Feche o editor e abra o registro atualizado.');
      }
    }
    if (previous?.payload['financial_id'] != null &&
        (payload['amount'] != previous!.payload['amount'] ||
            payload['employee_id'] != previous.payload['employee_id'] ||
            payload['due_date'] != previous.payload['due_date'])) {
      throw StateError(
          'O lançamento já está no financeiro. Valor, vencimento e colaborador devem ser ajustados no módulo financeiro.');
    }
    if (module.key == 'documentos' &&
        status == 'Assinatura comprovada pelo provedor' &&
        ('${payload['signature_provider'] ?? ''}'.trim().isEmpty ||
            '${payload['signature_protocol'] ?? ''}'.trim().isEmpty)) {
      throw ArgumentError(
          'Informe o provedor e o protocolo da assinatura externa.');
    }
    final saved = await _records.save(ErpModuleRecord(
      id: previous?.id,
      module: 'rh',
      recordType: module.key,
      title: title.trim(),
      status: status,
      payload: {
        ...payload,
        'updated_by': actor,
        'created_by': previous?.payload['created_by'] ?? actor
      },
      referenceId: previous?.referenceId,
      createdAt: previous?.createdAt,
    ));
    await _audit(saved, previous == null ? 'criado' : 'alterado', actor);
    return saved;
  }

  Future<void> delete(ErpModuleRecord record, String actor) async {
    if (record.payload['financial_id'] != null) {
      throw StateError(
          'Este registro está vinculado ao financeiro. Preserve o histórico e altere a situação para Cancelado.');
    }
    await _records.delete(record.id!);
    await _audit(record, 'excluído', actor);
  }

  Future<void> _audit(
      ErpModuleRecord record, String action, String actor) async {
    await _records.save(ErpModuleRecord(
      module: 'rh',
      recordType: 'auditoria',
      title: '${record.title}: $action',
      status: action,
      payload: {
        'record_id': record.id,
        'record_type': record.recordType,
        'actor': actor,
        'record_status': record.status,
        'at': DateTime.now().toIso8601String()
      },
    ));
  }

  /// Cria a conta e o vínculo na mesma transação. A RPC do Supabase serializa
  /// envios de dispositivos diferentes; o banco local usa sua transação nativa.
  Future<FinancialModel> sendToFinancial(
      ErpModuleRecord record, EmployeeModel employee, String actor) async {
    final id = record.id;
    if (id == null)
      throw StateError('Salve o registro antes de enviar ao financeiro.');
    final module = HrModule.byKey(record.recordType);
    if (!module.financial)
      throw StateError('Este tipo de registro não gera contas a pagar.');
    if (!_financialInFlight.add(id))
      throw StateError('O envio deste registro já está em andamento.');
    try {
      final current = await _records.getById(id);
      if (current == null) throw StateError('Registro não encontrado.');
      if (current.payload['financial_id'] == null &&
          current.status != 'Aprovado')
        throw StateError('Aprove o registro antes de gerar a conta a pagar.');
      final amount = (current.payload['amount'] as num?)?.toDouble() ?? 0;
      final due = DateTime.tryParse('${current.payload['due_date']}');
      if (!amount.isFinite || amount <= 0 || due == null)
        throw StateError(
            'Informe valor aprovado maior que zero e vencimento válido.');
      if (employee.id != current.payload['employee_id'])
        throw StateError(
            'O colaborador do registro não corresponde ao selecionado.');
      final now = DateTime.now();
      final financial = FinancialModel(
        description: '${module.title} • ${employee.name} • ${current.title}',
        amount: amount,
        type: 'pagar',
        dueDate: due,
        categoria: 'pessoal',
        status: 'pendente',
        notes:
            '[RH:$id] Origem: RH/${current.recordType}. Colaborador #${employee.id}. Aprovado por $actor.',
        createdAt: now,
        updatedAt: now,
      );
      final database = await _database.database;
      late FinancialModel transaction;
      if (database is SupabaseDatabase) {
        final result = await database.rpc('matterdi_module_financial', {
          'p_record_id': id,
          'p_financial': financial.toMap()..remove('id'),
        });
        transaction =
            FinancialModel.fromMap(Map<String, dynamic>.from(result as Map));
      } else {
        transaction = await database.transaction((executor) async {
          final rows = await executor.query('erp_module_records',
              where: 'id = ? AND module = ?', whereArgs: [id, 'rh']);
          if (rows.isEmpty) throw StateError('Registro não encontrado.');
          final locked = ErpModuleRecord.fromMap(rows.single);
          final linkedId = locked.payload['financial_id'];
          if (linkedId != null) {
            final linked = await executor
                .query('financial', where: 'id = ?', whereArgs: [linkedId]);
            if (linked.isEmpty)
              throw StateError(
                  'A conta vinculada foi removida. Confira o financeiro antes de gerar outra.');
            return FinancialModel.fromMap(linked.single);
          }
          if (locked.status != 'Aprovado')
            throw StateError(
                'Aprove o registro antes de gerar a conta a pagar.');
          if (locked.payload['amount'] != current.payload['amount'] ||
              locked.payload['due_date'] != current.payload['due_date'] ||
              locked.payload['employee_id'] != current.payload['employee_id']) {
            throw StateError(
                'O registro foi alterado durante o envio. Atualize os dados e tente novamente.');
          }
          final financialId = await executor.insert(
              'financial', financial.toMap()..remove('id'));
          await executor.update(
              'erp_module_records',
              {
                'status': module.statuses.contains('Enviado ao financeiro')
                    ? 'Enviado ao financeiro'
                    : locked.status,
                'payload': jsonEncode({
                  ...locked.payload,
                  'financial_id': financialId,
                  'financial_sent_at': now.toIso8601String(),
                  'financial_sent_by': actor
                }),
                'updated_at': now.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [id]);
          return financial.copyWith(id: financialId);
        });
      }
      await _audit(current, 'enviado ao financeiro #${transaction.id}', actor);
      return transaction;
    } finally {
      _financialInFlight.remove(id);
    }
  }
}
