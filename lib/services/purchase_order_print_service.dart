import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/purchase_order_model.dart';

class PurchaseOrderPrintService {
  static final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _date = DateFormat('dd/MM/yyyy');

  Future<void> print(PurchaseOrderModel order) async {
    final bytes = await buildPdf(order);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> buildPdf(PurchaseOrderModel order) async {
    final preferences = await SharedPreferences.getInstance();
    final company = preferences.getString('company_name') ?? 'MastterSystem';
    final cnpj = preferences.getString('company_cnpj') ?? '';
    final phone = preferences.getString('company_phone') ?? '';
    final address = preferences.getString('company_address') ?? '';
    final status = _statusLabel(order.status);
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 14),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.blue900, width: 2)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(company.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900)),
                      if (cnpj.isNotEmpty)
                        pw.Text('CNPJ: $cnpj',
                            style: const pw.TextStyle(fontSize: 9)),
                      if (address.isNotEmpty)
                        pw.Text(address,
                            style: const pw.TextStyle(fontSize: 9)),
                      if (phone.isNotEmpty)
                        pw.Text(phone, style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('ORDEM DE COMPRA',
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text(order.number,
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    _statusBadge(status),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _infoBlock('FORNECEDOR', order.supplierName)),
              pw.SizedBox(width: 18),
              pw.Expanded(
                child: _infoBlock(
                  'DATA / PREVISÃO',
                  'Emissão: ${_date.format(order.createdAt)}\nPrevisão: ${_formatDate(order.expectedDate)}',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('ITENS SOLICITADOS',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 7),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const [
              '#',
              'Descrição',
              'Qtd.',
              'Unidade',
              'Valor unit.',
              'Total'
            ],
            data: List<List<String>>.generate(order.items.length, (index) {
              final item = order.items[index];
              return [
                '${index + 1}',
                item.description,
                _formatQuantity(item.quantity),
                item.unit,
                item.unitValue > 0 ? _money.format(item.unitValue) : '-',
                item.total > 0 ? _money.format(item.total) : '-',
              ];
            }),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(4),
              2: pw.FixedColumnWidth(38),
              3: pw.FixedColumnWidth(58),
              4: pw.FixedColumnWidth(66),
              5: pw.FixedColumnWidth(58),
            },
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 190,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue900),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('VALOR ESTIMADO',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(_money.format(order.total),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900)),
                ],
              ),
            ),
          ),
          if (order.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 22),
            pw.Text('OBSERVAÇÕES',
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child:
                  pw.Text(order.notes, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
          pw.SizedBox(height: 48),
          pw.Row(
            children: [
              pw.Expanded(child: _signature('Solicitante')),
              pw.SizedBox(width: 46),
              pw.Expanded(child: _signature('Aprovação')),
              pw.SizedBox(width: 46),
              pw.Expanded(child: _signature('Fornecedor')),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _infoBlock(String title, String value) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(value,
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget _statusBadge(String status) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue100,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Text(status,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900)),
      );

  pw.Widget _signature(String label) => pw.Column(
        children: [
          pw.Container(height: 1, color: PdfColors.grey600),
          pw.SizedBox(height: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      );

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return 'Não informada';
    final date = DateTime.tryParse(value);
    return date == null ? value : _date.format(date);
  }

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  String _statusLabel(String status) => switch (status) {
        'aprovado' => 'APROVADO',
        'recebido' => 'RECEBIDO',
        'cancelado' => 'CANCELADO',
        _ => 'SOLICITADO',
      };
}
