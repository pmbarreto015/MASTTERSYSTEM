import 'product_model.dart';

class OrderItemModel {
  OrderItemModel({
    this.produtoId,
    this.produtoNome = '',
    this.quantidade = 1,
    this.precoUnitario = 0,
    this.subtotal = 0,
    this.especificacoes = '',
    this.largura = 0,
    this.altura = 0,
    this.custoUnitario = 0,
    this.detalhesCusto = '',
    this.terceirizado = false,
  });

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    return OrderItemModel(
      produtoId: map['produtoId'] ?? map['product_id'],
      produtoNome: map['produtoNome'] ??
          map['produto_nome'] ??
          map['product_name'] ??
          '',
      quantidade: map['quantidade'] ?? map['quantity'] ?? 1,
      precoUnitario:
          (map['precoUnitario'] ?? map['unit_price'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      especificacoes: map['especificacoes'] ?? map['specifications'] ?? '',
      largura: (map['largura'] ?? 0).toDouble(),
      altura: (map['altura'] ?? 0).toDouble(),
      custoUnitario: (map['custo_unitario'] ?? 0).toDouble(),
      detalhesCusto: map['detalhes_custo'] ?? '',
      terceirizado: map['terceirizado'] == true || map['terceirizado'] == 1,
    );
  }

  int? produtoId;
  String produtoNome;
  int quantidade;
  double precoUnitario;
  double subtotal;
  String especificacoes;
  double largura;
  double altura;
  double custoUnitario;
  String detalhesCusto;
  bool terceirizado;

  double get custoTotal => custoUnitario * quantidade;
  double get lucro => subtotal - custoTotal;
  double get margemLucro => subtotal > 0 ? (lucro / subtotal) * 100 : 0;

  Map<String, dynamic> toMap() => {
        'produtoId': produtoId,
        'produtoNome': produtoNome,
        'quantidade': quantidade,
        'precoUnitario': precoUnitario,
        'subtotal': subtotal,
        'especificacoes': especificacoes,
        'largura': largura,
        'altura': altura,
        'custo_unitario': custoUnitario,
        'detalhes_custo': detalhesCusto,
        'terceirizado': terceirizado ? 1 : 0,
      };
}

class OrderModel {
  /// Chaves históricas de produção, independentes da situação financeira.
  static const Map<String, String> productionStatuses = {
    'aguardando_pagamento': 'Arte',
    'pagamento_recebido': 'Impressão',
    'em_producao': 'Acabamento',
    'pronto': 'Qualidade',
    'entregue': 'Finalizado',
  };

  String get productionStatusLabel => status == 'cancelado'
      ? 'Cancelado'
      : productionStatuses[status] ?? status;

  /// A situação geral não altera a etapa detalhada da produção.
  String get orderStatusGroup => tipo == 'OS' &&
          const {
            'aguardando_pagamento',
            'pagamento_recebido',
            'em_producao',
            'pronto',
          }.contains(status)
      ? 'em_producao'
      : status;

  OrderModel({
    this.id,
    String? numero,
    this.tipo = 'ORCAMENTO',
    this.clienteId,
    this.clienteNome,
    this.sellerId,
    List<OrderItemModel>? itens,
    this.valorTotal = 0,
    this.desconto = 0,
    this.outrosValores = 0,
    this.formaPagamento = 'À Vista',
    this.entrada = 0,
    List<double>? parcelas,
    this.valorManual = 0,
    this.prioridade = 'normal',
    this.status = 'aguardando_pagamento',
    this.observacoes = '',
    String? dataCriacao,
    String? dataAtualizacao,
    this.dataEntrega,
    List<String>? parcelasDatas,
  })  : numero = numero ?? _gerarNumero(),
        dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String(),
        _itens = itens ?? [],
        _parcelas = parcelas ?? [],
        _parcelasDatas = parcelasDatas ?? [];

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    List<OrderItemModel> itensList = [];

    final itensData = map['itens'];
    if (itensData != null && itensData is List) {
      itensList = itensData
          .map((item) => OrderItemModel.fromMap(item as Map<String, dynamic>))
          .toList();
    }

    final parcelasStr = map['parcelas'] as String? ?? '';
    final parcelasList = parcelasStr.isNotEmpty
        ? parcelasStr.split(';').map((e) => double.tryParse(e) ?? 0).toList()
        : <double>[];

    final parcelasDatasStr = map['parcelas_datas'] as String? ?? '';
    final parcelasDatasList = parcelasDatasStr.isNotEmpty
        ? parcelasDatasStr.split(';').toList()
        : <String>[];

    return OrderModel(
      id: map['id'],
      numero: map['number'] ?? map['numero'],
      tipo: map['tipo'] ?? 'ORCAMENTO',
      clienteId: map['customer_id'] ?? map['cliente_id'],
      clienteNome: map['cliente_nome'],
      sellerId: map['seller_id'],
      valorTotal: (map['total'] ?? map['valor_total'] ?? 0).toDouble(),
      desconto: (map['discount'] ?? map['desconto'] ?? 0).toDouble(),
      outrosValores:
          (map['additional_amount'] ??
                  map['outros_valores'] ??
                  map['valor_manual'] ??
                  0)
              .toDouble(),
      formaPagamento:
          map['payment_method'] ?? map['forma_pagamento'] ?? 'À Vista',
      entrada: (map['entrada'] ?? 0).toDouble(),
      parcelas: parcelasList,
      parcelasDatas: parcelasDatasList,
      valorManual: (map['valor_manual'] ?? 0).toDouble(),
      prioridade: map['prioridade'] ?? 'normal',
      status: map['status'] ?? 'aguardando_pagamento',
      observacoes: map['observacoes'] ?? map['observations'] ?? '',
      dataCriacao: map['created_at'] ?? map['data_criacao'],
      dataAtualizacao: map['updated_at'] ?? map['data_atualizacao'],
      dataEntrega: map['delivery_date'] ?? map['data_entrega'],
      itens: itensList,
    );
  }

  int? id;
  String numero;
  String tipo;
  int? clienteId;
  String? clienteNome;
  int? sellerId; // ID DO VENDEDOR
  double valorTotal;
  double desconto;
  double outrosValores;
  String formaPagamento;
  double entrada;
  double valorManual;
  String prioridade;
  String status;
  String observacoes;
  String dataCriacao;
  String dataAtualizacao;
  String? dataEntrega;

  // LISTAS MUTÁVEIS
  List<OrderItemModel> _itens;
  List<double> _parcelas;
  List<String> _parcelasDatas;

  bool get isAcceptedSale => tipo == 'OS' && status != 'cancelado';

  // GETTERS
  List<OrderItemModel> get itens => List.unmodifiable(_itens);
  List<double> get parcelas => List.unmodifiable(_parcelas);
  List<String> get parcelasDatas => List.unmodifiable(_parcelasDatas);

  // MÉTODOS PARA MODIFICAR AS LISTAS
  void setItens(List<OrderItemModel> novosItens) {
    _itens = List.from(novosItens);
  }

  void setParcelas(List<double> novasParcelas) {
    _parcelas = List.from(novasParcelas);
  }

  void setParcelasDatas(List<String> novasDatas) {
    _parcelasDatas = List.from(novasDatas);
  }

  void adicionarItem(
      ProductModel produto, int quantidade, String especificacoes) {
    final item = OrderItemModel(
      produtoId: produto.id,
      produtoNome: produto.nome,
      quantidade: quantidade,
      precoUnitario: produto.preco,
      subtotal: produto.preco * quantidade,
      especificacoes: especificacoes,
    );
    _itens.add(item);
    calcularTotal();
  }

  bool removerItem(int index) {
    if (index >= 0 && index < _itens.length) {
      _itens.removeAt(index);
      calcularTotal();
      return true;
    }
    return false;
  }

  double calcularTotal() {
    final subtotal = _itens.fold(0.0, (sum, item) => sum + item.subtotal);
    valorTotal =
        (subtotal + outrosValores - desconto).clamp(0.0, double.infinity).toDouble();
    return valorTotal;
  }

  Map<String, dynamic> validar() {
    var erros = <String>[];

    if (clienteId == null) {
      erros.add('Cliente é obrigatório');
    }

    if (_itens.isEmpty) {
      erros.add('Pedido deve ter pelo menos um item');
    }

    for (var item in _itens) {
      if (item.quantidade <= 0) {
        erros.add('Quantidade deve ser maior que zero');
      }
      if (item.precoUnitario <= 0) {
        erros.add('Preço unitário inválido');
      }
    }

    return {'valido': erros.isEmpty, 'erros': erros};
  }

  void calcularParcelas(int totalParcelas, double entrada) {
    this.entrada = entrada;
    final restante = valorTotal - entrada;
    final valorParcela = restante / totalParcelas;
    _parcelas.clear();
    _parcelasDatas.clear();
    for (var i = 0; i < totalParcelas; i++) {
      _parcelas.add(valorParcela);
      _parcelasDatas.add(
        DateTime.now().add(Duration(days: (i + 1) * 30)).toIso8601String(),
      );
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'number': numero,
        'tipo': tipo,
        'customer_id': clienteId,
        'cliente_nome': clienteNome,
        'seller_id': sellerId,
        'total': valorTotal,
        'discount': desconto,
        'payment_method': formaPagamento,
        'entrada': entrada,
        'parcelas': _parcelas.join(';'),
        'parcelas_datas': _parcelasDatas.join(';'),
        'valor_manual': outrosValores,
        'prioridade': prioridade,
        'status': status,
        'observations': observacoes,
        'created_at': dataCriacao,
        'updated_at': dataAtualizacao,
        'delivery_date': dataEntrega,
      };

  OrderModel copyWith({
    int? id,
    String? numero,
    String? tipo,
    int? clienteId,
    String? clienteNome,
    int? sellerId,
    List<OrderItemModel>? itens,
    double? valorTotal,
    double? desconto,
    double? outrosValores,
    String? formaPagamento,
    double? entrada,
    List<double>? parcelas,
    List<String>? parcelasDatas,
    double? valorManual,
    String? prioridade,
    String? status,
    String? observacoes,
    String? dataCriacao,
    String? dataAtualizacao,
    String? dataEntrega,
  }) {
    final novoModel = OrderModel(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      tipo: tipo ?? this.tipo,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      sellerId: sellerId ?? this.sellerId,
      valorTotal: valorTotal ?? this.valorTotal,
      desconto: desconto ?? this.desconto,
      outrosValores: outrosValores ?? this.outrosValores,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      entrada: entrada ?? this.entrada,
      valorManual: valorManual ?? this.valorManual,
      prioridade: prioridade ?? this.prioridade,
      status: status ?? this.status,
      observacoes: observacoes ?? this.observacoes,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
      dataEntrega: dataEntrega ?? this.dataEntrega,
    );

    if (itens != null) {
      novoModel._itens = List.from(itens);
    } else {
      novoModel._itens = List.from(_itens);
    }

    if (parcelas != null) {
      novoModel._parcelas = List.from(parcelas);
    } else {
      novoModel._parcelas = List.from(_parcelas);
    }

    if (parcelasDatas != null) {
      novoModel._parcelasDatas = List.from(parcelasDatas);
    } else {
      novoModel._parcelasDatas = List.from(_parcelasDatas);
    }

    return novoModel;
  }

  // MÉTODO PARA CONVERTER PARA MAP COM ITENS
  Map<String, dynamic> toMapWithItems() {
    return {
      ...toMap(),
      'itens': _itens.map((item) => item.toMap()).toList(),
    };
  }

  static String _gerarNumero() {
    final now = DateTime.now();
    final ano = now.year;
    final mes = now.month.toString().padLeft(2, '0');
    final dia = now.day.toString().padLeft(2, '0');
    final seq = (DateTime.now().millisecondsSinceEpoch % 10000)
        .toString()
        .padLeft(4, '0');
    return 'PED-$ano$mes$dia-$seq';
  }
}
