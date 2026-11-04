import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/screens/quote/quote_screen.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

void main() {
  late Directory directory;
  late PathProviderPlatform previousPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('matterdi-sale-status-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    final database = await AppDatabase().database;
    final now = DateTime.now().toIso8601String();
    for (final (id, name, category) in [
      (1, 'Caneca de cerâmica', 'estamparia'),
      (2, 'Camiseta cadastrada anteriormente', 'vestuario'),
    ]) {
      await database.insert('products', {
        'id': id,
        'codigo': 'PROD-$id',
        'nome': name,
        'categoria': category,
        'preco': 25,
        'cost': 10,
        'unidade': 'un',
        'ativo': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
  });

  tearDownAll(() async {
    await AppDatabase().close();
    PathProviderPlatform.instance = previousPaths;
    if (!path.isWithin(Directory.systemTemp.resolveSymbolicLinksSync(),
            directory.resolveSymbolicLinksSync()) ||
        !path.basename(directory.path).startsWith('matterdi-sale-status-')) {
      throw StateError('Diretório de teste inesperado.');
    }
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSale(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: QuoteScreen())));
    await settle(tester);
  }

  Finder dropdown(String label) => find.byWidgetPredicate((widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == label);

  testWidgets('venda permite escolher a etapa sem mudar o pagamento',
      (tester) async {
    await pumpSale(tester);
    final production = dropdown('Etapa inicial da produção');
    expect(
        tester.widget<DropdownButtonFormField<String>>(production).initialValue,
        'aguardando_pagamento');
    await tester.ensureVisible(production);
    await tester.tap(production);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acabamento').last);
    await tester.pumpAndSettle();
    expect(
        tester.widget<DropdownButtonFormField<String>>(production).initialValue,
        'em_producao');
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(dropdown('Pagamento'))
            .initialValue,
        'À Vista');
  });

  for (final productName in [
    'Caneca de cerâmica',
    'Camiseta cadastrada anteriormente',
  ]) {
    testWidgets('$productName é incluída sem personalização automática',
        (tester) async {
      await pumpSale(tester);
      final chooser = find.text('Digite ou selecione um produto');
      await tester.ensureVisible(chooser);
      await tester.tap(chooser);
      await tester.pumpAndSettle();
      await tester.tap(find.text(productName));
      await tester.pumpAndSettle();
      expect(find.text('Opções de Personalização'), findsNothing);
      expect(dropdown('Tamanho'), findsNothing);
      expect(dropdown('Cor'), findsNothing);
      expect(dropdown('Material'), findsNothing);

      final observation = find.widgetWithText(TextField, 'Obs. do item');
      await tester.ensureVisible(observation);
      await tester.enterText(observation, 'Arte aprovada pelo cliente');
      final add = find.widgetWithText(ElevatedButton, 'Adicionar');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Arte aprovada pelo cliente'), findsOneWidget);
      expect(find.textContaining('Tamanho:'), findsNothing);
      expect(find.textContaining('Material: Algodão'), findsNothing);
    });
  }
}
