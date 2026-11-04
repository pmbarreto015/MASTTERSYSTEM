import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/financial_model.dart';

/// Valores monetários são repartidos em centavos para preservar o total.
List<double> financeInstallments(double total, int count) {
  if (!total.isFinite || total <= 0 || count < 1 || count > 120) {
    throw ArgumentError('Informe um valor positivo e de 1 a 120 parcelas.');
  }
  final cents = (total * 100).round();
  if (cents < count) {
    throw ArgumentError('Cada parcela deve ter pelo menos R\$ 0,01.');
  }
  return List.generate(count,
      (index) => (cents ~/ count + (index < cents % count ? 1 : 0)) / 100);
}

double? financeParseNumber(String text) {
  var value = text.trim().replaceAll(RegExp(r'R\$|\s'), '');
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite ? parsed : null;
}

DateTime financeAddMonths(DateTime date, int months) {
  final last = DateTime(date.year, date.month + months + 1, 0).day;
  return DateTime(
      date.year, date.month + months, date.day > last ? last : date.day);
}

class FinanceOfxEntry {
  const FinanceOfxEntry({
    required this.externalId,
    required this.date,
    required this.amount,
    required this.description,
    this.account = '',
  });
  final String externalId;
  final DateTime date;
  final double amount;
  final String description;
  final String account;

  String get reference =>
      sha256.convert(utf8.encode('$account|$externalId')).toString();
}

/// Lê OFX XML ou SGML. Nenhum lançamento é criado ou quitado na importação.
List<FinanceOfxEntry> financeParseOfx(String source) {
  String field(String input, String name) {
    final match = RegExp('<$name\\s*>\\s*([^<\\r\\n]+)', caseSensitive: false)
        .firstMatch(input);
    return (match?.group(1) ?? '')
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  final account = '${field(source, 'BANKID')}/${field(source, 'ACCTID')}';
  final blocks = RegExp(
          r'<STMTTRN\s*>(.*?)(?:</STMTTRN\s*>|(?=<STMTTRN\s*>)|(?=</BANKTRANLIST\s*>))',
          caseSensitive: false,
          dotAll: true)
      .allMatches(source);
  final entries = <FinanceOfxEntry>[];
  final references = <String>{};
  for (final block in blocks) {
    final body = block.group(1)!;
    final rawDate = field(body, 'DTPOSTED');
    final amount = financeParseNumber(field(body, 'TRNAMT'));
    final external = field(body, 'FITID');
    if (rawDate.length < 8 || amount == null || external.isEmpty) {
      throw const FormatException(
          'OFX contém movimento sem data, valor ou FITID.');
    }
    final year = int.tryParse(rawDate.substring(0, 4));
    final month = int.tryParse(rawDate.substring(4, 6));
    final day = int.tryParse(rawDate.substring(6, 8));
    if (year == null ||
        month == null ||
        day == null ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime(year, month + 1, 0).day) {
      throw const FormatException('OFX contém data inválida.');
    }
    final entry = FinanceOfxEntry(
      externalId: external,
      date: DateTime(year, month, day),
      amount: amount,
      description: [field(body, 'NAME'), field(body, 'MEMO')]
          .where((part) => part.isNotEmpty)
          .join(' — '),
      account: account,
    );
    if (references.add(entry.reference)) entries.add(entry);
  }
  if (entries.isEmpty) {
    throw const FormatException('Nenhum movimento STMTTRN válido no OFX.');
  }
  return entries;
}

class FinancePeriodTotals {
  FinancePeriodTotals(Iterable<FinancialModel> rows) {
    for (final row in rows.where((t) => t.status != 'cancelado')) {
      final receiving = row.type == 'receber';
      // Uma conta pode receber mais de uma baixa. O total realizado deve
      // refletir também os recebimentos parciais, sem ultrapassar a conta.
      final partial = row.pagamentos.fold<double>(0, (sum, value) {
        return value.isFinite && value > 0 ? sum + value : sum;
      });
      final settled =
          row.isPaid ? row.amount : partial.clamp(0, row.amount).toDouble();
      final open = (row.amount - settled).clamp(0, row.amount).toDouble();
      if (receiving) {
        revenue += row.amount;
        received += settled;
        receivable += open;
      } else {
        expense += row.amount;
        paid += settled;
        payable += open;
      }
      categories.update(row.categoria,
          (current) => current + (receiving ? row.amount : -row.amount),
          ifAbsent: () => receiving ? row.amount : -row.amount);
    }
  }
  double revenue = 0, expense = 0, received = 0, paid = 0;
  double receivable = 0, payable = 0;
  final Map<String, double> categories = {};
  double get result => revenue - expense;
  double get balance => received - paid;
  double get projected => balance + receivable - payable;
  double get margin => revenue == 0 ? 0 : 100 * result / revenue;
}
