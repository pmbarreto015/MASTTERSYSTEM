import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/models/order_model.dart';
import 'package:masttersystem/services/financial_repository.dart';

void main() {
  test('discount is saved and subtracted from item totals', () {
    final order = OrderModel(
      desconto: 45,
      itens: [
        OrderItemModel(
          produtoNome: 'Banner',
          quantidade: 1,
          precoUnitario: 150,
          subtotal: 150,
          largura: 1000,
          altura: 700,
        ),
      ],
    );

    order.calcularTotal();
    final restored = OrderModel.fromMap(order.toMap());

    expect(order.valorTotal, 105);
    expect(order.toMap()['discount'], 45);
    expect(restored.desconto, 45);
    expect(order.itens.single.largura, 1000);
    expect(order.itens.single.altura, 700);
  });

  test('entry and remaining balance add up to discounted total', () {
    final order = OrderModel(
      tipo: 'OS',
      valorTotal: 105,
      entrada: 30,
      formaPagamento: '50% no ato + 50% na entrega',
      clienteId: 1,
      clienteNome: 'Cliente',
    );

    final planned = FinancialRepository().planFromOrder(order);

    expect(planned.fold<double>(0, (sum, row) => sum + row.amount), 105);
    expect(planned.where((row) => row.isPaid).single.amount, 30);
    expect(planned.where((row) => !row.isPaid).single.amount, 75);
  });

  test('zero entry does not create a zero-value receipt', () {
    final order = OrderModel(
      tipo: 'OS',
      valorTotal: 105,
      formaPagamento: '50% no ato + 50% na entrega',
      clienteId: 1,
      clienteNome: 'Cliente',
    );

    final planned = FinancialRepository().planFromOrder(order);

    expect(planned, hasLength(1));
    expect(planned.single.amount, 105);
  });
}
