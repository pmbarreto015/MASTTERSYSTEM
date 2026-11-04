# Orçamentos, OS e financeiro

Na tela Venda, o sistema pede confirmação: **Orçamento** ou **OS — venda aceita**.
Orçamento pode ficar sem data de entrega e não gera ordem de produção, contas
a receber, comissão nem totais de venda. Em Pedidos, use Aprovar orçamento
ou altere o tipo para OS na edição para registrar o aceite.

Na edição de Pedidos também é possível voltar uma OS para Orçamento. O sistema
cancela os títulos em aberto e conserva o histórico. Havendo recebimento com
valor positivo, essa conversão é bloqueada para preservar o pagamento.
Um novo aceite cria títulos ativos sem reutilizar os cancelados.

O Financeiro permite selecionar mês atual, mês anterior, hoje, últimos 7 ou 30
dias, datas personalizadas ou todo o histórico, além de filtrar por cliente.
Mostra recebimentos, despesas pagas, saldos, contas em aberto, atrasos, vendas
aceitas e ticket médio. As tabelas detalham totais por mês, por dia, por cliente
e cliente/mês. O ticket é o total vendido dividido pela quantidade de OS aceitas;
parcelas não multiplicam a quantidade de vendas.

Os períodos dos lançamentos financeiros usam **vencimento**; os períodos de
vendas e ticket usam **criação da OS**. O sistema ainda não registra uma data
separada de recebimento para cada pagamento, portanto os valores recebidos
são agrupados pelo vencimento dos títulos, não pela data efetiva do caixa.
Os filtros de tipo, status, categoria e busca refinam a lista de lançamentos;
o resumo segue apenas período e cliente. Títulos cancelados ficam disponíveis
no filtro Cancelados e não entram nos totais.

O menu funciona como gaveta no PC e no celular, pelo botão de três linhas.

## Atualizar o projeto Supabase existente

Antes de instalar estas versões, execute **03_atualizar_orcamentos.sql** do
pacote de atualização no SQL Editor do projeto já configurado. Esse arquivo
reúne somente `20261009000000_accepted_sales.sql` em uma transação. Não execute
novamente a instalação inicial: suas tabelas já existem. A atualização conserva
clientes, pedidos, contas e usuários. Faça uma cópia de segurança antes.

No modo SQLite local, estas regras acompanham o aplicativo; não há SQL externo
a executar. PC e celular devem usar a mesma versão atualizada.
