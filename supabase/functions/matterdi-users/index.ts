const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

const allowedPermissions = new Set([
  "dashboard",
  "agenda",
  "clientes",
  "produtos",
  "vendas",
  "pedidos_alterar",
  "pedidos_reabrir",
  "pedidos_excluir",
  "orcamentos",
  "producao",
  "entregas",
  "estoque",
  "fornecedores",
  "financeiro",
  "vendedores",
  "funcionarios",
  "relatorios",
  "rentabilidade",
  "arquivos",
  "corte_materiais",
  "corte_maquinas",
  "corte_compositor",
  "corte_retalhos",
  "corte_aproveitamento",
  "configuracoes",
  "backup",
  "suporte",
]);

type JsonObject = Record<string, unknown>;

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function json(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new HttpError(500, `Configuracao ausente: ${name}.`);
  return value.replace(/\/$/, "");
}

function firstKeyFromJson(
  source: string | undefined,
  expectedPrefix?: string,
): string | null {
  if (!source) return null;
  try {
    const parsed: unknown = JSON.parse(source);
    if (typeof parsed === "string" && parsed.trim()) return parsed.trim();
    if (Array.isArray(parsed)) {
      const key = parsed.find((item) => typeof item === "string" && item.trim());
      return typeof key === "string" ? key.trim() : null;
    }
    if (parsed && typeof parsed === "object") {
      const record = parsed as JsonObject;
      const defaultKey = record.default;
      if (
        typeof defaultKey === "string" &&
        defaultKey.trim() &&
        (!expectedPrefix || defaultKey.startsWith(expectedPrefix))
      ) {
        return defaultKey.trim();
      }
      const values = Object.values(record);
      const preferred = values.find(
        (item) =>
          typeof item === "string" &&
          (!expectedPrefix || item.startsWith(expectedPrefix)),
      );
      const fallback = values.find(
        (item) => typeof item === "string" && item.trim(),
      );
      const key = preferred ?? fallback;
      return typeof key === "string" ? key.trim() : null;
    }
  } catch {
    return null;
  }
  return null;
}

function adminKey(): string {
  const configured =
    firstKeyFromJson(Deno.env.get("SUPABASE_SECRET_KEYS"), "sb_secret_") ||
    Deno.env.get("SUPABASE_SECRET_KEY")?.trim() ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!configured) {
    throw new HttpError(500, "Credencial privada da funcao nao configurada.");
  }
  return configured;
}

function isJwt(value: string): boolean {
  return value.split(".").length === 3;
}

function adminHeaders(key: string): HeadersInit {
  const headers: Record<string, string> = {
    apikey: key,
    "Content-Type": "application/json",
  };
  // As chaves privadas novas sao opacas e ficam apenas no cabecalho apikey.
  // A chave legada e um JWT e tambem e aceita como Bearer pela API administrativa.
  if (isJwt(key)) headers.Authorization = `Bearer ${key}`;
  return headers;
}

function userHeaders(apiKey: string, authorization: string): HeadersInit {
  return {
    apikey: apiKey,
    Authorization: authorization,
    "Content-Type": "application/json",
  };
}

async function safeMessage(response: Response, fallback: string): Promise<string> {
  try {
    const body = await response.json() as JsonObject;
    for (const field of ["msg", "message", "error_description", "error"]) {
      const value = body[field];
      if (typeof value === "string" && value.trim()) return value.trim();
    }
  } catch {
    // A resposta do provedor nao precisa ser devolvida integralmente ao cliente.
  }
  return fallback;
}

function requiredText(value: unknown, label: string, maxLength = 200): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpError(400, `${label} e obrigatorio.`);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new HttpError(400, `${label} excede o tamanho permitido.`);
  }
  return normalized;
}

function validEmail(value: unknown): string {
  const email = requiredText(value, "E-mail", 254).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpError(400, "E-mail invalido.");
  }
  return email;
}

function validPassword(value: unknown, required: boolean): string | undefined {
  if (value == null || value === "") {
    if (required) throw new HttpError(400, "Senha e obrigatoria.");
    return undefined;
  }
  if (typeof value !== "string" || value.length < 6 || value.length > 128) {
    throw new HttpError(400, "A senha deve ter entre 6 e 128 caracteres.");
  }
  return value;
}

function validPermissions(value: unknown): string[] {
  let source = value;
  if (typeof source === "string") {
    try {
      source = JSON.parse(source);
    } catch {
      throw new HttpError(400, "Permissoes invalidas.");
    }
  }
  if (!Array.isArray(source)) throw new HttpError(400, "Permissoes invalidas.");
  const result = [...new Set(source.map((item) => String(item)))];
  const invalid = result.find((item) => !allowedPermissions.has(item));
  if (invalid) throw new HttpError(400, `Permissao desconhecida: ${invalid}.`);
  return result.sort();
}

function validUuid(value: unknown, label = "Usuario"): string {
  const uuid = requiredText(value, label, 36).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid)) {
    throw new HttpError(400, `${label} invalido.`);
  }
  return uuid;
}

function profileObject(body: JsonObject): JsonObject {
  const raw = body.profile;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpError(400, "Perfil invalido.");
  }
  return raw as JsonObject;
}

function profileFrom(body: JsonObject) {
  const profile = profileObject(body);
  const emailValue = validEmail(profile.email);
  const active = profile.active == null ? true : profile.active === true || profile.active === 1;
  return {
    username: requiredText(profile.username, "Usuario", 80),
    full_name: requiredText(profile.full_name ?? profile.fullName, "Nome", 160),
    email: emailValue,
    active: active ? 1 : 0,
    permissions: validPermissions(profile.permissions),
    auth_user_id: profile.auth_user_id ?? profile.authUserId,
  };
}

async function verifyAdministrator(
  request: Request,
  baseUrl: string,
): Promise<{ authorization: string; apiKey: string; userId: string }> {
  const authorization = request.headers.get("Authorization")?.trim() ?? "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) {
    throw new HttpError(401, "Sessao ausente ou invalida.");
  }

  const apiKey =
    request.headers.get("apikey")?.trim() ||
    firstKeyFromJson(
      Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
      "sb_publishable_",
    ) ||
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ||
    Deno.env.get("SUPABASE_ANON_KEY")?.trim() ||
    "";
  if (!apiKey) throw new HttpError(401, "Chave publica ausente.");

  const authResponse = await fetch(`${baseUrl}/auth/v1/user`, {
    headers: userHeaders(apiKey, authorization),
  });
  if (!authResponse.ok) throw new HttpError(401, "Sessao expirada ou invalida.");
  const authUser = await authResponse.json() as JsonObject;
  const userId = validUuid(authUser.id, "Identificador da sessao");

  const query = new URL(`${baseUrl}/rest/v1/system_users`);
  query.searchParams.set("select", "id,auth_user_id,is_admin,active");
  query.searchParams.set("auth_user_id", `eq.${userId}`);
  query.searchParams.set("limit", "1");
  const profileResponse = await fetch(query, {
    headers: userHeaders(apiKey, authorization),
  });
  if (!profileResponse.ok) throw new HttpError(403, "Perfil sem acesso administrativo.");
  const profiles = await profileResponse.json() as JsonObject[];
  const profile = profiles[0];
  if (!profile || Number(profile.active) !== 1 || Number(profile.is_admin) !== 1) {
    throw new HttpError(403, "Perfil sem acesso administrativo.");
  }

  return { authorization, apiKey, userId };
}

async function adminAuthRequest(
  baseUrl: string,
  path: string,
  method: string,
  body?: JsonObject,
): Promise<JsonObject> {
  const response = await fetch(`${baseUrl}/auth/v1/admin${path}`, {
    method,
    headers: adminHeaders(adminKey()),
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    throw new HttpError(response.status >= 500 ? 502 : 400, await safeMessage(
      response,
      "Nao foi possivel atualizar a conta de acesso.",
    ));
  }
  if (response.status === 204) return {};
  try {
    return await response.json() as JsonObject;
  } catch {
    return {};
  }
}

async function profileRequest(
  baseUrl: string,
  session: { authorization: string; apiKey: string },
  path: string,
  method = "GET",
  body?: JsonObject,
): Promise<JsonObject[]> {
  const headers = new Headers(userHeaders(session.apiKey, session.authorization));
  headers.set("Prefer", "return=representation");
  const response = await fetch(`${baseUrl}/rest/v1/${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    throw new HttpError(response.status >= 500 ? 502 : 400, await safeMessage(
      response,
      "Nao foi possivel atualizar o perfil.",
    ));
  }
  if (response.status === 204) return [];
  try {
    return await response.json() as JsonObject[];
  } catch {
    return [];
  }
}

function publicProfile(profile: JsonObject): JsonObject {
  return {
    id: profile.id,
    auth_user_id: profile.auth_user_id,
    username: profile.username,
    full_name: profile.full_name,
    email: profile.email,
    is_admin: Number(profile.is_admin ?? 0),
    active: Number(profile.active ?? 0),
    permissions: profile.permissions ?? "[]",
    created_at: profile.created_at,
    updated_at: profile.updated_at,
  };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "Metodo nao permitido." });

  try {
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > 65536) {
      throw new HttpError(413, "Solicitacao muito grande.");
    }

    const source = await request.text();
    if (source.length > 65536) throw new HttpError(413, "Solicitacao muito grande.");
    let body: JsonObject;
    try {
      body = JSON.parse(source) as JsonObject;
    } catch {
      throw new HttpError(400, "JSON invalido.");
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new HttpError(400, "Solicitacao invalida.");
    }

    const baseUrl = requiredEnvironment("SUPABASE_URL");
    const session = await verifyAdministrator(request, baseUrl);
    const action = requiredText(body.action, "Acao", 16).toLowerCase();
    if (!["create", "update", "delete"].includes(action)) {
      throw new HttpError(400, "Acao desconhecida.");
    }

    if (action === "create") {
      const profile = profileFrom(body);
      const password = validPassword(body.password, true)!;
      const authResult = await adminAuthRequest(baseUrl, "/users", "POST", {
        email: profile.email,
        password,
        email_confirm: true,
        user_metadata: {
          username: profile.username,
          full_name: profile.full_name,
        },
      });
      const rawUser = (authResult.user && typeof authResult.user === "object")
        ? authResult.user as JsonObject
        : authResult;
      const authUserId = validUuid(rawUser.id, "Conta criada");
      const now = new Date().toISOString();
      try {
        const rows = await profileRequest(baseUrl, session, "system_users", "POST", {
          username: profile.username,
          full_name: profile.full_name,
          email: profile.email,
          auth_user_id: authUserId,
          is_admin: 0,
          active: profile.active,
          permissions: JSON.stringify(profile.permissions),
          created_at: now,
          updated_at: now,
        });
        if (!rows[0]) throw new HttpError(502, "O perfil nao foi devolvido pelo banco.");
        return json(200, { profile: publicProfile(rows[0]) });
      } catch (error) {
        // Compensacao: nao deixa uma conta Auth orfa se a criacao do perfil falhar.
        try {
          await adminAuthRequest(baseUrl, `/users/${authUserId}`, "DELETE");
        } catch {
          // O erro original e mais util; nenhum segredo e registrado.
        }
        throw error;
      }
    }

    const rawProfile = profileObject(body);
    const targetId = validUuid(
      rawProfile.auth_user_id ?? rawProfile.authUserId,
      "Conta do usuario",
    );
    if (targetId === session.userId) {
      throw new HttpError(400, "Use a troca de senha da propria conta para o administrador atual.");
    }

    const targetRows = await profileRequest(
      baseUrl,
      session,
      `system_users?select=*&auth_user_id=eq.${encodeURIComponent(targetId)}&limit=1`,
    );
    const target = targetRows[0];
    if (!target) throw new HttpError(404, "Usuario nao encontrado.");
    if (Number(target.is_admin) === 1) {
      throw new HttpError(400, "Um perfil administrador nao pode ser alterado por esta funcao.");
    }

    if (action === "delete") {
      await adminAuthRequest(baseUrl, `/users/${targetId}`, "DELETE");
      return json(200, { deleted: true, auth_user_id: targetId });
    }

    const profile = profileFrom(body);
    const password = validPassword(body.password, false);
    const authUpdate: JsonObject = {
      email: profile.email,
      email_confirm: true,
      user_metadata: {
        username: profile.username,
        full_name: profile.full_name,
      },
    };
    if (password) authUpdate.password = password;
    await adminAuthRequest(baseUrl, `/users/${targetId}`, "PUT", authUpdate);

    const rows = await profileRequest(
      baseUrl,
      session,
      `system_users?auth_user_id=eq.${encodeURIComponent(targetId)}`,
      "PATCH",
      {
        username: profile.username,
        full_name: profile.full_name,
        email: profile.email,
        active: profile.active,
        permissions: JSON.stringify(profile.permissions),
        updated_at: new Date().toISOString(),
      },
    );
    if (!rows[0]) throw new HttpError(502, "O perfil atualizado nao foi devolvido pelo banco.");
    return json(200, { profile: publicProfile(rows[0]) });
  } catch (error) {
    if (error instanceof HttpError) return json(error.status, { error: error.message });
    return json(500, { error: "Falha interna ao gerenciar o usuario." });
  }
});
