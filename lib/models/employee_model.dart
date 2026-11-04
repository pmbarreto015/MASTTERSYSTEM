class EmployeeModel {
  final int? id;
  final String name;
  final String document;
  final String phone;
  final String email;
  final String position;
  final double? salary;
  final DateTime? hireDate;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmployeeModel({
    this.id,
    required this.name,
    required this.document,
    required this.phone,
    required this.email,
    required this.position,
    this.salary,
    this.hireDate,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmployeeModel.create({
    required String name,
    required String document,
    required String phone,
    required String email,
    required String position,
    double? salary,
    DateTime? hireDate,
    bool active = true,
  }) {
    final now = DateTime.now();
    return EmployeeModel(
      name: name,
      document: document,
      phone: phone,
      email: email,
      position: position,
      salary: salary,
      hireDate: hireDate,
      active: active,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    return EmployeeModel(
      id: map['id'],
      name: map['name'] ?? '',
      document: map['document'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      position: map['position'] ?? '',
      salary: map['salary']?.toDouble(),
      hireDate:
          map['hire_date'] != null ? DateTime.parse(map['hire_date']) : null,
      active: map['active'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'document': document,
      'phone': phone,
      'email': email,
      'position': position,
      'salary': salary,
      'hire_date': hireDate?.toIso8601String(),
      'active': active ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  EmployeeModel copyWith({
    int? id,
    String? name,
    String? document,
    String? phone,
    String? email,
    String? position,
    double? salary,
    DateTime? hireDate,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      document: document ?? this.document,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      position: position ?? this.position,
      salary: salary ?? this.salary,
      hireDate: hireDate ?? this.hireDate,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
