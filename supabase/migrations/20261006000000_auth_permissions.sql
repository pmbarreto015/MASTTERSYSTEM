-- Autenticacao e autorizacao do MatterdiSistem no Supabase.
--
-- Cada sessao do aplicativo precisa existir em auth.users e estar vinculada a
-- um perfil ativo de public.system_users. A chave publica do projeto identifica
-- o aplicativo; auth.uid() identifica o usuario que realmente fez login.

CREATE OR REPLACE FUNCTION public.matterdi_permissions_has(
  permissions_text TEXT,
  permission_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  permissions_json JSONB;
BEGIN
  IF permissions_text IS NULL OR permission_key IS NULL OR permission_key = '' THEN
    RETURN FALSE;
  END IF;

  permissions_json := permissions_text::JSONB;
  RETURN jsonb_typeof(permissions_json) = 'array'
    AND permissions_json ? permission_key;
EXCEPTION
  WHEN invalid_text_representation OR data_exception THEN
    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_permissions_has_any(
  permissions_text TEXT,
  permission_keys TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  permissions_json JSONB;
BEGIN
  IF permissions_text IS NULL
     OR permission_keys IS NULL
     OR cardinality(permission_keys) = 0 THEN
    RETURN FALSE;
  END IF;

  permissions_json := permissions_text::JSONB;
  RETURN jsonb_typeof(permissions_json) = 'array'
    AND permissions_json ?| permission_keys;
EXCEPTION
  WHEN invalid_text_representation OR data_exception THEN
    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_is_active_user()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.system_users AS profile
     WHERE profile.auth_user_id = (SELECT auth.uid())
       AND profile.active = 1
  );
$$;

CREATE OR REPLACE FUNCTION public.matterdi_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.system_users AS profile
     WHERE profile.auth_user_id = (SELECT auth.uid())
       AND profile.active = 1
       AND profile.is_admin = 1
  );
$$;

CREATE OR REPLACE FUNCTION public.matterdi_has_permission(permission_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN permission_key IS NULL OR permission_key = '' THEN FALSE
    ELSE EXISTS (
      SELECT 1
        FROM public.system_users AS profile
       WHERE profile.auth_user_id = (SELECT auth.uid())
         AND profile.active = 1
         AND (
           profile.is_admin = 1
           OR public.matterdi_permissions_has(
                profile.permissions,
                permission_key
              )
         )
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_has_any_permission(
  permission_keys TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN permission_keys IS NULL OR cardinality(permission_keys) = 0 THEN FALSE
    ELSE EXISTS (
      SELECT 1
        FROM public.system_users AS profile
       WHERE profile.auth_user_id = (SELECT auth.uid())
         AND profile.active = 1
         AND (
           profile.is_admin = 1
           OR public.matterdi_permissions_has_any(
                profile.permissions,
                permission_keys
              )
         )
    )
  END;
$$;

-- Estes helpers leem system_users como proprietario para evitar recursao nas
-- policies dessa propria tabela. Eles devolvem apenas booleanos.
REVOKE ALL ON FUNCTION public.matterdi_permissions_has(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.matterdi_permissions_has_any(TEXT, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.matterdi_is_active_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.matterdi_is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.matterdi_has_permission(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.matterdi_has_any_permission(TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.matterdi_permissions_has(TEXT, TEXT) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.matterdi_permissions_has_any(TEXT, TEXT[]) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.matterdi_is_active_user() FROM anon;
REVOKE ALL ON FUNCTION public.matterdi_is_admin() FROM anon;
REVOKE ALL ON FUNCTION public.matterdi_has_permission(TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.matterdi_has_any_permission(TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.matterdi_is_active_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_has_permission(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_has_any_permission(TEXT[]) TO authenticated;

-- Mantem o documento de permissoes consistente mesmo se um administrador usar
-- o Data API diretamente.
ALTER TABLE public.system_users
  DROP CONSTRAINT IF EXISTS system_users_is_admin_check;
ALTER TABLE public.system_users
  ADD CONSTRAINT system_users_is_admin_check CHECK (is_admin IN (0, 1));
ALTER TABLE public.system_users
  DROP CONSTRAINT IF EXISTS system_users_active_check;
ALTER TABLE public.system_users
  ADD CONSTRAINT system_users_active_check CHECK (active IN (0, 1));
ALTER TABLE public.system_users
  DROP CONSTRAINT IF EXISTS system_users_permissions_check;
ALTER TABLE public.system_users
  ADD CONSTRAINT system_users_permissions_check
  CHECK (
    permissions IS NOT NULL
    AND jsonb_typeof(permissions::JSONB) = 'array'
  );

CREATE OR REPLACE FUNCTION public.matterdi_keep_auth_link()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  -- Permite vincular uma unica vez um perfil legado ainda sem auth_user_id.
  -- Depois do vinculo, somente a exclusao em cascata de auth.users o remove.
  IF OLD.auth_user_id IS NOT NULL
     AND NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
    RAISE EXCEPTION 'O vinculo do perfil com o Supabase Auth nao pode ser alterado.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_system_users_keep_auth_link ON public.system_users;
CREATE TRIGGER trg_system_users_keep_auth_link
BEFORE UPDATE OF auth_user_id ON public.system_users
FOR EACH ROW
EXECUTE FUNCTION public.matterdi_keep_auth_link();

REVOKE ALL ON FUNCTION public.matterdi_keep_auth_link() FROM PUBLIC, anon, authenticated;

-- A role anon pode somente executar a funcao de health criada pela migracao do
-- Data API. Nenhuma tabela ou sequence de negocio fica acessivel sem login.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

-- Perfis: cada usuario ativo ve o proprio perfil; administradores ativos veem
-- a lista. Somente administradores podem alterar perfis pelo Data API.
DROP POLICY IF EXISTS system_users_select ON public.system_users;
CREATE POLICY system_users_select ON public.system_users
FOR SELECT TO authenticated
USING (
  (
    auth_user_id = (SELECT auth.uid())
    AND active = 1
  )
  OR public.matterdi_is_admin()
);

DROP POLICY IF EXISTS system_users_insert ON public.system_users;
CREATE POLICY system_users_insert ON public.system_users
FOR INSERT TO authenticated
WITH CHECK (
  public.matterdi_is_admin()
  AND auth_user_id IS NOT NULL
  AND is_admin = 0
);

DROP POLICY IF EXISTS system_users_update ON public.system_users;
CREATE POLICY system_users_update ON public.system_users
FOR UPDATE TO authenticated
USING (public.matterdi_is_admin())
WITH CHECK (
  public.matterdi_is_admin()
  AND auth_user_id IS NOT NULL
  AND (
    auth_user_id <> (SELECT auth.uid())
    OR (is_admin = 1 AND active = 1)
  )
);

DROP POLICY IF EXISTS system_users_delete ON public.system_users;
CREATE POLICY system_users_delete ON public.system_users
FOR DELETE TO authenticated
USING (
  public.matterdi_is_admin()
  AND is_admin = 0
  AND auth_user_id <> (SELECT auth.uid())
);

-- Clientes -------------------------------------------------------------------
DROP POLICY IF EXISTS customers_select ON public.customers;
CREATE POLICY customers_select ON public.customers FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'dashboard', 'clientes', 'vendas', 'orcamentos', 'producao',
  'financeiro', 'relatorios', 'rentabilidade', 'arquivos', 'corte_compositor'
]));
DROP POLICY IF EXISTS customers_insert ON public.customers;
CREATE POLICY customers_insert ON public.customers FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['clientes', 'arquivos']));
DROP POLICY IF EXISTS customers_update ON public.customers;
CREATE POLICY customers_update ON public.customers FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['clientes', 'vendas', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['clientes', 'vendas', 'arquivos']));
DROP POLICY IF EXISTS customers_delete ON public.customers;
CREATE POLICY customers_delete ON public.customers FOR DELETE TO authenticated
USING (public.matterdi_has_permission('clientes'));

-- Produtos, insumos e estoque -------------------------------------------------
DROP POLICY IF EXISTS products_select ON public.products;
CREATE POLICY products_select ON public.products FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'dashboard', 'produtos', 'vendas', 'orcamentos', 'producao', 'estoque',
  'relatorios', 'rentabilidade', 'arquivos', 'corte_compositor',
  'corte_aproveitamento'
]));
DROP POLICY IF EXISTS products_insert ON public.products;
CREATE POLICY products_insert ON public.products FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['produtos', 'arquivos']));
DROP POLICY IF EXISTS products_update ON public.products;
CREATE POLICY products_update ON public.products FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['produtos', 'estoque', 'arquivos', 'corte_compositor']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['produtos', 'estoque', 'arquivos', 'corte_compositor']));
DROP POLICY IF EXISTS products_delete ON public.products;
CREATE POLICY products_delete ON public.products FOR DELETE TO authenticated
USING (public.matterdi_has_permission('produtos'));

DROP POLICY IF EXISTS insumos_select ON public.insumos;
CREATE POLICY insumos_select ON public.insumos FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['estoque', 'producao', 'relatorios', 'arquivos']));
DROP POLICY IF EXISTS insumos_insert ON public.insumos;
CREATE POLICY insumos_insert ON public.insumos FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['estoque', 'arquivos']));
DROP POLICY IF EXISTS insumos_update ON public.insumos;
CREATE POLICY insumos_update ON public.insumos FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['estoque', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['estoque', 'arquivos']));
DROP POLICY IF EXISTS insumos_delete ON public.insumos;
CREATE POLICY insumos_delete ON public.insumos FOR DELETE TO authenticated
USING (public.matterdi_has_permission('estoque'));

DROP POLICY IF EXISTS stock_movements_select ON public.stock_movements;
CREATE POLICY stock_movements_select ON public.stock_movements FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['estoque', 'producao', 'relatorios', 'rentabilidade']));
DROP POLICY IF EXISTS stock_movements_insert ON public.stock_movements;
CREATE POLICY stock_movements_insert ON public.stock_movements FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_permission('estoque'));
DROP POLICY IF EXISTS stock_movements_update ON public.stock_movements;
CREATE POLICY stock_movements_update ON public.stock_movements FOR UPDATE TO authenticated
USING (public.matterdi_has_permission('estoque'))
WITH CHECK (public.matterdi_has_permission('estoque'));
DROP POLICY IF EXISTS stock_movements_delete ON public.stock_movements;
CREATE POLICY stock_movements_delete ON public.stock_movements FOR DELETE TO authenticated
USING (public.matterdi_has_permission('estoque'));

-- Comercial ------------------------------------------------------------------
DROP POLICY IF EXISTS sellers_select ON public.sellers;
CREATE POLICY sellers_select ON public.sellers FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'dashboard', 'vendedores', 'vendas', 'orcamentos', 'producao',
  'relatorios', 'rentabilidade', 'arquivos'
]));
DROP POLICY IF EXISTS sellers_insert ON public.sellers;
CREATE POLICY sellers_insert ON public.sellers FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['vendedores', 'arquivos']));
DROP POLICY IF EXISTS sellers_update ON public.sellers;
CREATE POLICY sellers_update ON public.sellers FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['vendedores', 'vendas', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['vendedores', 'vendas', 'arquivos']));
DROP POLICY IF EXISTS sellers_delete ON public.sellers;
CREATE POLICY sellers_delete ON public.sellers FOR DELETE TO authenticated
USING (public.matterdi_has_permission('vendedores'));

DROP POLICY IF EXISTS suppliers_select ON public.suppliers;
CREATE POLICY suppliers_select ON public.suppliers FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['fornecedores', 'estoque', 'producao', 'relatorios', 'arquivos']));
DROP POLICY IF EXISTS suppliers_insert ON public.suppliers;
CREATE POLICY suppliers_insert ON public.suppliers FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['fornecedores', 'arquivos']));
DROP POLICY IF EXISTS suppliers_update ON public.suppliers;
CREATE POLICY suppliers_update ON public.suppliers FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['fornecedores', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['fornecedores', 'arquivos']));
DROP POLICY IF EXISTS suppliers_delete ON public.suppliers;
CREATE POLICY suppliers_delete ON public.suppliers FOR DELETE TO authenticated
USING (public.matterdi_has_permission('fornecedores'));

DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY orders_select ON public.orders FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'dashboard', 'vendas', 'orcamentos', 'producao', 'financeiro',
  'relatorios', 'rentabilidade', 'arquivos'
]));
DROP POLICY IF EXISTS orders_insert ON public.orders;
CREATE POLICY orders_insert ON public.orders FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['vendas', 'orcamentos', 'arquivos']));
DROP POLICY IF EXISTS orders_update ON public.orders;
CREATE POLICY orders_update ON public.orders FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'vendas', 'orcamentos', 'producao', 'pedidos_alterar', 'pedidos_reabrir', 'arquivos'
]))
WITH CHECK (public.matterdi_has_any_permission(ARRAY[
  'vendas', 'orcamentos', 'producao', 'pedidos_alterar', 'pedidos_reabrir', 'arquivos'
]));
DROP POLICY IF EXISTS orders_delete ON public.orders;
CREATE POLICY orders_delete ON public.orders FOR DELETE TO authenticated
USING (public.matterdi_has_permission('pedidos_excluir'));

DROP POLICY IF EXISTS order_items_select ON public.order_items;
CREATE POLICY order_items_select ON public.order_items FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'dashboard', 'vendas', 'orcamentos', 'producao', 'financeiro',
  'relatorios', 'rentabilidade', 'arquivos'
]));
DROP POLICY IF EXISTS order_items_insert ON public.order_items;
CREATE POLICY order_items_insert ON public.order_items FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['vendas', 'orcamentos', 'pedidos_alterar', 'arquivos']));
DROP POLICY IF EXISTS order_items_update ON public.order_items;
CREATE POLICY order_items_update ON public.order_items FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['vendas', 'orcamentos', 'pedidos_alterar', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['vendas', 'orcamentos', 'pedidos_alterar', 'arquivos']));
DROP POLICY IF EXISTS order_items_delete ON public.order_items;
CREATE POLICY order_items_delete ON public.order_items FOR DELETE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['pedidos_alterar', 'pedidos_excluir']));

-- Financeiro e funcionarios ---------------------------------------------------
DROP POLICY IF EXISTS financial_select ON public.financial;
CREATE POLICY financial_select ON public.financial FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'dashboard', 'financeiro', 'vendas', 'relatorios', 'rentabilidade', 'arquivos'
]));
DROP POLICY IF EXISTS financial_insert ON public.financial;
CREATE POLICY financial_insert ON public.financial FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['financeiro', 'arquivos']));
DROP POLICY IF EXISTS financial_update ON public.financial;
CREATE POLICY financial_update ON public.financial FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['financeiro', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['financeiro', 'arquivos']));
DROP POLICY IF EXISTS financial_delete ON public.financial;
CREATE POLICY financial_delete ON public.financial FOR DELETE TO authenticated
USING (public.matterdi_has_permission('financeiro'));

DROP POLICY IF EXISTS employees_select ON public.employees;
CREATE POLICY employees_select ON public.employees FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['funcionarios', 'financeiro', 'relatorios']));
DROP POLICY IF EXISTS employees_insert ON public.employees;
CREATE POLICY employees_insert ON public.employees FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_permission('funcionarios'));
DROP POLICY IF EXISTS employees_update ON public.employees;
CREATE POLICY employees_update ON public.employees FOR UPDATE TO authenticated
USING (public.matterdi_has_permission('funcionarios'))
WITH CHECK (public.matterdi_has_permission('funcionarios'));
DROP POLICY IF EXISTS employees_delete ON public.employees;
CREATE POLICY employees_delete ON public.employees FOR DELETE TO authenticated
USING (public.matterdi_has_permission('funcionarios'));

DROP POLICY IF EXISTS pontos_select ON public.pontos;
CREATE POLICY pontos_select ON public.pontos FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['funcionarios', 'relatorios']));
DROP POLICY IF EXISTS pontos_insert ON public.pontos;
CREATE POLICY pontos_insert ON public.pontos FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_permission('funcionarios'));
DROP POLICY IF EXISTS pontos_update ON public.pontos;
CREATE POLICY pontos_update ON public.pontos FOR UPDATE TO authenticated
USING (public.matterdi_has_permission('funcionarios'))
WITH CHECK (public.matterdi_has_permission('funcionarios'));
DROP POLICY IF EXISTS pontos_delete ON public.pontos;
CREATE POLICY pontos_delete ON public.pontos FOR DELETE TO authenticated
USING (public.matterdi_has_permission('funcionarios'));

DROP POLICY IF EXISTS holerites_select ON public.holerites;
CREATE POLICY holerites_select ON public.holerites FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['funcionarios', 'financeiro', 'relatorios']));
DROP POLICY IF EXISTS holerites_insert ON public.holerites;
CREATE POLICY holerites_insert ON public.holerites FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_permission('funcionarios'));
DROP POLICY IF EXISTS holerites_update ON public.holerites;
CREATE POLICY holerites_update ON public.holerites FOR UPDATE TO authenticated
USING (public.matterdi_has_permission('funcionarios'))
WITH CHECK (public.matterdi_has_permission('funcionarios'));
DROP POLICY IF EXISTS holerites_delete ON public.holerites;
CREATE POLICY holerites_delete ON public.holerites FOR DELETE TO authenticated
USING (public.matterdi_has_permission('funcionarios'));

-- Agenda ---------------------------------------------------------------------
DROP POLICY IF EXISTS agenda_followups_select ON public.agenda_followups;
CREATE POLICY agenda_followups_select ON public.agenda_followups FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['agenda', 'dashboard']));
DROP POLICY IF EXISTS agenda_followups_insert ON public.agenda_followups;
CREATE POLICY agenda_followups_insert ON public.agenda_followups FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_permission('agenda'));
DROP POLICY IF EXISTS agenda_followups_update ON public.agenda_followups;
CREATE POLICY agenda_followups_update ON public.agenda_followups FOR UPDATE TO authenticated
USING (public.matterdi_has_permission('agenda'))
WITH CHECK (public.matterdi_has_permission('agenda'));
DROP POLICY IF EXISTS agenda_followups_delete ON public.agenda_followups;
CREATE POLICY agenda_followups_delete ON public.agenda_followups FOR DELETE TO authenticated
USING (public.matterdi_has_permission('agenda'));

-- Corte a laser ---------------------------------------------------------------
DROP POLICY IF EXISTS materiais_select ON public.materiais;
CREATE POLICY materiais_select ON public.materiais FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'estoque', 'orcamentos', 'producao', 'relatorios', 'corte_materiais',
  'corte_compositor', 'corte_retalhos', 'corte_aproveitamento'
]));
DROP POLICY IF EXISTS materiais_insert ON public.materiais;
CREATE POLICY materiais_insert ON public.materiais FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['estoque', 'corte_materiais', 'arquivos']));
DROP POLICY IF EXISTS materiais_update ON public.materiais;
CREATE POLICY materiais_update ON public.materiais FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['estoque', 'corte_materiais', 'arquivos']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['estoque', 'corte_materiais', 'arquivos']));
DROP POLICY IF EXISTS materiais_delete ON public.materiais;
CREATE POLICY materiais_delete ON public.materiais FOR DELETE TO authenticated
USING (public.matterdi_has_permission('corte_materiais'));

DROP POLICY IF EXISTS maquinas_select ON public.maquinas;
CREATE POLICY maquinas_select ON public.maquinas FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'orcamentos', 'producao', 'relatorios', 'corte_maquinas', 'corte_compositor'
]));
DROP POLICY IF EXISTS maquinas_insert ON public.maquinas;
CREATE POLICY maquinas_insert ON public.maquinas FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_permission('corte_maquinas'));
DROP POLICY IF EXISTS maquinas_update ON public.maquinas;
CREATE POLICY maquinas_update ON public.maquinas FOR UPDATE TO authenticated
USING (public.matterdi_has_permission('corte_maquinas'))
WITH CHECK (public.matterdi_has_permission('corte_maquinas'));
DROP POLICY IF EXISTS maquinas_delete ON public.maquinas;
CREATE POLICY maquinas_delete ON public.maquinas FOR DELETE TO authenticated
USING (public.matterdi_has_permission('corte_maquinas'));

DROP POLICY IF EXISTS retalhos_select ON public.retalhos;
CREATE POLICY retalhos_select ON public.retalhos FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'orcamentos', 'producao', 'relatorios', 'corte_retalhos',
  'corte_compositor', 'corte_aproveitamento'
]));
DROP POLICY IF EXISTS retalhos_insert ON public.retalhos;
CREATE POLICY retalhos_insert ON public.retalhos FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['corte_retalhos', 'corte_compositor', 'corte_aproveitamento']));
DROP POLICY IF EXISTS retalhos_update ON public.retalhos;
CREATE POLICY retalhos_update ON public.retalhos FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['corte_retalhos', 'corte_compositor', 'corte_aproveitamento']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['corte_retalhos', 'corte_compositor', 'corte_aproveitamento']));
DROP POLICY IF EXISTS retalhos_delete ON public.retalhos;
CREATE POLICY retalhos_delete ON public.retalhos FOR DELETE TO authenticated
USING (public.matterdi_has_permission('corte_retalhos'));

DROP POLICY IF EXISTS composicoes_select ON public.composicoes;
CREATE POLICY composicoes_select ON public.composicoes FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'produtos', 'vendas', 'orcamentos', 'producao', 'relatorios',
  'rentabilidade', 'corte_compositor'
]));
DROP POLICY IF EXISTS composicoes_insert ON public.composicoes;
CREATE POLICY composicoes_insert ON public.composicoes FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']));
DROP POLICY IF EXISTS composicoes_update ON public.composicoes;
CREATE POLICY composicoes_update ON public.composicoes FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']));
DROP POLICY IF EXISTS composicoes_delete ON public.composicoes;
CREATE POLICY composicoes_delete ON public.composicoes FOR DELETE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']));

DROP POLICY IF EXISTS composicao_itens_select ON public.composicao_itens;
CREATE POLICY composicao_itens_select ON public.composicao_itens FOR SELECT TO authenticated
USING (public.matterdi_has_any_permission(ARRAY[
  'produtos', 'vendas', 'orcamentos', 'producao', 'relatorios',
  'rentabilidade', 'corte_compositor'
]));
DROP POLICY IF EXISTS composicao_itens_insert ON public.composicao_itens;
CREATE POLICY composicao_itens_insert ON public.composicao_itens FOR INSERT TO authenticated
WITH CHECK (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']));
DROP POLICY IF EXISTS composicao_itens_update ON public.composicao_itens;
CREATE POLICY composicao_itens_update ON public.composicao_itens FOR UPDATE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']))
WITH CHECK (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']));
DROP POLICY IF EXISTS composicao_itens_delete ON public.composicao_itens;
CREATE POLICY composicao_itens_delete ON public.composicao_itens FOR DELETE TO authenticated
USING (public.matterdi_has_any_permission(ARRAY['produtos', 'corte_compositor']));
