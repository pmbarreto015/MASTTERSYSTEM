import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SupabaseService {
  factory SupabaseService() => _instance;

  SupabaseService._() : _client = http.Client();

  /// Allows deterministic HTTP tests without changing the application client.
  SupabaseService.forTesting(http.Client client) : _client = client;

  static final SupabaseService _instance = SupabaseService._();

  static const _sessionProjectKey = 'supabase_session_project';
  static const _accessTokenKey = 'supabase_access_token';
  static const _refreshTokenKey = 'supabase_refresh_token';
  static const _expiresAtKey = 'supabase_expires_at';
  static const _userIdKey = 'supabase_user_id';

  final http.Client _client;
  String _baseUrl = '';
  String _publishableKey = '';
  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  DateTime? _expiresAt;
  int _sessionGeneration = 0;
  Future<void>? _refreshing;
  Future<void> _sessionPersistence = Future<void>.value();

  String get baseUrl => _baseUrl;
  String? get currentUserId => _userId;
  bool get hasSession => _accessToken != null && _refreshToken != null;

  static String normalizeProjectUrl(String value) {
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Informe a URL HTTPS do projeto Supabase, sem caminho adicional.',
      );
    }
    return uri.replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
  }

  static String validatePublishableKey(String value) {
    final key = value.trim();
    if (key.startsWith('sb_secret_')) {
      throw const FormatException(
        'Use somente a chave pública Publishable. Não use Secret key.',
      );
    }
    if (key.startsWith('sb_publishable_') && key.length >= 24) return key;

    final parts = key.split('.');
    if (parts.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ) as Map<String, dynamic>;
        final role = payload['role']?.toString();
        if (role == 'anon') return key;
        if (role == 'service_role') {
          throw const FormatException(
            'Não use a chave service_role no aplicativo.',
          );
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        // A mensagem genérica abaixo não revela o conteúdo da chave inválida.
      }
    }
    throw const FormatException(
      'Informe a chave pública Publishable do projeto Supabase.',
    );
  }

  Future<void> configure({
    required String projectUrl,
    required String publishableKey,
  }) async {
    final normalizedUrl = normalizeProjectUrl(projectUrl);
    final validatedKey = validatePublishableKey(publishableKey);
    final generation = ++_sessionGeneration;
    _refreshing = null;
    final changedKey = _baseUrl.isNotEmpty &&
        (_baseUrl != normalizedUrl || _publishableKey != validatedKey);
    final clearing = changedKey ? _clearSession() : null;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _sessionGeneration) {
      throw const SupabaseException('A configuração da conexão foi cancelada.');
    }
    final storedProject = prefs.getString(_sessionProjectKey);
    final changedProject = storedProject != null &&
        storedProject.isNotEmpty &&
        storedProject != normalizedUrl;
    if (clearing != null) await clearing;
    if (changedProject && !changedKey) await _clearSession();
    if (generation != _sessionGeneration) {
      throw const SupabaseException('A configuração da conexão foi cancelada.');
    }
    _baseUrl = normalizedUrl;
    _publishableKey = validatedKey;
  }

  Future<bool> restoreSession() async {
    _requireConfigured();
    final generation = _sessionGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _sessionGeneration) return false;
    if (prefs.getString(_sessionProjectKey) != _baseUrl) {
      await _clearSession();
      return false;
    }

    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _userId = prefs.getString(_userIdKey);
    final expiresAtMillis = prefs.getInt(_expiresAtKey);
    _expiresAt = expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis, isUtc: true);
    if (!hasSession || _userId == null) {
      await _clearSession();
      return false;
    }

    try {
      await _ensureFreshSession();
      return generation == _sessionGeneration && hasSession;
    } on SupabaseException {
      if (generation == _sessionGeneration) await _clearSession();
      return false;
    }
  }

  Future<String> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _requireConfigured();
    final generation = ++_sessionGeneration;
    final response = await _send(
      'POST',
      _uri('/auth/v1/token', {'grant_type': 'password'}),
      headers: _publicHeaders(),
      body: {'email': email.trim(), 'password': password},
    );
    final json = _decodeObject(response);
    if (generation != _sessionGeneration) {
      throw const SupabaseException('A tentativa de login foi cancelada.');
    }
    if (!await _storeSession(json, generation: generation) ||
        generation != _sessionGeneration) {
      throw const SupabaseException('A tentativa de login foi cancelada.');
    }
    if (_userId == null || _userId!.isEmpty) {
      await clearLocalSession();
      throw const SupabaseException(
        'O Supabase não retornou o identificador do usuário.',
      );
    }
    return _userId!;
  }

  Future<void> signOut() async {
    final token = _accessToken;
    final logoutUrl = _baseUrl;
    final logoutKey = _publishableKey;
    _sessionGeneration++;
    _refreshing = null;
    await _clearSession();
    if (token == null || logoutUrl.isEmpty || logoutKey.isEmpty) return;
    try {
      await _send(
        'POST',
        Uri.parse('$logoutUrl/auth/v1/logout'),
        headers: _headersForKey(logoutKey, accessToken: token),
        body: const <String, Object?>{},
      );
    } catch (_) {
      // A sessão local já foi encerrada; falha de rede não deve reativá-la.
    }
  }

  Future<void> clearLocalSession() async {
    _sessionGeneration++;
    _refreshing = null;
    await _clearSession();
  }

  Future<void> updateOwnPassword(String password) async {
    if (password.length < 6) {
      throw const SupabaseException(
          'A nova senha deve ter pelo menos 6 caracteres.');
    }
    final generation = _sessionGeneration;
    await _ensureFreshSession();
    if (generation != _sessionGeneration) {
      throw const SupabaseException(
          'A operação foi cancelada. Entre novamente.');
    }
    await _send(
      'PUT',
      _uri('/auth/v1/user'),
      headers: _publicHeaders(accessToken: _accessToken),
      body: {'password': password},
    );
  }

  Future<dynamic> rpc(
    String name,
    Map<String, Object?> params, {
    bool requireSession = true,
  }) async {
    _validateFunctionName(name);
    final generation = _sessionGeneration;
    if (requireSession) await _ensureFreshSession();
    if (generation != _sessionGeneration) {
      throw const SupabaseException(
          'A operação foi cancelada. Entre novamente.');
    }
    final response = await _send(
      'POST',
      _uri('/rest/v1/rpc/$name'),
      headers: {
        ..._publicHeaders(
          accessToken: requireSession ? _accessToken : null,
        ),
        'Accept-Profile': 'public',
        'Content-Profile': 'public',
      },
      body: params,
    );
    return _decodeAny(response);
  }

  Future<dynamic> invokeFunction(
    String name,
    Map<String, Object?> body,
  ) async {
    _validateFunctionName(name, allowHyphen: true);
    final generation = _sessionGeneration;
    await _ensureFreshSession();
    if (generation != _sessionGeneration) {
      throw const SupabaseException(
          'A operação foi cancelada. Entre novamente.');
    }
    final response = await _send(
      'POST',
      _uri('/functions/v1/$name'),
      headers: _publicHeaders(accessToken: _accessToken),
      body: body,
    );
    return _decodeAny(response);
  }

  Future<void> testConnection({
    required String projectUrl,
    required String publishableKey,
  }) async {
    final url = normalizeProjectUrl(projectUrl);
    final key = validatePublishableKey(publishableKey);
    final settings = await _send(
      'GET',
      Uri.parse('$url/auth/v1/settings'),
      headers: _headersForKey(key),
    );
    _decodeObject(settings);

    final health = await _send(
      'POST',
      Uri.parse('$url/rest/v1/rpc/matterdi_health'),
      headers: {
        ..._headersForKey(key),
        'Accept-Profile': 'public',
        'Content-Profile': 'public',
      },
      body: const <String, Object?>{},
    );
    final result = _decodeAny(health);
    final map = result is List && result.isNotEmpty ? result.first : result;
    if (map is! Map ||
        map['service'] != 'matterdi-supabase' ||
        map['protocol'] != 1 ||
        map['version'] != 29 ||
        map['ready'] != true) {
      throw const SupabaseException(
        'O projeto respondeu, mas ainda não recebeu as tabelas do MatterdiSistem.',
      );
    }
  }

  Future<void> _ensureFreshSession() async {
    _requireConfigured();
    if (!hasSession) {
      throw const SupabaseException(
        'Sua sessão expirou. Entre novamente no sistema.',
        statusCode: 401,
      );
    }
    final expiresAt = _expiresAt;
    if (expiresAt != null &&
        expiresAt
            .isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2)))) {
      return;
    }
    final pending = _refreshing;
    if (pending != null) return pending;
    final refresh = _refreshSession();
    _refreshing = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_refreshing, refresh)) _refreshing = null;
    }
  }

  Future<void> _refreshSession() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      throw const SupabaseException('Sua sessão expirou.', statusCode: 401);
    }
    final generation = _sessionGeneration;
    try {
      final response = await _send(
        'POST',
        _uri('/auth/v1/token', {'grant_type': 'refresh_token'}),
        headers: _publicHeaders(),
        body: {'refresh_token': refreshToken},
      );
      if (generation != _sessionGeneration ||
          !await _storeSession(_decodeObject(response),
              generation: generation) ||
          generation != _sessionGeneration) {
        throw const SupabaseException('A renovação da sessão foi cancelada.');
      }
    } on SupabaseException {
      if (generation == _sessionGeneration) {
        await _clearSession();
      }
      rethrow;
    }
  }

  Future<bool> _storeSession(
    Map<String, dynamic> json, {
    required int generation,
  }) async {
    final accessToken = json['access_token']?.toString();
    final refreshToken = json['refresh_token']?.toString();
    final user = json['user'];
    final userId =
        user is Map ? user['id']?.toString() : _jwtSubject(accessToken);
    if (accessToken == null || refreshToken == null || userId == null) {
      throw const SupabaseException('Resposta de autenticação inválida.');
    }
    final expiresIn = _integer(json['expires_in']) ?? 3600;
    final expiresAtSeconds = _integer(json['expires_at']);
    final expiresAt = expiresAtSeconds == null
        ? DateTime.now().toUtc().add(Duration(seconds: expiresIn))
        : DateTime.fromMillisecondsSinceEpoch(
            expiresAtSeconds * 1000,
            isUtc: true,
          );

    final projectUrl = _baseUrl;
    return _serializeSession(() async {
      if (generation != _sessionGeneration) return false;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _sessionGeneration) return false;
      _accessToken = accessToken;
      _refreshToken = refreshToken;
      _userId = userId;
      _expiresAt = expiresAt;
      await prefs.setString(_sessionProjectKey, projectUrl);
      await prefs.setString(_accessTokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
      await prefs.setString(_userIdKey, userId);
      await prefs.setInt(_expiresAtKey, expiresAt.millisecondsSinceEpoch);
      return generation == _sessionGeneration;
    });
  }

  Future<void> _clearSession() {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _expiresAt = null;
    return _serializeSession(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionProjectKey);
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_expiresAtKey);
      await prefs.remove(_userIdKey);
    });
  }

  Future<T> _serializeSession<T>(Future<T> Function() operation) {
    final result = _sessionPersistence.then((_) => operation());
    _sessionPersistence =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Map<String, String> _publicHeaders({String? accessToken}) =>
      _headersForKey(_publishableKey, accessToken: accessToken);

  static Map<String, String> _headersForKey(
    String key, {
    String? accessToken,
  }) =>
      {
        'apikey': key,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (accessToken != null && accessToken.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Map<String, Object?>? body,
  }) async {
    late http.Response response;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = encoded ?? '';
      final streamed = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const SupabaseException(
        'O Supabase demorou para responder. Verifique sua internet.',
      );
    } on SupabaseException {
      rethrow;
    } catch (_) {
      throw const SupabaseException(
        'Não foi possível conectar ao Supabase. Verifique sua internet.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseException(
        _messageFromResponse(response),
        statusCode: response.statusCode,
        code: _codeFromResponse(response),
      );
    }
    return response;
  }

  static dynamic _decodeAny(http.Response response) {
    if (response.body.trim().isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const SupabaseException(
          'O Supabase retornou uma resposta inválida.');
    }
  }

  static Map<String, dynamic> _decodeObject(http.Response response) {
    final value = _decodeAny(response);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    throw const SupabaseException('O Supabase retornou uma resposta inválida.');
  }

  static String _messageFromResponse(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map) {
        for (final key in const [
          'msg',
          'message',
          'error_description',
          'error'
        ]) {
          final message = value[key]?.toString().trim();
          if (message != null && message.isNotEmpty && message.length <= 300) {
            return message;
          }
        }
      }
    } catch (_) {}
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Sessão inválida ou acesso não autorizado.';
    }
    return 'O Supabase recusou a operação (código ${response.statusCode}).';
  }

  static String? _codeFromResponse(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map) {
        for (final key in const ['error_code', 'code']) {
          final code = value[key];
          if (code is String && code.isNotEmpty && code.length <= 100) {
            return code;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _jwtSubject(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map ? payload['sub']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  static int? _integer(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static void _validateFunctionName(String name, {bool allowHyphen = false}) {
    if (!RegExp(allowHyphen ? r'^[a-z][a-z0-9_-]*$' : r'^[a-z][a-z0-9_]*$')
        .hasMatch(name)) {
      throw ArgumentError('Nome de função inválido.');
    }
  }

  void _requireConfigured() {
    if (_baseUrl.isEmpty || _publishableKey.isEmpty) {
      throw const SupabaseException(
        'Configure o endereço e a chave pública do Supabase.',
      );
    }
  }
}

class SupabaseException implements Exception {
  const SupabaseException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
