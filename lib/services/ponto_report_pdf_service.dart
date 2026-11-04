import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/employee_model.dart';
import '../models/ponto_report.dart';

class PontoReportPdfService {
  Future<Uint8List> generate(EmployeeModel employee, PontoReport report) async {
    final pdf = pw.Document();
    final date = DateFormat('dd/MM/yyyy');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('RH - Relatório individual de ponto',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text(
                'Funcionário: ${employee.name} | Cargo: ${employee.position}'),
            if (employee.document.isNotEmpty)
              pw.Text('Documento: ${employee.document}'),
            pw.Text(
                'Período: ${date.format(report.start)} a ${date.format(report.end)}'),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (_) => [
          pw.Text(
            '${report.diasRegistrados} dia(s) com registro | '
            'Horas trabalhadas: ${PontoReport.formatHours(report.totalHoras)} | '
            'Horas extras: ${PontoReport.formatHours(report.totalExtras)} | '
            'Registros em aberto: ${report.registrosAbertos}',
          ),
          pw.SizedBox(height: 8),
          pw.Text(
              'Totais conforme os registros salvos. Batidas ausentes aparecem como "-".',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          if (report.pontos.isEmpty)
            pw.Text('Nenhum ponto registrado neste período.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Data',
                'Entrada 1',
                'Saída 1',
                'Entrada 2',
                'Saída 2',
                'Horas',
                'Extras',
                'Situação',
                'Observações',
              ],
              data: report.pontos
                  .map((ponto) => [
                        date.format(ponto.data),
                        ponto.entrada1Formatada,
                        ponto.saida1Formatada,
                        ponto.entrada2Formatada,
                        ponto.saida2Formatada,
                        PontoReport.formatHours(ponto.horasTrabalhadas),
                        PontoReport.formatHours(ponto.horasExtras),
                        ponto.statusLabel,
                        ponto.observacoes.isEmpty ? '-' : ponto.observacoes,
                      ])
                  .toList(),
              headerStyle:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellPadding: const pw.EdgeInsets.all(5),
              columnWidths: const {8: pw.FlexColumnWidth(2)},
            ),
        ],
      ),
    );
    return pdf.save();
  }
}
