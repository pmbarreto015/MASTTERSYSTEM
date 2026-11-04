import 'dart:io';

import 'package:flutter/material.dart';
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
    directory = await Directory.systemTemp.createTemp('mastter-license-admin-');
    server = await LanLicenseServer.createForTesting(
      File('${directory.path}${Platform.pathSeparator}licenses.json'),
    );
    packages = LicensePackageStore(await SharedPreferences.getInstance(),
        supportDirectory: directory, executableDirectory: directory.path);
  });

  tearDown(() async {
    server.dispose();
    // Only the directory returned by createTemp above is removed.
    await directory.delete(recursive: true);
  });

  Future<void> pumpAdmin(WidgetTester tester, {bool narrow = false}) async {
    tester.view.physicalSize =
        narrow ? const Size(390, 844) : const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: LicenseServerScreen(
          server: server, packages: packages, onLock: () {}),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> selectOption(
    WidgetTester tester,
    String key,
    String label,
  ) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillCredentials(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey('license-name')), 'Cliente Teste');
    await tester.enterText(
        find.byKey(const ValueKey('license-login')), 'teste.apk');
    await tester.enterText(
        find.byKey(const ValueKey('license-password')), 'teste123');
  }

  Future<void> saveLicense(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('license-save'));
    await tester.tap(button);
    // File persistence completes on the real event loop, outside fake widget time.
    for (var attempt = 0;
        attempt < 100 && button.evaluate().isNotEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(button, findsNothing);
    await tester.pumpAndSettle();
  }

  testWidgets('creates seven-day access with credentials on a narrow screen',
      (tester) async {
    await pumpAdmin(tester, narrow: true);
    expect(find.text('Licenças'), findsOneWidget);
    await tester.tap(find.text('Novo acesso'));
    await tester.pumpAndSettle();
    expect(find.text('Teste de 7 dias'), findsOneWidget);
    await fillCredentials(tester);
    final before = DateTime.now().toUtc();
    await saveLicense(tester);

    final customer = server.customers.single;
    expect(customer.allowedPlatform, 'both');
    expect(customer.maxDevices, 1);
    expect(customer.expiresAt, isNotNull);
    expect(customer.expiresAt!.difference(before).inHours,
        inInclusiveRange(167, 168));
    expect(find.text('Acesso criado'), findsOneWidget);
    final receipt =
        tester.widget<SelectableText>(find.byType(SelectableText).last).data!;
    expect(receipt, contains('Login: teste.apk'));
    expect(receipt, contains('Plataforma: APK e EXE'));
    expect(receipt, contains('Validade:'));
    expect(receipt, contains('Servidor:'));
    expect(find.text('Copiar e fechar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates Android access with a custom hour deadline',
      (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.text('Novo acesso'));
    await tester.pumpAndSettle();
    await fillCredentials(tester);
    await selectOption(tester, 'license-platform', 'APK (Android)');
    await selectOption(tester, 'license-validity', 'Duração personalizada');
    await tester.ensureVisible(find.byKey(const ValueKey('license-duration')));
    await tester.enterText(find.byKey(const ValueKey('license-duration')), '2');
    await selectOption(tester, 'license-duration-unit', 'Horas');
    final before = DateTime.now().toUtc();
    await saveLicense(tester);

    final customer = server.customers.single;
    expect(customer.allowedPlatform, 'android');
    expect(customer.expiresAt!.difference(before).inMinutes,
        inInclusiveRange(119, 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renews an expired license and changes platform and device limit',
      (tester) async {
    await tester.runAsync(() => server.createCustomer(
          name: 'Cliente Expirado',
          login: 'expirado',
          password: 'teste123',
          maxDevices: 1,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        ));
    final customer = server.customers.single;
    customer.expiresAt =
        DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    await pumpAdmin(tester);
    expect(find.text('Expirada'), findsOneWidget);
    expect(find.text('1 expiradas'), findsOneWidget);
    await tester.tap(find.text('Cliente Expirado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renovar / editar licença'));
    await tester.pumpAndSettle();
    expect(find.text('Teste de 7 dias'), findsOneWidget);
    await selectOption(tester, 'license-platform', 'EXE (Windows)');
    await tester.enterText(find.byKey(const ValueKey('license-devices')), '3');
    await selectOption(
        tester, 'license-validity', 'Permanente (sem vencimento)');
    await saveLicense(tester);

    expect(customer.expiresAt, isNull);
    expect(customer.allowedPlatform, 'windows');
    expect(customer.maxDevices, 3);
    expect(find.text('Permanente'), findsOneWidget);
    expect(find.text('0 expiradas'), findsOneWidget);
    expect(find.text('1 ativas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
