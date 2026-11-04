import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const workspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const now = '2026-10-24T12:00:00.000Z';
const ids = {
  hr: '11111111-1111-4111-8111-111111111111',
  finance: '22222222-2222-4222-8222-222222222222',
  delivery: '33333333-3333-4333-8333-333333333333',
  both: '44444444-4444-4444-8444-444444444444',
  inactive: '55555555-5555-4555-8555-555555555555',
  none: '66666666-6666-4666-8666-666666666666',
};

async function scalar(db, sql, params = []) {
  return Object.values((await db.query(sql, params)).rows[0])[0];
}

async function asUser(db, user, action, role = 'authenticated') {
  await db.exec('RESET ROLE');
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user ?? '']);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await action();
  } finally {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub', '', false)");
  }
}

function financial(recordId, overrides = {}) {
  return {
    description: 'Beneficio aprovado', amount: 200, type: 'pagar',
    due_date: '2026-10-28T00:00:00.000', is_paid: 0,
    notes: `[RH:${recordId}] Origem: RH/beneficios. Colaborador #1.`,
    order_id: null, customer_id: null, customer_name: null,
    categoria: 'pessoal', forma_pagamento: '', parcela: 0, total_parcelas: 0,
    valor_bruto: 0, taxa: 0, valor_liquido: 0,
    status: 'pendente', pagamentos: '', created_at: now, updated_at: now,
    ...overrides,
  };
}

test('expansao ERP v28: migracao, isolamento RLS e RPCs de dominio', async t => {
  const db = new PGlite();
  await db.waitReady;
  t.after(() => db.close());
  await db.exec(`
    CREATE ROLE anon NOLOGIN;
    CREATE ROLE authenticated NOLOGIN;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users(id UUID PRIMARY KEY);
    CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE SET search_path = ''
      AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID $$;
    GRANT USAGE ON SCHEMA auth TO anon, authenticated;
    GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;
  `);
  for (const migration of [
    '20261003000000_initial_schema.sql',
    '20261006000000_auth_permissions.sql',
    '20261006010000_data_api.sql',
    '20261006020000_business_rpc.sql',
    '20261009000000_accepted_sales.sql',
  ]) {
    await db.exec(await readFile(path.join(workspace, 'supabase', 'migrations', migration), 'utf8'));
  }
  const migration = await readFile(path.join(workspace, 'supabase', 'migrations', '20261024000000_erp_modules.sql'), 'utf8');
  await db.exec(migration);
  const permissions = {
    hr: ['funcionarios'], finance: ['financeiro'], delivery: ['entregas'],
    both: ['funcionarios', 'financeiro'], inactive: ['entregas', 'funcionarios', 'financeiro'], none: [],
  };
  for (const [name, user] of Object.entries(ids)) {
    await db.query('INSERT INTO auth.users VALUES ($1)', [user]);
    await db.query(`INSERT INTO public.system_users
      (username, full_name, email, auth_user_id, is_admin, active, permissions, created_at, updated_at)
      VALUES($1, $1, $2, $3, 0, $4, $5, $6, $6)`,
    [name, `${name}@example.test`, user, name === 'inactive' ? 0 : 1, JSON.stringify(permissions[name]), now]);
  }
  const insertRecord = async (module, recordType = 'teste', payload = {}, status = 'ativo') =>
    scalar(db, `INSERT INTO public.erp_module_records
      (module, record_type, title, status, payload, created_at, updated_at)
      VALUES($1,$2,'Registro',$3,$4,$5,$5) RETURNING id`,
    [module, recordType, status, JSON.stringify(payload), now]);
  const hr = await insertRecord('rh');
  await insertRecord('financeiro');
  await insertRecord('entregas');

  await t.test('reaplicar preserva os registros e health informa v28 pronto', async () => {
    await db.exec(migration);
    assert.equal(await scalar(db, 'SELECT count(*) FROM public.erp_module_records'), 3);
    const health = await asUser(db, null, () => scalar(db, 'SELECT public.matterdi_health()'), 'anon');
    assert.equal(health.version, 28);
    assert.equal(health.ready, true);
    await db.exec('DROP FUNCTION public.matterdi_delivery_balances(JSONB)');
    assert.equal((await scalar(db, 'SELECT public.matterdi_health()')).ready, false);
    await db.exec(migration);
  });

  await t.test('RH, financeiro e entregas enxergam apenas seu modulo e nao alteram outro', async () => {
    for (const [user, module] of [['hr', 'rh'], ['finance', 'financeiro'], ['delivery', 'entregas']]) {
      await asUser(db, ids[user], async () => {
        assert.deepEqual((await db.query('SELECT module FROM public.erp_module_records')).rows, [{ module }]);
        const other = module === 'rh' ? 'financeiro' : 'rh';
        assert.equal(await scalar(db, `WITH changed AS (
          UPDATE public.erp_module_records SET title='Intrusao' WHERE module=$1 RETURNING id
        ) SELECT count(*) FROM changed`, [other]), 0);
        await assert.rejects(() => db.query(`INSERT INTO public.erp_module_records
          (module,record_type,title,payload,created_at,updated_at) VALUES($1,'teste','Negado','{}',$2,$2)`, [other, now]), /row-level security/i);
      });
    }
    await asUser(db, ids.both, () => assert.rejects(
      () => db.query("UPDATE public.erp_module_records SET module='financeiro' WHERE id=$1", [hr]),
      /modulo.*nao pode/i,
    ));
  });

  await t.test('anon, sem permissao e perfil inativo nao acessam registros ou RPCs', async () => {
    await asUser(db, null, async () => {
      await assert.rejects(() => db.query('SELECT * FROM public.erp_module_records'), /permission denied/i);
      await assert.rejects(() => db.query("SELECT public.matterdi_delivery_balances('[]')"), /permission denied/i);
      await assert.rejects(() => db.query("SELECT public.matterdi_module_financial(1, '{}')"), /permission denied/i);
    }, 'anon');
    for (const user of [ids.none, ids.inactive]) {
      await asUser(db, user, async () => {
        assert.equal(await scalar(db, 'SELECT count(*) FROM public.erp_module_records'), 0);
        await assert.rejects(() => db.query("SELECT public.matterdi_delivery_balances('[]')"), /Sem permissao/i);
        await assert.rejects(() => db.query("SELECT public.matterdi_module_financial(1, '{}')"), /Sem permissao/i);
      });
    }
  });

  await t.test('API estruturada aceita a nova tabela sem ignorar as policies', async () => {
    const rows = await asUser(db, ids.hr, () => scalar(db,
      'SELECT public.matterdi_data($1::jsonb)',
      [JSON.stringify({ operation: 'query', table: 'erp_module_records' })]));
    assert.deepEqual(rows.map(row => row.module), ['rh']);
    await assert.rejects(() => insertRecord('rh', 'teste', []), /check constraint/i);
  });

  await db.query(`INSERT INTO public.customers(id,name,created_at,updated_at)
    VALUES(1,'Finalizado',$1,$1),(2,'Ainda em producao',$1,$1)`, [now]);
  await db.query(`INSERT INTO public.products
    (id,codigo,nome,categoria,preco,created_at,updated_at) VALUES(1,'P1','Caneca','estamparia',100,$1,$1)`, [now]);
  await db.query(`INSERT INTO public.orders
    (id,number,tipo,customer_id,total,payment_method,status,created_at,updated_at)
    VALUES(1,'OS1','OS',1,100,'Pix','entregue',$1,$1),
      (2,'OS2','OS',2,100,'Pix','em_producao',$1,$1),
      (3,'ORC3','ORCAMENTO',2,100,'Pix','aguardando_pagamento',$1,$1)`, [now]);
  await db.exec(`INSERT INTO public.order_items(order_id,product_id,quantity,unit_price,subtotal)
    VALUES(1,1,1,100,100),(2,1,1,100,100),(3,1,1,100,100)`);
  await db.query(`INSERT INTO public.employees
    (id,name,position,salary,hire_date,created_at,updated_at) VALUES(1,'Pessoa','Cargo',9000,$1,$1,$1)`, [now]);
  const insertFinancial = async (orderId, amount, paid = 0, status = 'pendente', type = 'receber') =>
    scalar(db, `INSERT INTO public.financial
      (description,amount,type,due_date,is_paid,order_id,status,created_at,updated_at)
      VALUES('Nao expor descricao',$1,$2,$3,$4,$5,$6,$3,$3) RETURNING id`,
    [amount, type, now, paid, orderId, status]);
  const partial = await insertFinancial(1, 100);
  await asUser(db, ids.finance, () => db.query('SELECT public.matterdi_financial_partial($1,40,$2)', [partial, now]));
  await insertFinancial(1, 999, 0, 'cancelado');
  await insertFinancial(1, 333, 0, 'pendente', 'pagar');
  await insertFinancial(2, 123);

  await t.test('entregas consulta somente OS pronta, seus itens e clientes, sem salarios ou financeiro geral', async () => {
    await asUser(db, ids.delivery, async () => {
      assert.deepEqual((await db.query('SELECT id FROM public.orders ORDER BY id')).rows, [{ id: 1 }]);
      assert.equal(await scalar(db, 'SELECT count(*) FROM public.order_items'), 1);
      assert.deepEqual((await db.query('SELECT id FROM public.customers')).rows, [{ id: 1 }]);
      assert.equal(await scalar(db, 'SELECT count(*) FROM public.employees'), 0);
      assert.equal(await scalar(db, 'SELECT count(*) FROM public.financial'), 0);
      const balances = await scalar(db, "SELECT public.matterdi_delivery_balances('[1,1,2,3,987654]')");
      assert.deepEqual(balances, [{ order_id: 1, pending: 60, total: 100, paid: 40 }]);
    });
  });

  await t.test('consulta de saldos limita IDs, tipos e permissao', async () => {
    await asUser(db, ids.delivery, async () => {
      for (const invalid of [null, {}, ['1'], [1.5], [-1], [0]]) {
        await assert.rejects(() => db.query('SELECT public.matterdi_delivery_balances($1::jsonb)', [JSON.stringify(invalid)]), /lista|ID.*invalido/i);
      }
      await assert.rejects(() => db.query('SELECT public.matterdi_delivery_balances($1::jsonb)', [JSON.stringify(Array(1001).fill(1))]), /1000/);
      assert.deepEqual(await scalar(db, "SELECT public.matterdi_delivery_balances('[]')"), []);
    });
    await asUser(db, ids.finance, () => assert.rejects(
      () => db.query("SELECT public.matterdi_delivery_balances('[1]')"), /Sem permissao/i,
    ));
  });

  const approvedPayload = { amount: 200, due_date: '2026-10-28', employee_id: 1 };
  const approved = await insertRecord('rh', 'beneficios', approvedPayload, 'Aprovado');
  const send = (user, recordId, payload) => asUser(db, user, () => scalar(db,
    'SELECT public.matterdi_module_financial($1, $2::jsonb)', [recordId, JSON.stringify(payload)]));

  await t.test('integracao financeira exige RH e financeiro, aprovacao e valores persistidos', async () => {
    for (const user of [ids.hr, ids.finance, ids.delivery]) {
      await assert.rejects(() => send(user, approved, financial(approved)), /Sem permissao/i);
    }
    const unapproved = await insertRecord('rh', 'beneficios', approvedPayload, 'Pendente');
    await assert.rejects(() => send(ids.both, unapproved, financial(unapproved)), /Aprove/);
    for (const changed of [
      { amount: 201 }, { type: 'receber' }, { is_paid: 1 }, { status: 'pago' },
      { categoria: 'outros' }, { due_date: '2026-11-01' }, { taxa: -1 },
      { valor_bruto: 'Infinity' }, { amount: 'NaN' }, { id: 123 }, { notes: 'sem referencia' },
    ]) {
      await assert.rejects(() => send(ids.both, approved, financial(approved, changed)));
    }
    assert.equal(await scalar(db, "SELECT count(*) FROM public.financial WHERE notes LIKE $1", [`%[RH:${approved}]%`]), 0);
    assert.equal(await scalar(db, "SELECT (payload::jsonb)->>'financial_id' FROM public.erp_module_records WHERE id=$1", [approved]), null);
  });

  await t.test('gera uma conta atomica, reaproveita o ID mesmo cancelado e nao duplica', async () => {
    const first = await send(ids.both, approved, financial(approved));
    assert.equal(first.type, 'pagar');
    assert.equal(first.amount, 200);
    assert.equal(first.is_paid, 0);
    assert.equal(first.status, 'pendente');
    const record = (await db.query('SELECT * FROM public.erp_module_records WHERE id=$1', [approved])).rows[0];
    assert.equal(record.status, 'Enviado ao financeiro');
    assert.equal(JSON.parse(record.payload).financial_id, first.id);
    await asUser(db, ids.both, async () => {
      for (const payload of [approvedPayload, { ...JSON.parse(record.payload), financial_id: first.id + 1 },
        { ...JSON.parse(record.payload), amount: 999 }, { ...JSON.parse(record.payload), employee_id: 2 },
        { ...JSON.parse(record.payload), due_date: '2026-12-01' }]) {
        await assert.rejects(() => db.query('UPDATE public.erp_module_records SET payload=$1 WHERE id=$2',
          [JSON.stringify(payload), approved]), /preservados/);
      }
      await assert.rejects(() => db.query('DELETE FROM public.erp_module_records WHERE id=$1', [approved]), /Preserve o historico/);
    });
    const second = await send(ids.both, approved, {});
    assert.equal(second.id, first.id);
    await db.query("UPDATE public.financial SET status='cancelado' WHERE id=$1", [first.id]);
    const third = await send(ids.both, approved, {});
    assert.equal(third.id, first.id);
    assert.equal(third.status, 'cancelado');
    assert.equal(await scalar(db, 'SELECT count(*) FROM public.financial WHERE notes LIKE $1', [`%[RH:${approved}]%`]), 1);
    await db.query('DELETE FROM public.financial WHERE id=$1', [first.id]);
    await assert.rejects(() => send(ids.both, approved, financial(approved)), /removida|nao corresponde/);
    assert.equal(await scalar(db, 'SELECT count(*) FROM public.financial WHERE notes LIKE $1', [`%[RH:${approved}]%`]), 0);
  });

  await t.test('ferias conserva aprovacao e conflito de referencia nao gera nova conta', async () => {
    const vacation = await insertRecord('rh', 'ferias', approvedPayload, 'Aprovado');
    await send(ids.both, vacation, financial(vacation));
    assert.equal(await scalar(db, 'SELECT status FROM public.erp_module_records WHERE id=$1', [vacation]), 'Aprovado');
    const conflict = await insertRecord('rh', 'folha', approvedPayload, 'Aprovado');
    for (let i = 0; i < 2; i++) {
      await db.query(`INSERT INTO public.financial(description,amount,type,due_date,notes,created_at,updated_at)
        VALUES('Duplicado',200,'pagar',$1,$2,$1,$1)`, [now, `[RH:${conflict}]`]);
    }
    await assert.rejects(() => send(ids.both, conflict, financial(conflict)), /mais de uma conta/);
  });

  await t.test('falha ao gravar o vinculo reverte tambem a conta criada', async () => {
    const recordId = await insertRecord('rh', 'rescisoes', approvedPayload, 'Aprovado');
    await db.exec(`CREATE FUNCTION public.test_fail_link() RETURNS TRIGGER
      LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Falha simulada no vinculo'; END; $$;
      CREATE TRIGGER test_fail_link BEFORE UPDATE ON public.erp_module_records
      FOR EACH ROW EXECUTE FUNCTION public.test_fail_link();`);
    try {
      await assert.rejects(() => send(ids.both, recordId, financial(recordId)), /Falha simulada/);
      assert.equal(await scalar(db, 'SELECT count(*) FROM public.financial WHERE notes LIKE $1', [`%[RH:${recordId}]%`]), 0);
      assert.equal(await scalar(db, "SELECT (payload::jsonb)->>'financial_id' FROM public.erp_module_records WHERE id=$1", [recordId]), null);
    } finally {
      await db.exec('DROP TRIGGER test_fail_link ON public.erp_module_records; DROP FUNCTION public.test_fail_link()');
    }
  });
});
