import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../core/licensing/license_trust.dart';
import '../core/licensing/offline_license.dart';

/// Gerador exclusivo do ADM. Os clientes importam apenas o verificador.
class OfflineLicenseIssuer {
  OfflineLicenseIssuer({
    required String privateKeySeed,
    required this.keyId,
  }) : _seed = decodeOfflineLicenseBase64(privateKeySeed, allowPadding: true) {
    if (_seed.length != 32 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(keyId)) {
      throw const FormatException('Chave privada de emissão inválida.');
    }
  }

  final List<int> _seed;
  final String keyId;

  static const String _compiledSeed =
      String.fromEnvironment('OFFLINE_LICENSE_PRIVATE_KEY');
  static const String _compiledKeyId =
      String.fromEnvironment('OFFLINE_LICENSE_KEY_ID');

  static bool get isCompiledKeyConfigured =>
      _compiledSeed.isNotEmpty && _compiledKeyId.isNotEmpty;

  static Future<OfflineLicenseIssuer> fromCompiledKey() async {
    if (!isCompiledKeyConfigured) {
      throw StateError(
          'Emissão offline indisponível. Prepare as chaves e recompile o ADM.');
    }
    final issuer = OfflineLicenseIssuer(
        privateKeySeed: _compiledSeed, keyId: _compiledKeyId);
    final pair = await Ed25519().newKeyPairFromSeed(issuer._seed);
    final publicKey = await pair.extractPublicKey();
    final expectedPublicKey = LicenseTrust.publicKeys[issuer.keyId];
    if (expectedPublicKey == null ||
        expectedPublicKey != encodeOfflineLicenseBase64(publicKey.bytes)) {
      throw StateError(
          'A chave privada do ADM não corresponde à chave pública dos clientes.');
    }
    return issuer;
  }

  Future<String> issue({
    required String customerName,
    required String installationCode,
    required String platform,
    required DateTime expiresAt,
    DateTime? now,
  }) async {
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final expiry = expiresAt.toUtc();
    if (!expiry.isAfter(issuedAt)) {
      throw const FormatException('Escolha uma data de vencimento futura.');
    }
    final claims = OfflineLicenseClaims.fromJson(OfflineLicenseClaims(
      id: const Uuid().v4(),
      customerName: customerName.trim(),
      installationCode: installationCode,
      platform: platform,
      issuedAt: issuedAt,
      expiresAt: expiry,
    ).toJson());
    final payload =
        encodeOfflineLicenseBase64(utf8.encode(jsonEncode(claims.toJson())));
    final message = 'MSL1.$keyId.$payload';
    final pair = await Ed25519().newKeyPairFromSeed(_seed);
    final signature = await Ed25519().sign(utf8.encode(message), keyPair: pair);
    return '$message.${encodeOfflineLicenseBase64(signature.bytes)}';
  }
}
