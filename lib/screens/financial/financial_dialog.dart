import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/financial_model.dart';
import '../../constants/financial_categories.dart';

class FinancialDialog extends StatefulWidget {
  const FinancialDialog({
    super.key,
    this.transaction,
    this.onSave,
  });

  final FinancialModel? transaction;
  final Function(FinancialModel)? onSave;

  @override
  State<FinancialDialog> createState() => _FinancialDialogState();
}

class _FinancialDialogState extends State<FinancialDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  late TextEditingController _valorBrutoController;
  late TextEditingController _taxaController;
  late TextEditingController _notesController;
  late TextEditingController _customerNameController;

  late String _selectedType;
  late String _selectedCategoria;
  late String _selectedFormaPagamento;
  late DateTime _selectedDate;
  bool _isPaid = false;

  final List<String> _tipos = ['receber', 'pagar'];
  final List<String> _formasPagamento = [
    'PIX',
    'Dinheiro',
    'Débito',
    'Crédito',
    'Boleto',
    'Transferência',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _amountController = TextEditingController(
      text: t?.amount.toString() ?? '',
    );
    _valorBrutoController = TextEditingController(
      text: t?.valorBruto.toString() ?? '',
    );
    _taxaController = TextEditingController(
      text: t?.taxa.toString() ?? '',
    );
    _notesController = TextEditingController(text: t?.notes ?? '');
    _customerNameController =
        TextEditingController(text: t?.customerName ?? '');
    _selectedType = t?.type ?? 'receber';
    _selectedCategoria = t?.categoria ?? 'vendas';
    _selectedFormaPagamento = t?.formaPagamento ?? 'PIX';
    _selectedDate = t?.dueDate ?? DateTime.now();
    _isPaid = t?.isPaid ?? false;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _valorBrutoController.dispose();
    _taxaController.dispose();
    _notesController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }

  void _calcularLiquido() {
    final bruto = double.tryParse(_valorBrutoController.text) ?? 0;
    final taxa = double.tryParse(_taxaController.text) ?? 0;
    if (bruto > 0 && taxa > 0) {
      final liquido = bruto - (bruto * taxa / 100);
      _amountController.text = liquido.toStringAsFixed(2);
    } else if (bruto > 0) {
      _amountController.text = bruto.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.transaction == null ? Icons.add : Icons.edit,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            widget.transaction == null ? 'Nova Transação' : 'Editar Transação',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tipo
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo *',
                    prefixIcon: Icon(Icons.swap_horiz),
                    border: OutlineInputBorder(),
                  ),
                  items: _tipos.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(
                            t == 'receber'
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: t == 'receber' ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(t == 'receber'
                              ? 'Contas a Receber'
                              : 'Contas a Pagar'),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
                const SizedBox(height: 12),

                // Categoria
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoria *',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: FinancialCategories.getCategorias().map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Row(
                        children: [
                          Icon(
                            FinancialCategories.getIcon(cat),
                            color: FinancialCategories.getColor(cat),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(FinancialCategories.getLabel(cat)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedCategoria = v!),
                ),
                const SizedBox(height: 12),

                // Descrição
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição *',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),

                // Cliente
                TextFormField(
                  controller: _customerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Cliente (opcional)',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Forma de Pagamento
                DropdownButtonFormField<String>(
                  initialValue: _selectedFormaPagamento,
                  decoration: const InputDecoration(
                    labelText: 'Forma de Pagamento',
                    prefixIcon: Icon(Icons.payment),
                    border: OutlineInputBorder(),
                  ),
                  items: _formasPagamento.map((f) {
                    return DropdownMenuItem(
                      value: f,
                      child: Text(f),
                    );
                  }).toList(),
                  onChanged: (v) =>
                      setState(() => _selectedFormaPagamento = v!),
                ),
                const SizedBox(height: 12),

                // Valor Bruto e Taxa
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _valorBrutoController,
                        decoration: const InputDecoration(
                          labelText: 'Valor Bruto',
                          prefixIcon: Icon(Icons.attach_money),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _calcularLiquido(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _taxaController,
                        decoration: const InputDecoration(
                          labelText: 'Taxa (%)',
                          prefixIcon: Icon(Icons.percent),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _calcularLiquido(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Valor Líquido
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Valor Líquido *',
                    prefixIcon: Icon(Icons.monetization_on),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),

                // Data
                ListTile(
                  title: const Text('Data de Vencimento'),
                  subtitle:
                      Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) {
                      setState(() => _selectedDate = date);
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Observações
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    prefixIcon: Icon(Icons.note),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),

                // Pago
                Row(
                  children: [
                    Checkbox(
                      value: _isPaid,
                      onChanged: (v) => setState(() => _isPaid = v!),
                      activeColor: const Color(0xFF0F62AC),
                    ),
                    const Text(
                      'Marcar como pago',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
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
            if (_formKey.currentState!.validate()) {
              final financial = FinancialModel(
                id: widget.transaction?.id,
                description: _descriptionController.text.trim(),
                amount: double.parse(_amountController.text),
                type: _selectedType,
                dueDate: _selectedDate,
                isPaid: _isPaid,
                notes: _notesController.text.trim(),
                customerName: _customerNameController.text.trim(),
                categoria: _selectedCategoria,
                formaPagamento: _selectedFormaPagamento,
                valorBruto: double.tryParse(_valorBrutoController.text) ?? 0,
                taxa: double.tryParse(_taxaController.text) ?? 0,
                valorLiquido: double.tryParse(_amountController.text) ?? 0,
                status: _isPaid ? 'pago' : 'pendente',
                createdAt: widget.transaction?.createdAt ?? DateTime.now(),
                updatedAt: DateTime.now(),
                orderId: widget.transaction?.orderId,
                customerId: widget.transaction?.customerId,
                parcela: widget.transaction?.parcela ?? 0,
                totalParcelas: widget.transaction?.totalParcelas ?? 0,
                pagamentos: widget.transaction?.pagamentos ?? [],
              );

              if (widget.onSave != null) {
                widget.onSave!(financial);
              }
              Navigator.pop(context, financial);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F62AC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(widget.transaction == null ? 'Adicionar' : 'Atualizar'),
        ),
      ],
    );
  }
}
