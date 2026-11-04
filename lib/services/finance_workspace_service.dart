import '../models/erp_module_record.dart';
import '../models/financial_model.dart';
import 'erp_module_repository.dart';
import 'finance_calculations.dart';
import 'financial_repository.dart';

class FinanceWorkspaceService {
  FinanceWorkspaceService(
      {ErpModuleRepository? records, FinancialRepository? financial})
      : records = records ?? ErpModuleRepository(),
        financial = financial ?? FinancialRepository();
  final ErpModuleRepository records;
  final FinancialRepository financial;
  static const module = 'financeiro';
  String actor = 'Sistema';
  int? actorId;

  Future<List<ErpModuleRecord>> load() => records.list(module);

  Future<ErpModuleRecord> saveRecord(ErpModuleRecord record) async {
    if (record.title.trim().isEmpty)
      throw ArgumentError('Informe a descrição.');
    final result = await records.save(record);
    await audit(record.id == null ? 'Cadastro' : 'Alteração', record.recordType,
        targetId: result.id, details: record.title);
    return result;
  }

  Future<void> archive(ErpModuleRecord record) async {
    await records.save(record.copyWith(status: 'inativo'));
    await audit('Arquivamento', record.recordType,
        targetId: record.id, details: record.title);
  }

  Future<void> audit(String action, String type,
      {int? targetId, String details = ''}) async {
    await records.save(ErpModuleRecord(
      module: module,
      recordType: 'audit',
      title: '$action — $details',
      payload: {
        'action': action,
        'targetType': type,
        'targetId': targetId,
        'actor': actor,
        'actorId': actorId
      },
    ));
  }

  static double accountBalance(int accountId, List<ErpModuleRecord> records,
      Iterable<FinancialModel> financial) {
    final account =
        records.where((r) => r.recordType == 'account' && r.id == accountId);
    if (account.isEmpty) return 0;
    var balance =
        (account.first.payload['openingBalance'] as num? ?? 0).toDouble();
    for (final r in records
        .where((r) => r.recordType == 'transfer' && r.status != 'cancelado')) {
      final amount = (r.payload['amount'] as num? ?? 0).toDouble();
      if (r.payload['fromId'] == accountId) balance -= amount;
      if (r.payload['toId'] == accountId) balance += amount;
    }
    final assigned = <int>{
      for (final r in records.where((r) =>
          r.recordType == 'transaction_meta' &&
          r.payload['accountId'] == accountId))
        if (r.payload['financialId'] is int) r.payload['financialId'] as int,
    };
    for (final t in financial.where((t) =>
        assigned.contains(t.id) && t.isPaid && t.status != 'cancelado')) {
      balance += t.type == 'receber' ? t.amount : -t.amount;
    }
    return (balance * 100).round() / 100;
  }

  Future<void> transfer(
      {required int fromId,
      required int toId,
      required double amount,
      required DateTime date,
      required String description,
      required String reference}) async {
    if (fromId == toId) throw ArgumentError('Escolha contas diferentes.');
    if (!amount.isFinite || amount <= 0)
      throw ArgumentError('Informe um valor positivo.');
    final all = await load();
    if (all
        .any((r) => r.recordType == 'transfer' && r.referenceId == reference))
      return;
    for (final id in [fromId, toId]) {
      if (!all.any((r) =>
          r.id == id && r.recordType == 'account' && r.status == 'ativo')) {
        throw StateError('A conta foi desativada. Atualize os dados.');
      }
    }
    final rows = await financial.getAll();
    if (accountBalance(fromId, all, rows) + 0.001 < amount) {
      throw StateError('Saldo insuficiente na conta de origem.');
    }
    // As duas pontas pertencem ao mesmo registro: não existe meia transferência.
    await saveRecord(ErpModuleRecord(
      module: module,
      recordType: 'transfer',
      referenceId: reference,
      title: description.trim().isEmpty
          ? 'Transferência entre contas'
          : description.trim(),
      payload: {
        'fromId': fromId,
        'toId': toId,
        'amount': (amount * 100).round() / 100,
        'date': date.toIso8601String()
      },
    ));
  }

  Future<FinancialModel> saveTransaction(FinancialModel row,
      {int? accountId, int? centerId}) async {
    if (row.description.trim().isEmpty ||
        !row.amount.isFinite ||
        row.amount <= 0) {
      throw ArgumentError('Informe descrição e valor maior que zero.');
    }
    if (!['receber', 'pagar'].contains(row.type))
      throw ArgumentError('Tipo inválido.');
    if (accountId != null || centerId != null) {
      final all = await load();
      for (final pair in [(accountId, 'account'), (centerId, 'cost_center')]) {
        if (pair.$1 != null &&
            !all.any((r) =>
                r.id == pair.$1 &&
                r.recordType == pair.$2 &&
                r.status == 'ativo')) {
          throw StateError('Conta ou centro de custos indisponível.');
        }
      }
    }
    final saved = row.id == null
        ? await financial.create(row)
        : await financial.update(row);
    final all = await records.list(module, recordType: 'transaction_meta');
    final existing =
        all.where((r) => r.payload['financialId'] == saved.id).firstOrNull;
    await records.save(ErpModuleRecord(
      id: existing?.id,
      module: module,
      recordType: 'transaction_meta',
      referenceId: 'financial:${saved.id}',
      title: saved.description,
      payload: {
        ...?existing?.payload,
        'financialId': saved.id,
        'accountId': accountId,
        'centerId': centerId
      },
      createdAt: existing?.createdAt,
    ));
    await audit(
        row.id == null ? 'Lançamento' : 'Alteração de lançamento', 'financial',
        targetId: saved.id, details: saved.description);
    return saved;
  }

  Future<void> settle(FinancialModel row) async {
    await financial.update(
        row.copyWith(isPaid: true, status: 'pago', updatedAt: DateTime.now()));
    await audit('Baixa', 'financial',
        targetId: row.id, details: row.description);
  }

  Future<void> cancel(FinancialModel row) async {
    await financial
        .update(row.copyWith(status: 'cancelado', updatedAt: DateTime.now()));
    await audit('Cancelamento', 'financial',
        targetId: row.id, details: row.description);
  }

  Future<int> importOfx(String source, int accountId) async {
    final entries = financeParseOfx(source);
    final all = await load();
    if (!all.any((r) =>
        r.id == accountId &&
        r.recordType == 'account' &&
        r.status == 'ativo')) {
      throw StateError('Selecione uma conta ativa.');
    }
    final known = all
        .where((r) => r.recordType == 'ofx')
        .map((r) => r.referenceId)
        .toSet();
    var added = 0;
    for (final entry in entries) {
      final ref = '$accountId:${entry.reference}';
      if (known.contains(ref)) continue;
      await records.save(ErpModuleRecord(
        module: module,
        recordType: 'ofx',
        referenceId: ref,
        title: entry.description.isEmpty ? entry.externalId : entry.description,
        status: 'pendente',
        payload: {
          'accountId': accountId,
          'externalId': entry.externalId,
          'date': entry.date.toIso8601String(),
          'amount': entry.amount,
          'bankAccount': entry.account,
        },
      ));
      known.add(ref);
      added++;
    }
    await audit('Importação OFX', 'ofx', details: '$added movimentos novos');
    return added;
  }

  Future<void> reconcile(
      ErpModuleRecord entry, FinancialModel transaction) async {
    final latest = await records.getById(entry.id!);
    if (latest == null || latest.status == 'conciliado')
      throw StateError('Movimento já conciliado.');
    final amount = (latest.payload['amount'] as num).toDouble();
    final current = await financial.getById(transaction.id!);
    if (current == null || current.status == 'cancelado')
      throw StateError('Lançamento indisponível.');
    if ((amount > 0) != (current.type == 'receber') ||
        (amount.abs() * 100).round() != (current.amount * 100).round()) {
      throw ArgumentError(
          'Valor e natureza do lançamento devem coincidir com o OFX.');
    }
    final all = await load();
    if (all.any((r) =>
        r.recordType == 'ofx' &&
        r.status == 'conciliado' &&
        r.id != entry.id &&
        r.payload['financialId'] == current.id)) {
      throw StateError('Lançamento já associado a outro movimento OFX.');
    }
    final meta = all
        .where((r) =>
            r.recordType == 'transaction_meta' &&
            r.payload['financialId'] == current.id)
        .firstOrNull;
    if (meta?.payload['accountId'] != null &&
        meta!.payload['accountId'] != latest.payload['accountId']) {
      throw StateError('Lançamento pertence a outra conta bancária.');
    }
    await saveTransaction(
        current.copyWith(
            isPaid: true, status: 'pago', updatedAt: DateTime.now()),
        accountId: latest.payload['accountId'] as int?,
        centerId: meta?.payload['centerId'] as int?);
    await records.save(latest.copyWith(status: 'conciliado', payload: {
      ...latest.payload,
      'financialId': current.id,
      'reconciledAt': DateTime.now().toIso8601String(),
    }));
    await audit('Conciliação', 'ofx',
        targetId: entry.id, details: current.description);
  }

  /// A chave da origem permite retomar uma geração interrompida sem duplicar.
  Future<FinancialModel> generateTransaction(
      {required String reference,
      required FinancialModel transaction,
      int? centerId}) async {
    final rows = await financial.getAll(includeCancelled: true);
    final marker = '[finance:$reference]';
    final existing =
        rows.where((r) => (r.notes ?? '').contains(marker)).firstOrNull;
    if (existing != null) return existing;
    return saveTransaction(
        transaction.copyWith(notes: '${transaction.notes ?? ''}\n$marker'),
        centerId: centerId);
  }

  Future<int> generateRecurring(ErpModuleRecord rule, DateTime until) async {
    final fresh = await records.getById(rule.id!);
    if (fresh == null || fresh.status != 'ativo')
      throw StateError('Recorrência inativa.');
    var date = DateTime.parse(fresh.payload['nextDate'] as String);
    var generated = 0;
    final day = (fresh.payload['day'] as num?)?.toInt() ?? date.day;
    while (!date.isAfter(until)) {
      if (generated >= 120)
        throw StateError('Limite de 120 competências por execução.');
      final now = DateTime.now();
      await generateTransaction(
        reference:
            'recurrence:${fresh.id}:${date.toIso8601String().substring(0, 10)}',
        transaction: FinancialModel(
            description: fresh.title,
            amount: (fresh.payload['amount'] as num).toDouble(),
            type: 'pagar',
            dueDate: date,
            categoria: fresh.payload['category'] as String? ?? 'operacional',
            customerName: fresh.payload['supplier'] as String?,
            createdAt: now,
            updatedAt: now),
        centerId: fresh.payload['centerId'] as int?,
      );
      generated++;
      final nextMonth = DateTime(date.year, date.month + 2, 0);
      date = DateTime(
          date.year, date.month + 1, day > nextMonth.day ? nextMonth.day : day);
    }
    await records.save(fresh.copyWith(
        payload: {...fresh.payload, 'nextDate': date.toIso8601String()}));
    await audit('Geração de despesas recorrentes', 'recurrence',
        targetId: fresh.id, details: '$generated competências');
    return generated;
  }

  Future<int> generateCardPlan(ErpModuleRecord plan) async {
    final gross = (plan.payload['gross'] as num).toDouble();
    final fee = (plan.payload['fee'] as num).toDouble();
    final advance = (plan.payload['advanceFee'] as num? ?? 0).toDouble();
    if (fee < 0 || advance < 0 || fee + advance >= 100)
      throw ArgumentError('Taxas devem totalizar menos de 100%.');
    final amounts = financeInstallments(gross * (1 - (fee + advance) / 100),
        (plan.payload['count'] as num).toInt());
    final grossParts = financeInstallments(gross, amounts.length);
    final first = DateTime.parse(plan.payload['firstDate'] as String);
    final now = DateTime.now();
    for (var i = 0; i < amounts.length; i++) {
      await generateTransaction(
          reference: 'card:${plan.id}:$i',
          transaction: FinancialModel(
            description: '${plan.title} — ${i + 1}/${amounts.length}',
            amount: amounts[i],
            type: 'receber',
            dueDate: financeAddMonths(first, i),
            customerName: plan.payload['customer'] as String?,
            categoria: 'vendas',
            formaPagamento: 'Crédito',
            parcela: i + 1,
            totalParcelas: amounts.length,
            valorBruto: grossParts[i],
            taxa: fee + advance,
            valorLiquido: amounts[i],
            createdAt: now,
            updatedAt: now,
          ));
    }
    await records.save(plan.copyWith(status: 'gerado'));
    await audit('Geração de recebíveis de cartão', 'card_plan',
        targetId: plan.id, details: plan.title);
    return amounts.length;
  }
}
