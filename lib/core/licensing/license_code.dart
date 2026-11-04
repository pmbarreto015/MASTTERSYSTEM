import 'dart:convert';

import 'package:crypto/crypto.dart';

// Este segredo existe apenas no projeto-fonte e no binário compilado. O
// gerador em tool/ não deve ser enviado junto com a pasta Release ao cliente.
const String _licenseSecret =
    'MastterSystem-ERP-2026-PB-Offline-License-v1-8f4c2a91';

String installationCodeFromFingerprint(String fingerprint) {
  final digest = sha256.convert(utf8.encode(fingerprint.trim().toUpperCase()));
  final value =
      BigInt.parse(digest.toString(), radix: 16) % BigInt.from(1000000000000);
  return value.toString().padLeft(12, '0');
}

String activationCodeForInstallation(String installationCode) {
  final normalized = installationCode.replaceAll(RegExp(r'\D'), '');
  final hmac = Hmac(sha256, utf8.encode(_licenseSecret));
  final digest = hmac.convert(utf8.encode('PC:$normalized'));
  final value =
      BigInt.parse(digest.toString(), radix: 16) % BigInt.from(1000000);
  return value.toString().padLeft(6, '0');
}

String formatInstallationCode(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '').padLeft(12, '0');
  return '${digits.substring(0, 4)}-${digits.substring(4, 8)}-${digits.substring(8, 12)}';
}

String normalizeOnlineLicenseKey(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String formatOnlineLicenseKey(String value) {
  final normalized = normalizeOnlineLicenseKey(value);
  final parts = <String>[];
  for (var index = 0; index < normalized.length; index += 4) {
    final end = index + 4 < normalized.length ? index + 4 : normalized.length;
    parts.add(normalized.substring(index, end));
  }
  return parts.join('-');
}
