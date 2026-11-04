import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class FinanceReportService {
  static String csv(List<String> columns, List<List<String>> rows) {
    String safe(String text) =>
        RegExp(r'^[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
    return '\uFEFF${const ListToCsvConverter(fieldDelimiter: ';').convert([
          columns.map(safe).toList(),
          ...rows.map((row) => row.map(safe).toList()),
        ])}';
  }

  static Uint8List excel(List<String> columns, List<List<String>> rows) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Financeiro'];
    workbook.setDefaultSheet('Financeiro');
    for (final name in workbook.tables.keys.toList()) {
      if (name != 'Financeiro') workbook.delete(name);
    }
    sheet.appendRow(columns);
    for (final row in rows) {
      sheet.appendRow(row);
    }
    return Uint8List.fromList(workbook.encode()!);
  }

  static Uint8List csvBytes(List<String> columns, List<List<String>> rows) =>
      Uint8List.fromList(utf8.encode(csv(columns, rows)));

  static Future<Uint8List> pdf(
      {required String title,
      required String period,
      required List<String> columns,
      required List<List<String>> rows}) async {
    final document = pw.Document();
    // Paginação manual impede que tabelas grandes ultrapassem o limite do PDF.
    final count = rows.isEmpty ? 1 : (rows.length / 32).ceil();
    for (var page = 0; page < count; page++) {
      final segment = rows.skip(page * 32).take(32).toList();
      document.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text('MastterSystem — $title',
                        style: pw.TextStyle(
                            fontSize: 17, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 6),
                    pw.Text('$period • ${rows.length} registros',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 12),
                    if (segment.isEmpty)
                      pw.Text('Nenhum registro no período selecionado.')
                    else
                      pw.TableHelper.fromTextArray(
                          headers: columns,
                          data: segment,
                          cellStyle: const pw.TextStyle(fontSize: 7),
                          headerStyle: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold),
                          headerDecoration:
                              const pw.BoxDecoration(color: PdfColors.blue100),
                          cellPadding: const pw.EdgeInsets.all(4)),
                    pw.Spacer(),
                    pw.Text(
                        'Página ${page + 1}/$count • Emitido em ${DateTime.now().toIso8601String().substring(0, 16)}',
                        style: const pw.TextStyle(fontSize: 8)),
                  ])));
    }
    return document.save();
  }
}
