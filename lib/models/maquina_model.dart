// lib/models/maquina_model.dart

class MaquinaModel {
  int? id;
  String nome;
  String tipo;
  String modelo;
  String fabricante;

  // Dimensões da área útil
  double areaUtilLargura;
  double areaUtilAltura;
  double areaUtil;

  // Custos por hora
  double custoEnergiaHora;
  double custoManutencaoHora;
  double custoDepreciacaoHora;
  double custoOperadorHora;
  double custoOutrosHora;

  double custoTotalHora;
  double custoTotalMinuto;

  // Dados operacionais
  double velocidadeMaxima;
  double potencia;
  double consumoEnergia;

  String observacoes;
  bool active;

  String dataCriacao;
  String dataAtualizacao;

  MaquinaModel({
    this.id,
    required this.nome,
    required this.tipo,
    this.modelo = '',
    this.fabricante = '',
    this.areaUtilLargura = 0,
    this.areaUtilAltura = 0,
    this.areaUtil = 0,
    this.custoEnergiaHora = 0,
    this.custoManutencaoHora = 0,
    this.custoDepreciacaoHora = 0,
    this.custoOperadorHora = 0,
    this.custoOutrosHora = 0,
    this.custoTotalHora = 0,
    this.custoTotalMinuto = 0,
    this.velocidadeMaxima = 0,
    this.potencia = 0,
    this.consumoEnergia = 0,
    this.observacoes = '',
    this.active = true,
    String? dataCriacao,
    String? dataAtualizacao,
  })  : dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String();

  factory MaquinaModel.fromMap(Map<String, dynamic> map) {
    return MaquinaModel(
      id: map['id'],
      nome: map['nome'] ?? '',
      tipo: map['tipo'] ?? 'laser',
      modelo: map['modelo'] ?? '',
      fabricante: map['fabricante'] ?? '',
      areaUtilLargura: (map['area_util_largura'] ?? 0).toDouble(),
      areaUtilAltura: (map['area_util_altura'] ?? 0).toDouble(),
      areaUtil: (map['area_util'] ?? 0).toDouble(),
      custoEnergiaHora: (map['custo_energia_hora'] ?? 0).toDouble(),
      custoManutencaoHora: (map['custo_manutencao_hora'] ?? 0).toDouble(),
      custoDepreciacaoHora: (map['custo_depreciacao_hora'] ?? 0).toDouble(),
      custoOperadorHora: (map['custo_operador_hora'] ?? 0).toDouble(),
      custoOutrosHora: (map['custo_outros_hora'] ?? 0).toDouble(),
      custoTotalHora: (map['custo_total_hora'] ?? 0).toDouble(),
      custoTotalMinuto: (map['custo_total_minuto'] ?? 0).toDouble(),
      velocidadeMaxima: (map['velocidade_maxima'] ?? 0).toDouble(),
      potencia: (map['potencia'] ?? 0).toDouble(),
      consumoEnergia: (map['consumo_energia'] ?? 0).toDouble(),
      observacoes: map['observacoes'] ?? '',
      active: (map['active'] ?? 1) == 1,
      dataCriacao: map['created_at'],
      dataAtualizacao: map['updated_at'],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'tipo': tipo,
        'modelo': modelo,
        'fabricante': fabricante,
        'area_util_largura': areaUtilLargura,
        'area_util_altura': areaUtilAltura,
        'area_util': areaUtil,
        'custo_energia_hora': custoEnergiaHora,
        'custo_manutencao_hora': custoManutencaoHora,
        'custo_depreciacao_hora': custoDepreciacaoHora,
        'custo_operador_hora': custoOperadorHora,
        'custo_outros_hora': custoOutrosHora,
        'custo_total_hora': custoTotalHora,
        'custo_total_minuto': custoTotalMinuto,
        'velocidade_maxima': velocidadeMaxima,
        'potencia': potencia,
        'consumo_energia': consumoEnergia,
        'observacoes': observacoes,
        'active': active ? 1 : 0,
        'created_at': dataCriacao,
        'updated_at': dataAtualizacao,
      };

  // CALCULAR ÁREA ÚTIL
  double calcularAreaUtil() {
    if (areaUtilLargura > 0 && areaUtilAltura > 0) {
      return (areaUtilLargura * areaUtilAltura) / 1000000;
    }
    return areaUtil;
  }

  // CALCULAR CUSTO TOTAL POR HORA
  double calcularCustoTotalHora() {
    return custoEnergiaHora +
        custoManutencaoHora +
        custoDepreciacaoHora +
        custoOperadorHora +
        custoOutrosHora;
  }

  // CALCULAR CUSTO TOTAL POR MINUTO
  double calcularCustoTotalMinuto() {
    return calcularCustoTotalHora() / 60;
  }

  // RECALCULAR TODOS OS CUSTOS
  void recalcularCustos() {
    custoTotalHora = calcularCustoTotalHora();
    custoTotalMinuto = calcularCustoTotalMinuto();
  }

  // TIPOS DE MÁQUINA
  static List<String> getTipos() {
    return ['laser', 'router', 'corte', 'dobra', 'jato_agua', 'outros'];
  }

  static String getTipoNome(String tipo) {
    final nomes = {
      'laser': 'Laser',
      'router': 'Router',
      'corte': 'Corte',
      'dobra': 'Dobra',
      'jato_agua': 'Jato de Água',
      'outros': 'Outros',
    };
    return nomes[tipo] ?? tipo;
  }

  MaquinaModel copyWith({
    int? id,
    String? nome,
    String? tipo,
    String? modelo,
    String? fabricante,
    double? areaUtilLargura,
    double? areaUtilAltura,
    double? areaUtil,
    double? custoEnergiaHora,
    double? custoManutencaoHora,
    double? custoDepreciacaoHora,
    double? custoOperadorHora,
    double? custoOutrosHora,
    double? custoTotalHora,
    double? custoTotalMinuto,
    double? velocidadeMaxima,
    double? potencia,
    double? consumoEnergia,
    String? observacoes,
    bool? active,
    String? dataCriacao,
    String? dataAtualizacao,
  }) {
    return MaquinaModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      modelo: modelo ?? this.modelo,
      fabricante: fabricante ?? this.fabricante,
      areaUtilLargura: areaUtilLargura ?? this.areaUtilLargura,
      areaUtilAltura: areaUtilAltura ?? this.areaUtilAltura,
      areaUtil: areaUtil ?? this.areaUtil,
      custoEnergiaHora: custoEnergiaHora ?? this.custoEnergiaHora,
      custoManutencaoHora: custoManutencaoHora ?? this.custoManutencaoHora,
      custoDepreciacaoHora: custoDepreciacaoHora ?? this.custoDepreciacaoHora,
      custoOperadorHora: custoOperadorHora ?? this.custoOperadorHora,
      custoOutrosHora: custoOutrosHora ?? this.custoOutrosHora,
      custoTotalHora: custoTotalHora ?? this.custoTotalHora,
      custoTotalMinuto: custoTotalMinuto ?? this.custoTotalMinuto,
      velocidadeMaxima: velocidadeMaxima ?? this.velocidadeMaxima,
      potencia: potencia ?? this.potencia,
      consumoEnergia: consumoEnergia ?? this.consumoEnergia,
      observacoes: observacoes ?? this.observacoes,
      active: active ?? this.active,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
    );
  }
}
