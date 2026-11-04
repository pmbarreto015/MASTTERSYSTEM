# Atualização ERP v28 no Supabase

Esta atualização ativa Entregas e Retiradas, os módulos do Financeiro e o RH
profissional no banco Supabase. Ela é necessária somente para quem usa
**Supabase (internet)**; quem usa banco local recebe as tabelas ao abrir a nova
versão do programa.

1. Entre no projeto Supabase `fxaktapjvbakbitsxbjl`.
2. Abra **SQL Editor > New query**.
3. Abra o arquivo
   `supabase/migrations/20261024000000_erp_modules.sql` na pasta do projeto,
   copie todo o conteúdo e execute no SQL Editor.
4. Quando aparecer sucesso, feche e abra o MastterSystem. Em **Configurações >
   Usuários e permissões**, marque **Entregas e retiradas** para os usuários
   que poderão operar a expedição.

A atualização preserva pedidos, clientes, pagamentos e usuários já existentes.
Ela cria registros próprios para Financeiro, RH e Entregas, e restringe cada
área à respectiva permissão. O módulo Entregas recebe apenas os pedidos que já
estão **Finalizados** na produção e somente os saldos financeiros agregados
desses pedidos.

Se o SQL Editor informar que alguma função ou política já existe, execute o
arquivo inteiro novamente: a migração foi preparada para reaplicação.
