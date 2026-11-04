import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const workspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const otherUserId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const userEmail = 'admin@example.test';
const otherUserEmail = 'other@example.test';

test('bootstrap vincula somente o perfil autorizado e preserva conflitos', async (t) => {
  const db = new PGlite();
  await db.waitReady;
  t.after(() => db.close());
  await db.exec(`
    CREATE ROLE anon NOLOGIN;
    CREATE ROLE authenticated NOLOGIN;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (
      id UUID PRIMARY KEY, email TEXT, created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE
      SET search_path = '' AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID $$;
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
  assert.equal((await db.query('SELECT public.matterdi_health() AS value')).rows[0].value.ready, true);
  const bootstrap = await readFile(path.join(workspace, 'tool', 'supabase_bootstrap_admin.sql'), 'utf8');
  const emailDeclaration = /v_admin_email\s+TEXT\s*:=\s*'(?:''|[^'])*';/;
  assert.match(bootstrap, emailDeclaration);
  // Substitui somente a copia em memoria; preserva o e-mail configurado no arquivo.
  const forEmail = email => bootstrap.replace(
    emailDeclaration,
    () => `v_admin_email TEXT := '${email.replaceAll("'", "''")}';`,
  );
  await db.query('INSERT INTO auth.users(id, email) VALUES ($1, $2), ($3, $4)', [
    userId, userEmail, otherUserId, otherUserEmail,
  ]);

  async function resetProfiles() {
    await db.exec('TRUNCATE public.system_users RESTART IDENTITY CASCADE');
  }

  async function addProfile({
    username = 'admin', authUserId = null, isAdmin = 1, active = 1,
    fullName = 'Nome preservado',
  } = {}) {
    return (await db.query(`
      INSERT INTO public.system_users (
        username, full_name, email, auth_user_id, is_admin, active,
        permissions, created_at, updated_at
      ) VALUES ($1, $2, '', $3, $4, $5, '[]', '2026-10-06', '2026-10-06')
      RETURNING id
    `, [username, fullName, authUserId, isAdmin, active])).rows[0].id;
  }

  async function profiles() {
    return (await db.query('SELECT * FROM public.system_users ORDER BY id')).rows;
  }

  async function expectUnchangedFailure(email, pattern) {
    const before = await profiles();
    await assert.rejects(db.exec(forEmail(email)), pattern);
    assert.deepEqual(await profiles(), before, 'uma recusa deve preservar todos os perfis');
  }

  await t.test('recusa e-mail nao configurado e conta Auth inexistente', async () => {
    await expectUnchangedFailure('ALTERE_PARA_O_EMAIL_DO_ADMINISTRADOR', /Troque v_admin_email/);
    await expectUnchangedFailure('missing@example.test', /Nenhuma conta Auth/);
  });

  await t.test('banco vazio cria um administrador vinculado e e idempotente', async () => {
    await resetProfiles();
    await db.exec(forEmail(userEmail));
    await db.exec(forEmail(userEmail));
    const rows = await profiles();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].auth_user_id, userId);
    assert.equal(rows[0].email, userEmail);
    assert.equal(Number(rows[0].is_admin), 1);
    assert.equal(Number(rows[0].active), 1);
    assert.equal(rows[0].permissions, '[]');
  });

  await t.test('reaproveita somente admin legado NULL, preservando o ID e o nome', async () => {
    await resetProfiles();
    const id = await addProfile({ username: 'AdMiN' });
    await db.exec(forEmail(userEmail));
    const rows = await profiles();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].id, id);
    assert.equal(rows[0].full_name, 'Nome preservado');
    assert.equal(rows[0].auth_user_id, userId);
    assert.equal(Number(rows[0].is_admin), 1);
    assert.equal(Number(rows[0].active), 1);
    await db.exec(forEmail(userEmail));
    assert.equal((await profiles()).length, 1);
  });

  await t.test('reaproveita o perfil da mesma conta Auth mesmo com outro username', async () => {
    await resetProfiles();
    const id = await addProfile({ username: 'dono', authUserId: userId, isAdmin: 0, active: 0 });
    await db.exec(forEmail(userEmail));
    const rows = await profiles();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].id, id);
    assert.equal(rows[0].username, 'dono');
    assert.equal(rows[0].auth_user_id, userId);
    assert.equal(Number(rows[0].is_admin), 1);
    assert.equal(Number(rows[0].active), 1);
  });

  await t.test('nunca reassocia admin de outra conta, ativo ou inativo', async () => {
    for (const active of [0, 1]) {
      for (const isAdmin of [0, 1]) {
        await resetProfiles();
        await addProfile({ authUserId: otherUserId, isAdmin, active });
        await expectUnchangedFailure(userEmail, /vinculado a outra conta Auth/);
      }
    }
  });

  await t.test('outros administradores ativos bloqueiam com ou sem vinculo Auth', async () => {
    for (const authUserId of [null, otherUserId]) {
      for (const hasTarget of [false, true]) {
        await resetProfiles();
        if (hasTarget) await addProfile();
        await addProfile({ username: 'outro-administrador', authUserId });
        await expectUnchangedFailure(userEmail, /Ja existe outro administrador ativo/);
      }
    }
  });

  await t.test('perfil da conta e admin legado separado continuam sendo conflito', async () => {
    await resetProfiles();
    await addProfile({ username: 'operador', authUserId: userId, isAdmin: 0 });
    await addProfile();
    await expectUnchangedFailure(userEmail, /perfis conflitantes/);
  });

  await t.test('outro legado sem privilegio nao e reaproveitado nem promovido', async () => {
    await resetProfiles();
    const legacyId = await addProfile({ username: 'operador', isAdmin: 0 });
    await db.exec(forEmail(userEmail));
    const rows = await profiles();
    assert.equal(rows.length, 2);
    const legacy = rows.find(row => row.id === legacyId);
    assert.equal(legacy.auth_user_id, null);
    assert.equal(Number(legacy.is_admin), 0);
    assert.equal(rows.find(row => row.auth_user_id === userId).username, 'admin');
  });

  await t.test('perfil criado pode consultar o proprio cadastro pelo RPC com RLS', async () => {
    await resetProfiles();
    await db.exec(forEmail(userEmail));
    await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [userId]);
    await db.exec('SET ROLE authenticated');
    try {
      const payload = {
        operation: 'query', table: 'system_users',
        filters: [
          { column: 'auth_user_id', operator: 'eq', value: userId },
          { column: 'active', operator: 'eq', value: 1 },
        ],
        limit: 1,
      };
      const rows = (await db.query('SELECT public.matterdi_data($1::jsonb) AS value', [JSON.stringify(payload)])).rows[0].value;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].auth_user_id, userId);
      assert.equal(Number(rows[0].active), 1);
    } finally {
      await db.exec('RESET ROLE');
      await db.query("SELECT set_config('request.jwt.claim.sub', '', false)");
    }
  });
});
