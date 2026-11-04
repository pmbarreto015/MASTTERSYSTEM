import 'erp_module_record.dart';

class DeliveryHistoryEntry {
  const DeliveryHistoryEntry({
    required this.at,
    required this.status,
    required this.responsible,
    this.note = '',
  });

  factory DeliveryHistoryEntry.fromMap(Map<String, dynamic> map) =>
      DeliveryHistoryEntry(
        at: DateTime.tryParse('${map['at']}') ?? DateTime.now(),
        status: '${map['status'] ?? ''}',
        responsible: '${map['responsible'] ?? ''}',
        note: '${map['note'] ?? ''}',
      );

  final DateTime at;
  final String status;
  final String responsible;
  final String note;

  Map<String, dynamic> toMap() => {
        'at': at.toIso8601String(),
        'status': status,
        'responsible': responsible,
        'note': note,
      };
}

class DeliveryModel {
  const DeliveryModel({
    required this.record,
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.method,
    required this.status,
    this.scheduledAt,
    this.responsible = '',
    this.address = '',
    this.reference = '',
    this.contact = '',
    this.deliveryFee = 0,
    this.notes = '',
    this.paymentPending = 0,
    this.paymentTotal = 0,
    this.history = const [],
  });

  static const methods = {
    'retirada_loja': 'Retirada na loja',
    'entrega_loja': 'Entrega pela loja',
    'uber': 'Uber',
    '99': '99',
    'lalamove': 'Lalamove',
    'outro': 'Outro',
  };
  static const statuses = {
    'aguardando_agendamento': 'Aguardando agendamento',
    'agendado': 'Agendado',
    'em_separacao': 'Em separação',
    'saiu_para_entrega': 'Saiu para entrega',
    'disponivel_para_retirada': 'Disponível para retirada',
    'concluido': 'Concluído',
    'cancelado': 'Cancelado',
  };

  factory DeliveryModel.fromRecord(ErpModuleRecord record) {
    final payload = record.payload;
    final rawHistory = payload['history'];
    return DeliveryModel(
      record: record,
      orderId: (payload['order_id'] as num?)?.toInt() ??
          int.tryParse(record.referenceId?.replaceFirst('order:', '') ?? '') ??
          0,
      orderNumber: '${payload['order_number'] ?? record.title}',
      customerName: '${payload['customer_name'] ?? ''}',
      method: '${payload['method'] ?? 'retirada_loja'}',
      status: record.status,
      scheduledAt: DateTime.tryParse('${payload['scheduled_at'] ?? ''}'),
      responsible: '${payload['responsible'] ?? ''}',
      address: '${payload['address'] ?? ''}',
      reference: '${payload['reference'] ?? ''}',
      contact: '${payload['contact'] ?? ''}',
      deliveryFee: (payload['delivery_fee'] as num? ?? 0).toDouble(),
      notes: '${payload['notes'] ?? ''}',
      paymentPending: (payload['payment_pending'] as num? ?? 0).toDouble(),
      paymentTotal: (payload['payment_total'] as num? ?? 0).toDouble(),
      history: rawHistory is List
          ? rawHistory
              .whereType<Map>()
              .map((entry) => DeliveryHistoryEntry.fromMap(
                  Map<String, dynamic>.from(entry)))
              .toList()
          : const [],
    );
  }

  final ErpModuleRecord record;
  final int orderId;
  final String orderNumber;
  final String customerName;
  final String method;
  final String status;
  final DateTime? scheduledAt;
  final String responsible;
  final String address;
  final String reference;
  final String contact;
  final double deliveryFee;
  final String notes;
  final double paymentPending;
  final double paymentTotal;
  final List<DeliveryHistoryEntry> history;

  String get methodLabel => methods[method] ?? method;
  String get statusLabel => statuses[status] ?? status;
  bool get isLate =>
      scheduledAt != null &&
      DateTime.now().isAfter(scheduledAt!) &&
      !const {'concluido', 'cancelado'}.contains(status);
  bool get isStoreDelivery => method == 'entrega_loja';
  bool get hasFinancialEntry => paymentTotal > .009;
  bool get isPaidInFull => hasFinancialEntry && paymentPending <= .009;
  bool get needsAddress => method != 'retirada_loja';
  bool get deliveryDataReady =>
      scheduledAt != null &&
      responsible.trim().isNotEmpty &&
      contact.trim().isNotEmpty &&
      (!needsAddress || address.trim().isNotEmpty);
  DateTime? get completedAt {
    for (final entry in history.reversed) {
      if (entry.status == 'concluido') return entry.at;
    }
    return status == 'concluido' ? record.updatedAt : null;
  }

  DeliveryModel copyWith({
    String? method,
    String? status,
    DateTime? scheduledAt,
    bool clearSchedule = false,
    String? responsible,
    String? address,
    String? reference,
    String? contact,
    double? deliveryFee,
    String? notes,
    double? paymentPending,
    double? paymentTotal,
    List<DeliveryHistoryEntry>? history,
  }) =>
      DeliveryModel(
        record: record,
        orderId: orderId,
        orderNumber: orderNumber,
        customerName: customerName,
        method: method ?? this.method,
        status: status ?? this.status,
        scheduledAt: clearSchedule ? null : scheduledAt ?? this.scheduledAt,
        responsible: responsible ?? this.responsible,
        address: address ?? this.address,
        reference: reference ?? this.reference,
        contact: contact ?? this.contact,
        deliveryFee: deliveryFee ?? this.deliveryFee,
        notes: notes ?? this.notes,
        paymentPending: paymentPending ?? this.paymentPending,
        paymentTotal: paymentTotal ?? this.paymentTotal,
        history: history ?? this.history,
      );
}
