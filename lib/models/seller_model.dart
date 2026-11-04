class SellerModel {
  final int? id;
  final String name;
  final String phone;
  final String email;
  final double commission;
  final double totalSales;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  SellerModel({
    this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.commission,
    this.totalSales = 0,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SellerModel.create({
    required String name,
    required String phone,
    required String email,
    required double commission,
    bool active = true,
  }) {
    final now = DateTime.now();
    return SellerModel(
      name: name,
      phone: phone,
      email: email,
      commission: commission,
      active: active,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory SellerModel.fromMap(Map<String, dynamic> map) {
    return SellerModel(
      id: map['id'],
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      commission: (map['commission'] ?? 0).toDouble(),
      totalSales: (map['total_sales'] ?? 0).toDouble(),
      active: map['active'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'commission': commission,
      'total_sales': totalSales,
      'active': active ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SellerModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    double? commission,
    double? totalSales,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SellerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      commission: commission ?? this.commission,
      totalSales: totalSales ?? this.totalSales,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
