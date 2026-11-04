import 'dart:convert';

class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.description,
    required this.quantity,
    this.unit = 'un.',
    this.unitValue = 0,
  });

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) =>
      PurchaseOrderItem(
        description: '${map['description'] ?? ''}',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        unit: '${map['unit'] ?? 'un.'}',
        unitValue: (map['unit_value'] as num?)?.toDouble() ?? 0,
      );

  final String description;
  final double quantity;
  final String unit;
  final double unitValue;

  double get total => quantity * unitValue;

  Map<String, dynamic> toMap() => {
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unit_value': unitValue,
      };
}

class PurchaseOrderModel {
  PurchaseOrderModel({
    this.id,
    String? number,
    this.supplierId,
    this.supplierName = '',
    this.status = 'solicitado',
    this.expectedDate,
    List<PurchaseOrderItem>? items,
    this.notes = '',
    this.total = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : number = number ?? _number(),
        items = items ?? const [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PurchaseOrderModel.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items']?.toString() ?? '[]';
    List<dynamic> decoded = const [];
    try {
      decoded = jsonDecode(rawItems) as List<dynamic>;
    } catch (_) {}
    return PurchaseOrderModel(
      id: (map['id'] as num?)?.toInt(),
      number: '${map['number'] ?? ''}',
      supplierId: (map['supplier_id'] as num?)?.toInt(),
      supplierName: '${map['supplier_name'] ?? ''}',
      status: '${map['status'] ?? 'solicitado'}',
      expectedDate: map['expected_date']?.toString(),
      items: decoded
          .whereType<Map>()
          .map((item) => PurchaseOrderItem.fromMap(
              Map<String, dynamic>.from(item)))
          .toList(),
      notes: '${map['notes'] ?? ''}',
      total: (map['total'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${map['updated_at']}') ?? DateTime.now(),
    );
  }

  final int? id;
  final String number;
  final int? supplierId;
  final String supplierName;
  final String status;
  final String? expectedDate;
  final List<PurchaseOrderItem> items;
  final String notes;
  final double total;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'number': number,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'status': status,
        'expected_date': expectedDate,
        'items': jsonEncode(items.map((item) => item.toMap()).toList()),
        'notes': notes,
        'total': total,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  PurchaseOrderModel copyWith({
    int? id,
    String? status,
    String? expectedDate,
    List<PurchaseOrderItem>? items,
    String? notes,
    double? total,
  }) =>
      PurchaseOrderModel(
        id: id ?? this.id,
        number: number,
        supplierId: supplierId,
        supplierName: supplierName,
        status: status ?? this.status,
        expectedDate: expectedDate ?? this.expectedDate,
        items: items ?? this.items,
        notes: notes ?? this.notes,
        total: total ?? this.total,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static String _number() {
    final now = DateTime.now();
    return 'OC-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
  }
}
