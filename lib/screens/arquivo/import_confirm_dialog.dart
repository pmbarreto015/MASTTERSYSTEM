import 'package:flutter/material.dart';

class ImportConfirmDialog extends StatefulWidget {
  const ImportConfirmDialog({
    super.key,
    required this.dadosNota,
  });

  final Map<String, dynamic> dadosNota;

  @override
  State<ImportConfirmDialog> createState() => _ImportConfirmDialogState();
}

class _ImportConfirmDialogState extends State<ImportConfirmDialog> {
  bool _importarProdutos = true;
  bool _importarFornecedor = true;

  @override
  Widget build(BuildContext context) {
    final produtos = widget.dadosNota['produtos'] as List<dynamic>? ?? [];
    final fornecedor = widget.dadosNota['fornecedor'] ?? 'Não informado';
    final cnpj = widget.dadosNota['cnpj'] ?? 'Não informado';
    final valor = widget.dadosNota['valor'] ?? 0;
    final tipo = widget.dadosNota['tipo'] ?? 'NF-e';
    final numero = widget.dadosNota['numero'] ?? '-';
    final cliente = widget.dadosNota['cliente'] ?? '';

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long,
              color: Color(0xFF0F62AC),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Resumo da Nota Fiscal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // INFORMAÇÕES DA NOTA
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tipo == 'NF-e'
                                ? Colors.blue.withValues(alpha: 0.1)
                                : Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color:
                                  tipo == 'NF-e' ? Colors.blue : Colors.purple,
                            ),
                          ),
                          child: Text(
                            tipo,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color:
                                  tipo == 'NF-e' ? Colors.blue : Colors.purple,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Nº $numero',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Fornecedor', fornecedor),
                    _buildInfoRow('CNPJ', cnpj),
                    _buildInfoRow(
                        'Valor Total', 'R\$ ${valor.toStringAsFixed(2)}'),
                    if (cliente.isNotEmpty) _buildInfoRow('Cliente', cliente),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // PRODUTOS
              if (produtos.isNotEmpty) ...[
                const Text(
                  'Produtos:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: produtos.map((prod) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                prod['nome'] ?? 'Produto',
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${prod['quantidade'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'R\$ ${(prod['valor_unitario'] ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // CHECKBOX: IMPORTAR PRODUTOS
                Row(
                  children: [
                    Checkbox(
                      value: _importarProdutos,
                      onChanged: (value) {
                        setState(() {
                          _importarProdutos = value ?? true;
                        });
                      },
                      activeColor: const Color(0xFF0F62AC),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Importar Produtos',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Serão importados ${produtos.length} produtos para o estoque',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              // CHECKBOX: IMPORTAR FORNECEDOR
              if (fornecedor != 'Não informado') ...[
                Row(
                  children: [
                    Checkbox(
                      value: _importarFornecedor,
                      onChanged: (value) {
                        setState(() {
                          _importarFornecedor = value ?? true;
                        });
                      },
                      activeColor: const Color(0xFF0F62AC),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Importar Fornecedor',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Será importado o fornecedor: $fornecedor',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),

              // RESUMO FINAL
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Serão importados: ${produtos.length} produto(s) e 1 fornecedor',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'importarProdutos': _importarProdutos,
              'importarFornecedor': _importarFornecedor,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F62AC),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Confirmar Importação'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
