import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/models/employee_model.dart';
import 'package:masttersystem/models/ponto_model.dart';
import 'package:masttersystem/models/ponto_report.dart';
import 'package:masttersystem/services/ponto_report_pdf_service.dart';

PontoModel ponto(int day,
    {int employeeId = 1,
    int month = 10,
    double hours = 8,
    double extras = 0,
    bool complete = true}) {
  final date = DateTime(2026, month, day);
  return PontoModel(
    employeeId: employeeId,
    employeeName: 'Funcionário $employeeId',
    data: date,
    entrada1: date.add(const Duration(hours: 8)),
    saida1: date.add(const Duration(hours: 12)),
    entrada2: date.add(const Duration(hours: 13)),
    saida2: complete ? date.add(const Duration(hours: 17)) : null,
    horasTrabalhadas: hours,
    horasExtras: extras,
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  test('período inclui as duas datas e isola o funcionário selecionado', () {
    final lastDay = ponto(31)..data = DateTime(2026, 10, 31, 23, 59);
    final report = PontoReport(
      employeeId: 1,
      start: DateTime(2026, 10, 1, 14),
      end: DateTime(2026, 10, 31, 8),
      records: [
        lastDay,
        ponto(1, month: 11),
        ponto(30, month: 9),
        ponto(15, employeeId: 2),
        ponto(1)
      ],
    );

    expect(report.pontos.map((p) => p.data.day), [1, 31]);
    expect(report.totalHoras, 16);
    expect(report.diasRegistrados, 2);
  });

  test('resume horas salvas, dias distintos e batidas incompletas', () {
    final report = PontoReport(
      employeeId: 1,
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 31),
      records: [
        ponto(2, hours: 9.5, extras: 1.5),
        ponto(2, hours: 1),
        ponto(3, hours: 4.25, complete: false)
      ],
    );

    expect(report.diasRegistrados, 2);
    expect(report.registrosAbertos, 1);
    expect(report.totalHoras, 14.75);
    expect(report.totalExtras, 1.5);
    expect(PontoReport.formatHours(report.totalHoras), '14:45');
  });

  test('arredondamento de horas não produz minuto 60', () {
    expect(PontoReport.formatHours(1.999999), '02:00');
    expect(PontoReport.formatHours(125.5), '125:30');
    expect(PontoReport.formatHours(0), '00:00');
  });

  test('intervalo inválido é rejeitado e relatório vazio tem totais zerados',
      () {
    expect(
        () => PontoReport(
            employeeId: 1,
            start: DateTime(2026, 10, 2),
            end: DateTime(2026, 10, 1),
            records: []),
        throwsArgumentError);
    final report = PontoReport(
        employeeId: 1,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 2),
        records: []);
    expect(report.totalHoras, 0);
    expect(report.totalExtras, 0);
    expect(report.diasRegistrados, 0);
    expect(report.registrosAbertos, 0);
  });

  test('PDF aceita relatório de vários meses e observações', () async {
    final employee = EmployeeModel.create(
            name: 'Ana da Silva',
            document: '',
            phone: '',
            email: '',
            position: 'Atendimento')
        .copyWith(id: 1);
    final report = PontoReport(
        employeeId: 1,
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31),
        records: List.generate(
            120,
            (index) => ponto(index + 1, month: 1)
              ..observacoes = 'Registro conferido pelo RH.'));
    final bytes = await PontoReportPdfService().generate(employee, report);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
