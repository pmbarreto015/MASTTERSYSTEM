import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/license_server_main.dart';
import 'package:masttersystem/services/lan_license_server.dart';
import 'package:masttersystem/services/license_package_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LanLicenseServer server;
  late LicensePackageStore packages;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('mastter-dual-admin-');
    server = await LanLicenseServer.createForTesting(
      File('${directory.path}${Platform.pathSeparator}licenses.json'),
    );
    packages = LicensePackageStore(
      await SharedPreferences.getInstance(),
      supportDirectory: directory,
      executableDirectory: directory.path,
    );
  });

  tearDown(() async {
    server.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> pumpAdmin(WidgetTester tester,
      {OfflineLicenseGenerator? generator, bool narrow = false}) async {
    tester.view.physicalSize =
        narrow ? const Size(390, 844) : const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(MaterialApp(
      home: LicenseServerScreen(
        server: server,
        packages: packages,
        onLock: () {},
        offlineLicenseGenerator: generator,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openOffline(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Chaves offline'));
    await tester.tap(find.text('Chaves offline'));
    await tester.pumpAndSettle();
  }

  Future<void> generate(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('offline-license-generate'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> selectOption(
      WidgetTester tester, String key, String label) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('offline form validates the customer and device on narrow screen',
      (tester) async {
    var calls = 0;
    await pumpAdmin(tester, narrow: true, generator: (
        {required customerName,
        required installationCode,
        required platform,
        required expiresAt}) async {
      calls++;
      return 'MSL1.test.fixture.signature';
    });
    await openOffline(tester);
    await generate(tester);
    expect(find.text('Informe o nome do cliente.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-name')), 'Cliente teste');
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-installation')), '1234');
    await generate(tester);
    expect(
        find.text(
            'Informe os 12 dígitos do código exibido no aplicativo do cliente.'),
        findsOneWidget);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generates Android key for two hours and copies the pure key',
      (tester) async {
    const key = 'MSL1.test.fixture.signature';
    final captured = <String, Object>{};
    String? clipboard;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpAdmin(tester, generator: (
        {required customerName,
        required installationCode,
        required platform,
        required expiresAt}) async {
      captured.addAll({
        'name': customerName,
        'installation': installationCode,
        'platform': platform,
        'expiresAt': expiresAt,
      });
      return key;
    });
    await openOffline(tester);
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-name')), 'Cliente Android');
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-installation')),
        '123456789012');
    await selectOption(tester, 'offline-license-platform', 'APK (Android)');
    await selectOption(
        tester, 'offline-license-validity', 'Duração personalizada');
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-duration')), '2');
    await selectOption(tester, 'offline-license-duration-unit', 'Horas');
    final before = DateTime.now().toUtc();
    await generate(tester);

    expect(captured['name'], 'Cliente Android');
    expect(captured['installation'], '123456789012');
    expect(captured['platform'], 'android');
    expect((captured['expiresAt'] as DateTime).difference(before).inMinutes,
        inInclusiveRange(119, 120));
    expect(find.text(key), findsOneWidget);
    final copy = find.byKey(const ValueKey('offline-license-copy'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard, key);

    // A key for the old form must not remain available after changing the device.
    final installation =
        find.byKey(const ValueKey('offline-license-installation'));
    await tester.ensureVisible(installation);
    await tester.enterText(installation, '999999999999');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('offline-license-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('internet tab rejects a public HTTP connection', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.text('Internet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('remote-license-address')),
        'http://licencas.example.com');
    await tester.enterText(find.byKey(const ValueKey('remote-license-token')),
        'admin-fixture-secret');
    final connect = find.byKey(const ValueKey('remote-license-connect'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(server.isRemote, isFalse);
    final message = tester
        .widget<Text>(find.byKey(const ValueKey('remote-license-message')))
        .data!;
    expect(message.toLowerCase(), contains('https'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline signing failure leaves the form ready to retry',
      (tester) async {
    await pumpAdmin(tester, generator: (
        {required customerName,
        required installationCode,
        required platform,
        required expiresAt}) async {
      throw StateError('Chave de emissão indisponível.');
    });
    await openOffline(tester);
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-name')), 'Cliente teste');
    await tester.enterText(
        find.byKey(const ValueKey('offline-license-installation')),
        '123456789012');
    await generate(tester);
    expect(
        find.textContaining('Chave de emissão indisponível.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('offline-license-generate')))
            .onPressed,
        isNotNull);
    expect(find.byKey(const ValueKey('offline-license-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
