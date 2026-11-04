# Ativação segura do primeiro administrador

Esta etapa deve ser feita somente depois de aplicar, na ordem, as migrações da
pasta `supabase/migrations`. Ela vincula uma conta do Supabase Auth ao perfil
administrador do MatterdiSistem sem copiar a senha do banco SQLite.

1. No painel do projeto Supabase, abra **Authentication > Users** e crie a conta
   do administrador com o e-mail que será usado para entrar no sistema. Marque o
   e-mail como confirmado e escolha uma senha nova com pelo menos 6 caracteres.
2. Abra `tool/supabase_bootstrap_admin.sql`, troque apenas
   `ALTERE_PARA_O_EMAIL_DO_ADMINISTRADOR` por esse e-mail e execute o arquivo no
   **SQL Editor**. O script recusa continuar se já houver outro administrador
   ativo ou se encontrar perfis conflitantes.
3. Publique a função `matterdi-users` da pasta `supabase/functions`. Ela sempre
   confirma a sessão no Supabase Auth e só aceita chamadas de um administrador
   ativo. As credenciais privadas usadas pela função permanecem no ambiente
   gerenciado do Supabase.
4. No PC e no celular, configure somente a URL do projeto e a chave pública
   `sb_publishable_...`. Depois, entre com o e-mail e a nova senha do passo 1.

Em **Authentication > Providers > Email**, mantenha desativada a criação pública
de contas. Novos funcionários devem ser criados pela tela de usuários do
MatterdiSistem; a função cria a conta Auth e o perfil vinculado como uma única
operação administrativa.

As políticas RLS deixam as tabelas invisíveis para conexões anônimas. Um usuário
autenticado também fica sem acesso quando o perfil está bloqueado. Para usuários
comuns, cada tabela valida as mesmas permissões exibidas em **Configurações >
Usuários e permissões**.
