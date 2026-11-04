import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/main.dart';
import 'package:masttersystem/providers/license_provider.dart';
import 'package:masttersystem/screens/auth/activation_screen.dart';
import 'package:masttersystem/services/license_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mobile chooses an offline key and expiry closes access',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final service = _OfflineActivation(prefs);
    final license = LicenseProvider(prefs, service: service);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: license,
      child: MaterialApp(
        builder: (_, child) => LicenseAccessGate(child: child!),
        home: const Scaffold(body: Text('Sistema liberado')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ActivationScreen), findsOneWidget);
    await tester.ensureVisible(find.text('Chave offline'));
    await tester.tap(find.text('Chave offline'));
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsNothing);
    final keyField = find.byKey(const ValueKey('offline-activation-code'));
    await tester.enterText(keyField, 'MSL1.test-key');
    await tester.ensureVisible(find.text('Entrar e ativar'));
    await tester.tap(find.text('Entrar e ativar'));
    await tester.pump();
    expect(service.received, 'MSL1.test-key');
    expect(license.isActivated, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(license.isActivated, isFalse);
    expect(find.byType(ActivationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    license.dispose();
  });
}

class _OfflineActivation extends LicenseService {
  _OfflineActivation(super.prefs);
  String? received;
  @override
  Future<void> loadPackagedSetup() async {}
  @override
  Future<String> getInstallationCode() async => '123456789012';
  @override
  Future<bool> isActivated() async => false;
  @override
  bool get isOfflineLicense => received != null;
  @override
  Duration? get remainingLicenseTime => const Duration(seconds: 2);
  @override
  Future<LicenseActivationResult> activateOffline(String input) async {
    received = input;
    return const LicenseActivationResult(
        success: true, message: 'Chave ativada.');
  }
}
