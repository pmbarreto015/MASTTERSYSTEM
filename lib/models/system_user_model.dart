import 'dart:convert';

class SystemUserModel {
  const SystemUserModel({
    this.id,
    this.authUserId,
    required this.username,
    required this.fullName,
    this.email = '',
    this.password = '',
    this.isAdmin = false,
    this.active = true,
    this.permissions = const {},
  });

  factory SystemUserModel.fromMap(Map<String, dynamic> map) {
    final permissionsValue = map['permissions'];
    final decoded = permissionsValue is List
        ? permissionsValue
        : jsonDecode(permissionsValue?.toString() ?? '[]') as List<dynamic>;
    return SystemUserModel(
      id: (map['id'] as num?)?.toInt(),
      authUserId: map['auth_user_id']?.toString(),
      username: map['username'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      password: map['password'] as String? ?? '',
      isAdmin: _flag(map['is_admin'], fallback: false),
      active: _flag(map['active'], fallback: true),
      permissions: decoded.map((item) => item.toString()).toSet(),
    );
  }

  factory SystemUserModel.fromSession(String source) =>
      SystemUserModel.fromMap(jsonDecode(source) as Map<String, dynamic>);

  final int? id;
  final String? authUserId;
  final String username;
  final String fullName;
  final String email;
  final String password;
  final bool isAdmin;
  final bool active;
  final Set<String> permissions;

  bool can(String permission) => isAdmin || permissions.contains(permission);

  Map<String, dynamic> toMap({bool includeAuthUserId = false}) => {
        'id': id,
        if (includeAuthUserId) 'auth_user_id': authUserId,
        'username': username,
        'full_name': fullName,
        'email': email,
        'password': password,
        'is_admin': isAdmin ? 1 : 0,
        'active': active ? 1 : 0,
        'permissions': jsonEncode(permissions.toList()..sort()),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  String toSession() {
    final map = toMap(includeAuthUserId: true)
      ..remove('password')
      ..remove('created_at')
      ..remove('updated_at');
    return jsonEncode(map);
  }

  static bool _flag(dynamic value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }
}
