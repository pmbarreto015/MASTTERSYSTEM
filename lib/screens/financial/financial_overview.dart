import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/financial_summary.dart';

class FinancialOverview extends StatelessWidget {
  const FinancialOverview({super.key, required this.summary});
  final FinancialSummary summary;
  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$'),
        t = summary.totals;
    final metrics = <(String, double, Color)>[
      ('Recebido', t.received, Colors.green),
      ('Despesas pagas', t.paid, Colors.red),
      ('Saldo realizado', t.balance, Colors.blue),
      ('A receber', t.receivable, Colors.orange),
      ('A pagar', t.payable, Colors.deepOrange),
      ('Saldo previsto', summary.projectedBalance, Colors.indigo),
      ('Recebíveis vencidos', summary.overdueReceivable, Colors.red),
      ('Contas vencidas', summary.overduePayable, Colors.red),
      ('Vendas aceitas / OS', t.sales, Colors.teal),
      ('Ticket médio por OS', summary.ticket, Colors.purple),
    ];
    final customers = summary.customers.values.toList()
      ..sort((a, b) => b.spent.compareTo(a.spent));
    final monthly = summary.months.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final daily = summary.days.keys.toList()..sort((a, b) => b.compareTo(a));
    List<String> bucketRow(String key, FinancialBucket b, bool month) => [
          month
              ? '${key.substring(5, 7)}/${key.substring(0, 4)}'
              : '${key.substring(8, 10)}/${key.substring(5, 7)}/${key.substring(0, 4)}',
          money.format(b.sales),
          b.orders.toString(),
          money.format(b.received),
          money.format(b.paid),
          money.format(b.receivable),
          money.format(b.payable),
          money.format(b.balance),
        ];
    final customerMonths = <List<String>>[];
    for (final c in customers) {
      final keys = c.months.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final k in keys) {
        customerMonths.add([
          c.name,
          '${k.substring(5, 7)}/${k.substring(0, 4)}',
          money.format(c.months[k])
        ]);
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Resumo do período', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
          'Contas agrupadas pelo vencimento. Vendas e gastos por cliente consideram somente OS não canceladas, pela data de criação. O ticket médio divide o valor vendido pela quantidade de OS; parcelas não aumentam essa quantidade.'),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth -
                (c.maxWidth < 600
                        ? 1
                        : c.maxWidth < 1000
                            ? 2
                            : 4) *
                    10) /
            (c.maxWidth < 600
                ? 2
                : c.maxWidth < 1000
                    ? 3
                    : 5);
        return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map((m) => SizedBox(
                    width: width,
                    child: Card(
                        child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$1),
                            const SizedBox(height: 8),
                            Text(money.format(m.$2),
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: m.$3)),
                          ]),
                    ))))
                .toList());
      }),
      const SizedBox(height: 12),
      Text('${t.orders} OS • ${customers.length} clientes no período'),
      FinancialReportTable(
          title: 'Totais por mês',
          columns: const [
            'Mês',
            'Vendas / OS',
            'OS',
            'Recebido',
            'Pago',
            'A receber',
            'A pagar',
            'Saldo realizado'
          ],
          rows: monthly
              .map((k) => bucketRow(k, summary.months[k]!, true))
              .toList()),
      FinancialReportTable(
          title: 'Totais por dia',
          columns: const [
            'Dia',
            'Vendas / OS',
            'OS',
            'Recebido',
            'Pago',
            'A receber',
            'A pagar',
            'Saldo realizado'
          ],
          rows:
              daily.map((k) => bucketRow(k, summary.days[k]!, false)).toList()),
      FinancialReportTable(
          title: 'Clientes — gasto total e ticket médio',
          columns: const [
            'Cliente',
            'OS',
            'Gasto em vendas aceitas',
            'Ticket médio'
          ],
          rows: customers
              .map((c) => [
                    c.name,
                    c.orders.toString(),
                    money.format(c.spent),
                    money.format(c.ticket)
                  ])
              .toList()),
      FinancialReportTable(
          title: 'Gasto mensal por cliente',
          columns: const ['Cliente', 'Mês', 'Gasto em vendas aceitas'],
          rows: customerMonths),
    ]);
  }
}

class FinancialReportTable extends StatelessWidget {
  const FinancialReportTable(
      {super.key,
      required this.title,
      required this.columns,
      required this.rows});
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) => Card(
          child: ExpansionTile(
              title: Text(title),
              subtitle: Text('${rows.length} registros'),
              children: [
            if (rows.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhum registro neste período.'))
            else
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PaginatedDataTable(
                    key: ValueKey(title),
                    columns:
                        columns.map((c) => DataColumn(label: Text(c))).toList(),
                    source: _ReportSource(rows),
                    rowsPerPage: rows.length < 10 ? rows.length : 10,
                    showFirstLastButtons: true,
                  )),
          ]));
}

class _ReportSource extends DataTableSource {
  _ReportSource(this.rows);
  final List<List<String>> rows;
  @override
  DataRow? getRow(int i) => i < rows.length
      ? DataRow.byIndex(
          index: i, cells: rows[i].map((s) => DataCell(Text(s))).toList())
      : null;
  @override
  int get rowCount => rows.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}
