import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InsumoModel {
  InsumoModel({
    this.id,
    required this.codigo,
    required this.nome,
    required this.categoria,
    this.quantidade = 0,
    required this.unidade,
    this.precoUnitario = 0,
    this.fornecedor = '',
    this.estoqueMinimo = 0,
    this.estoqueMaximo = 0,
    this.observacoes = '',
    this.active = true,
    String? dataCriacao,
    String? dataAtualizacao,
  })  : dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String();

  factory InsumoModel.fromMap(Map<String, dynamic> map) {
    return InsumoModel(
      id: map['id'],
      codigo: map['codigo'] ?? '',
      nome: map['nome'] ?? '',
      categoria: map['categoria'] ?? 'materiais',
      quantidade: (map['quantidade'] ?? 0).toDouble(),
      unidade: map['unidade'] ?? 'un',
      precoUnitario: (map['preco_unitario'] ?? 0).toDouble(),
      fornecedor: map['fornecedor'] ?? '',
      estoqueMinimo: (map['estoque_minimo'] ?? 0).toDouble(),
      estoqueMaximo: (map['estoque_maximo'] ?? 0).toDouble(),
      observacoes: map['observacoes'] ?? '',
      active: map['active'] == 1,
      dataCriacao: map['created_at'],
      dataAtualizacao: map['updated_at'],
    );
  }

  int? id;
  String codigo;
  String nome;
  String categoria;
  double quantidade;
  String unidade;
  double precoUnitario;
  String fornecedor;
  double estoqueMinimo;
  double estoqueMaximo;
  String observacoes;
  bool active;
  String dataCriacao;
  String dataAtualizacao;

  Map<String, dynamic> toMap() => {
        'id': id,
        'codigo': codigo,
        'nome': nome,
        'categoria': categoria,
        'quantidade': quantidade,
        'unidade': unidade,
        'preco_unitario': precoUnitario,
        'fornecedor': fornecedor,
        'estoque_minimo': estoqueMinimo,
        'estoque_maximo': estoqueMaximo,
        'observacoes': observacoes,
        'active': active ? 1 : 0,
        'created_at': dataCriacao,
        'updated_at': dataAtualizacao,
      };

  InsumoModel copyWith({
    int? id,
    String? codigo,
    String? nome,
    String? categoria,
    double? quantidade,
    String? unidade,
    double? precoUnitario,
    String? fornecedor,
    double? estoqueMinimo,
    double? estoqueMaximo,
    String? observacoes,
    bool? active,
    String? dataCriacao,
    String? dataAtualizacao,
  }) {
    return InsumoModel(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      quantidade: quantidade ?? this.quantidade,
      unidade: unidade ?? this.unidade,
      precoUnitario: precoUnitario ?? this.precoUnitario,
      fornecedor: fornecedor ?? this.fornecedor,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      estoqueMaximo: estoqueMaximo ?? this.estoqueMaximo,
      observacoes: observacoes ?? this.observacoes,
      active: active ?? this.active,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
    );
  }

  String get status {
    if (quantidade <= 0) return 'Esgotado';
    if (quantidade <= estoqueMinimo) return 'Baixo';
    if (estoqueMaximo > 0 && quantidade >= estoqueMaximo) return 'Excedente';
    return 'OK';
  }

  Color get statusColor {
    switch (status) {
      case 'OK':
        return Colors.green;
      case 'Baixo':
        return Colors.orange;
      case 'Esgotado':
        return Colors.red;
      case 'Excedente':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'OK':
        return Icons.check_circle;
      case 'Baixo':
        return Icons.warning;
      case 'Esgotado':
        return Icons.error;
      case 'Excedente':
        return Icons.trending_up;
      default:
        return Icons.help;
    }
  }

  String get valorTotal => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
      .format(quantidade * precoUnitario);

  String get quantidadeFormatada => '${quantidade.toStringAsFixed(0)} $unidade';
}
