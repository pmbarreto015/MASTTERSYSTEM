import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:masttersystem/core/database/app_database.dart';
import 'package:masttersystem/core/supabase/supabase_service.dart';
import 'package:masttersystem/models/system_user_model.dart';
import 'package:masttersystem/screens/settings/user_access_section.dart';
import 'package:masttersystem/services/system_user_repository.dart';

class _UserRepository extends SystemUserRepository {
  SupabaseException? createError;
  final users = <SystemUserModel>[];
  final createAttempts = <SystemUserModel>[];

  @override
  Future<List<SystemUserModel>> getAll() async => List.of(users);

  @override
  Future<void> create(SystemUserModel user) async {
    createAttempts.add(user);
    final error = createError;
    if (error != null) throw error;
    users.add(user);
  }
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _openNewUser(
  WidgetTester tester,
  _UserRepository repository,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1500, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: UserAccessSection(isDark: false, repository: repository),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Novo usuário'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('Nome do funcionário *'), 'Funcionário teste');
  await tester.enterText(_field('E-mail'), 'funcionario@example.com');
  await tester.enterText(_field('Usuário para entrar *'), 'funcionario');
  await tester.enterText(_field('Senha *'), 'senha-teste-123');
  await tester.tap(find.text('Vendas + Orçamentos'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppDatabase.databaseModeKey: AppDatabase.supabaseMode,
    });
  });

  testWidgets('erro do Supabase mantém os dados para corrigir e tentar de novo',
      (tester) async {
    const message = 'A função de usuários ainda não foi publicada no Supabase.';
    final repository = _UserRepository()
      ..createError = const SupabaseException(
        message,
        statusCode: 404,
        code: 'user_management_not_deployed',
      );
    await _openNewUser(tester, repository);

    await tester.tap(find.text('Salvar usuário'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Funcionário teste'), findsOneWidget);
    expect(find.text('funcionario@example.com'), findsOneWidget);
    expect(find.text('funcionario'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(_field('Senha *')).controller!.text,
      'senha-teste-123',
    );
    expect(repository.createAttempts, hasLength(1));
    expect(
        repository.createAttempts.single.permissions, {'vendas', 'orcamentos'});
    expect(repository.users, isEmpty);
    expect(
      find.text('Não foi possível salvar. Verifique se o usuário já existe.'),
      findsNothing,
    );

    ScaffoldMessenger.of(tester.element(find.byType(UserAccessSection)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    repository.createError = null;
    await tester.tap(find.text('Salvar usuário'));
    await tester.pumpAndSettle();

    expect(repository.createAttempts, hasLength(2));
    expect(repository.users.single.username, 'funcionario');
    expect(repository.users.single.permissions, {'vendas', 'orcamentos'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Usuário e permissões salvos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('salvar cria o usuário com as permissões e atualiza a lista',
      (tester) async {
    final repository = _UserRepository();
    await _openNewUser(tester, repository);

    await tester.tap(find.text('Salvar usuário'));
    await tester.pumpAndSettle();

    final created = repository.createAttempts.single;
    expect(created.fullName, 'Funcionário teste');
    expect(created.username, 'funcionario');
    expect(created.email, 'funcionario@example.com');
    expect(created.password, 'senha-teste-123');
    expect(created.active, isTrue);
    expect(created.permissions, {'vendas', 'orcamentos'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Funcionário teste'), findsOneWidget);
    expect(find.text('Usuário e permissões salvos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
