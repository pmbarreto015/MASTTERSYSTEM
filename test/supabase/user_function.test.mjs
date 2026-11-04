import assert from 'node:assert/strict';
import test from 'node:test';

const projectUrl = 'https://edge-test.example.test';
const publicKey = 'sb_publishable_fake_test_key';
const privateKey = 'sb_secret_fake_test_key_never_return';
const callerToken = 'fake-administrator-session';
const administratorId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const createdUserId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const suppliedAuthId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const password = 'Test-only-password-42';

function replaceGlobal(name, value) {
  const original = Object.getOwnPropertyDescriptor(globalThis, name);
  Object.defineProperty(globalThis, name, {
    value, configurable: true, writable: true,
  });
  return () => {
    if (original) Object.defineProperty(globalThis, name, original);
    else delete globalThis[name];
  };
}

async function loadHandler() {
  let handler;
  const restore = replaceGlobal('Deno', {
    serve: callback => { handler = callback; },
    env: { get: () => undefined },
  });
  try {
    // Node 24 removes erasable TypeScript annotations without a transpiler.
    await import('../../supabase/functions/matterdi-users/index.ts');
    assert.equal(typeof handler, 'function', 'a funcao deve registrar seu handler');
    return handler;
  } finally {
    restore();
  }
}

function request({ authorization = `Bearer ${callerToken}`, body = createBody() } = {}) {
  const headers = { apikey: publicKey, 'Content-Type': 'application/json' };
  if (authorization !== null) headers.Authorization = authorization;
  return new Request(`${projectUrl}/functions/v1/matterdi-users`, {
    method: 'POST', headers, body: JSON.stringify(body),
  });
}

function createBody() {
  return {
    action: 'create',
    password,
    profile: {
      username: ' operador ',
      full_name: ' Operador de teste ',
      email: ' OPERADOR@EXAMPLE.TEST ',
      permissions: ['vendas', 'dashboard', 'vendas'],
      active: true,
      // Estes campos enviados pelo cliente nao podem escolher a conta ou
      // promover o novo usuario a administrador.
      auth_user_id: suppliedAuthId,
      is_admin: 1,
    },
  };
}

function sessionSteps(profile = { id: 1, auth_user_id: administratorId, active: 1, is_admin: 1 }) {
  return [
    { path: '/auth/v1/user', method: 'GET', body: { id: administratorId } },
    { path: '/rest/v1/system_users', method: 'GET', body: profile ? [profile] : [] },
  ];
}

function authCreationStep(overrides = {}) {
  return {
    path: '/auth/v1/admin/users', method: 'POST', status: 201,
    body: { user: { id: createdUserId, encrypted_password: 'must-not-be-public' } },
    ...overrides,
  };
}

const savedProfile = {
  id: 29,
  username: 'operador',
  full_name: 'Operador de teste',
  email: 'operador@example.test',
  auth_user_id: createdUserId,
  is_admin: 0,
  active: 1,
  permissions: '["dashboard","vendas"]',
  created_at: '2026-10-22T10:00:00.000Z',
  updated_at: '2026-10-22T10:00:00.000Z',
};

async function withBackend(steps, run) {
  const calls = [];
  const violations = [];
  const environment = {
    SUPABASE_URL: projectUrl,
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: publicKey }),
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: privateKey }),
  };
  const restoreDeno = replaceGlobal('Deno', {
    env: { get: name => environment[name] },
    serve: () => { throw new Error('o handler ja deve estar registrado'); },
  });
  const restoreFetch = replaceGlobal('fetch', async (input, init = {}) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const call = {
      url,
      method: init.method ?? 'GET',
      headers: new Headers(init.headers),
      body: init.body == null ? undefined : JSON.parse(init.body),
    };
    const expected = steps[calls.length];
    calls.push(call);
    // Uma chamada inesperada nunca alcança a rede; a violacao continua visivel
    // mesmo quando o handler captura uma excecao e devolve HTTP 500.
    try {
      assert.ok(expected, `chamada inesperada: ${call.method} ${url}`);
      assert.equal(url.origin, projectUrl);
      assert.equal(url.pathname, expected.path);
      assert.equal(call.method, expected.method);
    } catch (error) {
      violations.push(error);
      throw error;
    }
    const status = expected.status ?? 200;
    return new Response(status === 204 ? null : JSON.stringify(expected.body), {
      status, headers: { 'Content-Type': 'application/json' },
    });
  });
  try {
    await run(calls);
    assert.deepEqual(violations, [], 'nenhuma chamada inesperada pode ser ocultada');
    assert.equal(calls.length, steps.length, 'todas e somente as chamadas previstas devem ocorrer');
  } finally {
    restoreFetch();
    restoreDeno();
  }
}

function assertCallerCredentials(call) {
  assert.equal(call.headers.get('apikey'), publicKey);
  assert.equal(call.headers.get('authorization'), `Bearer ${callerToken}`);
  assert.ok(!JSON.stringify(call.body ?? null).includes(privateKey));
}

function assertPrivateCredentials(call) {
  assert.equal(call.headers.get('apikey'), privateKey);
  assert.equal(call.headers.get('authorization'), null,
    'a chave opaca privada fica somente em apikey');
}

test('matterdi-users autoriza criacao e compensa falhas sem expor credenciais', { concurrency: false }, async (t) => {
  const handler = await loadHandler();

  await t.test('sem Bearer valido retorna 401 antes de consultar qualquer API', async () => {
    for (const authorization of [null, 'Basic invalid', 'Bearer']) {
      await withBackend([], async () => {
        const response = await handler(request({ authorization }));
        assert.equal(response.status, 401);
        assert.match((await response.json()).error, /Sessao ausente ou invalida/);
      });
    }
  });

  await t.test('sessao rejeitada pela Auth retorna 401 sem buscar perfil ou API administrativa', async () => {
    await withBackend([
      { path: '/auth/v1/user', method: 'GET', status: 401, body: { message: 'expired' } },
    ], async calls => {
      const response = await handler(request());
      assert.equal(response.status, 401);
      assert.match((await response.json()).error, /Sessao expirada ou invalida/);
      assertCallerCredentials(calls[0]);
    });
  });

  await t.test('perfil comum, inativo ou ausente retorna 403 sem chamar Auth administrativa', async () => {
    for (const profile of [
      { id: 2, auth_user_id: administratorId, active: 1, is_admin: 0 },
      { id: 2, auth_user_id: administratorId, active: 0, is_admin: 1 },
      null,
    ]) {
      await withBackend(sessionSteps(profile), async calls => {
        const response = await handler(request());
        assert.equal(response.status, 403);
        assert.match((await response.json()).error, /Perfil sem acesso administrativo/);
        calls.forEach(assertCallerCredentials);
        assert.equal(calls[1].url.searchParams.get('auth_user_id'), `eq.${administratorId}`);
      });
    }
  });

  await t.test('administrador cria conta e perfil vinculado com permissoes e sem promover usuario', async () => {
    await withBackend([
      ...sessionSteps(),
      authCreationStep(),
      {
        path: '/rest/v1/system_users', method: 'POST', status: 201,
        body: [{ ...savedProfile, password_hash: 'must-not-be-public', secret: privateKey }],
      },
    ], async calls => {
      const response = await handler(request());
      assert.equal(response.status, 200);
      const responseText = await response.text();
      assert.deepEqual(JSON.parse(responseText), { profile: savedProfile });
      for (const forbidden of [password, privateKey, callerToken, 'password_hash', 'encrypted_password']) {
        assert.ok(!responseText.includes(forbidden), `resposta nao pode incluir ${forbidden}`);
      }
      assertCallerCredentials(calls[0]);
      assertCallerCredentials(calls[1]);
      assertPrivateCredentials(calls[2]);
      assert.deepEqual(calls[2].body, {
        email: 'operador@example.test', password, email_confirm: true,
        user_metadata: { username: 'operador', full_name: 'Operador de teste' },
      });
      const profileInsert = calls[3];
      assertCallerCredentials(profileInsert);
      assert.equal(profileInsert.headers.get('prefer'), 'return=representation');
      assert.deepEqual({
        ...profileInsert.body,
        created_at: savedProfile.created_at,
        updated_at: savedProfile.updated_at,
      }, savedProfileWithoutId());
      assert.ok(Number.isFinite(Date.parse(profileInsert.body.created_at)));
      assert.equal(profileInsert.body.created_at, profileInsert.body.updated_at);
      assert.ok(!JSON.stringify(profileInsert.body).includes(password));
    });
  });

  await t.test('falha ao inserir perfil exclui a nova conta Auth e preserva o erro original', async () => {
    await withBackend([
      ...sessionSteps(),
      authCreationStep(),
      {
        path: '/rest/v1/system_users', method: 'POST', status: 409,
        body: { message: 'duplicate key value violates unique constraint system_users_username_key' },
      },
      { path: `/auth/v1/admin/users/${createdUserId}`, method: 'DELETE', status: 204 },
    ], async calls => {
      const response = await handler(request());
      assert.equal(response.status, 400);
      assert.match((await response.json()).error, /system_users_username_key/);
      assert.equal(calls[3].body.auth_user_id, createdUserId);
      assertPrivateCredentials(calls[4]);
      assert.equal(calls[4].body, undefined);
    });
  });

  await t.test('falha na compensacao nao substitui o erro que impediu salvar o perfil', async () => {
    await withBackend([
      ...sessionSteps(),
      authCreationStep(),
      { path: '/rest/v1/system_users', method: 'POST', status: 403, body: { message: 'profile permission denied' } },
      { path: `/auth/v1/admin/users/${createdUserId}`, method: 'DELETE', status: 503, body: { message: 'Auth unavailable' } },
    ], async () => {
      const response = await handler(request());
      assert.equal(response.status, 400);
      assert.deepEqual(await response.json(), { error: 'profile permission denied' });
    });
  });

  await t.test('e-mail duplicado na Auth nao insere perfil nem exclui a conta existente', async () => {
    await withBackend([
      ...sessionSteps(),
      authCreationStep({ status: 422, body: { msg: 'A user with this email address has already been registered' } }),
    ], async calls => {
      const response = await handler(request());
      assert.equal(response.status, 400);
      assert.match((await response.json()).error, /already been registered/);
      assertPrivateCredentials(calls[2]);
    });
  });
});

function savedProfileWithoutId() {
  const { id, ...profile } = savedProfile;
  return profile;
}
