class MaterialModel {
  int? id;
  String nome;
  String codigo;
  String tipo; // 'chapa', 'm2', 'metro', 'un'
  String categoria; // 'acrilico', 'mdf', 'madeira', 'metal', 'vidro', 'outros'
  String cor;
  String acabamento; // 'fosco', 'brilho', 'transparente', 'colorido'
  double espessura; // em mm

  // Dados para chapas
  double larguraChapa; // em mm
  double alturaChapa; // em mm
  double areaChapa; // em m² (calculado)
  double precoChapa;
  double precoPorM2;
  double perdaPadrao; // em %

  // Dados para materiais por metro/unidade
  double precoUnidade;
  double precoVenda;
  String unidade; // 'm²', 'm', 'kg', 'g', 'ml', 'un'

  // Estoque
  double quantidadeEstoque;
  double estoqueMinimo;
  double estoqueMaximo;

  // Fornecedor
  String fornecedor;
  String observacoes;
  bool active;

  String dataCriacao;
  String dataAtualizacao;

  MaterialModel({
    this.id,
    required this.nome,
    required this.codigo,
    required this.tipo,
    required this.categoria,
    this.cor = '',
    this.acabamento = '',
    this.espessura = 0,
    this.larguraChapa = 0,
    this.alturaChapa = 0,
    this.areaChapa = 0,
    this.precoChapa = 0,
    this.precoPorM2 = 0,
    this.perdaPadrao = 0,
    this.precoUnidade = 0,
    this.precoVenda = 0,
    this.unidade = 'un',
    this.quantidadeEstoque = 0,
    this.estoqueMinimo = 0,
    this.estoqueMaximo = 0,
    this.fornecedor = '',
    this.observacoes = '',
    this.active = true,
    String? dataCriacao,
    String? dataAtualizacao,
  })  : dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String();

  factory MaterialModel.fromMap(Map<String, dynamic> map) {
    return MaterialModel(
      id: map['id'],
      nome: map['nome'] ?? '',
      codigo: map['codigo'] ?? '',
      tipo: map['tipo'] ?? 'un',
      categoria: map['categoria'] ?? 'outros',
      cor: map['cor'] ?? '',
      acabamento: map['acabamento'] ?? '',
      espessura: (map['espessura'] ?? 0).toDouble(),
      larguraChapa: (map['largura_chapa'] ?? 0).toDouble(),
      alturaChapa: (map['altura_chapa'] ?? 0).toDouble(),
      areaChapa: (map['area_chapa'] ?? 0).toDouble(),
      precoChapa: (map['preco_chapa'] ?? 0).toDouble(),
      precoPorM2: (map['preco_por_m2'] ?? 0).toDouble(),
      perdaPadrao: (map['perda_padrao'] ?? 0).toDouble(),
      precoUnidade: (map['preco_unidade'] ?? 0).toDouble(),
      precoVenda: (map['preco_venda'] ?? 0).toDouble(),
      unidade: map['unidade'] ?? 'un',
      quantidadeEstoque: (map['quantidade_estoque'] ?? 0).toDouble(),
      estoqueMinimo: (map['estoque_minimo'] ?? 0).toDouble(),
      estoqueMaximo: (map['estoque_maximo'] ?? 0).toDouble(),
      fornecedor: map['fornecedor'] ?? '',
      observacoes: map['observacoes'] ?? '',
      active: (map['active'] ?? 1) == 1,
      dataCriacao: map['created_at'],
      dataAtualizacao: map['updated_at'],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'codigo': codigo,
        'tipo': tipo,
        'categoria': categoria,
        'cor': cor,
        'acabamento': acabamento,
        'espessura': espessura,
        'largura_chapa': larguraChapa,
        'altura_chapa': alturaChapa,
        'area_chapa': areaChapa,
        'preco_chapa': precoChapa,
        'preco_por_m2': precoPorM2,
        'perda_padrao': perdaPadrao,
        'preco_unidade': precoUnidade,
        'preco_venda': precoVenda,
        'unidade': unidade,
        'quantidade_estoque': quantidadeEstoque,
        'estoque_minimo': estoqueMinimo,
        'estoque_maximo': estoqueMaximo,
        'fornecedor': fornecedor,
        'observacoes': observacoes,
        'active': active ? 1 : 0,
        'created_at': dataCriacao,
        'updated_at': dataAtualizacao,
      };

  // CALCULAR ÁREA DA CHAPA
  double calcularArea() {
    if (larguraChapa > 0 && alturaChapa > 0) {
      return (larguraChapa * alturaChapa) / 1000000; // mm² m²
    }
    return areaChapa;
  }

  // CALCULAR PREÇO POR M²
  double calcularPrecoPorM2() {
    if (precoPorM2 > 0) return precoPorM2;
    final area = areaChapa > 0 ? areaChapa : calcularArea();
    if (area > 0 && precoChapa > 0) {
      return precoChapa / area;
    }
    return 0;
  }

  // CALCULAR CUSTO PARA UMA ÁREA
  double calcularCustoArea(double area) {
    final precoM2 = calcularPrecoPorM2();
    if (precoM2 <= 0) return 0;
    return area * precoM2;
  }

  double get precoCusto {
    switch (tipo) {
      case 'chapa':
        return calcularPrecoPorM2();
      case 'm2':
        return precoPorM2;
      case 'metro':
      case 'un':
        return precoUnidade;
      default:
        return precoUnidade > 0
            ? precoUnidade
            : (precoPorM2 > 0 ? precoPorM2 : precoChapa);
    }
  }

  String get unidadePreco {
    switch (tipo) {
      case 'chapa':
        return 'm²';
      case 'm2':
        return 'm²';
      case 'metro':
        return 'm';
      case 'un':
        return 'un';
      default:
        return unidade;
    }
  }

  /// Unidade usada tanto na precificação quanto na venda do material.
  /// Chapas são consumidas por área nas composições de corte a laser.
  String get unidadeVenda => unidadePreco;

  // FORMATAR DIMENSÃO
  String getDimensaoString() {
    if (larguraChapa > 0 && alturaChapa > 0) {
      return '${larguraChapa.toStringAsFixed(0)} × ${alturaChapa.toStringAsFixed(0)} mm';
    }
    return '';
  }

  // TIPO DE UNIDADE
  String getTipoNome() {
    switch (tipo) {
      case 'chapa':
        return 'Chapa';
      case 'm2':
        return 'Metro Quadrado (m²)';
      case 'metro':
        return 'Metro';
      case 'un':
        return 'Unidade';
      default:
        return tipo;
    }
  }

  // CATEGORIAS DISPONÍVEIS
  static List<String> getCategorias() {
    return [
      'acrilico',
      'mdf',
      'madeira',
      'metal',
      'vidro',
      'policarbonato',
      'pvc',
      'perifericos',
      'outros'
    ];
  }

  static String getCategoriaNome(String categoria) {
    final nomes = {
      'acrilico': 'Acrílico',
      'mdf': 'MDF',
      'madeira': 'Madeira',
      'metal': 'Metal',
      'vidro': 'Vidro',
      'policarbonato': 'Policarbonato',
      'pvc': 'PVC',
      'perifericos': 'Periféricos',
      'outros': 'Outros',
    };
    return nomes[categoria] ?? categoria;
  }

  // TIPOS DISPONÍVEIS
  static List<String> getTipos() {
    return ['chapa', 'm2', 'metro', 'un'];
  }
}
