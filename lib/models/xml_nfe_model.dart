class XmlNfeModel {
  XmlNfeModel({
    required this.chave,
    required this.numero,
    required this.serie,
    required this.fornecedor,
    required this.fornecedorCnpj,
    required this.fornecedorEndereco,
    this.fornecedorTelefone = '',
    required this.dataEmissao,
    required this.dataEntrada,
    required this.valorTotal,
    required this.valorProdutos,
    required this.valorIcms,
    required this.valorFrete,
    required this.valorDesconto,
    required this.formaPagamento,
    required this.produtos,
    required this.parcelas,
  });

  String chave;
  String numero;
  String serie;
  String fornecedor;
  String fornecedorCnpj;
  String fornecedorEndereco;
  String fornecedorTelefone;
  DateTime dataEmissao;
  DateTime dataEntrada;
  double valorTotal;
  double valorProdutos;
  double valorIcms;
  double valorFrete;
  double valorDesconto;
  String formaPagamento;
  List<XmlProdutoNfe> produtos;
  List<XmlParcelaNfe> parcelas;

  Map<String, dynamic> toMap() => {
        'chave': chave,
        'numero': numero,
        'serie': serie,
        'fornecedor': fornecedor,
        'fornecedor_cnpj': fornecedorCnpj,
        'fornecedor_endereco': fornecedorEndereco,
        'fornecedor_telefone': fornecedorTelefone,
        'data_emissao': dataEmissao.toIso8601String(),
        'data_entrada': dataEntrada.toIso8601String(),
        'valor_total': valorTotal,
        'valor_produtos': valorProdutos,
        'valor_icms': valorIcms,
        'valor_frete': valorFrete,
        'valor_desconto': valorDesconto,
        'forma_pagamento': formaPagamento,
      };
}

class XmlProdutoNfe {
  XmlProdutoNfe({
    required this.codigo,
    required this.nome,
    required this.ncm,
    required this.cfop,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.valorTotal,
    required this.icms,
    required this.ipi,
  });

  String codigo;
  String nome;
  String ncm;
  String cfop;
  String unidade;
  double quantidade;
  double valorUnitario;
  double valorTotal;
  double icms;
  double ipi;

  Map<String, dynamic> toMap() => {
        'codigo': codigo,
        'nome': nome,
        'ncm': ncm,
        'cfop': cfop,
        'unidade': unidade,
        'quantidade': quantidade,
        'valor_unitario': valorUnitario,
        'valor_total': valorTotal,
        'icms': icms,
        'ipi': ipi,
      };
}

class XmlParcelaNfe {
  XmlParcelaNfe({
    required this.numero,
    required this.valor,
    required this.vencimento,
  });

  int numero;
  double valor;
  DateTime vencimento;

  Map<String, dynamic> toMap() => {
        'numero': numero,
        'valor': valor,
        'vencimento': vencimento.toIso8601String(),
      };
}
