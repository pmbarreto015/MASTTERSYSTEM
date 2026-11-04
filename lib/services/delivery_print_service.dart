import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery_model.dart';
import '../models/order_model.dart';

class DeliveryPrintService {
  static final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _date = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> print(DeliveryModel delivery, OrderModel order) async {
    final bytes = await buildPdf(delivery, order);
    await Printing.layoutPdf(
      name:
          'Entrega_${delivery.orderNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}',
      onLayout: (_) async => bytes,
    );
  }

  Future<Uint8List> buildPdf(DeliveryModel delivery, OrderModel order) async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? 'MastterSystem';
    final cnpj = prefs.getString('company_cnpj') ?? '';
    final phone = prefs.getString('company_phone') ?? '';
    final companyAddress = prefs.getString('company_address') ?? '';
    final page = pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 16),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
            'Pedido de entrega ? ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 9),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.blue900, width: 1.6))),
          child: pw
              .Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(company.toUpperCase(),
                        style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900)),
                    if (cnpj.isNotEmpty)
                      pw.Text('CNPJ: $cnpj',
                          style: const pw.TextStyle(fontSize: 7.5)),
                    if (companyAddress.isNotEmpty)
                      pw.Text(companyAddress,
                          style: const pw.TextStyle(fontSize: 7.5)),
                    if (phone.isNotEmpty)
                      pw.Text(phone, style: const pw.TextStyle(fontSize: 7.5)),
                  ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('PEDIDO DE ENTREGA',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(delivery.orderNumber,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              _badge(delivery.statusLabel),
            ]),
          ]),
        ),
        pw.SizedBox(height: 12),
        _section('DESTINAT?RIO', [
          _line('Cliente', delivery.customerName),
          _line('Contato', _value(delivery.contact)),
          _line(
              'Endere?o',
              delivery.needsAddress
                  ? _value(delivery.address)
                  : 'Retirada na loja'),
          if (delivery.reference.trim().isNotEmpty)
            _line('Refer?ncia', delivery.reference),
        ]),
        pw.SizedBox(height: 9),
        _section('LOG?STICA', [
          _line('Modalidade', delivery.methodLabel),
          _line(
              'Agendamento',
              delivery.scheduledAt == null
                  ? 'A combinar'
                  : _date.format(delivery.scheduledAt!)),
          _line('Respons?vel', _value(delivery.responsible)),
        ]),
        pw.SizedBox(height: 11),
        pw.Text('ITENS DO PEDIDO',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          headers: const ['Item', 'Qtd.', 'Detalhes'],
          data: order.itens
              .map((item) => [
                    item.produtoNome,
                    item.quantidade.toString(),
                    item.especificacoes.trim().isEmpty
                        ? '-'
                        : item.especificacoes,
                  ])
              .toList(),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FixedColumnWidth(30),
            2: pw.FlexColumnWidth(2),
          },
          border: pw.TableBorder.all(color: PdfColors.grey400, width: .45),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue200),
              borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _moneyLine('Total do pedido', order.valorTotal),
                if (delivery.deliveryFee > .009)
                  _moneyLine('Taxa de entrega', delivery.deliveryFee),
                pw.Divider(color: PdfColors.blue200),
                _moneyLine(
                    'TOTAL A RECEBER', order.valorTotal + delivery.deliveryFee,
                    bold: true),
                if (delivery.hasFinancialEntry)
                  _moneyLine('Em aberto', delivery.paymentPending,
                      bold: true, color: PdfColors.orange800),
              ]),
        ),
        if (delivery.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _section('OBSERVA??ES', [
            pw.Text(delivery.notes, style: const pw.TextStyle(fontSize: 8))
          ]),
        ],
        pw.SizedBox(height: 24),
        pw.Row(children: [
          pw.Expanded(child: _signature('Respons?vel pela entrega')),
          pw.SizedBox(width: 26),
          pw.Expanded(child: _signature('Recebedor / cliente')),
        ]),
      ],
    );
    final document = pw.Document();
    document.addPage(page);
    return document.save();
  }

  pw.Widget _section(String title, List<pw.Widget> children) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900)),
              pw.SizedBox(height: 4),
              ...children,
            ]),
      );

  pw.Widget _line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(
                text: '$label: ',
                style:
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 8)),
          ]),
        ),
      );

  pw.Widget _moneyLine(String label, double value,
          {bool bold = false, PdfColor? color}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(_money.format(value),
              style: pw.TextStyle(
                  fontSize: 8.5,
                  color: color,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );

  pw.Widget _badge(String status) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(
            color: PdfColors.blue100,
            borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Text(status.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.blue900,
                fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _signature(String label) => pw.Column(children: [
        pw.Container(height: 1, color: PdfColors.grey600),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
      ]);

  String _value(String value) =>
      value.trim().isEmpty ? 'N?o informado' : value.trim();
}
