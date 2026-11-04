import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../services/product_repository.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    this.product,
    this.onSave,
  });

  final ProductModel? product;
  final VoidCallback? onSave;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final ProductRepository _repository = ProductRepository();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nomeController;
  late TextEditingController _codigoController;
  late TextEditingController _precoController;
  late TextEditingController _custoController;
  late TextEditingController _descricaoController;
  late TextEditingController _estoqueController;
  late TextEditingController _unidadeController;

  String _selectedCategoria = 'grafica';
  bool _isActive = true;

  final List<Map<String, String>> _categorias = [
    {'id': 'grafica', 'nome': 'Gráfica'},
    {'id': 'comunicacao_visual', 'nome': 'Comunicação Visual'},
    {'id': 'estamparia', 'nome': 'Estamparia'},
    {'id': 'presentes', 'nome': 'Presentes / Lembrancinhas'},
    {'id': 'corte_laser', 'nome': 'Corte a Laser'},
  ];

  String _unidadeParaCategoria(String categoria) =>
      categoria == 'comunicacao_visual' || categoria == 'corte_laser'
          ? 'm²'
          : 'un';

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nomeController = TextEditingController(text: p?.nome ?? '');
    _codigoController = TextEditingController(text: p?.codigo ?? '');
    _precoController = TextEditingController(
      text: p?.preco != null ? p!.preco.toString() : '',
    );
    _custoController = TextEditingController(
      text: p?.cost != null ? p!.cost.toString() : '',
    );
    _descricaoController = TextEditingController(text: p?.descricao ?? '');
    _estoqueController = TextEditingController(
      text: p?.estoque != null ? p!.estoque.toString() : '0',
    );
    _selectedCategoria =
        p?.isEstamparia == true ? 'estamparia' : p?.categoria ?? 'grafica';
    _unidadeController = TextEditingController(
      text: _unidadeParaCategoria(_selectedCategoria),
    );
    _isActive = p?.ativo ?? true;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _codigoController.dispose();
    _precoController.dispose();
    _custoController.dispose();
    _descricaoController.dispose();
    _estoqueController.dispose();
    _unidadeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final product = ProductModel(
      id: widget.product?.id,
      codigo: _codigoController.text.trim(),
      nome: _nomeController.text.trim(),
      preco: double.tryParse(_precoController.text) ?? 0,
      cost: double.tryParse(_custoController.text) ?? 0,
      descricao: _descricaoController.text.trim(),
      categoria: _selectedCategoria,
      ativo: _isActive,
      estoque: double.tryParse(_estoqueController.text) ?? 0,
      unidade: _unidadeParaCategoria(_selectedCategoria),
    );

    try {
      if (widget.product != null) {
        await _repository.update(product);
      } else {
        await _repository.insert(product);
      }
      widget.onSave?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final isLaser = _selectedCategoria == 'corte_laser';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar Produto' : 'Novo Produto'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Código e Nome
                TextFormField(
                  controller: _codigoController,
                  decoration: const InputDecoration(
                    labelText: 'Código *',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Produto *',
                    prefixIcon: Icon(Icons.inventory_2),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoria *',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: _categorias.map((cat) {
                    return DropdownMenuItem<String>(
                      value: cat['id'],
                      child: Text(cat['nome']!),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() {
                    _selectedCategoria = v!;
                    _unidadeController.text = _unidadeParaCategoria(v);
                  }),
                ),
                const SizedBox(height: 12),

                if (isLaser)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.deepOrange.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.cut, color: Colors.deepOrange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O preço do Corte a Laser será calculado pelo Compositor.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.deepOrange),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Preço e Custo
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _precoController,
                        decoration: InputDecoration(
                          labelText: isLaser ? 'Preço (calculado)' : 'Preço *',
                          prefixIcon: const Icon(Icons.attach_money),
                          border: const OutlineInputBorder(),
                          enabled: !isLaser,
                        ),
                        keyboardType: TextInputType.number,
                        validator: isLaser
                            ? null
                            : (v) {
                                final val = double.tryParse(v ?? '');
                                if (val == null || val <= 0) {
                                  return 'Preço deve ser > 0';
                                }
                                return null;
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _custoController,
                        decoration: const InputDecoration(
                          labelText: 'Custo (R\$)',
                          prefixIcon: Icon(Icons.monetization_on),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Estoque e unidade de venda
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _estoqueController,
                        decoration: const InputDecoration(
                          labelText: 'Estoque',
                          prefixIcon: Icon(Icons.inventory),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unidadeController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Unidade de venda',
                          helperText: 'Definida pela categoria do produto',
                          prefixIcon: Icon(Icons.square_foot),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Descrição
                TextFormField(
                  controller: _descricaoController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeThumbColor: const Color(0xFF0F62AC),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isActive ? 'Ativo' : 'Inativo',
                      style: TextStyle(
                        color: _isActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Botão Salvar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(isEdit ? 'Atualizar Produto' : 'Criar Produto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F62AC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
