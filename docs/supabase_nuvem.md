# Mesmo banco no PC e no celular com Supabase

O MatterdiSistem pode usar o PostgreSQL do Supabase como banco central. Nesse
modo, PC e celular enxergam os mesmos dados pela internet e o PC pode ficar
desligado.

O aplicativo está preparado com:

- URL: `https://fxaktapjvbakbitsxbjl.supabase.co`
- chave pública Publishable recebida para esse projeto
- login por e-mail e senha no Supabase Auth
- políticas RLS por usuário e pelas permissões do MatterdiSistem
- operações atômicas para pedidos, estoque, financeiro, agenda, composições e
  holerites

A chave Publishable pode acompanhar o aplicativo. Nunca coloque uma Secret key
ou `service_role` no aplicativo, no APK ou em arquivos distribuídos.

A instalação no painel ainda precisa ser concluída pelo dono do projeto.

## 1. Instalar o banco no projeto Supabase

No painel do Supabase, abra **SQL Editor** e execute as migrações abaixo nesta
ordem:

1. `supabase/migrations/20261003000000_initial_schema.sql`
2. `supabase/migrations/20261006000000_auth_permissions.sql`
3. `supabase/migrations/20261006010000_data_api.sql`
4. `supabase/migrations/20261006020000_business_rpc.sql`
5. `supabase/migrations/20261009000000_accepted_sales.sql`
6. `supabase/migrations/20261024000000_erp_modules.sql`

O pacote de distribuição reúne essas migrações no arquivo
`01_instalar_banco.sql`. A instalação ativa RLS; conexões anônimas não leem nem
alteram os dados.

## 2. Levar os dados atuais do SQLite

Abra o banco na versão atual do MatterdiSistem antes de exportar. No terminal,
na pasta do projeto, execute:

```powershell
dart run tool/exportar_sqlite_supabase.dart `
  --database "C:\caminho\matterdi_sistem.db" `
  --output "importar_dados.sql"
```

Revise e execute `importar_dados.sql` no **SQL Editor**. O arquivo preserva os
IDs e reajusta as sequências do PostgreSQL. Ele não exporta `system_users`,
senhas ou hashes de senha. A importação espera um projeto vazio; se já houver
registros conflitantes, a transação inteira falha sem deixar uma carga parcial.

## 3. Criar o primeiro administrador

Siga [Ativação segura do primeiro administrador](supabase_primeiro_admin.md).
Crie a conta em **Authentication > Users** com um e-mail confirmado e uma senha
nova. Depois execute `tool/supabase_bootstrap_admin.sql`, trocando somente o
e-mail indicado no arquivo.

As senhas antigas do banco local não são reutilizadas. Depois do primeiro
acesso, o administrador cria os demais usuários pela tela **Configurações >
Usuários e permissões**.

## 4. Publicar a função de usuários

A função `supabase/functions/matterdi-users/index.ts` cria, atualiza e exclui
contas Auth somente quando a chamada vem de um administrador ativo. Você também pode publicar pelo painel em **Edge Functions > Deploy a new function >
Via Editor**. Use o nome `matterdi-users`, cole o conteúdo do arquivo
`supabase/functions/matterdi-users/index.ts` e publique, mantendo a validação JWT.
Veja o [guia oficial](https://supabase.com/docs/guides/functions/quickstart-dashboard).

Para publicá-la com a CLI oficial:

```powershell
supabase login
supabase link --project-ref fxaktapjvbakbitsxbjl
supabase functions deploy matterdi-users
```

Se o cadastro de usuários falhar e o endpoint retornar `404 NOT_FOUND`, falta
publicar essa função. Executar os arquivos SQL cria as tabelas, mas a publicação
em **Edge Functions** é uma etapa separada. Veja o passo a passo em
[cadastro_usuarios_supabase.md](cadastro_usuarios_supabase.md).

As chaves privadas ficam no ambiente gerenciado da função. Não copie essas
chaves para o PC ou celular.

## 5. Configurar os aplicativos

No PC e no celular, abra **Conexão com o banco**, escolha **Supabase
(internet)** e toque em **Testar Supabase**. A URL e a chave pública deste
projeto já aparecem preenchidas. Salve e entre com o e-mail e a senha criados
no Supabase Auth.

Se o teste informar que as tabelas do MatterdiSistem ainda não foram
instaladas, volte ao passo 1. Backups do arquivo `.db` não se aplicam ao modo
Supabase; use os recursos de backup do próprio projeto Supabase.

Quem já usava o Supabase antes desta versão deve executar somente a atualização
de módulos v28 explicada em [Atualização ERP v28](atualizacao_erp_v28.md).
