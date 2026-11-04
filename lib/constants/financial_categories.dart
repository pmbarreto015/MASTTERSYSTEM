import 'package:flutter/material.dart';

class FinancialCategories {
  static const Map<String, Map<String, dynamic>> categorias = {
    'vendas': {
      'label': 'Vendas',
      'icon': Icons.shopping_cart,
      'color': Colors.green,
      'subcategorias': ['Venda direta', 'Orçamento', 'OS'],
    },
    'materiais': {
      'label': 'Materiais',
      'icon': Icons.inventory,
      'color': Colors.blue,
      'subcategorias': [
        'Papel',
        'Tinta',
        'DTF',
        'Sublimação',
        'Vinil',
        'Adesivo',
        'Embalagem'
      ],
    },
    'operacional': {
      'label': 'Operacional',
      'icon': Icons.build,
      'color': Colors.orange,
      'subcategorias': ['Energia', 'Água', 'Internet', 'Aluguel', 'Manutenção'],
    },
    'terceirizacao': {
      'label': 'Terceirização',
      'icon': Icons.factory,
      'color': Colors.purple,
      'subcategorias': ['Impressão', 'Corte', 'Bordado', 'Acabamento'],
    },
    'pessoal': {
      'label': 'Pessoal',
      'icon': Icons.people,
      'color': Colors.teal,
      'subcategorias': ['Salários', 'Benefícios', 'Encargos'],
    },
    'marketing': {
      'label': 'Marketing',
      'icon': Icons.campaign,
      'color': Colors.pink,
      'subcategorias': ['Publicidade', 'Redes Sociais', 'Materiais'],
    },
    'entrega': {
      'label': 'Entrega',
      'icon': Icons.local_shipping,
      'color': Colors.cyan,
      'subcategorias': ['Frete', 'Motorista', 'Combustível'],
    },
    'outros': {
      'label': 'Outros',
      'icon': Icons.more_horiz,
      'color': Colors.grey,
      'subcategorias': ['Imprevistos', 'Diversos'],
    },
  };

  static List<String> getCategorias() => categorias.keys.toList();
  static String getLabel(String key) => categorias[key]?['label'] ?? key;
  static IconData getIcon(String key) =>
      categorias[key]?['icon'] ?? Icons.category;
  static Color getColor(String key) => categorias[key]?['color'] ?? Colors.grey;
  static List<String> getSubcategorias(String key) =>
      List<String>.from(categorias[key]?['subcategorias'] ?? []);
}
