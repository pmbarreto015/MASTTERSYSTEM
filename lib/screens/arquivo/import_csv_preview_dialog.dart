import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ImportCsvPreviewDialog extends StatefulWidget {
  const ImportCsvPreviewDialog({
    super.key,
    required this.produtos,
    required this.onConfirm,
  });

  final List<Map<String, dynamic>> produtos;
  final Function(double margem) onConfirm;

  @override
  State<ImportCsvPreviewDialog> createState() => _ImportCsvPreviewDialogState();
}

class _ImportCsvPreviewDialogState extends State<ImportCsvPreviewDialog> {
  final TextEditingController _margemController =
      TextEditingController(text: '30');
  double _margem = 30;

  // FÓRMULA CORRETA: Preço = Custo × (1 + Margem%)
  double _calcularPrecoVenda(double custo) {
    if (custo <= 0) return custo;

    final multiplicador = 1 + (_margem / 100);
    return custo * multiplicador;
  }

  @override
  void initState() {
    super.initState();
    _margemController.addListener(_atualizarMargem);
  }

  @override
  void dispose() {
    _margemController.removeListener(_atualizarMargem);
    _margemController.dispose();
    super.dispose();
  }

  void _atualizarMargem() {
    final valor = double.tryParse(_margemController.text.replaceAll(',', '.'));
    if (valor != null && valor > 0) {
      setState(() => _margem = valor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalProdutos = widget.produtos.length;
    final totalCusto = widget.produtos.fold<double>(
      0,
      (sum, p) => sum + (p['custo']?.toDouble() ?? 0),
    );
    final precoTotal = widget.produtos.fold<double>(
      0,
      (sum, p) => sum + _calcularPrecoVenda(p['custo']?.toDouble() ?? 0),
    );
    final lucroTotal = precoTotal - totalCusto;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.upload_file, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            'Prévia da Importação',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resumo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Produtos',
                          style: TextStyle(
                              fontSize: 10, color: Colors.blue.shade700),
                        ),
                        Text(
                          '$totalProdutos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Custo Total',
                          style: TextStyle(
                              fontSize: 10, color: Colors.blue.shade700),
                        ),
                        Text(
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(totalCusto),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Preço Total',
                          style: TextStyle(
                              fontSize: 10, color: Colors.green.shade700),
                        ),
                        Text(
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(precoTotal),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Lucro Total',
                          style: TextStyle(
                              fontSize: 10, color: Colors.purple.shade700),
                        ),
                        Text(
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(lucroTotal),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Margem de Lucro
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.percent, color: Color(0xFF0F62AC), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _margemController,
                      decoration: const InputDecoration(
                        labelText: 'Margem de Lucro (%)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixText: '%',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _margem >= 30
                          ? Colors.green.shade50
                          : _margem >= 15
                              ? Colors.orange.shade50
                              : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _margem >= 30
                            ? Colors.green.shade300
                            : _margem >= 15
                                ? Colors.orange.shade300
                                : Colors.red.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _margem >= 30
                              ? Icons.trending_up
                              : _margem >= 15
                                  ? Icons.trending_flat
                                  : Icons.trending_down,
                          size: 14,
                          color: _margem >= 30
                              ? Colors.green
                              : _margem >= 15
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _margem >= 30
                              ? 'Excelente'
                              : _margem >= 15
                                  ? 'Boa'
                                  : 'Baixa',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _margem >= 30
                                ? Colors.green
                                : _margem >= 15
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Lista de Produtos
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      // Cabeçalho
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F62AC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Produto',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'Custo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'Venda',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'Lucro',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...widget.produtos.take(10).map((prod) {
                        final custo = prod['custo']?.toDouble() ?? 0;
                        final venda = _calcularPrecoVenda(custo);
                        final lucro = venda - custo;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  prod['nome'] ?? 'Sem nome',
                                  style: const TextStyle(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  NumberFormat.currency(
                                          locale: 'pt_BR', symbol: 'R\$')
                                      .format(custo),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade700,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  NumberFormat.currency(
                                          locale: 'pt_BR', symbol: 'R\$')
                                      .format(venda),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: lucro > 0
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    NumberFormat.currency(
                                            locale: 'pt_BR', symbol: 'R\$')
                                        .format(lucro),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          lucro > 0 ? Colors.green : Colors.red,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (widget.produtos.length > 10)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '... e mais ${widget.produtos.length - 10} produtos',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            widget.onConfirm(_margem);
          },
          icon: const Icon(Icons.check, size: 18),
          label: Text(
            'Importar ${widget.produtos.length} produtos',
            style: const TextStyle(fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
