import 'package:flutter/material.dart';

class ProductModel {
  int? id;
  String codigo;
  String nome;
  double preco;
  double cost;
  String descricao;
  String categoria;
  bool ativo;
  double estoque;
  String unidade;
  String dataCriacao;
  String dataAtualizacao;
  int? composicaoId;

  ProductModel({
    this.id,
    this.codigo = '',
    this.nome = '',
    this.preco = 0,
    this.cost = 0,
    this.descricao = '',
    this.categoria = 'grafica',
    this.ativo = true,
    this.estoque = 0,
    this.unidade = 'un',
    this.composicaoId,
    String? dataCriacao,
    String? dataAtualizacao,
  })  : dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String();

  // FROM MAP
  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'],
      codigo: map['codigo'] ?? '',
      nome: map['nome'] ?? '',
      preco: (map['preco'] ?? 0).toDouble(),
      cost: (map['cost'] ?? 0).toDouble(),
      descricao: map['descricao'] ?? '',
      categoria: map['categoria'] ?? 'grafica',
      ativo: (map['ativo'] ?? 1) == 1,
      estoque: (map['estoque'] ?? 0).toDouble(),
      unidade: map['unidade'] ?? 'un',
      composicaoId: map['composicao_id'],
      dataCriacao: map['created_at'] ?? '',
      dataAtualizacao: map['updated_at'] ?? '',
    );
  }

  // TO MAP
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'nome': nome,
      'preco': preco,
      'cost': cost,
      'descricao': descricao,
      'categoria': categoria,
      'ativo': ativo ? 1 : 0,
      'estoque': estoque,
      'unidade': unidade,
      'composicao_id': composicaoId,
      'created_at': dataCriacao,
      'updated_at': dataAtualizacao,
    };
  }

  // COPY WITH
  ProductModel copyWith({
    int? id,
    String? codigo,
    String? nome,
    double? preco,
    double? cost,
    String? descricao,
    String? categoria,
    bool? ativo,
    double? estoque,
    String? unidade,
    int? composicaoId,
    String? dataCriacao,
    String? dataAtualizacao,
  }) {
    return ProductModel(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nome: nome ?? this.nome,
      preco: preco ?? this.preco,
      cost: cost ?? this.cost,
      descricao: descricao ?? this.descricao,
      categoria: categoria ?? this.categoria,
      ativo: ativo ?? this.ativo,
      estoque: estoque ?? this.estoque,
      unidade: unidade ?? this.unidade,
      composicaoId: composicaoId ?? this.composicaoId,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
    );
  }

  // ============================================================
  // GETTERS (SEM PARÊNTESES - CORRETO)
  // ============================================================

  bool get isCorteLaser => categoria == 'corte_laser';
  bool get isGraficaUn => categoria == 'grafica';
  bool get isComunicacaoVisual => categoria == 'comunicacao_visual';
  bool get isEstamparia =>
      categoria == 'estamparia' || categoria == 'vestuario';
  bool get isPresentes => categoria == 'presentes';
  bool get isPorMetroQuadrado => categoria == 'comunicacao_visual';
  bool get temComposicao => composicaoId != null && composicaoId! > 0;

  // ============================================================
  // MÉTODOS DE CATEGORIA
  // ============================================================

  String getCategoriaLabel() {
    switch (categoria) {
      case 'corte_laser':
        return 'Corte a Laser';
      case 'grafica':
        return 'Gráfica (UN)';
      case 'comunicacao_visual':
        return 'Comunicação Visual (m²)';
      case 'estamparia':
      case 'vestuario':
        return 'Estamparia (UN)';
      case 'presentes':
        return 'Presentes / Lembrancinhas (UN)';
      default:
        return categoria;
    }
  }

  Color getCategoriaColor() {
    switch (categoria) {
      case 'corte_laser':
        return Colors.deepOrange;
      case 'grafica':
        return Colors.blue;
      case 'comunicacao_visual':
        return Colors.green;
      case 'estamparia':
      case 'vestuario':
        return Colors.purple;
      case 'presentes':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData getCategoriaIcon() {
    switch (categoria) {
      case 'corte_laser':
        return Icons.cut;
      case 'grafica':
        return Icons.print;
      case 'comunicacao_visual':
        return Icons.photo_size_select_large;
      case 'estamparia':
      case 'vestuario':
        return Icons.checkroom;
      case 'presentes':
        return Icons.card_giftcard;
      default:
        return Icons.category;
    }
  }

  // ============================================================
  // CÁLCULOS
  // ============================================================

  double getMargem() {
    if (cost <= 0 || preco <= 0) return 0;
    return ((preco - cost) / preco) * 100;
  }

  String formatarPreco() {
    return 'R\$ ${preco.toStringAsFixed(2)}';
  }

  // CALCULAR PREÇO POR ÁREA (COMUNICAÇÃO VISUAL)
  double calcularPrecoArea(double larguraMm, double alturaMm, int quantidade) {
    if (larguraMm <= 0 || alturaMm <= 0) return 0;
    final areaM2 = (larguraMm * alturaMm) / 1000000;
    return areaM2 * preco * quantidade;
  }

  // CALCULAR PREÇO UNITÁRIO (GRÁFICA UN)
  double calcularPrecoUnitario(int quantidade) {
    return preco * quantidade;
  }

  // ============================================================
  // VALIDAÇÃO
  // ============================================================

  Map<String, dynamic> validar() {
    List<String> erros = [];
    if (codigo.isEmpty) erros.add('Código é obrigatório');
    if (nome.isEmpty) erros.add('Nome é obrigatório');
    if (categoria.isEmpty) erros.add('Categoria é obrigatória');
    if (categoria != 'corte_laser' && preco <= 0) {
      erros.add('Preço deve ser maior que zero');
    }
    return {'valido': erros.isEmpty, 'erros': erros};
  }

  // ============================================================
  // MÉTODOS ESTÁTICOS
  // ============================================================

  static List<String> getCategorias() {
    return [
      'grafica',
      'comunicacao_visual',
      'estamparia',
      'presentes',
      'corte_laser',
    ];
  }

  static Map<String, String> getCategoriasMap() {
    return {
      'grafica': 'Gráfica (UN)',
      'comunicacao_visual': 'Comunicação Visual (m²)',
      'estamparia': 'Estamparia (UN)',
      'presentes': 'Presentes / Lembrancinhas (UN)',
      'corte_laser': 'Corte a Laser',
    };
  }
}
