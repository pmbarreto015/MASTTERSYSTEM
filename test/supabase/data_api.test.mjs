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

async function asRole(db, role, userId, action) {
  await db.exec('RESET ROLE');
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [
    userId ?? '',
  ]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await action();
  } finally {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub', '', false)");
  }
}

async function expectFailure(action, pattern) {
  let failure;
  try {
    await action();
  } catch (error) {
    failure = error;
  }
  assert.ok(failure, 'a operação deveria falhar');
  if (pattern) assert.match(String(failure.message ?? failure), pattern);
}

async function data(db, userId, payload) {
  const result = await asRole(db, 'authenticated', userId, () =>
    db.query('SELECT public.matterdi_data($1::jsonb) AS value', [
      JSON.stringify(payload),
    ]),
  );
  return result.rows[0].value;
}

test('API de dados estruturada do Supabase', async (t) => {
  const db = new PGlite();
  await db.waitReady;
  t.after(async () => db.close());

  await db.exec(`
    CREATE ROLE anon NOLOGIN;
    CREATE ROLE authenticated NOLOGIN;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE OR REPLACE FUNCTION auth.uid()
    RETURNS UUID LANGUAGE sql STABLE SET search_path = ''
    AS $$
      SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID;
    $$;
    GRANT USAGE ON SCHEMA auth TO anon, authenticated;
    GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;
  `);

  for (const migration of [
    '20261003000000_initial_schema.sql',
    '20261006000000_auth_permissions.sql',
    '20261006010000_data_api.sql',
  ]) {
    await db.exec(
      await readFile(
        path.join(workspace, 'supabase', 'migrations', migration),
        'utf8',
      ),
    );
  }

  const adminId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const inactiveId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const now = '2026-10-06T12:00:00.000Z';
  await db.query(
    'INSERT INTO auth.users(id) VALUES ($1::uuid), ($2::uuid)',
    [adminId, inactiveId],
  );
  await db.query(
    `INSERT INTO public.system_users
      (username, full_name, email, auth_user_id, is_admin, active,
       permissions, created_at, updated_at)
     VALUES
      ('admin-api', 'Admin API', 'admin@example.test', $1::uuid, 1, 1,
       '[]', $3, $3),
      ('inactive-api', 'Inativo API', 'inactive@example.test', $2::uuid, 0, 0,
       '[]', $3, $3)`,
    [adminId, inactiveId, now],
  );
  await db.query(
    `INSERT INTO public.customers
      (uuid, name, total_purchases, created_at, updated_at)
     VALUES ('cus_one', 'Alfa', 10, $1, $1),
            ('cus_two', 'Beta', 20, $1, $1)`,
    [now],
  );

  await t.test('health é público e funções de dados não são anônimas', async () => {
    const health = await asRole(db, 'anon', null, () =>
      db.query('SELECT public.matterdi_health() AS value'),
    );
    assert.equal(health.rows[0].value.service, 'matterdi-supabase');
    assert.equal(health.rows[0].value.ready, false);
    await db.exec(await readFile(path.join(workspace, 'supabase', 'migrations', '20261006020000_business_rpc.sql'), 'utf8'));
    const installed = await asRole(db, 'anon', null, () => db.query('SELECT public.matterdi_health() AS value'));
    assert.equal(installed.rows[0].value.ready, true);
    await expectFailure(
      () =>
        asRole(db, 'anon', null, () =>
          db.query("SELECT public.matterdi_data('{\"operation\":\"query\",\"table\":\"customers\"}'::jsonb)"),
        ),
      /permission denied|permissão/i,
    );
  });

  await t.test('query usa filtros e ordenação estruturados', async () => {
    const rows = await data(db, adminId, {
      operation: 'query',
      table: 'customers',
      columns: ['id', 'name'],
      filters: [
        { column: 'name', operator: 'ilike', value: '%a%' },
        { connector: 'and', column: 'id', operator: 'gte', value: 1 },
      ],
      order: [{ column: 'name', direction: 'desc', nocase: true }],
    });
    assert.deepEqual(rows.map((row) => row.name), ['Beta', 'Alfa']);

    const hidden = await data(db, inactiveId, {
      operation: 'query',
      table: 'customers',
    });
    assert.deepEqual(hidden, []);
  });

  await t.test('insert, update e delete respeitam tipos e RLS', async () => {
    const insertedId = Number(await data(db, adminId, {
      operation: 'insert',
      table: 'customers',
      values: {
        uuid: 'cus_three',
        name: 'Gama',
        total_purchases: 0,
        created_at: now,
        updated_at: now,
      },
    }));
    assert.ok(insertedId > 2);

    assert.equal(Number(await data(db, adminId, {
      operation: 'update',
      table: 'customers',
      values: { name: 'Gama Atualizado' },
      filters: [{ column: 'id', operator: 'eq', value: insertedId }],
    })), 1);
    assert.equal(Number(await data(db, adminId, {
      operation: 'delete',
      table: 'customers',
      filters: [{ column: 'id', operator: 'eq', value: insertedId }],
    })), 1);
  });

  await t.test('relatórios usam catálogo fechado', async () => {
    const result = await asRole(db, 'authenticated', adminId, () =>
      db.query(
        "SELECT public.matterdi_report('composicoes_count', '[]'::jsonb) AS value",
      ),
    );
    assert.equal(Number(result.rows[0].value[0].total), 0);
    await expectFailure(
      () =>
        asRole(db, 'authenticated', adminId, () =>
          db.query(
            "SELECT public.matterdi_report('select_anything', '[]'::jsonb)",
          ),
        ),
      /relatório não permitido/i,
    );
  });

  await t.test('batch reverte todas as gravações quando uma falha', async () => {
    const before = Number((await db.query(
      'SELECT count(*) AS value FROM public.customers',
    )).rows[0].value);
    const operations = [
      {
        kind: 'data',
        payload: {
          operation: 'insert',
          table: 'customers',
          values: {
            uuid: 'cus_batch',
            name: 'Lote',
            created_at: now,
            updated_at: now,
          },
        },
      },
      {
        kind: 'data',
        payload: {
          operation: 'insert',
          table: 'customers',
          values: {
            uuid: 'cus_one',
            name: 'Duplicado',
            created_at: now,
            updated_at: now,
          },
        },
      },
    ];
    await expectFailure(
      () =>
        asRole(db, 'authenticated', adminId, () =>
          db.query(
            'SELECT public.matterdi_batch($1::jsonb, false, false)',
            [JSON.stringify(operations)],
          ),
        ),
      /unique|duplicate|duplicada/i,
    );
    const after = Number((await db.query(
      'SELECT count(*) AS value FROM public.customers',
    )).rows[0].value);
    assert.equal(after, before);
  });

  await t.test('rejeita identificadores e alterações sem filtro', async () => {
    await expectFailure(
      () => data(db, adminId, {
        operation: 'query',
        table: 'customers; drop table customers',
      }),
      /tabela não permitida/i,
    );
    await expectFailure(
      () => data(db, adminId, {
        operation: 'query',
        table: 'customers',
        filters: [{ column: 'id; delete', operator: 'eq', value: 1 }],
      }),
      /coluna não permitida/i,
    );
    await expectFailure(
      () => data(db, adminId, {
        operation: 'delete',
        table: 'customers',
        filters: [],
      }),
      /sem filtro não permitida/i,
    );
  });
});
