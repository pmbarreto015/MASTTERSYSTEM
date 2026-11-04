import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/core/licensing/offline_license.dart';
import 'package:masttersystem/services/offline_license_issuer.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);
  final expiry = now.add(const Duration(days: 7));
  final seed = List<int>.generate(32, (index) => index);
  const keyId = 'test_issuer';
  late OfflineLicenseIssuer issuer;
  late OfflineLicenseVerifier verifier;
  late SimpleKeyPair pair;

  setUpAll(() async {
    pair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await pair.extractPublicKey();
    verifier = OfflineLicenseVerifier(trustedKeys: {
      keyId: encodeOfflineLicenseBase64(publicKey.bytes),
    });
    issuer = OfflineLicenseIssuer(
        privateKeySeed: encodeOfflineLicenseBase64(seed), keyId: keyId);
  });

  Future<String> issue({String platform = 'windows'}) => issuer.issue(
        customerName: 'Cliente de teste',
        installationCode: '123456789012',
        platform: platform,
        expiresAt: expiry,
        now: now,
      );

  Future<String> signedPayload(Map<String, dynamic> payload) async {
    final encoded =
        encodeOfflineLicenseBase64(utf8.encode(jsonEncode(payload)));
    final message = 'MSL1.$keyId.$encoded';
    final signature = await Ed25519().sign(utf8.encode(message), keyPair: pair);
    return '$message.${encodeOfflineLicenseBase64(signature.bytes)}';
  }

  test('licença assinada preserva cliente, aparelho, plataforma e prazo UTC',
      () async {
    final claims = await verifier.verify(await issue());
    expect(claims.id, isNotEmpty);
    expect(claims.customerName, 'Cliente de teste');
    expect(claims.installationCode, '123456789012');
    expect(claims.platform, 'windows');
    expect(claims.issuedAt, now);
    expect(claims.expiresAt, expiry);
    expect(claims.expiresAt.isUtc, isTrue);
    expect((await verifier.verify(await issue(platform: 'android'))).platform,
        'android');
  });

  test('verificador aceita código copiado com espaços externos', () async {
    expect(await verifier.verify('  ${await issue()}\n'),
        isA<OfflineLicenseClaims>());
  });

  test('chaves de configuração aceitam base64url padrão com padding', () async {
    final publicKey = await pair.extractPublicKey();
    final standardVerifier = OfflineLicenseVerifier(
        trustedKeys: {keyId: base64UrlEncode(publicKey.bytes)});
    final standardIssuer = OfflineLicenseIssuer(
        privateKeySeed: base64UrlEncode(seed), keyId: keyId);
    final code = await standardIssuer.issue(
        customerName: 'Cliente',
        installationCode: '123456789012',
        platform: 'windows',
        expiresAt: expiry,
        now: now);
    expect(await standardVerifier.verify(code), isA<OfflineLicenseClaims>());
  });

  test('adulterar aparelho, plataforma ou prazo invalida assinatura', () async {
    final code = await issue();
    final parts = code.split('.');
    final original =
        jsonDecode(utf8.decode(decodeOfflineLicenseBase64(parts[2])))
            as Map<String, dynamic>;
    for (final replacement in <String, Object>{
      'installationCode': '111111111111',
      'platform': 'android',
      'expiresAt': expiry.add(const Duration(days: 365)).toIso8601String(),
    }.entries) {
      final payload = {...original, replacement.key: replacement.value};
      final encoded =
          encodeOfflineLicenseBase64(utf8.encode(jsonEncode(payload)));
      final tampered = '${parts[0]}.${parts[1]}.$encoded.${parts[3]}';
      await expectLater(verifier.verify(tampered), throwsFormatException);
    }
  });

  test('assinatura de outra chave é rejeitada', () async {
    final attacker = OfflineLicenseIssuer(
        privateKeySeed: encodeOfflineLicenseBase64(List.filled(32, 99)),
        keyId: keyId);
    final code = await attacker.issue(
        customerName: 'Cliente',
        installationCode: '123456789012',
        platform: 'windows',
        expiresAt: expiry,
        now: now);
    await expectLater(verifier.verify(code), throwsFormatException);
  });

  test('chave emissora desconhecida é rejeitada', () async {
    final code = (await issue()).replaceFirst('.$keyId.', '.unknown_key.');
    await expectLater(verifier.verify(code), throwsFormatException);
  });

  test('assinatura corrompida é rejeitada', () async {
    final parts = (await issue()).split('.');
    final bytes = decodeOfflineLicenseBase64(parts[3]);
    bytes[0] ^= 1;
    parts[3] = encodeOfflineLicenseBase64(bytes);
    await expectLater(verifier.verify(parts.join('.')), throwsFormatException);
  });

  test('schema inválido é rejeitado mesmo quando está assinado', () async {
    final payload = (await verifier.verify(await issue())).toJson();
    for (final replacement in <String, Object?>{
      'v': 2,
      'id': '',
      'customerName': ' ',
      'installationCode': '123',
      'platform': 'ios',
      'issuedAt': now.toLocal().toIso8601String().replaceAll('Z', ''),
      'expiresAt': null,
    }.entries) {
      final code =
          await signedPayload({...payload, replacement.key: replacement.value});
      await expectLater(verifier.verify(code), throwsFormatException);
    }
    await expectLater(
        verifier.verify(await signedPayload({...payload, 'extra': true})),
        throwsFormatException);
  });

  test('datas impossíveis e prazo anterior à emissão são rejeitados', () async {
    final payload = (await verifier.verify(await issue())).toJson();
    for (final value in [
      '2026-02-30T12:00:00.000Z',
      now.subtract(const Duration(seconds: 1)).toIso8601String(),
      now.toIso8601String(),
    ]) {
      final code = await signedPayload({...payload, 'expiresAt': value});
      await expectLater(verifier.verify(code), throwsFormatException);
    }
  });

  test('verificador deixa expiração e vínculo de aparelho para o serviço',
      () async {
    final pastIssuer = now.subtract(const Duration(days: 3000));
    final code = await issuer.issue(
        customerName: 'Licença antiga',
        installationCode: '999999999999',
        platform: 'android',
        expiresAt: pastIssuer.add(const Duration(days: 1)),
        now: pastIssuer);
    expect((await verifier.verify(code)).installationCode, '999999999999');
  });

  test('emissor rejeita prazo vencido e aparelho inválido', () async {
    await expectLater(
        issuer.issue(
            customerName: 'Cliente',
            installationCode: '123456789012',
            platform: 'windows',
            expiresAt: now,
            now: now),
        throwsFormatException);
    await expectLater(
        issuer.issue(
            customerName: 'Cliente',
            installationCode: '1234-5678-9012',
            platform: 'windows',
            expiresAt: expiry,
            now: now),
        throwsFormatException);
  });

  test('formato, tamanho e base64 não canônico são rejeitados', () async {
    final code = await issue();
    final parts = code.split('.');
    for (final invalid in [
      '',
      '123456',
      code.replaceFirst('MSL1', 'MSL2'),
      '$code.extra',
      '${parts[0]}.${parts[1]}.${parts[2]}=.${parts[3]}',
      'x' * 8193,
    ]) {
      await expectLater(verifier.verify(invalid), throwsFormatException);
    }
  });
}
