import 'package:flutter/material.dart';

class SystemPermission {
  const SystemPermission(this.key, this.label, this.group, this.icon);

  final String key;
  final String label;
  final String group;
  final IconData icon;
}

const systemPermissions = <SystemPermission>[
  SystemPermission('dashboard', 'Dashboard', 'Geral', Icons.dashboard),
  SystemPermission('agenda', 'Agenda', 'Geral', Icons.calendar_month),
  SystemPermission('clientes', 'Clientes', 'Comercial', Icons.people),
  SystemPermission('produtos', 'Produtos', 'Comercial', Icons.inventory_2),
  SystemPermission('vendas', 'Vendas', 'Comercial', Icons.shopping_cart),
  SystemPermission(
    'pedidos_alterar',
    'Alterar pedidos',
    'Comercial',
    Icons.edit_note,
  ),
  SystemPermission(
    'pedidos_reabrir',
    'Reabrir pedidos finalizados ou cancelados',
    'Comercial',
    Icons.lock_open,
  ),
  SystemPermission(
    'pedidos_excluir',
    'Excluir pedidos e dados relacionados',
    'Comercial',
    Icons.delete_forever,
  ),
  SystemPermission(
    'orcamentos',
    'Orçamentos e aprovações',
    'Comercial',
    Icons.request_quote,
  ),
  SystemPermission('producao', 'Produção', 'Operação', Icons.factory),
  SystemPermission(
    'entregas',
    'Entregas e retiradas',
    'Operação',
    Icons.local_shipping_outlined,
  ),
  SystemPermission('estoque', 'Estoque', 'Operação', Icons.inventory),
  SystemPermission('fornecedores', 'Fornecedores', 'Operação', Icons.business),
  SystemPermission('financeiro', 'Financeiro', 'Gestão', Icons.monetization_on),
  SystemPermission('vendedores', 'Vendedores', 'Gestão', Icons.person_outline),
  SystemPermission(
    'funcionarios',
    'RH — Funcionários e ponto',
    'Gestão',
    Icons.people_outline,
  ),
  SystemPermission('relatorios', 'Relatórios', 'Gestão', Icons.assessment),
  SystemPermission('rentabilidade', 'Rentabilidade', 'Gestão', Icons.insights),
  SystemPermission('arquivos', 'Arquivos', 'Gestão', Icons.folder_open),
  SystemPermission(
    'corte_materiais',
    'Corte a Laser — Materiais',
    'Corte a Laser',
    Icons.inventory_2,
  ),
  SystemPermission(
    'corte_maquinas',
    'Corte a Laser — Máquinas',
    'Corte a Laser',
    Icons.precision_manufacturing,
  ),
  SystemPermission(
    'corte_compositor',
    'Corte a Laser — Compositor',
    'Corte a Laser',
    Icons.calculate,
  ),
  SystemPermission(
    'corte_retalhos',
    'Corte a Laser — Retalhos',
    'Corte a Laser',
    Icons.recycling,
  ),
  SystemPermission(
    'corte_aproveitamento',
    'Corte a Laser — Aproveitamento',
    'Corte a Laser',
    Icons.lightbulb,
  ),
  SystemPermission('configuracoes', 'Configurações', 'Sistema', Icons.settings),
  SystemPermission('backup', 'Backup', 'Sistema', Icons.backup),
  SystemPermission('suporte', 'Suporte', 'Sistema', Icons.help_outline),
];
