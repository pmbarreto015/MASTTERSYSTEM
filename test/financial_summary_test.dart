import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/models/order_model.dart';
import 'package:masttersystem/models/financial_model.dart';
import 'package:masttersystem/models/financial_summary.dart';
import 'package:masttersystem/services/financial_repository.dart';

FinancialModel entry(double amount,
        {String type = 'receber',
        bool paid = false,
        String status = 'pendente',
        DateTime? date}) =>
    FinancialModel(
        description: 'Teste',
        amount: amount,
        type: type,
        dueDate: date ?? DateTime(2026, 10, 5),
        isPaid: paid,
        status: status,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1));
OrderModel sale(int id, double total,
        {String type = 'OS',
        String status = 'aguardando_pagamento',
        int customer = 1,
        String date = '2026-10-01T10:00:00'}) =>
    OrderModel(
        id: id,
        valorTotal: total,
        tipo: type,
        status: status,
        clienteId: customer,
        clienteNome: 'Cliente',
        dataCriacao: date);

void main() {
  test('orçamento e OS cancelada não planejam financeiro', () {
    expect(FinancialRepository().planFromOrder(sale(1, 100, type: 'ORCAMENTO')),
        isEmpty);
    expect(
        FinancialRepository().planFromOrder(sale(2, 100, status: 'cancelado')),
        isEmpty);
  });
  test('ticket ignora orçamento, cancelamento e OS duplicada', () {
    final os = sale(1, 100);
    final s = FinancialSummary([], [
      os,
      os,
      sale(2, 200),
      sale(3, 1000, type: 'ORCAMENTO'),
      sale(4, 900, status: 'cancelado')
    ]);
    expect(s.totals.sales, 300);
    expect(s.totals.orders, 2);
    expect(s.ticket, 150);
    expect(s.customers['1']!.spent, 300);
  });
  test('parcial não duplica venda ou ticket', () {
    final s = FinancialSummary(
        [entry(20, paid: true), entry(80, status: 'parcial')], [sale(1, 100)]);
    expect(s.totals.received, 20);
    expect(s.totals.receivable, 80);
    expect(s.ticket, 100);
  });
  test('saldo desconta despesas pagas e previsão considera contas abertas', () {
    final s = FinancialSummary([
      entry(100, paid: true),
      entry(30, type: 'pagar', paid: true),
      entry(50),
      entry(40, type: 'pagar')
    ], []);
    expect(s.totals.balance, 70);
    expect(s.projectedBalance, 80);
  });
  test('cancelados não entram nos saldos', () {
    final s = FinancialSummary([
      entry(100, status: 'cancelado'),
      entry(200, paid: true, status: 'cancelado'),
      entry(50)
    ], []);
    expect(s.totals.received, 0);
    expect(s.totals.receivable, 50);
  });
  test('IDs diferentes não misturam clientes de nomes iguais', () {
    final s = FinancialSummary([], [sale(1, 100), sale(2, 300, customer: 2)]);
    expect(s.customers.length, 2);
    expect(s.customers['1']!.spent, 100);
    expect(s.customers['2']!.spent, 300);
  });
  test('totais por mês e dia incluem OS sem parcelas', () {
    final s = FinancialSummary(
        [entry(40, paid: true, date: DateTime(2026, 9, 30))],
        [sale(1, 100, date: '2026-09-30T23:00:00'), sale(2, 200)]);
    expect(s.months['2026-09']!.sales, 100);
    expect(s.months['2026-10']!.sales, 200);
    expect(s.days['2026-09-30']!.received, 40);
  });
  test('período inclui os dias completos', () {
    final a = DateTime(2026, 10, 1), b = DateTime(2026, 10, 31);
    expect(inFinancialPeriod(a, a, b), isTrue);
    expect(inFinancialPeriod(DateTime(2026, 10, 31, 23, 59, 59), a, b), isTrue);
    expect(inFinancialPeriod(DateTime(2026, 11, 1), a, b), isFalse);
    expect(inFinancialPeriod(DateTime(2026, 9, 30, 23, 59), a, b), isFalse);
  });
  test('conta vencendo hoje não é vencida', () {
    final s = FinancialSummary([
      entry(50, date: DateTime(2026, 10, 9)),
      entry(20, date: DateTime(2026, 10, 8))
    ], [], now: DateTime(2026, 10, 9, 18));
    expect(s.overdueReceivable, 20);
  });
}
