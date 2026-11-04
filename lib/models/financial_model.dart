import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FinancialModel {
  FinancialModel({
    this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.dueDate,
    this.isPaid = false,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.orderId,
    this.customerId,
    this.customerName,
    this.categoria = 'outros',
    this.formaPagamento = '',
    this.parcela = 0,
    this.totalParcelas = 0,
    this.valorBruto = 0,
    this.taxa = 0,
    this.valorLiquido = 0,
    this.status = 'pendente',
    this.pagamentos = const [],
  });

  factory FinancialModel.fromMap(Map<String, dynamic> map) {
    final pagamentosStr = map['pagamentos'] as String? ?? '';
    final pagamentosList = pagamentosStr.isNotEmpty
        ? pagamentosStr.split(';').map((e) => double.tryParse(e) ?? 0).toList()
        : <double>[];

    return FinancialModel(
      id: map['id'],
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'pagar',
      dueDate: DateTime.parse(map['due_date']),
      isPaid: map['is_paid'] == 1,
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      orderId: map['order_id'],
      customerId: map['customer_id'],
      customerName: map['customer_name'],
      categoria: map['categoria'] ?? 'outros',
      formaPagamento: map['forma_pagamento'] ?? '',
      parcela: map['parcela'] ?? 0,
      totalParcelas: map['total_parcelas'] ?? 0,
      valorBruto: (map['valor_bruto'] ?? 0).toDouble(),
      taxa: (map['taxa'] ?? 0).toDouble(),
      valorLiquido: (map['valor_liquido'] ?? 0).toDouble(),
      status: map['status'] ?? 'pendente',
      pagamentos: pagamentosList,
    );
  }

  int? id;
  String description;
  double amount;
  String type;
  DateTime dueDate;
  bool isPaid;
  String? notes;
  DateTime createdAt;
  DateTime updatedAt;

  // CAMPOS DE INTEGRAÇÃO
  int? orderId;
  int? customerId;
  String? customerName;
  String categoria;
  String formaPagamento;
  int parcela;
  int totalParcelas;
  double valorBruto;
  double taxa;
  double valorLiquido;
  String status;
  List<double> pagamentos;

  Map<String, dynamic> toMap() => {
        'id': id,
        'description': description,
        'amount': amount,
        'type': type,
        'due_date': dueDate.toIso8601String(),
        'is_paid': isPaid ? 1 : 0,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'order_id': orderId,
        'customer_id': customerId,
        'customer_name': customerName,
        'categoria': categoria,
        'forma_pagamento': formaPagamento,
        'parcela': parcela,
        'total_parcelas': totalParcelas,
        'valor_bruto': valorBruto,
        'taxa': taxa,
        'valor_liquido': valorLiquido,
        'status': status,
        'pagamentos': pagamentos.join(';'),
      };

  FinancialModel copyWith({
    int? id,
    String? description,
    double? amount,
    String? type,
    DateTime? dueDate,
    bool? isPaid,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? orderId,
    int? customerId,
    String? customerName,
    String? categoria,
    String? formaPagamento,
    int? parcela,
    int? totalParcelas,
    double? valorBruto,
    double? taxa,
    double? valorLiquido,
    String? status,
    List<double>? pagamentos,
  }) =>
      FinancialModel(
        id: id ?? this.id,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        dueDate: dueDate ?? this.dueDate,
        isPaid: isPaid ?? this.isPaid,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        orderId: orderId ?? this.orderId,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        categoria: categoria ?? this.categoria,
        formaPagamento: formaPagamento ?? this.formaPagamento,
        parcela: parcela ?? this.parcela,
        totalParcelas: totalParcelas ?? this.totalParcelas,
        valorBruto: valorBruto ?? this.valorBruto,
        taxa: taxa ?? this.taxa,
        valorLiquido: valorLiquido ?? this.valorLiquido,
        status: status ?? this.status,
        pagamentos: pagamentos ?? this.pagamentos,
      );

  // GETTERS AUXILIARES
  String get statusLabel {
    if (status == 'cancelado') return 'Cancelado';
    if (isPaid) return 'Pago';
    if (DateTime(dueDate.year,dueDate.month,dueDate.day).isBefore(DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day))) return 'Vencido';
    if (status == 'parcial') return 'Parcial';
    return 'Pendente';
  }

  Color get statusColor {
    if (status == 'cancelado') return Colors.grey;
    if (isPaid) return Colors.green;
    if (DateTime(dueDate.year,dueDate.month,dueDate.day).isBefore(DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day))) return Colors.red;
    if (status == 'parcial') return Colors.orange;
    return Colors.orange;
  }

  String get categoriaLabel {
    final categorias = {
      'vendas': 'Vendas',
      'materiais': 'Materiais',
      'operacional': 'Operacional',
      'terceirizacao': 'Terceirização',
      'pessoal': 'Pessoal',
      'marketing': 'Marketing',
      'entrega': 'Entrega',
      'outros': 'Outros',
    };
    return categorias[categoria] ?? categoria;
  }

  Color get categoriaColor {
    final cores = {
      'vendas': Colors.green,
      'materiais': Colors.blue,
      'operacional': Colors.orange,
      'terceirizacao': Colors.purple,
      'pessoal': Colors.teal,
      'marketing': Colors.pink,
      'entrega': Colors.cyan,
      'outros': Colors.grey,
    };
    return cores[categoria] ?? Colors.grey;
  }

  String get valorFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(amount);

  String get valorBrutoFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valorBruto);

  String get valorLiquidoFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
          .format(valorLiquido);

  String get dataFormatada => DateFormat('dd/MM/yyyy').format(dueDate);

  String get dataCriacaoFormatada =>
      DateFormat('dd/MM/yyyy HH:mm').format(createdAt);

  String get tipoLabel => type == 'receber' ? 'Receber' : 'Pagar';
  Color get tipoColor => type == 'receber' ? Colors.green : Colors.red;

  bool get isOverdue => !isPaid && DateTime(dueDate.year,dueDate.month,dueDate.day).isBefore(DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day));
}
