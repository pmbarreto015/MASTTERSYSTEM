import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StockMovementModel {
  StockMovementModel({
    this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.type,
    required this.previousStock,
    required this.newStock,
    required this.reason,
    this.orderId,
    this.supplierId,
    this.userId,
    required this.createdAt,
  });

  factory StockMovementModel.fromMap(Map<String, dynamic> map) {
    return StockMovementModel(
      id: map['id'],
      productId: map['product_id'],
      productName: map['product_name'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      type: map['type'] ?? 'entrada',
      previousStock: (map['previous_stock'] ?? 0).toDouble(),
      newStock: (map['new_stock'] ?? 0).toDouble(),
      reason: map['reason'] ?? '',
      orderId: map['order_id'],
      supplierId: map['supplier_id'],
      userId: map['user_id'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  int? id;
  int productId;
  String productName;
  double quantity;
  String type; // 'entrada', 'saida', 'ajuste', 'compra', 'venda'
  double previousStock;
  double newStock;
  String reason;
  int? orderId;
  int? supplierId;
  int? userId;
  DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'type': type,
        'previous_stock': previousStock,
        'new_stock': newStock,
        'reason': reason,
        'order_id': orderId,
        'supplier_id': supplierId,
        'user_id': userId,
        'created_at': createdAt.toIso8601String(),
      };

  String get typeLabel {
    final labels = {
      'entrada': 'Entrada',
      'saida': 'Saída',
      'ajuste': 'Ajuste',
      'compra': 'Compra',
      'venda': 'Venda',
    };
    return labels[type] ?? type;
  }

  Color get typeColor {
    final colors = {
      'entrada': Colors.green,
      'saida': Colors.red,
      'ajuste': Colors.orange,
      'compra': Colors.blue,
      'venda': Colors.purple,
    };
    return colors[type] ?? Colors.grey;
  }

  String get dataFormatada => DateFormat('dd/MM/yyyy HH:mm').format(createdAt);

  String get sinal => type == 'entrada' || type == 'compra'
      ? '+'
      : type == 'ajuste'
          ? '±'
          : '-';

  Color get sinalColor => type == 'entrada' || type == 'compra'
      ? Colors.green
      : type == 'ajuste'
          ? Colors.orange
          : Colors.red;

  String get quantidadeFormatada {
    final sinalStr = sinal;
    final qtdStr = quantity.toStringAsFixed(0);
    return '$sinalStr $qtdStr';
  }
}
