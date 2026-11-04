-- Execute este arquivo uma unica vez no SQL Editor do Supabase, depois de
-- criar o usuario em Authentication > Users. Troque somente o e-mail abaixo.
-- Nenhuma senha e gravada nas tabelas publicas.

DO $$
DECLARE
  v_admin_email TEXT := 'pedri12345barreto17@gmail.com';
  v_auth_user_id UUID;
  v_auth_email TEXT;
  v_profile_id BIGINT;
  v_conflicting_profile_id BIGINT;
  v_now TEXT := to_char(
    clock_timestamp() AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  );
BEGIN
  IF position('@' IN v_admin_email) = 0 THEN
    RAISE EXCEPTION 'pedri12345barreto17@gmail.com > Users.';
  END IF;

  SELECT id, email
    INTO v_auth_user_id, v_auth_email
    FROM auth.users
   WHERE lower(email) = lower(trim(v_admin_email))
   ORDER BY created_at
   LIMIT 1;

  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma conta Auth encontrada para o e-mail informado.';
  END IF;

  -- Serializa a escolha do perfil e a verificacao de administradores existentes.
  LOCK TABLE public.system_users IN SHARE ROW EXCLUSIVE MODE;

  SELECT id
    INTO v_profile_id
    FROM public.system_users
   WHERE auth_user_id = v_auth_user_id
      OR lower(username) = 'admin'
   ORDER BY CASE WHEN auth_user_id = v_auth_user_id THEN 0 ELSE 1 END, id
   LIMIT 1;

  SELECT id
    INTO v_conflicting_profile_id
    FROM public.system_users
   WHERE (auth_user_id = v_auth_user_id OR lower(username) = 'admin')
     AND id IS DISTINCT FROM v_profile_id
   LIMIT 1;

  IF v_conflicting_profile_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ha perfis conflitantes para esta conta ou para o usuario admin.';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.system_users
     WHERE id = v_profile_id
       AND auth_user_id IS NOT NULL
       AND auth_user_id IS DISTINCT FROM v_auth_user_id
  ) THEN
    RAISE EXCEPTION 'O perfil admin ja esta vinculado a outra conta Auth. Operacao cancelada.';
  END IF;

  -- Somente o perfil alvo pode ser reaproveitado: o da mesma conta Auth ou
  -- o usuario admin legado sem vinculo. Outros administradores ativos bloqueiam.
  IF EXISTS (
    SELECT 1
      FROM public.system_users
     WHERE is_admin = 1
       AND active = 1
       AND id IS DISTINCT FROM v_profile_id
  ) THEN
    RAISE EXCEPTION 'Ja existe outro administrador ativo. Operacao cancelada.';
  END IF;

  IF v_profile_id IS NULL THEN
    INSERT INTO public.system_users (
      username,
      full_name,
      email,
      auth_user_id,
      is_admin,
      active,
      permissions,
      created_at,
      updated_at
    ) VALUES (
      'admin',
      'Administrador',
      v_auth_email,
      v_auth_user_id,
      1,
      1,
      '[]',
      v_now,
      v_now
    );
  ELSE
    UPDATE public.system_users
       SET full_name = CASE
             WHEN trim(full_name) = '' THEN 'Administrador'
             ELSE full_name
           END,
           email = v_auth_email,
           auth_user_id = v_auth_user_id,
           is_admin = 1,
           active = 1,
           permissions = '[]',
           updated_at = v_now
     WHERE id = v_profile_id;
  END IF;

  RAISE NOTICE 'Administrador vinculado com sucesso ao Supabase Auth.';
END
$$;
