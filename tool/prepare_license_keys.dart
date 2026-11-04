import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'package:masttersystem/core/licensing/license_trust.dart';
import 'package:masttersystem/core/licensing/offline_license.dart';

/// Gera uma única identidade de emissão. A chave privada permanece fora dos
/// assets; somente o build do ADM recebe build_defines_admin.json.
Future<void> main() async {
  final project = File.fromUri(Platform.script).parent.parent;
  final keyDirectory = Directory('${project.path}/data/licensing');
  await keyDirectory.create(recursive: true);
  final lock = await File('${keyDirectory.path}/prepare.lock')
      .open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    await _prepare(project, keyDirectory);
  } catch (error) {
    // Não escreva JSON, argumentos de build ou bytes de chave no console.
    stderr.writeln('Não foi possível preparar as chaves: $error');
    exitCode = 1;
  } finally {
    await lock.close();
  }
}

Future<void> _prepare(Directory project, Directory keyDirectory) async {
  final privateFile = File('${keyDirectory.path}/issuer_private.json');
  final definesFile = File('${keyDirectory.path}/build_defines_admin.json');
  final registryFile =
      File('${project.path}/lib/core/licensing/license_trust.dart');
  final existed = await privateFile.exists();
  late final String seed;
  late final String keyId;
  late final String publicKey;
  if (existed) {
    final privateJson = await _readObject(privateFile);
    if (privateJson['version'] != 1 ||
        privateJson['algorithm'] != 'Ed25519' ||
        privateJson['keyId'] is! String ||
        privateJson['privateKeySeed'] is! String ||
        privateJson['publicKey'] is! String) {
      throw const FormatException(
          'Arquivo privado inválido. Restaure o backup.');
    }
    seed = privateJson['privateKeySeed'] as String;
    keyId = privateJson['keyId'] as String;
    publicKey = privateJson['publicKey'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(keyId)) {
      throw const FormatException('Identificador da chave inválido.');
    }
    final seedBytes = decodeOfflineLicenseBase64(seed);
    if (seedBytes.length != 32) {
      throw const FormatException('Chave privada inválida. Restaure o backup.');
    }
    final pair = await Ed25519().newKeyPairFromSeed(seedBytes);
    final derivedPublicKey = await pair.extractPublicKey();
    if (publicKey != encodeOfflineLicenseBase64(derivedPublicKey.bytes)) {
      throw const FormatException(
          'Par de chaves incompatível. Restaure o backup.');
    }
  } else {
    if (LicenseTrust.publicKeys.isNotEmpty || await definesFile.exists()) {
      throw StateError('A chave privada anterior está ausente. Restaure '
          'data/licensing/issuer_private.json; nenhuma chave será substituída.');
    }
    final random = Random.secure();
    final seedBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final pair = await Ed25519().newKeyPairFromSeed(seedBytes);
    final derivedPublicKey = await pair.extractPublicKey();
    seed = encodeOfflineLicenseBase64(seedBytes);
    publicKey = encodeOfflineLicenseBase64(derivedPublicKey.bytes);
    keyId =
        'ed25519_${sha256.convert(derivedPublicKey.bytes).toString().substring(0, 16)}';
  }

  final registered = LicenseTrust.publicKeys[keyId];
  if (registered != null && registered != publicKey) {
    throw StateError('A chave pública registrada é incompatível. '
        'Nenhum arquivo foi substituído.');
  }
  if (await definesFile.exists()) {
    final defines = await _readObject(definesFile);
    if (defines['OFFLINE_LICENSE_PRIVATE_KEY'] != seed ||
        defines['OFFLINE_LICENSE_KEY_ID'] != keyId ||
        defines.length != 2) {
      throw StateError('As definições do ADM pertencem a outro par de chaves. '
          'Nenhum arquivo foi substituído.');
    }
  }

  const encoder = JsonEncoder.withIndent('  ');
  if (!existed) {
    await _atomicWrite(
        privateFile,
        '${encoder.convert(<String, Object>{
              'version': 1,
              'algorithm': 'Ed25519',
              'keyId': keyId,
              'privateKeySeed': seed,
              'publicKey': publicKey,
            })}\n');
  }
  // A identidade privada foi preservada antes de publicar a chave pública.
  // Uma interrupção pode ser corrigida repetindo o comando, sem gerar outro par.
  final keys = <String, String>{...LicenseTrust.publicKeys, keyId: publicKey};
  final entries = keys.entries
      .map((entry) =>
          '    ${jsonEncode(entry.key)}: ${jsonEncode(entry.value)},')
      .join('\n');
  await _atomicWrite(registryFile,
      '''// Gerado por tool/prepare_license_keys.dart. Somente chaves públicas.
class LicenseTrust {
  const LicenseTrust._();

  static const Map<String, String> publicKeys = <String, String>{
$entries
  };
}
''');
  await _atomicWrite(
      definesFile,
      '${encoder.convert(<String, Object>{
            'OFFLINE_LICENSE_PRIVATE_KEY': seed,
            'OFFLINE_LICENSE_KEY_ID': keyId,
          })}\n');

  stdout.writeln(existed
      ? 'Par de chaves existente preservado; arquivos de build atualizados.'
      : 'Par de chaves criado; chave pública registrada para os clientes.');
  stdout.writeln(
      'Definições exclusivas do ADM: data/licensing/build_defines_admin.json');
  stdout.writeln(
      'Guarde uma cópia segura de data/licensing/issuer_private.json.');
}

Future<Map<String, dynamic>> _readObject(File file) async {
  dynamic value;
  try {
    value = jsonDecode(await file.readAsString());
  } on FormatException {
    throw const FormatException(
        'Arquivo de chaves inválido. Restaure o backup.');
  }
  if (value is! Map<String, dynamic>) {
    throw const FormatException(
        'Arquivo de chaves inválido. Restaure o backup.');
  }
  return value;
}

Future<void> _atomicWrite(File destination, String content) async {
  await destination.parent.create(recursive: true);
  final temporary = File('${destination.path}.tmp_${pid}_'
      '${Random.secure().nextInt(1 << 32)}');
  try {
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
