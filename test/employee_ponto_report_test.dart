import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/models/employee_model.dart';
import 'package:masttersystem/models/ponto_model.dart';
import 'package:masttersystem/screens/employees/employee_ponto_report.dart';

EmployeeModel employee(int id) => EmployeeModel.create(
      name: 'Funcionário $id',
      document: '',
      phone: '',
      email: '',
      position: 'Atendimento',
    ).copyWith(id: id);

PontoModel record(int employeeId, double hours) {
  final now = DateTime.now();
  return PontoModel(
    employeeId: employeeId,
    employeeName: 'Funcionário $employeeId',
    data: now,
    horasTrabalhadas: hours,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('consulta antiga não substitui relatório do funcionário atual',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final first = Completer<List<PontoModel>>();
    final second = Completer<List<PontoModel>>();
    final employees = [employee(1), employee(2)];

    Widget screen(int selectedId) => MaterialApp(
          home: Scaffold(
            body: EmployeePontoReport(
              employees: employees,
              initialEmployeeId: selectedId,
              loadPontos: (id) => id == 1 ? first.future : second.future,
            ),
          ),
        );

    await tester.pumpWidget(screen(1));
    await tester.pumpWidget(screen(2));
    second.complete([record(2, 7)]);
    await tester.pumpAndSettle();
    expect(find.text('07:00'), findsWidgets);

    first.complete([record(1, 3)]);
    await tester.pumpAndSettle();
    expect(find.text('07:00'), findsWidgets);
    expect(find.text('03:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('atualizar lista da equipe preserva relatório e seleção',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var calls = 0;
    Widget screen(List<EmployeeModel> employees, {int version = 0}) =>
        MaterialApp(
          home: Scaffold(
            body: EmployeePontoReport(
              employees: employees,
              initialEmployeeId: 1,
              selectionVersion: version,
              loadPontos: (_) async {
                calls++;
                return [record(1, 6.5)];
              },
            ),
          ),
        );

    await tester.pumpWidget(screen([employee(1)]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen([employee(1), employee(2)]));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('06:30'), findsWidgets);

    // Abrir novamente o mesmo funcionário atualiza os registros.
    await tester.pumpWidget(screen([employee(1), employee(2)], version: 1));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('06:30'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('relatório permite rolagem em uma tela pequena', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmployeePontoReport(
          employees: [employee(1)],
          initialEmployeeId: 1,
          loadPontos: (_) async => [record(1, 8)],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
