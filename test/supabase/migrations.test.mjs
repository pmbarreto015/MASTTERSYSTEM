import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const workspace = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);
const migrations = [
  '20261003000000_initial_schema.sql',
  '20261006000000_auth_permissions.sql',
  '20261006010000_data_api.sql',
  '20261006020000_business_rpc.sql',
    '20261009000000_accepted_sales.sql',
];
const now = '2026-10-06T12:00:00.000Z';

async function scalar(db, sql, params = []) {
  const result = await db.query(sql, params);
  return Object.values(result.rows[0])[0];
}

async function session(db, role, userId, action) {
  await db.exec('RESET ROLE');
  await db.query(
    "SELECT set_config('request.jwt.claim.sub', $1, false)",
    [userId ?? ''],
  );
  await db.exec(`SET ROLE ${role}`);
  try {
    return await action();
  } finally {
    await db.exec('RESET ROLE');
    await db.query(
      "SELECT set_config('request.jwt.claim.sub', '', false)",
    );
  }
}

async function expectFailure(action, pattern) {
  let error;
  try {
    await action();
  } catch (caught) {
    error = caught;
  }
  assert.ok(error, 'a operação deveria falhar');
  if (pattern) assert.match(String(error.message ?? error), pattern);
}

function orderPayload(number, overrides = {}) {
  return {
    number,
    tipo: 'OS',
    cliente_nome: 'Cliente Teste',
    customer_id: 1,
    seller_id: null,
    total: 100,
    discount: 0,
    entrada: 0,
    parcelas: '',
    parcelas_datas: '',
    valor_manual: 0,
    prioridade: 'normal',
    payment_method: 'Boleto',
    status: 'aguardando_pagamento',
    observations: '',
    delivery_date: '2026-10-20T12:00:00.000Z',
    created_at: now,
    updated_at: now,
    ...overrides,
  };
}

function financialPayload(overrides = {}) {
  return {
    description: 'Pedido de teste',
    amount: 100,
    type: 'receber',
    due_date: '2026-10-20T12:00:00.000Z',
    is_paid: 0,
    notes: 'Teste',
    order_id: null,
    customer_id: 1,
    customer_name: 'Cliente Teste',
    categoria: 'vendas',
    forma_pagamento: 'Boleto',
    parcela: 0,
    total_parcelas: 0,
    valor_bruto: 0,
    taxa: 0,
    valor_liquido: 0,
    status: 'pendente',
    pagamentos: '',
    created_at: now,
    updated_at: now,
    ...overrides,
  };
}

test('migrações Supabase e RPCs transacionais', async (t) => {
  const db = new PGlite();
  await db.waitReady;
  t.after(async () => db.close());

  await db.exec(`
    CREATE ROLE anon NOLOGIN;
    CREATE ROLE authenticated NOLOGIN;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE OR REPLACE FUNCTION auth.uid()
    RETURNS UUID
    LANGUAGE sql
    STABLE
    SET search_path = ''
    AS $$
      SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID;
    $$;
    GRANT USAGE ON SCHEMA auth TO anon, authenticated;
    GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;
  `);

  for (const migration of migrations) {
    const sql = await readFile(
      path.join(workspace, 'supabase', 'migrations', migration),
      'utf8',
    );
    await t.test(`aplica ${migration}`, async () => {
      await db.exec(sql);
    });
  }

  const userId = '11111111-1111-4111-8111-111111111111';
  const noPermissionId = '22222222-2222-4222-8222-222222222222';
  const permissions = [
    'agenda',
    'clientes',
    'produtos',
    'vendas',
    'pedidos_alterar',
    'pedidos_excluir',
    'orcamentos',
    'producao',
    'estoque',
    'financeiro',
    'funcionarios',
    'corte_compositor',
  ];
  await db.query(
    'INSERT INTO auth.users(id) VALUES ($1::uuid), ($2::uuid)',
    [userId, noPermissionId],
  );
  await db.query(
    `INSERT INTO public.system_users
      (username, full_name, email, auth_user_id, is_admin, active,
       permissions, created_at, updated_at)
     VALUES
      ('tester', 'Usuário Teste', 'tester@example.test', $1::uuid, 0, 1,
       $2, $3, $3),
      ('limited', 'Usuário Limitado', 'limited@example.test', $4::uuid, 0, 1,
       '[]', $3, $3)`,
    [userId, JSON.stringify(permissions), now, noPermissionId],
  );
  await db.query(
    `INSERT INTO public.customers
      (id, uuid, name, created_at, updated_at)
     VALUES (1, 'cus_test', 'Cliente Teste', $1, $1)`,
    [now],
  );
  await db.query(
    `INSERT INTO public.products
      (id, codigo, nome, categoria, preco, cost, estoque, unidade, ativo,
       created_at, updated_at)
     VALUES (1, 'P-001', 'Produto Teste', 'grafica', 100, 50, 10, 'un', 1,
             $1, $1)`,
    [now],
  );

  await db.query(
    "SELECT setval(pg_get_serial_sequence('public.customers', 'id'), " +
    "(SELECT MAX(id) FROM public.customers))",
  );

  await t.test('anon e usuário sem permissão não executam RPCs privadas', async () => {
    await expectFailure(
      () => session(db, 'anon', null, () =>
        db.query('SELECT public.matterdi_order_delete(1::BIGINT)')),
      /permission denied|permissão/i,
    );
    await expectFailure(
      () => session(db, 'authenticated', noPermissionId, () =>
        db.query('SELECT public.matterdi_order_delete(1::BIGINT)')),
      /sem permissão/i,
    );
    await expectFailure(
      () => session(db, 'anon', null, () =>
        db.query('SELECT * FROM public.customers')),
      /permission denied/i,
    );
  });

  await t.test('RLS respeita perfil ativo, permissão do módulo e administrador', async () => {
    const inactiveId = '33333333-3333-4333-8333-333333333333';
    const customersId = '44444444-4444-4444-8444-444444444444';
    const adminId = '55555555-5555-4555-8555-555555555555';
    await db.query(
      'INSERT INTO auth.users(id) VALUES ($1::uuid), ($2::uuid), ($3::uuid)',
      [inactiveId, customersId, adminId],
    );
    await db.query(
      `INSERT INTO public.system_users
        (username, full_name, email, auth_user_id, is_admin, active,
         permissions, created_at, updated_at)
       VALUES
        ('inactive', 'Inativo', '', $1::uuid, 0, 0, '["clientes"]', $4, $4),
        ('customers', 'Clientes', '', $2::uuid, 0, 1, '["clientes"]', $4, $4),
        ('admin-test', 'Administrador', '', $3::uuid, 1, 1, '[]', $4, $4)`,
      [inactiveId, customersId, adminId, now],
    );

    const inactiveRows = await session(db, 'authenticated', inactiveId, () =>
      db.query('SELECT id FROM public.customers'));
    assert.equal(inactiveRows.rows.length, 0);

    const customerRows = await session(db, 'authenticated', customersId, () =>
      db.query('SELECT id FROM public.customers'));
    assert.ok(customerRows.rows.length > 0);
    const financialRows = await session(db, 'authenticated', customersId, () =>
      db.query('SELECT id FROM public.financial'));
    assert.equal(financialRows.rows.length, 0);

    const adminPermission = await session(db, 'authenticated', adminId, () =>
      scalar(db, "SELECT public.matterdi_has_permission('qualquer')"));
    assert.equal(adminPermission, true);
  });

  await t.test('Data API faz CRUD e relatório sem aceitar identificadores injetados', async () => {
    const insertPayload = {
      operation: 'insert',
      table: 'customers',
      values: {
        uuid: 'cus_data_api',
        name: 'Cliente Data API',
        document: '',
        phone: '',
        email: '',
        address: '',
        observations: '',
        total_purchases: 0,
        created_at: now,
        updated_at: now,
      },
    };
    const inserted = await session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_data($1::JSONB) AS value',
      [JSON.stringify(insertPayload)],
    ));
    const customerId = Number(inserted.rows[0].value);
    assert.ok(customerId > 1);

    const queryPayload = {
      operation: 'query',
      table: 'customers',
      columns: ['id', 'name'],
      filters: [{ connector: 'and', column: 'id', operator: 'eq', value: customerId }],
      order: [{ column: 'name', direction: 'asc', nocase: true }],
      limit: 10,
      offset: 0,
    };
    const queried = await session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_data($1::JSONB) AS value',
      [JSON.stringify(queryPayload)],
    ));
    assert.equal(queried.rows[0].value[0].name, 'Cliente Data API');

    const updatePayload = {
      operation: 'update',
      table: 'customers',
      values: { name: 'Cliente Atualizado', updated_at: now },
      filters: [{ connector: 'and', column: 'id', operator: 'eq', value: customerId }],
    };
    const updated = await session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_data($1::JSONB) AS value',
      [JSON.stringify(updatePayload)],
    ));
    assert.equal(Number(updated.rows[0].value), 1);

    const report = await session(db, 'authenticated', userId, () => db.query(
      "SELECT public.matterdi_report('stock_summary', '[]'::JSONB) AS value",
    ));
    assert.equal(Number(report.rows[0].value[0].total_produtos), 1);

    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        'SELECT public.matterdi_data($1::JSONB)',
        [JSON.stringify({ ...queryPayload, table: 'customers; DROP TABLE public.customers' })],
      )),
      /tabela não permitida/i,
    );
    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        'SELECT public.matterdi_data($1::JSONB)',
        [JSON.stringify({ ...queryPayload, columns: ['name) FROM public.system_users --'] })],
      )),
      /coluna não permitida/i,
    );
    await expectFailure(
      () => session(db, 'anon', null, () => db.query(
        'SELECT public.matterdi_data($1::JSONB)',
        [JSON.stringify(queryPayload)],
      )),
      /permission denied/i,
    );

    const deleted = await session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_data($1::JSONB) AS value',
      [JSON.stringify({
        operation: 'delete',
        table: 'customers',
        filters: [{ connector: 'and', column: 'id', operator: 'eq', value: customerId }],
      })],
    ));
    assert.equal(Number(deleted.rows[0].value), 1);
  });

  let orderId;
  await t.test('pedido, itens e financeiro são gravados juntos', async () => {
    const result = await session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_order_create(
        $1::JSONB, $2::JSONB, $3::JSONB
      ) AS id`,
      [
        JSON.stringify(orderPayload('PED-ATOMIC-1')),
        JSON.stringify([{
          product_id: 1,
          quantity: 1,
          unit_price: 100,
          subtotal: 100,
          specifications: '',
          largura: 0,
          altura: 0,
          custo_unitario: 50,
          detalhes_custo: '',
          terceirizado: 0,
        }]),
        JSON.stringify([financialPayload()]),
      ],
    ));
    orderId = Number(result.rows[0].id);
    assert.ok(orderId > 0);
    assert.equal(Number(await scalar(db,
      'SELECT count(*) FROM public.order_items WHERE order_id = $1',
      [orderId])), 1);
    assert.equal(Number(await scalar(db,
      'SELECT count(*) FROM public.financial WHERE order_id = $1',
      [orderId])), 1);

    const before = Number(await scalar(db, 'SELECT count(*) FROM public.orders'));
    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        `SELECT public.matterdi_order_create(
          $1::JSONB, $2::JSONB, $3::JSONB
        )`,
        [
          JSON.stringify(orderPayload('PED-ROLLBACK')),
          JSON.stringify([{
            product_id: 999999,
            quantity: 1,
            unit_price: 100,
            subtotal: 100,
          }]),
          JSON.stringify([financialPayload()]),
        ],
      )),
      /foreign key|violates/i,
    );
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.orders')), before);
  });

  await t.test('aprovação de orçamento é idempotente e não duplica financeiro', async () => {
    const created = await session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_order_create($1::JSONB, $2::JSONB, $3::JSONB) AS id',
      [
        JSON.stringify(orderPayload('ORC-ATOMIC-1', {
          tipo: 'ORCAMENTO',
          status: 'aguardando_pagamento',
        })),
        JSON.stringify([{
          product_id: 1,
          quantity: 1,
          unit_price: 100,
          subtotal: 100,
        }]),
        '[]',
      ],
    ));
    const quoteId = Number(created.rows[0].id);
    const approved = orderPayload('ORC-ATOMIC-1', {
      tipo: 'OS',
      status: 'pagamento_recebido',
    });
    const approve = () => session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_order_approve($1::BIGINT, $2::JSONB, $3::JSONB)',
      [quoteId, JSON.stringify(approved), JSON.stringify([financialPayload()])],
    ));
    await approve();
    await expectFailure(approve, /já foi processado/i);
    assert.equal(Number(await scalar(db,
      'SELECT count(*) FROM public.financial WHERE order_id = $1',
      [quoteId])), 1);
  });

  await t.test('movimentação de estoque reverte atualização quando o saldo é insuficiente', async () => {
    const move = (quantity) => session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_stock_move(
        1::BIGINT, $1::DOUBLE PRECISION, 'venda', 'Teste',
        NULL::BIGINT, $2::BIGINT, NULL::BIGINT, $3::TEXT
      )`,
      [quantity, orderId, now],
    ));
    await move(3);
    assert.equal(Number(await scalar(db,
      'SELECT estoque FROM public.products WHERE id = 1')), 7);
    const movements = Number(await scalar(db,
      'SELECT count(*) FROM public.stock_movements WHERE product_id = 1'));
    await expectFailure(() => move(100), /estoque insuficiente/i);
    assert.equal(Number(await scalar(db,
      'SELECT estoque FROM public.products WHERE id = 1')), 7);
    assert.equal(Number(await scalar(db,
      'SELECT count(*) FROM public.stock_movements WHERE product_id = 1')),
    movements);
  });

  await t.test('pagamento parcial bloqueia valor maior sem criar histórico', async () => {
    const financialId = Number(await scalar(db,
      'SELECT id FROM public.financial WHERE order_id = $1 ORDER BY id LIMIT 1',
      [orderId]));
    await session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_financial_partial(
        $1::BIGINT, 30::DOUBLE PRECISION, $2::TEXT
      )`,
      [financialId, now],
    ));
    assert.equal(Number(await scalar(db,
      'SELECT amount FROM public.financial WHERE id = $1',
      [financialId])), 70);
    const count = Number(await scalar(db, 'SELECT count(*) FROM public.financial'));
    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        `SELECT public.matterdi_financial_partial(
          $1::BIGINT, 100::DOUBLE PRECISION, $2::TEXT
        )`,
        [financialId, now],
      )),
      /maior que o saldo/i,
    );
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.financial')), count);
  });

  await t.test('exclusão em lote de produtos reverte o lote inteiro', async () => {
    await db.query(
      `INSERT INTO public.products
        (id, codigo, nome, categoria, preco, created_at, updated_at)
       VALUES (2, 'P-002', 'Produto Livre', 'grafica', 10, $1, $1)`,
      [now],
    );
    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        'SELECT public.matterdi_product_delete_many($1::JSONB)',
        [JSON.stringify([1, 2])],
      )),
      /foreign key|violates/i,
    );
    assert.equal(Number(await scalar(db,
      'SELECT count(*) FROM public.products WHERE id IN (1, 2)')), 2);
  });

  await t.test('agenda recorrente cria somente uma próxima ocorrência', async () => {
    const agendaId = Number(await scalar(db,
      `INSERT INTO public.agenda_followups
        (cliente_nome, telefone, assunto, observacoes, status, periodicidade,
         agendado_para, created_at, updated_at)
       VALUES ('Cliente Teste', '', 'Retorno', '', 'responder', 'semanal',
               $1, $2, $2)
       RETURNING id`,
      ['2026-10-07T12:00:00.000Z', now]));
    const completed = {
      cliente_nome: 'Cliente Teste',
      telefone: '',
      assunto: 'Retorno',
      observacoes: '',
      status: 'concluido',
      periodicidade: 'semanal',
      agendado_para: '2026-10-07T12:00:00.000Z',
      concluido_em: now,
      updated_at: now,
    };
    const next = {
      cliente_nome: 'Cliente Teste',
      telefone: '',
      assunto: 'Retorno',
      observacoes: '',
      status: 'responder',
      periodicidade: 'semanal',
      agendado_para: '2026-10-14T12:00:00.000Z',
      concluido_em: null,
      created_at: now,
      updated_at: now,
    };
    const complete = () => session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_agenda_complete_next(
        $1::BIGINT, $2::JSONB, $3::JSONB
      )`,
      [agendaId, JSON.stringify(completed), JSON.stringify(next)],
    ));
    await complete();
    await complete();
    assert.equal(Number(await scalar(db,
      "SELECT count(*) FROM public.agenda_followups WHERE assunto = 'Retorno'")), 2);
  });

  await t.test('composição grava cabeçalho e itens na mesma transação', async () => {
    const header = {
      pedido_id: null,
      orcamento_id: null,
      produto_id: null,
      custo_total_materiais: 10,
      custo_total_maquinas: 0,
      custo_total_servicos: 0,
      custo_total: 10,
      margem_lucro: 50,
      preco_venda: 15,
      observacoes: '',
      created_at: now,
      updated_at: now,
    };
    const before = Number(await scalar(db, 'SELECT count(*) FROM public.composicoes'));
    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        'SELECT public.matterdi_composition_save(NULL::BIGINT, $1::JSONB, $2::JSONB)',
        [JSON.stringify(header), JSON.stringify([{ tipo: 'invalido' }])],
      )),
      /tipo de item/i,
    );
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.composicoes')), before);

    const result = await session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_composition_save(
        NULL::BIGINT, $1::JSONB, $2::JSONB
      ) AS id`,
      [JSON.stringify(header), JSON.stringify([{
        tipo: 'material',
        descricao: 'Material Teste',
        quantidade: 1,
        unidade: 'un',
        valor_unitario: 10,
        valor_total: 10,
        observacoes: '',
        item_id: null,
        item_original_id: null,
        created_at: now,
      }])],
    ));
    const compositionId = Number(result.rows[0].id);
    assert.equal(Number(await scalar(db,
      'SELECT count(*) FROM public.composicao_itens WHERE composicao_id = $1',
      [compositionId])), 1);
  });

  await t.test('orçamento e aceite preservam histórico e recebimentos', async () => {
    const draft = orderPayload('TEST-ACCEPTED-SALES', { tipo: 'ORCAMENTO', status: 'aguardando_pagamento' });
    const items = [{ product_id: 1, quantity: 1, unit_price: 100, subtotal: 100, specifications: '' }];
    const finance = { description: 'Venda aceita', amount: 100, type: 'receber', due_date: now, is_paid: 0,
      customer_id: 1, customer_name: 'Cliente Teste', categoria: 'vendas', forma_pagamento: 'Boleto',
      status: 'pendente', created_at: now, updated_at: now };
    const id = Number(await session(db, 'authenticated', userId, () => scalar(db,
      "SELECT public.matterdi_order_create($1::JSONB,$2::JSONB,$3::JSONB)",
      [JSON.stringify(draft), JSON.stringify(items), JSON.stringify([finance])])));
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.financial WHERE order_id=$1', [id])), 0);
    await expectFailure(() => db.query("INSERT INTO public.financial(description,amount,type,due_date,order_id,created_at,updated_at) VALUES('Indevido',100,'receber',$1,$2,$1,$1)", [now, id]), /Orçamento precisa/i);
    const accepted = { ...draft, tipo: 'OS' };
    const update = (order) => session(db, 'authenticated', userId, () => db.query(
      'SELECT public.matterdi_order_update($1::BIGINT,$2::JSONB,$3::JSONB,$4::JSONB)',
      [id, JSON.stringify(order), JSON.stringify(items), JSON.stringify([finance])]));
    await update(accepted);
    assert.equal(Number(await scalar(db, "SELECT count(*) FROM public.financial WHERE order_id=$1 AND status<>'cancelado'", [id])), 1);
    await update(draft);
    assert.equal(await scalar(db, 'SELECT tipo FROM public.orders WHERE id=$1', [id]), 'ORCAMENTO');
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.financial WHERE order_id=$1', [id])), 1);
    assert.equal(await scalar(db, 'SELECT status FROM public.financial WHERE order_id=$1', [id]), 'cancelado');
    await update(accepted);
    assert.equal(Number(await scalar(db, "SELECT count(*) FROM public.financial WHERE order_id=$1 AND status<>'cancelado'", [id])), 1);
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.financial WHERE order_id=$1', [id])), 2);
    await db.query("UPDATE public.financial SET is_paid=1,status='pago' WHERE order_id=$1 AND status<>'cancelado'", [id]);
    await expectFailure(() => update(draft), /possui recebimentos/i);
    assert.equal(await scalar(db, 'SELECT tipo FROM public.orders WHERE id=$1', [id]), 'OS');
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.financial WHERE order_id=$1 AND is_paid=1', [id])), 1);
  });

  await t.test('holerite e lançamento financeiro são atômicos', async () => {
    await db.query(
      `INSERT INTO public.employees
        (id, name, position, hire_date, created_at, updated_at)
       VALUES (1, 'Funcionário Teste', 'Operador', '2026-01-01', $1, $1)`,
      [now],
    );
    const row = {
      employee_id: 1,
      employee_name: 'Funcionário Teste',
      mes_referencia: '2026-10',
      salario_base: 2000,
      horas_trabalhadas: 160,
      horas_extras: 0,
      valor_hora: 12.5,
      valor_hora_extra: 0,
      total_horas_extras: 0,
      salario_bruto: 2000,
      descontos: 200,
      vale_transporte: 0,
      vale_alimentacao: 0,
      insalubridade: 0,
      periculosidade: 0,
      comissao: 0,
      outros: 0,
      inss: 200,
      irrf: 0,
      salario_liquido: 1800,
      observacoes: '',
      pago: 0,
      created_at: now,
      updated_at: now,
    };
    const payment = financialPayload({
      description: 'Salário Outubro/2026 - Funcionário Teste',
      amount: 1800,
      type: 'pagar',
      customer_id: null,
      customer_name: null,
      categoria: 'pessoal',
      forma_pagamento: 'Transferência',
      notes: 'Holerite gerado automaticamente - 2026-10',
    });
    const result = await session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_holerite_save(
        NULL::BIGINT, $1::JSONB, $2::JSONB
      ) AS id`,
      [JSON.stringify(row), JSON.stringify(payment)],
    ));
    const holeriteId = Number(result.rows[0].id);
    assert.equal(Number(await scalar(db,
      "SELECT count(*) FROM public.financial WHERE notes = 'Holerite gerado automaticamente - 2026-10'")), 1);

    await session(db, 'authenticated', userId, () => db.query(
      `SELECT public.matterdi_holerite_save(
        $1::BIGINT, $2::JSONB, NULL::JSONB
      )`,
      [holeriteId, JSON.stringify({ pago: 1, updated_at: now })],
    ));
    assert.equal(Number(await scalar(db,
      "SELECT is_paid FROM public.financial WHERE notes = 'Holerite gerado automaticamente - 2026-10'")), 1);

    const before = Number(await scalar(db, 'SELECT count(*) FROM public.holerites'));
    await expectFailure(
      () => session(db, 'authenticated', userId, () => db.query(
        `SELECT public.matterdi_holerite_save(
          NULL::BIGINT, $1::JSONB, $2::JSONB
        )`,
        [
          JSON.stringify({ ...row, mes_referencia: '2026-11' }),
          JSON.stringify({ ...payment, description: null }),
        ],
      )),
      /null value|not-null/i,
    );
    assert.equal(Number(await scalar(db, 'SELECT count(*) FROM public.holerites')), before);
  });
});
