import '../models/holerite_model.dart';
import '../models/financial_model.dart';
import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';
import 'financial_repository.dart';

class HoleriteRepository {
  final AppDatabase _db = AppDatabase();
  final FinancialRepository _financialRepo = FinancialRepository();

  // CRIAR HOLERITE COM INTEGRAÇÃO FINANCEIRA
  Future<HoleriteModel> create(HoleriteModel holerite) async {
    final database = await _db.database;
    final map = holerite.toMap();
    map.remove('id');
    if (database is SupabaseDatabase) {
      final financial = holerite.salarioLiquido > 0
          ? (_financialForHolerite(holerite).toMap()..remove('id'))
          : null;
      final id = await database.rpc('matterdi_holerite_save', {
        'p_id': null,
        'p_row': map,
        'p_financial': financial,
      });
      return holerite.copyWith(id: (id as num).toInt());
    }
    final id = await database.insert('holerites', map);
    final created = await getById(id);

    // LANÇAR NO FINANCEIRO (Contas a Pagar)
    if (created != null && created.salarioLiquido > 0) {
      await _lancarNoFinanceiro(created);
    }

    return created!;
  }

  // LANÇAR HOLERITE NO FINANCEIRO
  Future<void> _lancarNoFinanceiro(HoleriteModel holerite) async {
    try {
      // Buscar funcionário para obter o nome completo
      final database = await _db.database;
      final employeeResult = await database.query(
        'employees',
        where: 'id = ?',
        whereArgs: [holerite.employeeId],
      );

      String employeeName = holerite.employeeName;
      if (employeeResult.isNotEmpty) {
        // CORREÇÃO: Converter para String com segurança
        final name = employeeResult.first['name'];
        if (name != null) {
          employeeName = name.toString();
        }
      }

      // Criar lançamento financeiro
      final financial = FinancialModel(
        description:
            'Salário ${holerite.mesReferenciaFormatada} - $employeeName',
        amount: holerite.salarioLiquido,
        type: 'pagar',
        dueDate: DateTime.now().add(const Duration(days: 5)),
        isPaid: holerite.pago,
        notes: 'Holerite gerado automaticamente - ${holerite.mesReferencia}',
        categoria: 'pessoal',
        formaPagamento: 'Transferência',
        status: holerite.pago ? 'pago' : 'pendente',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _financialRepo.create(financial);
      print(
          'Lançamento financeiro criado para $employeeName - R\$ ${holerite.salarioLiquido}');
    } catch (e) {
      print('Erro ao lançar holerite no financeiro: $e');
    }
  }

  FinancialModel _financialForHolerite(HoleriteModel holerite) {
    final now = DateTime.now();
    return FinancialModel(
      description:
          'Salário ${holerite.mesReferenciaFormatada} - ${holerite.employeeName}',
      amount: holerite.salarioLiquido,
      type: 'pagar',
      dueDate: now.add(const Duration(days: 5)),
      isPaid: holerite.pago,
      notes: 'Holerite gerado automaticamente - ${holerite.mesReferencia}',
      categoria: 'pessoal',
      formaPagamento: 'Transferência',
      status: holerite.pago ? 'pago' : 'pendente',
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<HoleriteModel> update(HoleriteModel holerite) async {
    final database = await _db.database;
    final map = holerite.toMap();
    map.remove('id');
    map.remove('created_at');
    if (database is SupabaseDatabase) {
      if (holerite.id == null) {
        throw ArgumentError('Holerite sem identificador.');
      }
      final id = await database.rpc('matterdi_holerite_save', {
        'p_id': holerite.id,
        'p_row': map,
        'p_financial': null,
      });
      return holerite.copyWith(id: (id as num).toInt());
    }
    await database.update(
      'holerites',
      map,
      where: 'id = ?',
      whereArgs: [holerite.id],
    );
    final updated = await getById(holerite.id!);

    // Se o holerite foi marcado como pago, atualizar o financeiro
    if (updated != null && updated.pago) {
      await _atualizarFinanceiro(updated);
    }

    return updated!;
  }

  // ATUALIZAR FINANCEIRO QUANDO HOLERITE É PAGO
  Future<void> _atualizarFinanceiro(HoleriteModel holerite) async {
    try {
      // Buscar o lançamento financeiro relacionado
      final database = await _db.database;
      final result = await database.query(
        'financial',
        where: 'description LIKE ? AND type = ?',
        whereArgs: ['%${holerite.employeeName}%', 'pagar'],
      );

      for (var row in result) {
        final financial = FinancialModel.fromMap(row);
        if (!financial.isPaid) {
          await _financialRepo.markAsPaid(financial.id!);
          print(
              'Lançamento financeiro marcado como pago para ${holerite.employeeName}');
        }
      }
    } catch (e) {
      print('Erro ao atualizar financeiro: $e');
    }
  }

  Future<HoleriteModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'holerites',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return HoleriteModel.fromMap(result.first);
  }

  Future<List<HoleriteModel>> getByEmployeeId(int employeeId) async {
    final database = await _db.database;
    final result = await database.query(
      'holerites',
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      orderBy: 'mes_referencia DESC',
    );
    return result.map((map) => HoleriteModel.fromMap(map)).toList();
  }

  Future<HoleriteModel?> getByEmployeeAndMonth(
      int employeeId, String mesReferencia) async {
    final database = await _db.database;
    final result = await database.query(
      'holerites',
      where: 'employee_id = ? AND mes_referencia = ?',
      whereArgs: [employeeId, mesReferencia],
    );
    if (result.isEmpty) return null;
    return HoleriteModel.fromMap(result.first);
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'holerites',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarPago(int id) async {
    final database = await _db.database;
    if (database is SupabaseDatabase) {
      await database.rpc('matterdi_holerite_save', {
        'p_id': id,
        'p_row': {
          'pago': 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        'p_financial': null,
      });
      return;
    }
    await database.update(
      'holerites',
      {
        'pago': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Atualizar financeiro
    final holerite = await getById(id);
    if (holerite != null) {
      await _atualizarFinanceiro(holerite);
    }
  }

  Future<Map<String, dynamic>> getResumoPeriodo(String mesReferencia) async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_funcionarios,
        SUM(salario_liquido) as total_pagar,
        COUNT(CASE WHEN pago = 1 THEN 1 END) as pagos,
        COUNT(CASE WHEN pago = 0 THEN 1 END) as pendentes
      FROM holerites
      WHERE mes_referencia = ?
    ''', [mesReferencia]);

    if (result.isEmpty) {
      return {
        'total_funcionarios': 0,
        'total_pagar': 0.0,
        'pagos': 0,
        'pendentes': 0,
      };
    }
    return result.first;
  }
}
