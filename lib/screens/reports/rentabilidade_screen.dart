import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/background_refresh_mixin.dart';

import '../../models/order_model.dart';
import '../../services/order_repository.dart';

/// Mostra a rentabilidade gravada no momento da venda.
class RentabilidadeScreen extends StatefulWidget {
  const RentabilidadeScreen({super.key});

  @override
  State<RentabilidadeScreen> createState() => _RentabilidadeScreenState();
}

class _RentabilidadeScreenState extends State<RentabilidadeScreen>
    with BackgroundRefreshMixin<RentabilidadeScreen> {
  final _repository = OrderRepository();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  List<OrderModel> _pedidos = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  Future<void> refreshInBackground() => _carregar();

  Future<void> _carregar() async {
    if (!isRefreshingInBackground) setState(() => _carregando = true);
    try {
      final pedidos =
          (await _repository.getAll()).where((o) => o.isAcceptedSale).toList();
      if (mounted) setState(() => _pedidos = pedidos);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  double get _vendas =>
      _pedidos.fold<double>(0, (total, pedido) => total + pedido.valorTotal);
  double get _custos => _pedidos.fold<double>(
      0,
      (total, pedido) =>
          total +
          pedido.itens.fold<double>(0, (soma, item) => soma + item.custoTotal));
  double get _lucro => _vendas - _custos;

  Iterable<OrderItemModel> get _itensTerceirizados =>
      _pedidos.expand((pedido) => pedido.itens).where(
            (item) => item.terceirizado,
          );

  int get _quantidadeItensTerceirizados => _itensTerceirizados.length;
  double get _vendasTerceirizadas => _itensTerceirizados.fold<double>(
        0,
        (total, item) => total + item.subtotal,
      );
  double get _custosTerceirizados => _itensTerceirizados.fold<double>(
        0,
        (total, item) => total + item.custoTotal,
      );
  double get _lucroTerceirizado => _vendasTerceirizadas - _custosTerceirizados;

  Color _cor(double valor) => valor >= 0 ? Colors.green : Colors.red;

  @override
  Widget build(BuildContext context) {
    final margem = _vendas == 0 ? 0.0 : _lucro / _vendas * 100;
    final margemTerceirizada = _vendasTerceirizadas == 0
        ? 0.0
        : _lucroTerceirizado / _vendasTerceirizadas * 100;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentabilidade de Vendas'),
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _resumo('Vendas', _moeda.format(_vendas), Colors.blue),
                      _resumo('Custos', _moeda.format(_custos), Colors.orange),
                      _resumo('Lucro', _moeda.format(_lucro), _cor(_lucro)),
                      _resumo('Margem', '${margem.toStringAsFixed(1)}%',
                          _cor(margem)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Terceirização • uso interno',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '($_quantidadeItensTerceirizados itens)',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _resumo(
                        'Vendas terceirizadas',
                        _moeda.format(_vendasTerceirizadas),
                        Colors.orange,
                      ),
                      _resumo(
                        'Custos terceirizados',
                        _moeda.format(_custosTerceirizados),
                        Colors.deepOrange,
                      ),
                      _resumo(
                        'Lucro terceirizado',
                        _moeda.format(_lucroTerceirizado),
                        _cor(_lucroTerceirizado),
                      ),
                      _resumo(
                        'Margem terceirizada',
                        '${margemTerceirizada.toStringAsFixed(1)}%',
                        _cor(margemTerceirizada),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Detalhe por compra / venda',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_pedidos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('Nenhuma venda cadastrada.')),
                    ),
                  ..._pedidos.map(_pedidoCard),
                ],
              ),
            ),
    );
  }

  Widget _resumo(String titulo, String valor, Color cor) => Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: cor.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: TextStyle(color: cor, fontSize: 12)),
          const SizedBox(height: 4),
          Text(valor,
              style: TextStyle(
                  color: cor, fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
      );

  Widget _pedidoCard(OrderModel pedido) {
    final custo =
        pedido.itens.fold<double>(0, (total, item) => total + item.custoTotal);
    final lucro = pedido.valorTotal - custo;
    final margem = pedido.valorTotal == 0 ? 0 : lucro / pedido.valorTotal * 100;
    final terceirizados =
        pedido.itens.where((item) => item.terceirizado).length;
    return Card(
      child: ExpansionTile(
        title: Text('${pedido.numero} — ${pedido.clienteNome ?? 'Cliente'}'),
        subtitle: Text(
          'Venda ${_moeda.format(pedido.valorTotal)} · Lucro ${_moeda.format(lucro)} (${margem.toStringAsFixed(1)}%)${terceirizados > 0 ? ' · $terceirizados terceirizado(s)' : ''}',
          style: TextStyle(color: _cor(lucro)),
        ),
        children: pedido.itens.map((item) => _itemTile(item)).toList(),
      ),
    );
  }

  Widget _itemTile(OrderItemModel item) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.terceirizado
              ? Colors.orange.withValues(alpha: .08)
              : Colors.grey.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
          border: item.terceirizado
              ? Border.all(color: Colors.orange.withValues(alpha: .7))
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.produtoNome,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (item.terceirizado)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'TERCEIRIZAÇÃO',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            Text('Qtd: ${item.quantidade}'),
            Text('Venda: ${_moeda.format(item.subtotal)}'),
            Text('Custo: ${_moeda.format(item.custoTotal)}'),
            Text(
                'Lucro: ${_moeda.format(item.lucro)} (${item.margemLucro.toStringAsFixed(1)}%)',
                style: TextStyle(
                    color: _cor(item.lucro), fontWeight: FontWeight.w600)),
          ]),
          if (item.detalhesCusto.isNotEmpty) ...[
            const Divider(),
            const Text('Materiais e custos do corte:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(item.detalhesCusto),
          ],
        ]),
      );
}
