class SupplierModel {
  SupplierModel({
    this.id,
    required this.name,
    this.document = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.product = '',
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupplierModel.create({
    required String name,
    String document = '',
    String phone = '',
    String email = '',
    String address = '',
    String product = '',
    bool active = true,
  }) {
    final now = DateTime.now();
    return SupplierModel(
      name: name,
      document: document,
      phone: phone,
      email: email,
      address: address,
      product: product,
      active: active,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      id: map['id'],
      name: map['name'] ?? '',
      document: map['document'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      address: map['address'] ?? '',
      product: map['product'] ?? '',
      active: map['active'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
  final int? id;
  final String name;
  final String document;
  final String phone;
  final String email;
  final String address;
  final String product;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'document': document,
        'phone': phone,
        'email': email,
        'address': address,
        'product': product,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  SupplierModel copyWith({
    String? name,
    String? document,
    String? phone,
    String? email,
    String? address,
    String? product,
    bool? active,
  }) =>
      SupplierModel(
        id: id,
        name: name ?? this.name,
        document: document ?? this.document,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        product: product ?? this.product,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
