import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/models/order_model.dart';

void main() {
  test('etapas de uma venda aparecem como em produção sem perder a etapa', () {
    for (final entry in OrderModel.productionStatuses.entries) {
      final order = OrderModel(tipo: 'OS', status: entry.key);
      expect(order.productionStatusLabel, entry.value);
      expect(order.orderStatusGroup,
          entry.key == 'entregue' ? 'entregue' : 'em_producao');
    }
    expect(OrderModel(tipo: 'OS', status: 'cancelado').orderStatusGroup,
        'cancelado');
    expect(
        OrderModel(tipo: 'ORCAMENTO', status: 'aguardando_pagamento')
            .orderStatusGroup,
        'aguardando_pagamento');
  });
}
