import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'license_trust.dart';

/// Dados autenticados da licença. A validade atual e o aparelho são conferidos
/// pelo serviço cliente depois da verificação da assinatura.
class OfflineLicenseClaims {
  const OfflineLicenseClaims({
    required this.id,
    required this.customerName,
    required this.installationCode,
    required this.platform,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String id;
  final String customerName;
  final String installationCode;
  final String platform;
  final DateTime issuedAt;
  final DateTime expiresAt;

  Map<String, Object> toJson() => <String, Object>{
        'v': 1,
        'id': id,
        'customerName': customerName,
        'installationCode': installationCode,
        'platform': platform,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };

  factory OfflineLicenseClaims.fromJson(Map<String, dynamic> json) {
    const fields = <String>{
      'v',
      'id',
      'customerName',
      'installationCode',
      'platform',
      'issuedAt',
      'expiresAt',
    };
    if (json.length != fields.length ||
        !fields.every(json.containsKey) ||
        json['v'] is! int ||
        json['v'] != 1) {
      throw const FormatException('Versão ou dados da licença inválidos.');
    }
    final id = _requiredString(json, 'id', 128);
    final customerName = _requiredString(json, 'customerName', 200);
    final installationCode = _requiredString(json, 'installationCode', 12);
    final platform = _requiredString(json, 'platform', 16);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        !RegExp(r'^\d{12}$').hasMatch(installationCode) ||
        (platform != 'windows' && platform != 'android')) {
      throw const FormatException(
          'Aparelho ou plataforma da licença inválidos.');
    }
    final issuedAt = _requiredUtcDate(json, 'issuedAt');
    final expiresAt = _requiredUtcDate(json, 'expiresAt');
    if (!expiresAt.isAfter(issuedAt)) {
      throw const FormatException(
          'O prazo da licença deve ser posterior à emissão.');
    }
    return OfflineLicenseClaims(
      id: id,
      customerName: customerName,
      installationCode: installationCode,
      platform: platform,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  static String _requiredString(
      Map<String, dynamic> json, String field, int maxLength) {
    final value = json[field];
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        value != value.trim() ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('Dados da licença inválidos.');
    }
    return value;
  }

  static DateTime _requiredUtcDate(Map<String, dynamic> json, String field) {
    final value = _requiredString(json, field, 32);
    final parsed = DateTime.tryParse(value);
    // Exige a representação UTC canônica emitida pelo ADM. Isso também rejeita
    // datas impossíveis que DateTime.parse normalizaria para o mês seguinte.
    if (parsed == null ||
        !parsed.isUtc ||
        parsed.year < 1970 ||
        parsed.year > 9999 ||
        parsed.toIso8601String() != value) {
      throw const FormatException('Data da licença inválida; utilize UTC.');
    }
    return parsed;
  }
}

/// Verifica somente autenticidade e estrutura. Não consulta a rede e não
/// contém a chave privada utilizada no ADM.
class OfflineLicenseVerifier {
  OfflineLicenseVerifier({Map<String, String>? trustedKeys})
      : _trustedKeys = Map.unmodifiable(trustedKeys ?? LicenseTrust.publicKeys);

  final Map<String, String> _trustedKeys;

  Future<OfflineLicenseClaims> verify(String code) async {
    if (code.length > 8192) {
      throw const FormatException('Código de licença muito longo.');
    }
    final parts = code.trim().split('.');
    if (parts.length != 4 ||
        parts[0] != 'MSL1' ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(parts[1])) {
      throw const FormatException('Código de licença offline inválido.');
    }
    final encodedPublicKey = _trustedKeys[parts[1]];
    if (encodedPublicKey == null) {
      throw const FormatException(
          'Chave emissora desconhecida. Atualize o aplicativo cliente.');
    }
    final publicBytes =
        decodeOfflineLicenseBase64(encodedPublicKey, allowPadding: true);
    final payload = decodeOfflineLicenseBase64(parts[2]);
    final signatureBytes = decodeOfflineLicenseBase64(parts[3]);
    if (publicBytes.length != 32 ||
        payload.isEmpty ||
        payload.length > 6000 ||
        signatureBytes.length != 64) {
      throw const FormatException('Código de licença offline inválido.');
    }
    final signedBytes = utf8.encode(parts.take(3).join('.'));
    final verified = await Ed25519().verify(
      signedBytes,
      signature: Signature(signatureBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519)),
    );
    if (!verified) {
      throw const FormatException('Assinatura da licença inválida.');
    }
    final dynamic json;
    try {
      json = jsonDecode(utf8.decode(payload));
    } on FormatException {
      throw const FormatException('Dados da licença inválidos.');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Dados da licença inválidos.');
    }
    return OfflineLicenseClaims.fromJson(json);
  }
}

String encodeOfflineLicenseBase64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> decodeOfflineLicenseBase64(String value,
    {bool allowPadding = false}) {
  final pattern =
      allowPadding ? r'^[A-Za-z0-9_-]+={0,2}$' : r'^[A-Za-z0-9_-]+$';
  if (value.isEmpty || !RegExp(pattern).hasMatch(value)) {
    throw const FormatException('Codificação da licença inválida.');
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (encodeOfflineLicenseBase64(bytes) != value &&
        !(allowPadding && base64Url.encode(bytes) == value)) {
      throw const FormatException('Codificação da licença inválida.');
    }
    return bytes;
  } on FormatException {
    throw const FormatException('Codificação da licença inválida.');
  }
}
