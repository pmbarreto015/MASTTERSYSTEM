import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/core/licensing/license_admin_config.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'masttersystem_admin_credentials_test_',
    );
    file = File('${directory.path}/license_admin_credentials.json');
    await LicenseAdminConfig.initialize(credentialsFile: file);
  });

  tearDown(() async {
    // Only the directory returned by createTemp above is removed.
    await directory.delete(recursive: true);
  });

  test('first launch requires an eight-character matching password', () async {
    expect(LicenseAdminConfig.isConfigured, isFalse);
    expect(LicenseAdminConfig.verifyPassword('admin1234'), isFalse);
    expect(await LicenseAdminConfig.configurePassword('short'), isNotNull);
    expect(await LicenseAdminConfig.configurePassword('        '), isNotNull);
    expect(
      await LicenseAdminConfig.configurePassword(
        'admin1234',
        confirmation: 'different',
      ),
      isNotNull,
    );
    expect(await file.exists(), isFalse);
    expect(LicenseAdminConfig.isConfigured, isFalse);
  });

  test('persists only a salted hash and reloads the same password', () async {
    expect(
      await LicenseAdminConfig.configurePassword(
        'admin1234',
        confirmation: 'admin1234',
      ),
      isNull,
    );
    expect(LicenseAdminConfig.isConfigured, isTrue);
    expect(LicenseAdminConfig.verifyPassword('admin1234'), isTrue);
    expect(LicenseAdminConfig.verifyPassword('incorrect'), isFalse);
    final stored = await file.readAsString();
    expect(stored, isNot(contains('admin1234')));
    final credentials = jsonDecode(stored) as Map;
    expect(credentials['salt'], isA<String>());
    expect(credentials['password_hash'], matches(r'^[a-f0-9]{64}$'));
    expect(credentials['algorithm'], 'pbkdf2-hmac-sha256');

    expect(
      await LicenseAdminConfig.configurePassword('replacement123'),
      isNotNull,
    );
    expect(await file.readAsString(), stored);
    await LicenseAdminConfig.initialize(credentialsFile: file);
    expect(LicenseAdminConfig.isConfigured, isTrue);
    expect(LicenseAdminConfig.verifyPassword('admin1234'), isTrue);
    expect(LicenseAdminConfig.verifyPassword('replacement123'), isFalse);
  });

  test('verifies a PBKDF2 fixture generated independently with Python',
      () async {
    await file.writeAsString(jsonEncode({
      'version': 1,
      'algorithm': 'pbkdf2-hmac-sha256',
      'iterations': 120000,
      'salt': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'password_hash':
          'd722b1bceba5b25aa1cee31cf7b59fce83e096b9d58ef170996c2e104b3a13bb',
    }));
    await LicenseAdminConfig.initialize(credentialsFile: file);
    expect(LicenseAdminConfig.verifyPassword('admin1234'), isTrue);
    expect(LicenseAdminConfig.verifyPassword('ADMIN1234'), isFalse);
  });

  test('corrupt stored credentials fail closed without offering a reset',
      () async {
    const corrupted = '{"password_hash":"invalid"}';
    await file.writeAsString(corrupted);
    await expectLater(
      LicenseAdminConfig.initialize(credentialsFile: file),
      throwsA(isA<StateError>()),
    );
    expect(LicenseAdminConfig.isConfigured, isFalse);
    expect(LicenseAdminConfig.verifyPassword('admin1234'), isFalse);
    expect(await LicenseAdminConfig.configurePassword('admin1234'), isNotNull);
    expect(await file.readAsString(), corrupted);
  });

  test('does not overwrite a credential file created after initialization',
      () async {
    await file.writeAsString('existing credential file');
    expect(await LicenseAdminConfig.configurePassword('admin1234'), isNotNull);
    expect(LicenseAdminConfig.isConfigured, isFalse);
    expect(await file.readAsString(), 'existing credential file');
  });
}
