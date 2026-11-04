import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/core/database/remote_database.dart';
import 'package:masttersystem/services/database_server_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  const originalToken = 'original-controller-access-token-32-characters';
  const replacementToken = 'replacement-controller-access-token-32-characters';
  final controller = DatabaseServerController();
  Directory? temporaryDirectory;
  ServerSocket? occupiedSocket;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await controller.configure(enabled: false, token: '');
    await AppDatabase().close();

    temporaryDirectory = await Directory.systemTemp.createTemp(
      'matterdi_server_controller_test_',
    );
    final databasePath = path.join(temporaryDirectory!.path, 'controller.db');
    final fixture = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 29,
        singleInstance: false,
        onCreate: (database, _) => database.execute(
          'CREATE TABLE records (id INTEGER PRIMARY KEY, name TEXT)',
        ),
      ),
    );
    await fixture.close();

    SharedPreferences.setMockInitialValues({
      AppDatabase.databaseModeKey: AppDatabase.sharedMode,
      AppDatabase.databasePathKey: databasePath,
    });
    await AppDatabase().database;
  });

  tearDown(() async {
    try {
      await controller.configure(enabled: false, token: '');
    } finally {
      try {
        await AppDatabase().close();
      } finally {
        await occupiedSocket?.close();
        occupiedSocket = null;
        final directory = temporaryDirectory;
        temporaryDirectory = null;
        if (directory != null && await directory.exists()) {
          // Exclusivamente a pasta devolvida por createTemp neste teste.
          await directory.delete(recursive: true);
        }
      }
    }
  });

  test('porta ocupada preserva servidor, chave e preferências anteriores',
      () async {
    final originalPort = await _availablePort();
    await controller.configure(
      enabled: true,
      token: originalToken,
      port: originalPort,
    );
    final url = 'http://127.0.0.1:$originalPort';
    final initialConnection = await RemoteDatabase.connect(
      serverUrl: url,
      token: originalToken,
    );
    try {
      await initialConnection.insert('records', {'name': 'servidor original'});
    } finally {
      await initialConnection.close();
    }

    occupiedSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final unavailablePort = occupiedSocket!.port;
    expect(unavailablePort, greaterThanOrEqualTo(1024));
    expect(unavailablePort, isNot(originalPort));

    await expectLater(
      controller.configure(
        enabled: true,
        token: replacementToken,
        port: unavailablePort,
      ),
      throwsA(isA<SocketException>()),
    );

    expect(controller.isRunning, isTrue);
    expect(controller.port, originalPort);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(DatabaseServerController.enabledKey), isTrue);
    expect(preferences.getString(DatabaseServerController.tokenKey),
        originalToken);
    expect(preferences.getInt(DatabaseServerController.portKey), originalPort);

    final restoredConnection = await RemoteDatabase.connect(
      serverUrl: url,
      token: originalToken,
    );
    try {
      expect(
        (await restoredConnection.query('records')).single['name'],
        'servidor original',
      );
    } finally {
      await restoredConnection.close();
    }
    await expectLater(
      RemoteDatabase.connect(serverUrl: url, token: replacementToken),
      throwsA(isA<RemoteDatabaseException>()),
    );
  });

  test('desativação aceita chave vazia e encerra o servidor ativo', () async {
    await controller.configure(
      enabled: true,
      token: originalToken,
      port: await _availablePort(),
    );
    expect(controller.isRunning, isTrue);

    await controller.configure(enabled: false, token: '', port: 0);

    expect(controller.isRunning, isFalse);
    expect(controller.port, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(DatabaseServerController.enabledKey), isFalse);
  });
}

Future<int> _availablePort() async {
  final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    expect(socket.port, greaterThanOrEqualTo(1024));
    return socket.port;
  } finally {
    await socket.close();
  }
}
