import 'package:flutter/material.dart';

class FinanceTable extends StatelessWidget {
  const FinanceTable(
      {super.key,
      required this.columns,
      required this.rows,
      this.emptyMessage = 'Nenhum registro para os filtros selecionados.'});
  final List<String> columns;
  final List<DataRow> rows;
  final String emptyMessage;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(emptyMessage),
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: colors.surface,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          child: DataTable(
            headingRowColor:
                WidgetStatePropertyAll(colors.surfaceContainerHighest),
            dataRowColor: WidgetStatePropertyAll(colors.surface),
            columns: columns
                .map((label) => DataColumn(label: Text(label)))
                .toList(),
            rows: rows,
            columnSpacing: 26,
            dataRowMaxHeight: 70,
            horizontalMargin: 18,
            dividerThickness: .5,
          ),
        ),
      ),
    );
  }
}
