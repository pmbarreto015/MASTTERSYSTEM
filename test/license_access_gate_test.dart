import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masttersystem/screens/auth/license_access_gate.dart';
import 'package:masttersystem/providers/license_provider.dart';
import 'package:masttersystem/screens/auth/activation_screen.dart';
import 'package:masttersystem/services/license_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('return from another app preserves route and draft at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final service = _ControlledLicense(prefs)
        ..licenseTime = const Duration(hours: 1);
      final license = LicenseProvider(prefs, service: service);
      final navigator = GlobalKey<NavigatorState>();
      final draft = TextEditingController();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: license,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => LicenseAccessGate(child: child!),
          home: const Scaffold(body: Text('Dashboard')),
        ),
      ));
      await tester.pump();
      final navigatorState = navigator.currentState!;
      unawaited(navigatorState.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Venda em andamento')),
          body: TextField(controller: draft),
        ),
      )));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField), 'Itens e medidas da venda');
      final formState = tester.state(find.byType(TextField));

      for (var attempt = 0; attempt < 2; attempt++) {
        final validation = Completer<bool>();
        service.pendingValidation = validation;
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        expect(license.isLoading, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(navigator.currentState, same(navigatorState));
        expect(find.text('Venda em andamento'), findsNothing);
        validation.complete(true);
        await tester.pumpAndSettle();
        expect(license.isLoading, isFalse);
        expect(find.text('Venda em andamento'), findsOneWidget);
        expect(navigator.currentState, same(navigatorState));
        expect(tester.state(find.byType(TextField)), same(formState));
        expect(draft.text, 'Itens e medidas da venda');
        expect(find.text('Dashboard'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      license.dispose();
      draft.dispose();
    });
  }

  testWidgets('expiry blocks an open page and its dialog on mobile',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final service = _ControlledLicense(prefs);
    final license = LicenseProvider(prefs, service: service);
    final navigator = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: license,
      child: MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => LicenseAccessGate(child: child!),
        home: const Scaffold(body: Text('Sistema liberado')),
      ),
    ));
    await tester.pump();
    expect(find.text('Sistema liberado'), findsOneWidget);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Página interna'))));
    await tester.pump(const Duration(milliseconds: 400));
    showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Documento aberto')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Documento aberto'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(license.isActivated, isFalse);
    expect(find.byType(ActivationScreen), findsOneWidget);
    expect(find.text('Página interna'), findsNothing);
    expect(find.text('Documento aberto'), findsNothing);
    expect(find.textContaining('expirou'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    license.dispose();
  });

  testWidgets('return from background revalidates and blocks a revoked access',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final service = _ControlledLicense(prefs);
    final license = LicenseProvider(prefs, service: service);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: license,
      child: MaterialApp(
          builder: (_, child) => LicenseAccessGate(child: child!),
          home: const Scaffold(body: Text('Sistema liberado'))),
    ));
    await tester.pump();
    expect(license.isActivated, isTrue);
    service.authorized = false;
    license.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(license.isActivated, isFalse);
    expect(find.byType(ActivationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    license.dispose();
  });
}

class _ControlledLicense extends LicenseService {
  _ControlledLicense(super.prefs);
  bool authorized = true;
  Duration licenseTime = const Duration(seconds: 2);
  Completer<bool>? pendingValidation;
  @override
  bool get isLanMode => true;
  @override
  DateTime? get expiresAt => DateTime.utc(2026, 10, 14, 12);
  @override
  Duration? get remainingLicenseTime => licenseTime;
  @override
  Future<void> loadPackagedSetup() async {}
  @override
  Future<String> getInstallationCode() async => '123456789012';
  @override
  Future<bool> isActivated() async {
    final pending = pendingValidation;
    pendingValidation = null;
    final active = pending == null ? authorized : await pending.future;
    lastValidationMessage = active ? 'Válida' : 'Acesso bloqueado';
    return active;
  }
}
