// lib/models/composicao_model.dart

class ComposicaoItem {
  String tipo; // 'material', 'maquina', 'servico'
  String descricao;
  double quantidade;
  String unidade;
  double valorUnitario;
  double valorTotal;
  String observacoes;
  int? itemId; // ID do material, máquina ou serviço
  int? itemOriginalId; // ID original do material/maquina no banco

  ComposicaoItem({
    required this.tipo,
    required this.descricao,
    this.quantidade = 0,
    this.unidade = '',
    this.valorUnitario = 0,
    this.valorTotal = 0,
    this.observacoes = '',
    this.itemId,
    this.itemOriginalId,
  });

  Map<String, dynamic> toMap() => {
        'tipo': tipo,
        'descricao': descricao,
        'quantidade': quantidade,
        'unidade': unidade,
        'valorUnitario': valorUnitario,
        'valorTotal': valorTotal,
        'observacoes': observacoes,
        'item_id': itemId,
        'item_original_id': itemOriginalId,
      };

  factory ComposicaoItem.fromMap(Map<String, dynamic> map) => ComposicaoItem(
        tipo: map['tipo'] ?? 'material',
        descricao: map['descricao'] ?? '',
        quantidade: (map['quantidade'] ?? 0).toDouble(),
        unidade: map['unidade'] ?? '',
        valorUnitario: (map['valorUnitario'] ?? 0).toDouble(),
        valorTotal: (map['valorTotal'] ?? 0).toDouble(),
        observacoes: map['observacoes'] ?? '',
        itemId: map['item_id'],
        itemOriginalId: map['item_original_id'],
      );
}

class ComposicaoModel {
  int? id;
  int? pedidoId;
  int? orcamentoId;
  int? produtoId; // NOVO: ID do produto associado

  List<ComposicaoItem> materiais = [];
  List<ComposicaoItem> maquinas = [];
  List<ComposicaoItem> servicos = [];

  double custoTotalMateriais = 0;
  double custoTotalMaquinas = 0;
  double custoTotalServicos = 0;
  double custoTotal = 0;

  double margemLucro = 0;
  double precoVenda = 0;

  String observacoes = '';
  String dataCriacao;
  String dataAtualizacao;

  ComposicaoModel({
    this.id,
    this.pedidoId,
    this.orcamentoId,
    this.produtoId, // NOVO
    this.materiais = const [],
    this.maquinas = const [],
    this.servicos = const [],
    this.custoTotalMateriais = 0,
    this.custoTotalMaquinas = 0,
    this.custoTotalServicos = 0,
    this.custoTotal = 0,
    this.margemLucro = 0,
    this.precoVenda = 0,
    this.observacoes = '',
    String? dataCriacao,
    String? dataAtualizacao,
  })  : dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String();

  // RECALCULAR TOTAIS
  void recalcularTotais() {
    custoTotalMateriais =
        materiais.fold(0, (sum, item) => sum + item.valorTotal);
    custoTotalMaquinas = maquinas.fold(0, (sum, item) => sum + item.valorTotal);
    custoTotalServicos = servicos.fold(0, (sum, item) => sum + item.valorTotal);
    custoTotal = custoTotalMateriais + custoTotalMaquinas + custoTotalServicos;
  }

  // CALCULAR PREÇO DE VENDA
  void calcularPrecoVenda() {
    recalcularTotais();
    if (custoTotal > 0 && margemLucro > 0) {
      precoVenda = custoTotal * (1 + margemLucro / 100);
    } else {
      precoVenda = custoTotal;
    }
  }

  // ADICIONAR ITEM
  void adicionarMaterial(ComposicaoItem item) {
    materiais.add(item);
    recalcularTotais();
  }

  void adicionarMaquina(ComposicaoItem item) {
    maquinas.add(item);
    recalcularTotais();
  }

  void adicionarServico(ComposicaoItem item) {
    servicos.add(item);
    recalcularTotais();
  }

  // REMOVER ITEM
  void removerMaterial(int index) {
    materiais.removeAt(index);
    recalcularTotais();
  }

  void removerMaquina(int index) {
    maquinas.removeAt(index);
    recalcularTotais();
  }

  void removerServico(int index) {
    servicos.removeAt(index);
    recalcularTotais();
  }

  // COPIA PARA ATUALIZAÇÃO
  ComposicaoModel copyWith({
    int? id,
    int? pedidoId,
    int? orcamentoId,
    int? produtoId,
    List<ComposicaoItem>? materiais,
    List<ComposicaoItem>? maquinas,
    List<ComposicaoItem>? servicos,
    double? custoTotalMateriais,
    double? custoTotalMaquinas,
    double? custoTotalServicos,
    double? custoTotal,
    double? margemLucro,
    double? precoVenda,
    String? observacoes,
    String? dataCriacao,
    String? dataAtualizacao,
  }) {
    return ComposicaoModel(
      id: id ?? this.id,
      pedidoId: pedidoId ?? this.pedidoId,
      orcamentoId: orcamentoId ?? this.orcamentoId,
      produtoId: produtoId ?? this.produtoId,
      materiais: materiais ?? this.materiais,
      maquinas: maquinas ?? this.maquinas,
      servicos: servicos ?? this.servicos,
      custoTotalMateriais: custoTotalMateriais ?? this.custoTotalMateriais,
      custoTotalMaquinas: custoTotalMaquinas ?? this.custoTotalMaquinas,
      custoTotalServicos: custoTotalServicos ?? this.custoTotalServicos,
      custoTotal: custoTotal ?? this.custoTotal,
      margemLucro: margemLucro ?? this.margemLucro,
      precoVenda: precoVenda ?? this.precoVenda,
      observacoes: observacoes ?? this.observacoes,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
    );
  }

  // TO STRING
  @override
  String toString() {
    return 'ComposicaoModel{id: $id, produtoId: $produtoId, custoTotal: $custoTotal, precoVenda: $precoVenda}';
  }
}
