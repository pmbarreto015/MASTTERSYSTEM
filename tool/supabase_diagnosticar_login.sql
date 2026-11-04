-- Execute no SQL Editor do mesmo projeto configurado no aplicativo.
-- Somente leitura: nao altera contas, senhas, perfis ou permissoes.
-- A tabela public.system_users deve existir (migracoes do sistema instaladas).
-- Envie somente o valor da coluna diagnostico para verificar o proximo passo.

WITH conta AS (
  SELECT id, email_confirmed_at
    FROM auth.users
   WHERE lower(email) = lower('pedri12345barreto17@gmail.com')
   ORDER BY created_at
   LIMIT 1
), perfil AS (
  SELECT id, active
    FROM public.system_users
   WHERE auth_user_id = (SELECT id FROM conta)
   ORDER BY id
   LIMIT 1
)
SELECT
  CASE
    WHEN conta.id IS NULL THEN 'EMAIL_NAO_CADASTRADO_NO_AUTH'
    WHEN conta.email_confirmed_at IS NULL THEN 'EMAIL_NAO_CONFIRMADO'
    WHEN perfil.id IS NOT NULL AND perfil.active IS DISTINCT FROM 1
      THEN 'CADASTRO_DO_SISTEMA_BLOQUEADO'
    WHEN perfil.id IS NOT NULL THEN 'PERFIL_ATIVO_VERIFICAR_PERMISSOES'
    WHEN EXISTS (
      SELECT 1 FROM public.system_users
       WHERE lower(username) = 'admin'
         AND auth_user_id IS NOT NULL
         AND auth_user_id <> conta.id
    ) THEN 'ADMIN_VINCULADO_A_OUTRA_CONTA'
    WHEN EXISTS (
      SELECT 1 FROM public.system_users
       WHERE is_admin = 1 AND active = 1
         AND (lower(username) <> 'admin' OR auth_user_id IS NOT NULL)
    ) THEN 'OUTRO_ADMINISTRADOR_ATIVO'
    WHEN EXISTS (
      SELECT 1 FROM public.system_users
       WHERE lower(username) = 'admin' AND auth_user_id IS NULL
    ) THEN 'FALTA_VINCULAR_ADMIN_LEGADO'
    ELSE 'FALTA_CRIAR_PERFIL_DO_SISTEMA'
  END AS diagnostico
FROM (SELECT 1) AS unico
LEFT JOIN conta ON true
LEFT JOIN perfil ON true;
