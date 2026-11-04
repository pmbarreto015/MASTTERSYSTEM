import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/core/database/supabase_database.dart';

void main() {
  group('SupabaseDatabase', () {
    test('converte query sqflite em filtros estruturados', () async {
      late String rpcName;
      late Map<String, Object?> rpcParams;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          rpcName = name;
          rpcParams = params;
          return [
            {'id': 7, 'number': '0007'},
          ];
        },
      );

      final rows = await database.query(
        'orders',
        columns: ['id', 'number'],
        where: 'tipo = ? AND status IN (?, ?, ?) OR total > 0',
        whereArgs: ['OS', 'novo', 'producao', 'pronto'],
        orderBy: 'number COLLATE NOCASE DESC',
        limit: 25,
      );

      expect(rows.single['number'], '0007');
      expect(rpcName, 'matterdi_data');
      final payload = rpcParams['payload']! as Map;
      expect(payload['operation'], 'query');
      expect(payload['table'], 'orders');
      expect(payload['columns'], ['id', 'number']);
      expect(payload['limit'], 25);
      expect(payload['filters'], [
        {
          'connector': 'and',
          'column': 'tipo',
          'operator': 'eq',
          'value': 'OS',
        },
        {
          'connector': 'and',
          'column': 'status',
          'operator': 'in',
          'values': ['novo', 'producao', 'pronto'],
        },
        {
          'connector': 'or',
          'column': 'total',
          'operator': 'gt',
          'value': 0,
        },
      ]);
      expect(payload['order'], [
        {
          'column': 'number',
          'direction': 'desc',
          'nocase': true,
        },
      ]);
      expect(rpcParams.toString(), isNot(contains('SELECT')));
    });

    test('query sem limite consulta todas as páginas além de 10000 linhas',
        () async {
      final source = List<Map<String, Object?>>.generate(
        10237,
        (index) => {'id': index + 1, 'nome': 'Produto ${index + 1}'},
      );
      final payloads = <Map<String, Object?>>[];
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          expect(name, 'matterdi_data');
          final payload = Map<String, Object?>.from(params['payload']! as Map);
          payloads.add(payload);
          final offset = payload['offset']! as int;
          final limit = payload['limit']! as int;
          return source.skip(offset).take(limit).toList();
        },
      );

      final rows = await database.query('products');

      expect(rows.length, source.length);
      expect(rows.map((row) => row['id']),
          orderedEquals(source.map((row) => row['id'])));
      expect(payloads.map((payload) => payload['offset']),
          orderedEquals(List.generate(11, (index) => index * 1000)));
      for (final payload in payloads) {
        expect(payload['limit'], 1000);
        expect(payload['order'], [
          {'column': 'id', 'direction': 'asc'},
        ]);
      }
    });

    test('paginação mantém o offset inicial e desempata a ordenação', () async {
      final source = List<Map<String, Object?>>.generate(
        1600,
        (index) => {'id': index + 1, 'nome': 'Mesmo nome'},
      );
      final payloads = <Map<String, Object?>>[];
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          final payload = Map<String, Object?>.from(params['payload']! as Map);
          payloads.add(payload);
          return source
              .skip(payload['offset']! as int)
              .take(payload['limit']! as int)
              .toList();
        },
      );

      final rows = await database.query(
        'products',
        orderBy: 'nome COLLATE NOCASE DESC',
        offset: 137,
      );

      expect(rows.map((row) => row['id']),
          orderedEquals(source.skip(137).map((row) => row['id'])));
      expect(payloads.map((payload) => payload['offset']), [137, 1137]);
      expect(payloads.first['order'], [
        {'column': 'nome', 'direction': 'desc', 'nocase': true},
        {'column': 'id', 'direction': 'asc'},
      ]);
    });

    test('limite explícito mantém uma chamada e o offset solicitado', () async {
      var calls = 0;
      late Map payload;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          calls++;
          payload = params['payload']! as Map;
          return [
            {'id': 501},
          ];
        },
      );

      final rows = await database.query('products', limit: 25, offset: 500);

      expect(rows.single['id'], 501);
      expect(calls, 1);
      expect(payload['limit'], 25);
      expect(payload['offset'], 500);
      expect(payload['order'], isEmpty);
    });

    test('falha em página posterior não devolve resultado parcial', () async {
      var calls = 0;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          calls++;
          if (calls == 2) throw StateError('conexão interrompida');
          return List.generate(1000, (index) => {'id': index + 1});
        },
      );

      await expectLater(database.query('products'), throwsStateError);
      expect(calls, 2);
    });

    test('DISTINCT usa apenas a projeção como desempate das páginas', () async {
      late Map payload;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          payload = params['payload']! as Map;
          return [
            {'nome': 'A'},
            {'nome': 'B'},
          ];
        },
      );

      await database.query('products', distinct: true, columns: ['nome']);

      expect(payload['order'], [
        {'column': 'nome', 'direction': 'asc'},
      ]);
    });

    test('lote exige limite explícito para não truncar leitura silenciosamente',
        () async {
      var calls = 0;
      late Map payload;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          calls++;
          expect(name, 'matterdi_batch');
          payload =
              ((params['operations']! as List).single as Map)['payload'] as Map;
          return [<Object?>[]];
        },
      );
      final batch = database.batch();

      expect(() => batch.query('products'), throwsUnsupportedError);
      expect(batch.length, 0);
      expect(calls, 0);
      batch.query('products', limit: 20, offset: 10);
      await batch.commit();

      expect(calls, 1);
      expect(payload['limit'], 20);
      expect(payload['offset'], 10);
    });

    test('mapeia relatório conhecido sem enviar SQL', () async {
      late Map<String, Object?> rpcParams;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          expect(name, 'matterdi_report');
          rpcParams = params;
          return [
            {'total': 3},
          ];
        },
      );

      final rows = await database.rawQuery(
        'SELECT COUNT(*) as total FROM composicoes',
      );

      expect(rows.single['total'], 3);
      expect(rpcParams, {
        'report_name': 'composicoes_count',
        'arguments': <Object?>[],
      });
    });

    test('consulta de itens aceita lista dinâmica de ids', () async {
      late Map<String, Object?> rpcParams;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          rpcParams = params;
          return <Object?>[];
        },
      );

      await database.rawQuery('''
        SELECT oi.*, p.nome AS produto_nome
        FROM order_items oi
        LEFT JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id IN (?, ?, ?)
      ''', [2, 5, 9]);

      expect(rpcParams['report_name'], 'order_items_for_orders');
      expect(rpcParams['arguments'], [2, 5, 9]);
    });

    test('bloqueia tabela, filtro, ordenação e SQL desconhecidos', () async {
      var calls = 0;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          calls++;
          return <Object?>[];
        },
      );

      expect(
        () => database.query('pg_user'),
        throwsArgumentError,
      );
      expect(
        () => database.query(
          'products',
          where: 'id = ?; DROP TABLE products',
          whereArgs: [1],
        ),
        throwsArgumentError,
      );
      expect(
        () => database.query('products', orderBy: 'nome; DELETE'),
        throwsArgumentError,
      );
      expect(
        () => database.rawQuery('SELECT password FROM auth.users'),
        throwsUnsupportedError,
      );
      expect(calls, 0);
    });

    test('aceita todos os formatos de filtro usados pelos repositórios',
        () async {
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async => <Object?>[],
      );
      final cases = <(String, List<Object?>)>[
        ('deleted_at IS NULL', const []),
        ('id = ? AND deleted_at IS NULL', const [1]),
        ('name LIKE ? AND deleted_at IS NULL', const ['%a%']),
        ('total_purchases > 3000 AND deleted_at IS NULL', const []),
        ('LOWER(username) = LOWER(?) AND active = 1', const ['a@b.com']),
        (
          'name LIKE ? OR product LIKE ? OR document LIKE ?',
          const ['%a%', '%a%', '%a%']
        ),
        ('created_at BETWEEN ? AND ?', const ['2026-01-01', '2026-12-31']),
        (
          'area >= ? AND status = ? AND material_id = ?',
          const [1.5, 'disponivel', 3]
        ),
        ('quantidade_estoque <= estoque_minimo AND active = 1', const []),
        ('employee_id = ? AND date(data) = date(?)', const [4, '2026-10-06']),
        (
          'tipo = ? AND status IN (?, ?, ?, ?)',
          const ['OS', 'a', 'b', 'c', 'd']
        ),
      ];

      for (final (where, arguments) in cases) {
        await database.query(
          'orders',
          where: where,
          whereArgs: arguments,
        );
      }
      await database.query(
        'agenda_followups',
        orderBy:
            "CASE WHEN status = 'concluido' THEN 1 ELSE 0 END, agendado_para ASC",
      );
    });

    test('gravações simples usam matterdi_data', () async {
      final payloads = <Map>[];
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          expect(name, 'matterdi_data');
          final payload = params['payload']! as Map;
          payloads.add(payload);
          return switch (payload['operation']) {
            'insert' => 12,
            'update' => 1,
            'delete' => 1,
            _ => throw StateError('operação inesperada'),
          };
        },
      );

      expect(
        await database.insert('customers', {
          'name': 'Cliente',
          'created_at': '2026-10-06T00:00:00',
          'updated_at': '2026-10-06T00:00:00',
        }),
        12,
      );
      expect(
        await database.update(
          'customers',
          {'name': 'Novo nome'},
          where: 'id = ?',
          whereArgs: [12],
        ),
        1,
      );
      expect(
        await database.delete('customers', where: 'id = ?', whereArgs: [12]),
        1,
      );

      expect(payloads.map((item) => item['operation']), [
        'insert',
        'update',
        'delete',
      ]);
      expect(payloads[1]['filters'], [
        {
          'connector': 'and',
          'column': 'id',
          'operator': 'eq',
          'value': 12,
        },
      ]);
    });

    test('batch é enviado em uma única RPC e não reutiliza o objeto', () async {
      var calls = 0;
      late Map<String, Object?> rpcParams;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async {
          calls++;
          expect(name, 'matterdi_batch');
          rpcParams = params;
          return [31, 32];
        },
      );
      final batch = database.batch()
        ..insert('products', {'nome': 'A'})
        ..insert('products', {'nome': 'B'});

      expect(await batch.commit(), [31, 32]);
      expect(calls, 1);
      expect((rpcParams['operations']! as List).length, 2);
      expect(() => batch.commit(), throwsStateError);
    });

    test('callback transaction falha antes de executar a callback', () {
      var callbackCalled = false;
      final database = SupabaseDatabase.forTesting(
        rpcCall: (name, params, {requireSession = true}) async => null,
      );

      expect(
        () => database.transaction((transaction) async {
          callbackCalled = true;
        }),
        throwsUnsupportedError,
      );
      expect(callbackCalled, isFalse);
    });
  });
}
