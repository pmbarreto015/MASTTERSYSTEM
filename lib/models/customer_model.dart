class CustomerModel {
  final int? id;
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String? document;
  final String? observations;
  final double totalPurchases;
  final String? uuid;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;

  CustomerModel({
    this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.document,
    this.observations,
    this.totalPurchases = 0,
    this.uuid,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory CustomerModel.create({
    required String name,
    required String phone,
    String? email,
    String? address,
    String? document,
    String? observations,
    double totalPurchases = 0,
  }) {
    final now = DateTime.now().toIso8601String();
    return CustomerModel(
      name: name,
      phone: phone,
      email: email,
      address: address,
      document: document,
      observations: observations,
      totalPurchases: totalPurchases,
      uuid: 'cus_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: now,
      updatedAt: now,
    );
  }

  CustomerModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? document,
    String? observations,
    double? totalPurchases,
    String? uuid,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      document: document ?? this.document,
      observations: observations ?? this.observations,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      uuid: uuid ?? this.uuid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'document': document,
      'observations': observations,
      'total_purchases': totalPurchases,
      'uuid': uuid,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'],
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      address: map['address'],
      document: map['document'],
      observations: map['observations'],
      totalPurchases: (map['total_purchases'] ?? 0).toDouble(),
      uuid: map['uuid'],
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
      deletedAt: map['deleted_at'],
    );
  }

  String get formattedPhone {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 11) {
      return '(${clean.substring(0, 2)}) ${clean.substring(2, 7)}-${clean.substring(7)}';
    } else if (clean.length == 10) {
      return '(${clean.substring(0, 2)}) ${clean.substring(2, 6)}-${clean.substring(6)}';
    }
    return phone;
  }

  Map<String, dynamic> validate() {
    final errors = <String>[];

    if (name.trim().isEmpty) {
      errors.add('Nome é obrigatório');
    }

    if (phone.isNotEmpty) {
      final clean = phone.replaceAll(RegExp(r'\D'), '');
      if (clean.length != 10 && clean.length != 11) {
        errors.add('Telefone inválido (DDD + 8 ou 9 dígitos)');
      }
    }

    if (email != null && email!.isNotEmpty) {
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      if (!emailRegex.hasMatch(email!)) {
        errors.add('E-mail inválido');
      }
    }

    if (document != null && document!.isNotEmpty) {
      final clean = document!.replaceAll(RegExp(r'\D'), '');
      if (clean.length != 11 && clean.length != 14) {
        errors.add('CPF/CNPJ inválido');
      }
    }

    return {
      'valid': errors.isEmpty,
      'errors': errors,
    };
  }
}
