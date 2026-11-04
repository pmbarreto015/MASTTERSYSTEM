import 'package:flutter/material.dart';
import '../../models/order_model.dart';
import '../../models/product_model.dart';
import '../../models/customer_model.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, this.existingOrder});
  final OrderModel? existingOrder;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen>
    with TickerProviderStateMixin {
  late OrderModel _order;
  late TabController _tabController;

  final TextEditingController _observationController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  List<CustomerModel> _mockCustomers = [];
  List<ProductModel> _mockProducts = [];

  CustomerModel? _selectedCustomer;
  ProductModel? _selectedProductToAdd;

  final Map<String, String> _statusLabels = {
    'aguardando_pagamento': 'Aguardando Pagamento',
    'pagamento_recebido': 'Pagamento Recebido',
    'em_producao': 'Em Produção',
    'pronto': 'Pronto',
    'entregue': 'Entregue',
    'cancelado': 'Cancelado',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _order = widget.existingOrder ?? OrderModel();

    _mockCustomers = [
      CustomerModel.create(name: 'ROBERT DE NIRO', phone: '(88) 8888-8888'),
      CustomerModel.create(
          name: 'FERRAMENTAS CORTA FINO', phone: '(88) 8888-8888'),
    ];
    _selectedCustomer = _mockCustomers.first;

    _mockProducts = [
      ProductModel(
          id: 1,
          nome: 'IMPRESSÃO DIGITAL EM VINIL PERFURATE',
          categoria: 'comunicacao_visual',
          unidade: 'm²',
          preco: 120.00),
      ProductModel(
          id: 2,
          nome: 'PLACA BACKT 2 FACES',
          categoria: 'comunicacao_visual',
          unidade: 'm²',
          preco: 480.00),
      ProductModel(
          id: 3,
          nome: 'MANTA MAGNÉTICA 0,8MM',
          categoria: 'adesivos',
          unidade: 'm²',
          preco: 275.00),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    _observationController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // MÉTODO CORRIGIDO
  void _addProductToOrder(ProductModel product) {
    var width = double.tryParse(_widthController.text);
    var height = double.tryParse(_heightController.text);
    var qty = int.tryParse(_quantityController.text) ?? 1;

    var totalQty = qty.toDouble();

    if (product.isPorMetroQuadrado) {
      // CORRIGIDO: sem parênteses
      if (width != null && height != null) {
        totalQty = (width * height) * qty;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Informe Largura e Altura para produtos em m²!')),
        );
        return;
      }
    }

    // CORREÇÃO PRINCIPAL: Verificar se _order não é nulo
    _order.adicionarItem(
        product, totalQty.toInt(), _observationController.text);
    setState(() {});

    _widthController.clear();
    _heightController.clear();
    _quantityController.clear();
  }

  void _removeItem(int index) {
    setState(() {
      _order.removerItem(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ordem de Serviço #${_order.numero}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F62AC)),
                ),
                Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.print, color: Color(0xFF0F62AC)),
                        onPressed: () {}),
                    IconButton(
                        icon: const Icon(Icons.save, color: Color(0xFF0F62AC)),
                        onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
          _buildOrderHeader(),
          const Divider(height: 1),
          Expanded(
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF0F62AC),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF0F62AC),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(text: "Lista de Produtos e Serviços"),
                    Tab(text: "Imagens do Trabalho / Serviço"),
                    Tab(text: "Informações e Observações"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildProductListTab(),
                      _buildImagesTab(),
                      _buildObservationsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildOrderFooter(),
        ],
      ),
    );
  }

  Widget _buildOrderHeader() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<CustomerModel>(
              decoration: const InputDecoration(
                labelText: "Cliente",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              initialValue: _selectedCustomer,
              items: _mockCustomers
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c.name),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => _selectedCustomer = val),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.search, size: 16),
            label: const Text("Pesquisar"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F62AC),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductListTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ProductModel>(
                  decoration: const InputDecoration(
                    labelText: "Selecionar Produto",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _selectedProductToAdd,
                  items: _mockProducts
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.nome),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedProductToAdd = val),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _quantityController,
                  decoration: const InputDecoration(
                      labelText: "Qtde",
                      isDense: true,
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _widthController,
                  decoration: const InputDecoration(
                      labelText: "Larg",
                      isDense: true,
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _heightController,
                  decoration: const InputDecoration(
                      labelText: "Alt",
                      isDense: true,
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon:
                    const Icon(Icons.add_circle, color: Colors.green, size: 32),
                onPressed: () {
                  if (_selectedProductToAdd != null) {
                    _addProductToOrder(_selectedProductToAdd!);
                  }
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 8,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F5F5)),
              border: TableBorder.all(color: const Color(0xFFE0E0E0)),
              columns: const [
                DataColumn(
                    label: Text("Produto",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(
                    label: Text("Un.",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(
                    label: Text("Qtde",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(
                    label: Text("Larg",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(
                    label: Text("Alt",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(
                    label: Text("Total",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(
                    label: Text("Ações",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              rows: _order.itens.asMap().entries.map((entry) {
                int idx = entry.key;
                OrderItemModel item = entry.value;
                return DataRow(
                  cells: [
                    DataCell(Text(item.produtoNome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                    const DataCell(Text("MT2", style: TextStyle(fontSize: 12))),
                    DataCell(Text(item.quantidade.toString(),
                        style: const TextStyle(fontSize: 12))),
                    const DataCell(
                        Text("1,000", style: TextStyle(fontSize: 12))),
                    const DataCell(
                        Text("2,300", style: TextStyle(fontSize: 12))),
                    DataCell(Text(
                      "R\$ ${item.subtotal.toStringAsFixed(2)}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F62AC),
                          fontSize: 12),
                    )),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.delete,
                            color: Colors.red, size: 20),
                        onPressed: () => _removeItem(idx),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagesTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: [
          _buildImageCard(
              "https://via.placeholder.com/150x150.png?text=Arte+1"),
          _buildImageCard(
              "https://via.placeholder.com/150x150.png?text=Arte+2"),
          _buildImageCard(
              "https://via.placeholder.com/150x150.png?text=Arte+3"),
          _buildImageCard(
              "https://via.placeholder.com/150x150.png?text=Arte+4"),
        ],
      ),
    );
  }

  Widget _buildImageCard(String url) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Column(
        children: [
          Expanded(child: Image.network(url, fit: BoxFit.cover)),
          const Padding(
            padding: EdgeInsets.all(4.0),
            child: Text("ARQUIVO.JPG",
                style: TextStyle(fontSize: 10, color: Color(0xFF0F62AC))),
          )
        ],
      ),
    );
  }

  Widget _buildObservationsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _observationController,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: "Observações Gerais do Serviço",
                border: OutlineInputBorder(),
                hintText: "Ex: Trocar os painéis, Painel quebrado...",
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text("Status:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _order.status,
                items: [
                  'aguardando_pagamento',
                  'pagamento_recebido',
                  'em_producao',
                  'pronto',
                  'entregue',
                  'cancelado'
                ]
                    .map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(_statusLabels[status] ?? status,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _order.status = val;
                    });
                  }
                },
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildOrderFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.print),
                label: const Text("Imprimir"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.attach_money),
                label: const Text("Finalizar"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Text("Total Produtos:",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 10),
                  Text("R\$ ${_order.valorTotal.toStringAsFixed(2)}",
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F62AC))),
                ],
              ),
              Row(
                children: [
                  const Text("Total Final:",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 10),
                  Text("R\$ ${_order.valorTotal.toStringAsFixed(2)}",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
