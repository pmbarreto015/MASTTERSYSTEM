import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/models/system_user_model.dart';
import 'package:masttersystem/models/customer_model.dart';
import 'package:masttersystem/providers/auth_provider.dart';
import 'package:masttersystem/providers/theme_provider.dart';
import 'package:masttersystem/screens/customers/customer_list_screen.dart';
import 'package:masttersystem/screens/dashboard/dashboard_screen.dart';
import 'package:masttersystem/screens/main_screen.dart';
import 'package:masttersystem/screens/settings/settings_screen.dart';
import 'package:masttersystem/screens/financial/financial_screen.dart';
import 'package:masttersystem/screens/quote/quote_screen.dart';
import 'package:masttersystem/services/customer_repository.dart';

Future<void> settle(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  late Directory directory;
  late PathProviderPlatform previousPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('matterdi-navigation-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    await AppDatabase().database;
    final customers = CustomerRepository();
    await customers.create(CustomerModel.create(
      name: 'Cliente em edição Alfa',
      phone: '111111111',
    ).copyWith(uuid: 'navigation-search-match'));
    await customers.create(CustomerModel.create(
      name: 'Cliente fora da busca',
      phone: '222222222',
    ).copyWith(uuid: 'navigation-search-other'));
  });

  tearDownAll(() async {
    await AppDatabase().close();
    PathProviderPlatform.instance = previousPaths;
    if (!path.isWithin(Directory.systemTemp.resolveSymbolicLinksSync(),
        directory.resolveSymbolicLinksSync())) {
      throw StateError('Unexpected test directory');
    }
    await directory.delete(recursive: true);
  });

  Future<_TestAuth> pumpApp(
    WidgetTester tester, {
    bool desktop = false,
    bool standalone = false,
    Widget? home,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = _TestAuth(prefs, admin: desktop);
    final theme = ThemeProvider(prefs);
    tester.view.physicalSize =
        desktop ? const Size(1280, 1000) : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      auth.dispose();
      theme.dispose();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(
          home: home ??
              (standalone ? const SettingsScreen() : const MainScreen())),
    ));
    await settle(tester);
    return auth;
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Abrir menu'));
    await settle(tester);
    await tester.tap(find.text('Configurações'));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  Future<void> openSection(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Abrir menu'));
    await settle(tester);
    final item = find.descendant(
      of: find.byType(Drawer),
      matching: find.text(label),
    );
    await tester.ensureVisible(item);
    await tester.tap(item);
    await settle(tester);
  }

  testWidgets('sections mount on demand and retain searches when returning',
      (tester) async {
    await pumpApp(tester);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
    expect(find.byType(DashboardScreen, skipOffstage: false), findsNothing);
    final customerState = tester.state(find.byType(CustomerListScreen));
    final search = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.hintText ==
            'Buscar cliente por nome, e-mail, telefone...');
    await tester.enterText(search, 'Cliente em edição');
    await tester.pump();
    expect(find.text('Cliente em edição Alfa'), findsOneWidget);
    expect(find.text('Cliente fora da busca'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    expect(find.text('Cliente em edição Alfa'), findsOneWidget);
    expect(find.text('Cliente fora da busca'), findsNothing);
    await openSettings(tester);
    expect(find.byType(CustomerListScreen), findsNothing);
    expect(
        find.byType(CustomerListScreen, skipOffstage: false), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await settle(tester);
    expect(tester.state(find.byType(CustomerListScreen)), same(customerState));
    expect(find.text('Cliente em edição'), findsOneWidget);
    expect(find.text('Cliente fora da busca'), findsNothing);
    await openSection(tester, 'Clientes');
    expect(tester.state(find.byType(CustomerListScreen)), same(customerState));
    expect(find.text('Cliente em edição'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sale draft survives section switches and automatic refresh',
      (tester) async {
    await pumpApp(tester, desktop: true);
    await openSection(tester, 'Nova venda');
    final saleState = tester.state(find.byType(QuoteScreen));
    Finder observations() => find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.hintText ==
            'Ex: Trocar os painéis, Painel quebrado...');
    await tester.ensureVisible(observations());
    await tester.enterText(observations(), 'Rascunho de venda preservado');
    await tester.pump();
    await openSection(tester, 'Clientes');
    expect(find.byType(QuoteScreen), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    await openSection(tester, 'Nova venda');
    expect(tester.state(find.byType(QuoteScreen)), same(saleState));
    expect(tester.widget<TextField>(observations()).controller!.text,
        'Rascunho de venda preservado');
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    expect(tester.widget<TextField>(observations()).controller!.text,
        'Rascunho de venda preservado');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mobile settings arrow returns to previous section without logout',
      (tester) async {
    final auth = await pumpApp(tester);
    await openSettings(tester);
    await tester.tap(find.byTooltip('Voltar'));
    await settle(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(CustomerListScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(auth.isAuthenticated, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android system back returns to previous section',
      (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(CustomerListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back closes the drawer without changing the section',
      (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.tap(find.byTooltip('Abrir menu'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    final scaffold = tester.state<ScaffoldState>(
      find.byType(Scaffold).first,
    );
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from a pushed page preserves the underlying section',
      (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    final context = tester.element(find.byType(SettingsScreen));
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: AppBar(title: const Text('Detalhe'))),
    ));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await settle(tester);
    expect(find.byType(CustomerListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop menu renders Portuguese accents and settings returns home',
      (tester) async {
    await pumpApp(tester, desktop: true);
    await tester.tap(find.byTooltip('Abrir menu'));
    await settle(tester);
    for (final label in [
      'Orçamentos',
      'Produção',
      'RH',
      'Rentabilidade',
      'Configurações'
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Configura??o'), findsNothing);
    await tester.ensureVisible(find.text('Configurações'));
    await tester.tap(find.text('Configurações'));
    await settle(tester);
    await tester.tap(find.byTooltip('Voltar'));
    await settle(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone settings cannot remove the only route',
      (tester) async {
    await pumpApp(tester, standalone: true);
    await tester.tap(find.byTooltip('Voltar'));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('financial layout fits mobile and changes the selected period',
      (tester) async {
    await pumpApp(tester, home: const FinancialScreen());
    await settle(tester);
    expect(find.text('Resumo do período'), findsOneWidget);
    expect(find.text('Ticket médio por OS'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await settle(tester);
    await tester.tap(find.text('Hoje').last);
    await settle(tester);
    expect(find.text('Hoje'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('financial layout fits desktop', (tester) async {
    await pumpApp(tester, desktop: true, home: const FinancialScreen());
    await settle(tester);
    expect(find.text('Resumo do período'), findsOneWidget);
    expect(find.text('Ticket médio por OS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

class _TestAuth extends AuthProvider {
  _TestAuth(super.prefs, {required this.admin});
  final bool admin;
  @override
  bool get isAdmin => admin;
  @override
  bool get isAuthenticated => true;
  @override
  bool get isInitializing => false;
  @override
  SystemUserModel get currentUser => SystemUserModel(
        id: 1,
        username: 'teste',
        fullName: 'Usuário de teste',
        isAdmin: admin,
        permissions: const {'clientes', 'configuracoes'},
      );
  @override
  bool hasPermission(String permission) => currentUser.can(permission);
}
