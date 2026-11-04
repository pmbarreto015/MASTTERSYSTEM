import 'dart:convert';

class ErpModuleRecord {
  ErpModuleRecord({
    this.id,
    required this.module,
    required this.recordType,
    required this.title,
    this.status = 'ativo',
    Map<String, dynamic> payload = const {},
    this.referenceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : payload = Map<String, dynamic>.from(payload),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ErpModuleRecord.fromMap(Map<String, dynamic> map) {
    final raw = map['payload'];
    final value = raw is String ? jsonDecode(raw) : raw;
    if (value is! Map)
      throw const FormatException('Registro de módulo inválido.');
    return ErpModuleRecord(
      id: (map['id'] as num?)?.toInt(),
      module: map['module'] as String,
      recordType: map['record_type'] as String,
      title: map['title'] as String,
      status: map['status'] as String? ?? 'ativo',
      payload: Map<String, dynamic>.from(value),
      referenceId: map['reference_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final int? id;
  final String module;
  final String recordType;
  final String title;
  final String status;
  final Map<String, dynamic> payload;
  final String? referenceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'module': module,
        'record_type': recordType,
        'title': title,
        'status': status,
        'payload': jsonEncode(payload),
        'reference_id': referenceId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  ErpModuleRecord copyWith({
    int? id,
    String? module,
    String? recordType,
    String? title,
    String? status,
    Map<String, dynamic>? payload,
    String? referenceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ErpModuleRecord(
        id: id ?? this.id,
        module: module ?? this.module,
        recordType: recordType ?? this.recordType,
        title: title ?? this.title,
        status: status ?? this.status,
        payload: payload ?? this.payload,
        referenceId: referenceId ?? this.referenceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
