import 'financial_model.dart';
import 'order_model.dart';

bool inFinancialPeriod(DateTime date, DateTime? start, DateTime? end) {
  final local = date.toLocal(),
      day = DateTime(
          date.toLocal().year, date.toLocal().month, date.toLocal().day);
  return (start == null ||
          !day.isBefore(DateTime(start.year, start.month, start.day))) &&
      (end == null ||
          !DateTime(local.year, local.month, local.day)
              .isAfter(DateTime(end.year, end.month, end.day)));
}

class FinancialBucket {
  double received = 0, paid = 0, receivable = 0, payable = 0, sales = 0;
  int orders = 0;
  double get balance => received - paid;
}

class CustomerFinancialSummary {
  CustomerFinancialSummary(this.name);
  final String name;
  double spent = 0;
  int orders = 0;
  final Map<String, double> months = {};
  double get ticket => orders == 0 ? 0 : spent / orders;
}

class FinancialSummary {
  FinancialSummary(List<FinancialModel> transactions, List<OrderModel> orders,
      {DateTime? now}) {
    final today = now ?? DateTime.now();
    for (final t in transactions.where((t) => t.status != 'cancelado')) {
      final date = t.dueDate.toLocal(),
          month = _month(t.dueDate.toLocal()),
          day = _day(t.dueDate.toLocal());
      for (final b in [
        totals,
        months.putIfAbsent(month, FinancialBucket.new),
        days.putIfAbsent(day, FinancialBucket.new)
      ]) {
        if (t.type == 'receber') {
          if (t.isPaid) {
            b.received += t.amount;
          } else {
            b.receivable += t.amount;
          }
        } else {
          if (t.isPaid) {
            b.paid += t.amount;
          } else {
            b.payable += t.amount;
          }
        }
      }
      if (!t.isPaid &&
          DateTime(date.year, date.month, date.day)
              .isBefore(DateTime(today.year, today.month, today.day))) {
        if (t.type == 'receber') {
          overdueReceivable += t.amount;
        } else {
          overduePayable += t.amount;
        }
      }
    }
    final seen = <int>{};
    for (final o in orders.where((o) => o.isAcceptedSale)) {
      if (o.id != null && !seen.add(o.id!)) continue;
      final date = DateTime.tryParse(o.dataCriacao)?.toLocal();
      if (date == null) continue;
      final month = _month(date), day = _day(date);
      for (final b in [
        totals,
        months.putIfAbsent(month, FinancialBucket.new),
        days.putIfAbsent(day, FinancialBucket.new)
      ]) {
        b.sales += o.valorTotal;
        b.orders++;
      }
      final key = o.clienteId?.toString() ??
          ('nome:${o.clienteNome ?? 'Não informado'}');
      final c = customers.putIfAbsent(key,
          () => CustomerFinancialSummary(o.clienteNome ?? 'Não informado'));
      c.spent += o.valorTotal;
      c.orders++;
      c.months
          .update(month, (v) => v + o.valorTotal, ifAbsent: () => o.valorTotal);
    }
  }
  final FinancialBucket totals = FinancialBucket();
  final Map<String, FinancialBucket> months = {}, days = {};
  final Map<String, CustomerFinancialSummary> customers = {};
  double overdueReceivable = 0, overduePayable = 0;
  double get ticket => totals.orders == 0 ? 0 : totals.sales / totals.orders;
  double get projectedBalance =>
      totals.balance + totals.receivable - totals.payable;
  static String _month(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String _day(DateTime d) =>
      '${_month(d)}-${d.day.toString().padLeft(2, '0')}';
}
