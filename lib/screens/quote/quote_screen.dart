import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/order_model.dart';
import '../../models/customer_model.dart';
import '../../models/seller_model.dart';
import '../../models/product_model.dart';
import '../../models/material_model.dart';
import '../../models/maquina_model.dart';
import '../../models/retalho_model.dart';
import '../../services/impressao_service.dart';
import '../../services/order_repository.dart' as repo;
import '../../services/customer_repository.dart';
import '../../services/sales_repository.dart';
import '../../services/product_repository.dart';
import '../../services/material_repository.dart';
import '../../services/maquina_repository.dart';
import '../../services/retalho_repository.dart';
import '../customers/customer_form_screen.dart';
import 'preview_pdf_screen.dart';

class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key});

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen>
    with BackgroundRefreshMixin<QuoteScreen> {
  final CustomerRepository _customerRepo = CustomerRepository();
  final SalesRepository _salesRepo = SalesRepository();
  final ProductRepository _productRepo = ProductRepository();
  final MaterialRepository _materialRepo = MaterialRepository();
  final MaquinaRepository _maquinaRepo = MaquinaRepository();
  final RetalhoRepository _retalhoRepo = RetalhoRepository();

  // Dados
  List<CustomerModel> _customers = [];
  List<SellerModel> _sellers = [];
  List<ProductModel> _products = [];
  List<MaterialModel> _materiais = [];
  List<MaquinaModel> _maquinas = [];
  List<RetalhoModel> _retalhos = [];

  // Controllers
  final TextEditingController _customerSearchController =
      TextEditingController();
  final TextEditingController _entryController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _otherValuesController = TextEditingController();
  final TextEditingController _observationsController = TextEditingController();
  final TextEditingController _productObservationController =
      TextEditingController();

  // CONTROLLERS DA ÁREA
  final TextEditingController _larguraController = TextEditingController();
  final TextEditingController _alturaController = TextEditingController();

  // Compositor Controllers
  final TextEditingController _tempoMaquinaController = TextEditingController();
  final TextEditingController _outrosDescricaoController =
      TextEditingController();
  final TextEditingController _outrosController = TextEditingController();
  final TextEditingController _observacoesCompositorController =
      TextEditingController();

  // LISTA DINÂMICA DE MATERIAIS
  final List<Map<String, dynamic>> _materiaisSelecionados = [];

  // Selecionados
  CustomerModel? _selectedCustomer;
  SellerModel? _selectedSeller;
  ProductModel? _selectedProduct;
  MaquinaModel? _selectedMaquina;

  // Estado
  final List<Map<String, dynamic>> _items = [];
  bool _isSaving = false;
  bool _isLoading = true;
  bool _showCustomerSearch = false;

  // Controles do produto
  double _length = 0.0;
  double _width = 0.0;
  int _quantity = 1;
  bool _isTerceirizado = false;

  // DADOS DA COMPOSIÇÃO
  double _areaTotal = 0.0;
  double _valorMaterial = 0.0;
  double _valorMaquina = 0.0;
  double _valorOutros = 0.0;
  double _totalComposicao = 0.0;
  bool _mostrarCompositor = false;

  // Dados do pedido
  DateTime? _deliveryDate;
  DateTime? _approvalDate;
  String _paymentMethod = 'À Vista';
  String _tipoDocumento = 'OS';
  String _productionStatus = 'aguardando_pagamento';
  double _maxDiscount = 10.0;

  // GETTERS
  bool get _isAreaProduct => _selectedProduct?.isPorMetroQuadrado ?? false;
  bool get _isCorteLaser => _selectedProduct?.isCorteLaser ?? false;

  // Getters
  double get _subtotal =>
      _items.fold(0.0, (sum, item) => sum + (item['total'] as double));
  double get _discountPercent => _parseMoney(_discountController.text);
  double get _discountValue =>
      (_subtotal * _discountPercent / 100).clamp(0.0, _subtotal).toDouble();
  double get _otherValues => _parseMoney(_otherValuesController.text);
  double get _total => _subtotal - _discountValue + _otherValues;
  double get _entryValue =>
      _parseMoney(_entryController.text).clamp(0.0, _total).toDouble();

  double _parseMoney(String value) {
    var normalized = value.trim().replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (normalized.contains(',') && normalized.contains('.')) {
      if (normalized.lastIndexOf(',') > normalized.lastIndexOf('.')) {
        normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = normalized.replaceAll(',', '');
      }
    } else {
      normalized = normalized.replaceAll(',', '.');
    }
    return double.tryParse(normalized) ?? 0;
  }

  double _parseDecimal(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
            value?.toString().trim().replaceAll(',', '.') ?? '') ??
        0;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadMaxDiscount();
    _approvalDate = DateTime.now();
    _adicionarLinhaMaterial();
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    _entryController.dispose();
    _discountController.dispose();
    _otherValuesController.dispose();
    _observationsController.dispose();
    _productObservationController.dispose();
    _larguraController.dispose();
    _alturaController.dispose();
    _tempoMaquinaController.dispose();
    _outrosDescricaoController.dispose();
    _outrosController.dispose();
    _observacoesCompositorController.dispose();
    for (var item in _materiaisSelecionados) {
      (item['controllerQuantidade'] as TextEditingController).dispose();
      (item['controllerValor'] as TextEditingController).dispose();
      if (item['controllerLargura'] != null) {
        (item['controllerLargura'] as TextEditingController).dispose();
      }
      if (item['controllerAltura'] != null) {
        (item['controllerAltura'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadMaxDiscount() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _maxDiscount =
        double.tryParse(prefs.getString('max_discount') ?? '10') ?? 10;
    setState(() {});
  }

  @override
  Future<void> refreshInBackground() => _loadData();

  Future<void> _loadData() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final customers = await _customerRepo.getAll();
      final sellers = await _salesRepo.getAll();
      final products = await _productRepo.getAll();
      final materiais = await _materialRepo.getAll();
      final maquinas = await _maquinaRepo.getAll();
      final retalhos = await _retalhoRepo.getDisponiveis();
      if (!mounted) return;
      _customers = customers;
      _sellers = sellers;
      _products = products;
      _materiais = materiais;
      _maquinas = maquinas;
      _retalhos = retalhos;
      print(
          'Clientes: ${_customers.length}, Produtos: ${_products.length}, Materiais: ${_materiais.length}, Máquinas: ${_maquinas.length}, Retalhos: ${_retalhos.length}');
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Falha ao carregar dados da venda: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(
        'Não foi possível carregar os dados. Verifique o acesso ao banco e tente novamente.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  String _friendlySaveError(Object error) {
    if (error is ArgumentError && error.message != null) {
      return error.message.toString();
    }
    if (error is StateError) {
      return error.message;
    }

    final details = error.toString().toLowerCase();
    if (details.contains('orders.customer_id') ||
        details.contains('customer_id') && details.contains('not null')) {
      return 'O cliente selecionado não está vinculado ao cadastro. '
          'Remova o cliente desta venda e selecione-o novamente.';
    }
    if (details.contains('foreign key')) {
      return 'Um cliente, vendedor ou produto desta venda não existe mais. '
          'Selecione novamente os dados e tente salvar.';
    }
    if (details.contains('unique') && details.contains('orders.number')) {
      return 'Não foi possível gerar o número do pedido. Tente salvar novamente.';
    }
    if (details.contains('database is locked') ||
        details.contains('database is busy')) {
      return 'O banco de dados está sendo usado por outra operação. '
          'Aguarde alguns segundos e tente novamente.';
    }
    if (details.contains('readonly') ||
        details.contains('read-only') ||
        details.contains('permission denied')) {
      return 'O sistema não tem permissão para gravar no banco de dados. '
          'Verifique as permissões da pasta configurada.';
    }
    if (details.contains('disk full') || details.contains('database or disk')) {
      return 'Não há espaço disponível para salvar. Libere espaço no disco e tente novamente.';
    }
    return 'Não foi possível salvar a venda. Confira os dados informados e tente novamente.';
  }

  List<CustomerModel> get _filteredCustomers {
    final query = _customerSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _customers;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return _customers.where((c) {
      final phoneDigits = c.phone.replaceAll(RegExp(r'\D'), '');
      return c.name.toLowerCase().contains(query) ||
          c.phone.toLowerCase().contains(query) ||
          (digits.isNotEmpty && phoneDigits.contains(digits)) ||
          (c.email?.toLowerCase().contains(query) ?? false) ||
          (c.document?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  void _selectCustomer(CustomerModel customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerSearchController.clear();
      _showCustomerSearch = false;
    });
  }

  void _clearCustomer() {
    setState(() {
      _selectedCustomer = null;
      _customerSearchController.clear();
      _showCustomerSearch = false;
    });
  }

  Future<T?> _showSearchPicker<T>({
    required String title,
    required String hint,
    required List<T> items,
    required String Function(T item) labelBuilder,
    required String Function(T item) searchTextBuilder,
    String Function(T item)? subtitleBuilder,
  }) async {
    final controller = TextEditingController();
    var filtered = List<T>.from(items);
    final route = DialogRoute<T>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final query = value.trim().toLowerCase();
                    final digits = query.replaceAll(RegExp(r'\D'), '');
                    setDialogState(() {
                      filtered = items.where((item) {
                        final text = searchTextBuilder(item).toLowerCase();
                        final textDigits = text.replaceAll(RegExp(r'\D'), '');
                        return query.isEmpty ||
                            text.contains(query) ||
                            (digits.isNotEmpty && textDigits.contains(digits));
                      }).toList();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Nenhum resultado encontrado'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final subtitle = subtitleBuilder?.call(item);
                            return ListTile(
                              dense: true,
                              title: Text(labelBuilder(item)),
                              subtitle: subtitle == null || subtitle.isEmpty
                                  ? null
                                  : Text(subtitle),
                              onTap: () => Navigator.pop(dialogContext, item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    final selected = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    return selected;
  }

  Widget _buildSearchSelectionField({
    required String label,
    required String hint,
    required String? value,
    required VoidCallback onTap,
    IconData icon = Icons.search,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(
          value ?? hint,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: value == null ? Colors.grey.shade600 : null,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _chooseSeller() async {
    final seller = await _showSearchPicker<SellerModel>(
      title: 'Selecionar vendedor',
      hint: 'Digite nome, celular ou e-mail',
      items: _sellers,
      labelBuilder: (item) => item.name,
      subtitleBuilder: (item) => '${item.phone}  •  ${item.email}',
      searchTextBuilder: (item) => '${item.name} ${item.phone} ${item.email}',
    );
    if (seller != null && mounted) setState(() => _selectedSeller = seller);
  }

  Future<void> _chooseProduct() async {
    final product = await _showSearchPicker<ProductModel>(
      title: 'Selecionar produto ou serviço',
      hint: 'Digite nome, código, descrição ou categoria',
      items: _products,
      labelBuilder: (item) => item.nome,
      subtitleBuilder: (item) =>
          '${item.codigo}  •  ${item.getCategoriaLabel()}  •  ${item.unidade}',
      searchTextBuilder: (item) =>
          '${item.nome} ${item.codigo} ${item.descricao} ${item.categoria} ${item.getCategoriaLabel()}',
    );
    if (product != null && mounted) _selectProduct(product);
  }

  void _selectProduct(ProductModel product) {
    setState(() {
      _selectedProduct = product;
      _length = 0.0;
      _width = 0.0;
      _quantity = 1;
      _isTerceirizado = false;

      if (product.isCorteLaser) {
        _mostrarCompositor = true;
        _selectedMaquina = null;
        _larguraController.clear();
        _alturaController.clear();
        _tempoMaquinaController.clear();
        _outrosDescricaoController.clear();
        _outrosController.clear();
        _observacoesCompositorController.clear();
        _areaTotal = 0.0;
        _valorMaterial = 0.0;
        _valorMaquina = 0.0;
        _valorOutros = 0.0;
        _totalComposicao = 0.0;
        _materiaisSelecionados.clear();
        _adicionarLinhaMaterial();
      } else {
        _mostrarCompositor = false;
      }
    });
  }

  // ============================================================
  // GERENCIAMENTO DE MATERIAIS DINÂMICOS
  // ============================================================

  void _adicionarLinhaMaterial() {
    setState(() {
      _materiaisSelecionados.add({
        'material': null as MaterialModel?,
        'retalho': null as RetalhoModel?,
        'quantidade': 0.0,
        'valor': 0.0,
        'largura': 0.0,
        'altura': 0.0,
        'unidade': '',
        'isRetalho': false,
        'controllerQuantidade': TextEditingController(),
        'controllerValor': TextEditingController(),
        'controllerLargura': TextEditingController(),
        'controllerAltura': TextEditingController(),
      });
    });
  }

  void _removerLinhaMaterial(int index) {
    setState(() {
      _materiaisSelecionados.removeAt(index);
    });
    _calcularComposicao();
  }

  void _atualizarMaterial(int index, MaterialModel? material) {
    setState(() {
      _materiaisSelecionados[index]['material'] = material;
      _materiaisSelecionados[index]['unidade'] = material?.unidade ?? '';
      _materiaisSelecionados[index]['isRetalho'] = false;
      _materiaisSelecionados[index]['retalho'] = null;

      if (material?.unidade == 'm²') {
        final qtd = _materiaisSelecionados[index]['controllerQuantidade']
            as TextEditingController;
        qtd.text = _areaTotal.toStringAsFixed(2);
        _materiaisSelecionados[index]['quantidade'] = _areaTotal;
      }

      _calcularValorMaterial(index);
    });
  }

  void _usarRetalho(int index, RetalhoModel retalho) {
    final material = _materiais.firstWhere(
      (m) => m.id == retalho.materialId,
      orElse: () => MaterialModel(
        nome: 'Material não encontrado',
        codigo: 'N/A',
        tipo: 'm2',
        categoria: 'outros',
        unidade: 'm²',
      ),
    );

    setState(() {
      _materiaisSelecionados[index]['material'] = material;
      _materiaisSelecionados[index]['retalho'] = retalho;
      _materiaisSelecionados[index]['unidade'] = material.unidade;
      _materiaisSelecionados[index]['isRetalho'] = true;
      _materiaisSelecionados[index]['quantidade'] = retalho.area;

      final qtd = _materiaisSelecionados[index]['controllerQuantidade']
          as TextEditingController;
      qtd.text = retalho.area.toStringAsFixed(2);

      final larg = _materiaisSelecionados[index]['controllerLargura']
          as TextEditingController;
      final alt = _materiaisSelecionados[index]['controllerAltura']
          as TextEditingController;
      larg.text = retalho.largura.toStringAsFixed(0);
      alt.text = retalho.altura.toStringAsFixed(0);

      _larguraController.text = retalho.largura.toStringAsFixed(0);
      _alturaController.text = retalho.altura.toStringAsFixed(0);
      _areaTotal = retalho.area;

      _calcularValorMaterial(index);
      _showSuccess('Retalho ${retalho.codigo} selecionado!');
    });
  }

  void _calcularValorMaterial(int index) {
    final item = _materiaisSelecionados[index];
    final material = item['material'] as MaterialModel?;
    final controllerQuantidade =
        item['controllerQuantidade'] as TextEditingController;
    final controllerValor = item['controllerValor'] as TextEditingController;

    if (material != null) {
      double quantidade = double.tryParse(controllerQuantidade.text) ?? 0;
      final preco = _precoVendaUnitarioMaterial(material);

      final valorTotal = quantidade * preco;
      controllerValor.text = valorTotal.toStringAsFixed(2);
      item['quantidade'] = quantidade;
      item['valor'] = valorTotal;
    }
    _calcularComposicao();
  }

  double _custoUnitarioMaterial(MaterialModel material) {
    return material.unidade == 'm²'
        ? material.calcularPrecoPorM2()
        : material.precoUnidade;
  }

  double _precoVendaUnitarioMaterial(MaterialModel material) {
    // Sem preço de venda cadastrado, mantém compatibilidade com materiais antigos.
    return material.precoVenda > 0
        ? material.precoVenda
        : _custoUnitarioMaterial(material);
  }

  double _calcularCustoMateriaisSelecionados() {
    return _materiaisSelecionados.fold(0.0, (total, item) {
      final material = item['material'] as MaterialModel?;
      final quantidade = double.tryParse(
            (item['controllerQuantidade'] as TextEditingController).text,
          ) ??
          0;
      return total +
          (material == null
              ? 0
              : quantidade * _custoUnitarioMaterial(material));
    });
  }

  void _calcularArea() {
    final largura = _parseDecimal(_larguraController.text);
    final altura = _parseDecimal(_alturaController.text);
    _areaTotal = (largura * altura) / 1000000;
    setState(() {});

    for (int i = 0; i < _materiaisSelecionados.length; i++) {
      final item = _materiaisSelecionados[i];
      final material = item['material'] as MaterialModel?;
      if (material != null && material.unidade == 'm²' && !item['isRetalho']) {
        final controller =
            item['controllerQuantidade'] as TextEditingController;
        controller.text = _areaTotal.toStringAsFixed(2);
        _calcularValorMaterial(i);
      }
    }
    _calcularComposicao();
  }

  double _calcularTotalMateriais() {
    double total = 0.0;
    for (var item in _materiaisSelecionados) {
      final controllerValor = item['controllerValor'] as TextEditingController;
      String valorStr = controllerValor.text
          .replaceAll('R\$', '')
          .replaceAll(',', '.')
          .trim();
      if (valorStr.isEmpty) valorStr = '0';
      final valor = double.tryParse(valorStr) ?? 0;
      total += valor;
    }
    return total;
  }

  void _calcularComposicao() {
    _valorMaterial = _calcularTotalMateriais();

    final tempo = _parseDecimal(_tempoMaquinaController.text);
    double custoMinuto = _selectedMaquina?.custoTotalMinuto ?? 0;
    _valorMaquina = tempo * custoMinuto;

    _valorOutros = _parseDecimal(_outrosController.text);

    _totalComposicao = _valorMaterial + _valorMaquina + _valorOutros;

    setState(() {});
  }

  void _adicionarComposicao() {
    if (_areaTotal <= 0) {
      _showError('Informe a Largura e Altura para calcular a área');
      return;
    }

    bool temMaterial = false;
    String materiaisTexto = '';
    for (var item in _materiaisSelecionados) {
      final material = item['material'] as MaterialModel?;
      final controllerValor = item['controllerValor'] as TextEditingController;
      final controllerQuantidade =
          item['controllerQuantidade'] as TextEditingController;
      final isRetalho = item['isRetalho'] ?? false;
      final retalho = item['retalho'] as RetalhoModel?;

      if (material != null &&
          controllerValor.text.isNotEmpty &&
          controllerValor.text != '0' &&
          controllerValor.text != '0,00') {
        temMaterial = true;
        final tipo = isRetalho ? 'RETALHO' : 'MATERIAL';
        final quantidade = double.tryParse(controllerQuantidade.text) ?? 0;
        final custo = quantidade * _custoUnitarioMaterial(material);
        materiaisTexto +=
            '$tipo: ${material.nome}: ${controllerQuantidade.text} ${material.unidade} | Custo R\$ ${custo.toStringAsFixed(2)} | Venda R\$ ${controllerValor.text}\n';
        if (isRetalho && retalho != null) {
          materiaisTexto += '   Código Retalho: ${retalho.codigo}\n';
          materiaisTexto +=
              '   Dimensões: ${retalho.largura.toStringAsFixed(0)}x${retalho.altura.toStringAsFixed(0)}mm\n';
        }
      }
    }

    if (!temMaterial) {
      _showError('Selecione pelo menos um material com valor');
      return;
    }

    if (_valorMaquina <= 0 && _valorOutros <= 0) {
      _showError('Adicione máquina ou outros custos');
      return;
    }

    final nomeProduto = _selectedProduct?.nome ?? 'Corte a Laser';
    final outrosDescricao = _outrosDescricaoController.text.trim();
    if (_valorOutros > 0) {
      materiaisTexto +=
          'OUTROS: ${outrosDescricao.isEmpty ? 'Sem descrição' : outrosDescricao} | Venda R\$ ${_valorOutros.toStringAsFixed(2)}\n';
    }

    setState(() {
      _items.add({
        'product': nomeProduto,
        'productId': _selectedProduct?.id,
        'quantity': 1,
        'price': _totalComposicao,
        'total': _totalComposicao,
        'unit': 'un',
        'isArea': true,
        'isCorteLaser': true,
        'terceirizado': _isTerceirizado,
        'specs': _observacoesCompositorController.text,
        'cost': _calcularCustoMateriaisSelecionados() +
            _valorMaquina +
            _valorOutros,
        'area': _areaTotal,
        'largura': _parseDecimal(_larguraController.text),
        'altura': _parseDecimal(_alturaController.text),
        'materiais': materiaisTexto,
        'maquina': _selectedMaquina?.nome ?? 'N/A',
        'tempoMaquina': _tempoMaquinaController.text,
        'valorMaquina': _valorMaquina,
        'valorOutros': _valorOutros,
        'outrosDescricao': outrosDescricao,
        'totalMateriais': _valorMaterial,
      });
    });

    _limparCompositor();
    _showSuccess('Item de Corte a Laser adicionado!');
  }

  void _limparCompositor() {
    for (var item in _materiaisSelecionados) {
      (item['controllerQuantidade'] as TextEditingController).clear();
      (item['controllerValor'] as TextEditingController).clear();
      if (item['controllerLargura'] != null) {
        (item['controllerLargura'] as TextEditingController).clear();
      }
      if (item['controllerAltura'] != null) {
        (item['controllerAltura'] as TextEditingController).clear();
      }
      item['material'] = null;
      item['retalho'] = null;
      item['isRetalho'] = false;
    }
    _materiaisSelecionados.clear();
    _larguraController.clear();
    _alturaController.clear();
    _tempoMaquinaController.clear();
    _outrosDescricaoController.clear();
    _outrosController.clear();
    _observacoesCompositorController.clear();
    _areaTotal = 0.0;
    _valorMaterial = 0.0;
    _valorMaquina = 0.0;
    _valorOutros = 0.0;
    _totalComposicao = 0.0;
    _mostrarCompositor = false;
    _isTerceirizado = false;
    _selectedMaquina = null;
    _selectedProduct = null;
    _adicionarLinhaMaterial();
  }

  void _fecharCompositor() {
    setState(() {
      _mostrarCompositor = false;
      _isTerceirizado = false;
      _selectedProduct = null;
      _selectedMaquina = null;
      for (var item in _materiaisSelecionados) {
        (item['controllerQuantidade'] as TextEditingController).dispose();
        (item['controllerValor'] as TextEditingController).dispose();
        if (item['controllerLargura'] != null) {
          (item['controllerLargura'] as TextEditingController).dispose();
        }
        if (item['controllerAltura'] != null) {
          (item['controllerAltura'] as TextEditingController).dispose();
        }
      }
      _materiaisSelecionados.clear();
      _larguraController.clear();
      _alturaController.clear();
      _tempoMaquinaController.clear();
      _outrosDescricaoController.clear();
      _outrosController.clear();
      _observacoesCompositorController.clear();
      _areaTotal = 0.0;
      _valorMaterial = 0.0;
      _valorMaquina = 0.0;
      _valorOutros = 0.0;
      _totalComposicao = 0.0;
    });
  }

  // ============================================================
  // ADICIONAR ITEM NORMAL
  // ============================================================

  void _addItem() {
    if (_selectedCustomer == null) {
      _showError('Selecione um cliente primeiro');
      return;
    }

    if (_selectedProduct == null) {
      _showError('Selecione um produto');
      return;
    }

    if (_selectedProduct!.isCorteLaser) {
      setState(() {
        _mostrarCompositor = true;
        _selectedMaquina = null;
        _larguraController.clear();
        _alturaController.clear();
        _tempoMaquinaController.clear();
        _outrosDescricaoController.clear();
        _outrosController.clear();
        _observacoesCompositorController.clear();
        _areaTotal = 0.0;
        _valorMaterial = 0.0;
        _valorMaquina = 0.0;
        _valorOutros = 0.0;
        _totalComposicao = 0.0;
        _materiaisSelecionados.clear();
        _adicionarLinhaMaterial();
      });
      return;
    }

    double total = 0.0;
    final precoUnitario = _selectedProduct!.preco;

    if (_isAreaProduct) {
      if (_length <= 0 || _width <= 0) {
        _showError('Informe a Largura e Altura (mm)');
        return;
      }
      final areaM2 = (_length * _width) / 1000000;
      total = areaM2 * precoUnitario * _quantity;
    } else {
      total = precoUnitario * _quantity;
    }

    final specs = _productObservationController.text.trim();

    setState(() {
      _items.add({
        'product': _selectedProduct!.nome,
        'productId': _selectedProduct!.id,
        'quantity': _quantity,
        'price': precoUnitario,
        'total': total,
        'largura': _length,
        'altura': _width,
        'unit': _selectedProduct!.unidade,
        'isArea': _isAreaProduct,
        'isCorteLaser': false,
        'terceirizado': _isTerceirizado,
        'specs': specs,
        // O custo do rascunho representa o total da linha. Na gravação ele
        // é dividido pela quantidade para formar custoUnitario da OS.
        'cost': (_isAreaProduct
                ? _selectedProduct!.cost * ((_length * _width) / 1000000)
                : _selectedProduct!.cost) *
            _quantity,
      });
    });

    _quantity = 1;
    _isTerceirizado = false;
    _length = 0.0;
    _width = 0.0;
    _productObservationController.clear();
    _showSuccess('Item adicionado!');
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _saveOrder() async {
    if (_selectedCustomer == null) {
      _showError('Selecione um cliente');
      return;
    }
    if (_selectedCustomer!.id == null) {
      _showError(
        'Este cliente ainda não foi vinculado ao cadastro. Remova-o da venda e selecione novamente.',
      );
      return;
    }
    if (_items.isEmpty) {
      _showError('Adicione pelo menos um item');
      return;
    }
    if (_selectedSeller == null) {
      _showError('Selecione um vendedor');
      return;
    }
    if (_selectedSeller!.id == null) {
      _showError(
        'O vendedor selecionado não possui um cadastro válido. Selecione outro vendedor.',
      );
      return;
    }
    if (_items.any((item) =>
        item['productId'] == null || (item['productId'] as num) <= 0)) {
      _showError(
        'Existe um produto sem cadastro válido na lista. Remova o item e selecione o produto novamente.',
      );
      return;
    }

    if (_isSaving) return;
    final documentType = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Salvar como orçamento ou OS?'),
        content: const Text(
            'Orçamento aguarda o aceite e não entra no financeiro, nas entregas ou nos totais de vendas. OS confirma uma venda aceita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          OutlinedButton(
              onPressed: () => Navigator.pop(c, 'ORCAMENTO'),
              child: const Text('Orçamento')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'OS'),
              child: const Text('OS — venda aceita')),
        ],
      ),
    );
    if (documentType == null || !mounted) return;
    if (documentType == 'OS' && _deliveryDate == null) {
      _showError('Selecione a data de entrega da OS');
      return;
    }
    setState(() => _tipoDocumento = documentType);
    final selectedCustomer = _selectedCustomer!;
    final selectedSeller = _selectedSeller!;

    setState(() => _isSaving = true);

    try {
      final orderItems = _items
          .map((item) => OrderItemModel(
                produtoId: item['productId'] ?? 0,
                produtoNome: item['product'],
                quantidade: item['quantity'],
                precoUnitario: item['price'],
                subtotal: item['total'],
                especificacoes: item['specs'] ?? '',
                largura: _parseDecimal(item['largura']),
                altura: _parseDecimal(item['altura']),
                custoUnitario: ((item['cost'] ?? 0) as num).toDouble() /
                    ((item['quantity'] ?? 1) as num).toDouble(),
                detalhesCusto: item['materiais'] ?? '',
                terceirizado: item['terceirizado'] == true,
              ))
          .toList();

      final order = OrderModel(
        tipo: _tipoDocumento,
        status:
            _tipoDocumento == 'OS' ? _productionStatus : 'aguardando_pagamento',
        clienteId: selectedCustomer.id,
        clienteNome: selectedCustomer.name,
        sellerId: selectedSeller.id,
        formaPagamento: _paymentMethod,
        prioridade: 'normal',
        observacoes: _observationsController.text,
        dataEntrega: _deliveryDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_deliveryDate!),
        itens: orderItems,
        desconto: _discountValue,
        outrosValores: _otherValues,
        entrada: _entryValue,
      );

      order.calcularTotal();

      final repository = repo.OrderRepository();
      final savedOrder = await repository.create(order);

      final printingService = ImpressaoService();
      final bytes = await printingService.gerarPdfBytes(
        savedOrder,
        selectedCustomer,
        selectedSeller,
      );
      final productionBytes = savedOrder.tipo == 'OS'
          ? await printingService.gerarPdfProducaoBytes(
              savedOrder,
              selectedCustomer,
              selectedSeller,
            )
          : null;

      if (!mounted) return;
      setState(() => _isSaving = false);

      _showSuccess(
          '${_tipoDocumento == 'ORCAMENTO' ? 'Orçamento' : 'OS'} #${savedOrder.numero} salva!');

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPdfScreen(
            pdfBytes: bytes,
            productionPdfBytes: productionBytes,
            titulo:
                'Via do cliente • ${_tipoDocumento == 'ORCAMENTO' ? 'Orçamento' : 'Pedido'} #${savedOrder.numero}',
            productionTitle: 'Ordem de produção #${savedOrder.numero}',
          ),
        ),
      );

      if (!mounted) return;
      setState(() {
        _items.clear();
        _selectedProduct = null;
        _entryController.clear();
        _discountController.clear();
        _otherValuesController.clear();
        _observationsController.clear();
        _deliveryDate = null;
        _productionStatus = 'aguardando_pagamento';
        _quantity = 1;
        _isTerceirizado = false;
        _length = 0.0;
        _width = 0.0;
        _mostrarCompositor = false;
      });
    } catch (e) {
      debugPrint('Falha ao salvar venda/orçamento: $e');
      setState(() => _isSaving = false);
      _showError(_friendlySaveError(e));
    }
  }

  // ============================================================
  // WIDGET: LINHA DE MATERIAL
  // ============================================================

  Widget _buildMaterialRow(int index) {
    final item = _materiaisSelecionados[index];
    final material = item['material'] as MaterialModel?;
    final retalho = item['retalho'] as RetalhoModel?;
    final controllerQuantidade =
        item['controllerQuantidade'] as TextEditingController;
    final controllerValor = item['controllerValor'] as TextEditingController;
    final controllerLargura =
        item['controllerLargura'] as TextEditingController;
    final controllerAltura = item['controllerAltura'] as TextEditingController;
    final unidade = item['unidade'] ?? '';
    final isRetalho = item['isRetalho'] ?? false;

    final isM2 = unidade == 'm²';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isRetalho
            ? Colors.green.shade50
            : index % 2 == 0
                ? Colors.white
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRetalho ? Colors.green.shade300 : Colors.grey.shade300,
          width: isRetalho ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color:
                      isRetalho ? Colors.green.shade100 : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: isRetalho ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isRetalho)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'RETALHO',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: isRetalho && retalho != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            retalho.nome,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            'Código: ${retalho.codigo}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    : _buildSearchSelectionField(
                        label: 'Material',
                        hint: 'Digite ou selecione',
                        value: material == null
                            ? null
                            : '${material.nome} (${material.unidade})',
                        icon: Icons.layers,
                        onTap: () async {
                          final selected =
                              await _showSearchPicker<MaterialModel>(
                            title: 'Selecionar material',
                            hint: 'Digite nome, código, tipo ou categoria',
                            items: _materiais,
                            labelBuilder: (item) => item.nome,
                            subtitleBuilder: (item) =>
                                '${item.codigo}  •  ${item.categoria}  •  ${item.unidade}',
                            searchTextBuilder: (item) =>
                                '${item.nome} ${item.codigo} ${item.tipo} ${item.categoria} ${item.cor}',
                          );
                          if (selected != null && mounted) {
                            _atualizarMaterial(index, selected);
                          }
                        },
                      ),
              ),
              if (_retalhos.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.recycling,
                    color: isRetalho ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                  onPressed: () => _mostrarRetalhosDisponiveis(index),
                  tooltip: 'Aproveitar Retalho',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (index > 0 || _materiaisSelecionados.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 18),
                  onPressed: () => _removerLinhaMaterial(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (material != null && isM2) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllerLargura,
                    decoration: const InputDecoration(
                      labelText: 'Largura (mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11),
                    onChanged: (_) {
                      final larg = _parseDecimal(controllerLargura.text);
                      final alt = _parseDecimal(controllerAltura.text);
                      double area = (larg * alt) / 1000000;
                      controllerQuantidade.text = area.toStringAsFixed(2);
                      _calcularValorMaterial(index);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                const Text('×', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controllerAltura,
                    decoration: const InputDecoration(
                      labelText: 'Altura (mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11),
                    onChanged: (_) {
                      final larg = _parseDecimal(controllerLargura.text);
                      final alt = _parseDecimal(controllerAltura.text);
                      double area = (larg * alt) / 1000000;
                      controllerQuantidade.text = area.toStringAsFixed(2);
                      _calcularValorMaterial(index);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ÁREA',
                        style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                      Text(
                        '${controllerQuantidade.text} m²',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: controllerQuantidade,
                  decoration: InputDecoration(
                    labelText: isM2
                        ? 'Área (m²)'
                        : 'Quantidade (${material?.unidade ?? unidade})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  keyboardType: TextInputType.number,
                  readOnly: isM2 && !isRetalho,
                  onChanged: (_) => _calcularValorMaterial(index),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: TextField(
                    controller: controllerValor,
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      labelStyle: TextStyle(color: Colors.blue),
                      prefixStyle: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                    ),
                    readOnly: true,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DIÁLOGO DE APROVEITAMENTO DE RETALHOS
  // ============================================================

  void _mostrarRetalhosDisponiveis(int index) {
    if (_retalhos.isEmpty) {
      _showError('Nenhum retalho disponível');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.recycling,
                            color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aproveitamento de Retalhos',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Selecione um retalho disponível',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: _retalhos.length,
                      itemBuilder: (context, retalhoIndex) {
                        final retalho = _retalhos[retalhoIndex];
                        final material = _materiais.firstWhere(
                          (m) => m.id == retalho.materialId,
                          orElse: () => MaterialModel(
                            nome: 'Material não encontrado',
                            codigo: 'N/A',
                            tipo: 'm2',
                            categoria: 'outros',
                            unidade: 'm²',
                          ),
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side:
                                const BorderSide(color: Colors.green, width: 1),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.recycling,
                                  color: Colors.green),
                            ),
                            title: Text(
                              retalho.nome,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Código: ${retalho.codigo} | Material: ${material.nome}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                Text(
                                  '${retalho.largura.toStringAsFixed(0)} x ${retalho.altura.toStringAsFixed(0)} mm = ${retalho.area.toStringAsFixed(3)} m²',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.green),
                                ),
                                Text(
                                  'Valor estimado: R\$ ${retalho.valorEstimado.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.blue),
                                ),
                              ],
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _usarRetalho(index, retalho);
                              },
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Usar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // SEÇÃO: CLIENTE (COM DATA APROVAÇÃO E VENDEDOR AUTO)
  // ============================================================

  Widget _buildCustomerSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person, color: Color(0xFF0F62AC), size: 18),
                SizedBox(width: 8),
                Text(
                  'Dados do Cliente',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const Divider(height: 12),

            // Cliente
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _selectedCustomer == null
                      ? Column(
                          children: [
                            TextField(
                              controller: _customerSearchController,
                              decoration: const InputDecoration(
                                hintText:
                                    'Digite nome, celular, documento ou selecione',
                                prefixIcon: Icon(Icons.search, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (v) => setState(() {
                                _showCustomerSearch = v.isNotEmpty;
                              }),
                              onTap: () =>
                                  setState(() => _showCustomerSearch = true),
                            ),
                            if (_showCustomerSearch)
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                child: _filteredCustomers.isEmpty
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child:
                                              Text('Nenhum cliente encontrado'),
                                        ),
                                      )
                                    : ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _filteredCustomers.length,
                                        itemBuilder: (context, index) {
                                          final customer =
                                              _filteredCustomers[index];
                                          return ListTile(
                                            dense: true,
                                            visualDensity: const VisualDensity(
                                              vertical: -4,
                                            ),
                                            leading: const Icon(
                                              Icons.person_outline,
                                              size: 16,
                                            ),
                                            title: Text(
                                              customer.name,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                            subtitle: Text(
                                              customer.formattedPhone,
                                              style:
                                                  const TextStyle(fontSize: 10),
                                            ),
                                            onTap: () =>
                                                _selectCustomer(customer),
                                          );
                                        },
                                      ),
                              ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFF0F62AC),
                                child: Text(
                                  _selectedCustomer!.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedCustomer!.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      _selectedCustomer!.phone,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                onPressed: _clearCustomer,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerFormScreen(
                          onSave: (customer) async {
                            try {
                              final createdCustomer =
                                  await _customerRepo.create(customer);
                              await _loadData();
                              _selectCustomer(createdCustomer);
                              _showSuccess('Cliente criado!');
                            } catch (error) {
                              debugPrint('Falha ao cadastrar cliente: $error');
                              _showError(
                                'Não foi possível cadastrar o cliente. '
                                'Verifique os dados informados e tente novamente.',
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Novo', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // VENDEDOR (AUTOMÁTICO) + DATAS
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchSelectionField(
                  label: 'Vendedor',
                  hint: 'Digite ou selecione o vendedor',
                  value: _selectedSeller?.name,
                  icon: Icons.person,
                  onTap: _chooseSeller,
                ),
                const SizedBox(height: 10),
                // DATA DE APROVAÇÃO
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _approvalDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _approvalDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Aprovação',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.edit_calendar, size: 18),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          child: Text(
                            _approvalDate != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(_approvalDate!)
                                : 'Selecione',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // DATA DE ENTREGA
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                DateTime.now().add(const Duration(days: 3)),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _deliveryDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Entrega',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          child: Text(
                            _deliveryDate != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(_deliveryDate!)
                                : 'Selecione',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEÇÃO: PAGAMENTO
  // ============================================================

  Widget _buildPaymentSection() {
    final paymentMethod = DropdownButtonFormField<String>(
      initialValue: _paymentMethod,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Pagamento',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        '\u00c0 Vista',
        'PIX',
        'Cart\u00e3o D\u00e9bito',
        'Cart\u00e3o Cr\u00e9dito',
        '50% no ato + 50% na entrega',
        'Parcelado Loja',
      ]
          .map(
            (method) => DropdownMenuItem(
              value: method,
              child: Text(
                method,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _paymentMethod = value);
      },
    );
    final entry = TextField(
      controller: _entryController,
      decoration: const InputDecoration(
        labelText: 'Entrada',
        prefixIcon: Icon(Icons.monetization_on, size: 18),
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.payment, color: Color(0xFF0F62AC), size: 18),
                SizedBox(width: 8),
                Text(
                  'Formas de Pagamento',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const Divider(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 500
                  ? Column(
                      children: [
                        paymentMethod,
                        const SizedBox(height: 8),
                        entry,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 2, child: paymentMethod),
                        const SizedBox(width: 8),
                        Expanded(child: entry),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEÇÃO: PRODUTOS (CORRIGIDA)
  // ============================================================

  Widget _buildOrderStatusSection() {
    final isSale = _tipoDocumento == 'OS';
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    color: Color(0xFF0F62AC), size: 18),
                SizedBox(width: 8),
                Text(
                  'Status da venda',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const Divider(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('sale-production-status-$_productionStatus'),
              initialValue: _productionStatus,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Etapa inicial da produção',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: OrderModel.productionStatuses.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: isSale && !_isSaving
                  ? (value) {
                      if (value != null) {
                        setState(() => _productionStatus = value);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              isSale
                  ? 'A etapa da produção não altera os pagamentos. Confira os recebimentos no Financeiro.'
                  : 'O orçamento só entra na produção após o aceite da venda.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2, color: Color(0xFF0F62AC), size: 18),
                SizedBox(width: 8),
                Text(
                  'Relacionar Produtos e Serviços',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const Divider(height: 12),

            // SELEÇÃO DO PRODUTO - CORRIGIDA
            Container(
              constraints: const BoxConstraints(minWidth: 200),
              child: _buildSearchSelectionField(
                label: 'Produto',
                hint: 'Digite ou selecione um produto',
                value: _selectedProduct == null
                    ? null
                    : '${_selectedProduct!.nome} (${_selectedProduct!.unidade})',
                icon: Icons.inventory_2,
                onTap: _chooseProduct,
              ),
            ),

            if (_selectedProduct != null && !_isCorteLaser)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _selectedProduct!.getCategoriaColor().withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color:
                          _selectedProduct!.getCategoriaColor().withAlpha(50)),
                ),
                child: Row(
                  children: [
                    Icon(_selectedProduct!.getCategoriaIcon(),
                        color: _selectedProduct!.getCategoriaColor()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedProduct!.getCategoriaLabel(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: _selectedProduct!.getCategoriaColor(),
                            ),
                          ),
                          Text(
                            'Preço: ${_selectedProduct!.formatarPreco()} / ${_selectedProduct!.unidade}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            if (_selectedProduct != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isTerceirizado
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isTerceirizado
                        ? Colors.orange
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.factory_outlined,
                      size: 18,
                      color: _isTerceirizado
                          ? Colors.orange
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Execução do item',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Uso interno — não aparece no impresso',
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Interna'),
                          icon: Icon(Icons.home_repair_service, size: 15),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Terceirização'),
                          icon: Icon(Icons.local_shipping_outlined, size: 15),
                        ),
                      ],
                      selected: {_isTerceirizado},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _isTerceirizado = selection.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_isAreaProduct && !_isCorteLaser) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Largura (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _length = _parseDecimal(v),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Altura (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _width = _parseDecimal(v),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],

            if (!_isCorteLaser)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _quantity = int.tryParse(v) ?? 1,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _productObservationController,
                        decoration: const InputDecoration(
                          labelText: 'Obs. do item',
                          hintText: 'Ex: Especificações, cores, etc...',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectedProduct != null && !_isCorteLaser
                          ? _addItem
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F62AC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Adicionar',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),

            if (_isCorteLaser && _selectedProduct != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepOrange.withAlpha(50)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Produto Corte a Laser - Preencha a composição abaixo',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEÇÃO: COMPOSITOR
  // ============================================================

  Widget _buildCompositorSection() {
    final NumberFormat moeda =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Card(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.deepOrange.shade300, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CABEÇALHO
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cut, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'COMPOSITOR CORTE A LASER',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.deepOrange,
                        ),
                      ),
                      Text(
                        'Calcule materiais, máquina e serviços',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (_retalhos.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_retalhos.length} retalhos disponíveis',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.deepOrange),
                  onPressed: _fecharCompositor,
                ),
              ],
            ),
            const Divider(height: 16),

            // ÁREA
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.square_foot, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'DIMENSÕES (para materiais em m²)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _larguraController,
                          decoration: const InputDecoration(
                            labelText: 'Largura (mm)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _calcularArea(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '×',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _alturaController,
                          decoration: const InputDecoration(
                            labelText: 'Altura (mm)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _calcularArea(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ÁREA TOTAL',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              _areaTotal > 0
                                  ? '${_areaTotal.toStringAsFixed(2)} m²'
                                  : '0,00 m²',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // MATERIAIS
            Row(
              children: [
                const Icon(Icons.inventory, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Materiais',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  'Clique no ícone para aproveitar retalhos',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            ..._materiaisSelecionados.asMap().entries.map((entry) {
              return _buildMaterialRow(entry.key);
            }),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _adicionarLinhaMaterial,
                icon: const Icon(Icons.add, size: 18),
                label: const SizedBox.shrink(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // TOTAL MATERIAIS
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL MATERIAIS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blue,
                    ),
                  ),
                  Text(
                    moeda.format(_valorMaterial),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // MÁQUINA
            const Text(
              'Máquina',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildSearchSelectionField(
                    label: 'Máquina',
                    hint: 'Digite ou selecione a máquina',
                    value: _selectedMaquina?.nome,
                    icon: Icons.precision_manufacturing,
                    onTap: () async {
                      final selected = await _showSearchPicker<MaquinaModel>(
                        title: 'Selecionar máquina',
                        hint: 'Digite nome, tipo, modelo ou fabricante',
                        items: _maquinas,
                        labelBuilder: (item) => item.nome,
                        subtitleBuilder: (item) =>
                            '${item.tipo}  •  ${item.modelo}  •  ${item.fabricante}',
                        searchTextBuilder: (item) =>
                            '${item.nome} ${item.tipo} ${item.modelo} ${item.fabricante}',
                      );
                      if (selected != null && mounted) {
                        setState(() {
                          _selectedMaquina = selected;
                          _calcularComposicao();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _tempoMaquinaController,
                    decoration: const InputDecoration(
                      labelText: 'Tempo (min)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _calcularComposicao(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Valor Máquina',
                            style:
                                TextStyle(fontSize: 9, color: Colors.orange)),
                        Text(
                          moeda.format(_valorMaquina),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // OUTROS
            const Text(
              'Outros custos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _outrosDescricaoController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _outrosController,
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _calcularComposicao(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // OBSERVAÇÕES
            TextField(
              controller: _observacoesCompositorController,
              decoration: const InputDecoration(
                labelText: 'Observações da Composição',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // TOTAL GERAL
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL DA COMPOSIÇÃO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    moeda.format(_totalComposicao),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // BOTÕES
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _fecharCompositor,
                    icon: const Icon(Icons.clear),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _totalComposicao > 0 && _areaTotal > 0
                        ? _adicionarComposicao
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Adicionar ao Pedido'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEÇÃO: LISTA DE ITENS
  // ============================================================

  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return const Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text('Adicione produtos ao pedido',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt, color: Color(0xFF0F62AC), size: 18),
                const SizedBox(width: 8),
                const Text('Lista de Itens',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_items.length} item(ns)',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0F62AC),
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('Produto',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11))),
                  Expanded(
                      flex: 1,
                      child: Text('Qtd',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 1,
                      child: Text('Total',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11),
                          textAlign: TextAlign.right)),
                  SizedBox(width: 40),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final isLaser = item['isCorteLaser'] ?? false;

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          if (isLaser)
                            const Icon(Icons.cut,
                                color: Colors.deepOrange, size: 12),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['product'],
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item['terceirizado'] == true)
                                  const Text(
                                    'TERCEIRIZAÇÃO • USO INTERNO',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (item['specs'] != null &&
                                    item['specs'].toString().isNotEmpty)
                                  Text(
                                    '${item['specs']}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.orange),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (isLaser) ...[
                                  Text(
                                    '${item['largura'] ?? 0} x ${item['altura'] ?? 0} mm = ${item['area']?.toStringAsFixed(2) ?? 0} m²',
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.blue),
                                  ),
                                  Text(
                                    'Materiais:\n${item['materiais'] ?? 'N/A'}',
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.grey),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Máquina: ${item['maquina'] ?? 'N/A'}',
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.grey),
                                  ),
                                  if ((item['outrosDescricao'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text(
                                      'Outros: ${item['outrosDescricao']} (${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item['valorOutros'] ?? 0)})',
                                      style: const TextStyle(
                                          fontSize: 9, color: Colors.grey),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('${item['quantity']}',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                            .format(item['total']),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF0F62AC)),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 18),
                      onPressed: () => _removeItem(idx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEÇÃO: OBSERVAÇÕES
  // ============================================================

  Widget _buildObservationsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.note, color: Color(0xFF0F62AC), size: 18),
                SizedBox(width: 8),
                Text('Observações Gerais',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const Divider(height: 12),
            TextField(
              controller: _observationsController,
              decoration: const InputDecoration(
                hintText: 'Ex: Trocar os painéis, Painel quebrado...',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEÇÃO: AÇÕES E TOTAIS
  // ============================================================

  Widget _buildActionsSection() {
    final discount = TextField(
      controller: _discountController,
      decoration: InputDecoration(
        labelText: 'Desconto (%)',
        prefixIcon: const Icon(Icons.percent, size: 18),
        border: const OutlineInputBorder(),
        isDense: true,
        suffixText: 'Max: ${_maxDiscount.toStringAsFixed(0)}%',
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        suffixStyle: const TextStyle(fontSize: 9),
      ),
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 12),
      onChanged: (_) => setState(() {}),
    );
    final otherValues = TextField(
      controller: _otherValuesController,
      decoration: const InputDecoration(
        labelText: 'Outros valores',
        prefixIcon: Icon(Icons.add_circle_outline, size: 18),
        prefixText: 'R\$ ',
        helperText: 'Frete, instalação ou ajuste adicional',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12),
      onChanged: (_) => setState(() {}),
    );
    final subtotal = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Subtotal',
              style: TextStyle(fontSize: 9, color: Colors.grey)),
          Text(
            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                .format(_subtotal),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF0F62AC),
            ),
          ),
        ],
      ),
    );
    final total = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F62AC), Color(0xFF4589FF)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          _paymentSummaryLine('TOTAL', _total, prominent: true),
          const SizedBox(height: 6),
          _paymentSummaryLine('Outros valores', _otherValues),
          _paymentSummaryLine('Desconto', _discountValue),
          _paymentSummaryLine('Entrada informada', _entryValue),
          _paymentSummaryLine('Restante após entrada', _total - _entryValue),
        ],
      ),
    );
    final saveButton = ElevatedButton.icon(
      onPressed: _isSaving || _items.isEmpty ? null : _saveOrder,
      icon: _isSaving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.save, size: 16),
      label: Text(_isSaving ? 'Salvando...' : 'Salvar'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
    final clearButton = OutlinedButton.icon(
      onPressed: _items.isEmpty ? null : () => setState(() => _items.clear()),
      icon: const Icon(Icons.clear_all, size: 16),
      label: const Text('Limpar'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.summarize, color: Color(0xFF0F62AC), size: 18),
                SizedBox(width: 8),
                Text(
                  'Resumo e Finaliza\u00e7\u00e3o',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const Divider(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 460
                  ? Column(
                      children: [
                        discount,
                        const SizedBox(height: 8),
                        otherValues,
                        const SizedBox(height: 8),
                        subtotal,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: discount),
                        const SizedBox(width: 8),
                        Expanded(child: otherValues),
                        const SizedBox(width: 8),
                        Expanded(child: subtotal),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 520
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        total,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: saveButton),
                            const SizedBox(width: 8),
                            Expanded(child: clearButton),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 2, child: total),
                        const SizedBox(width: 8),
                        Expanded(child: saveButton),
                        const SizedBox(width: 6),
                        Expanded(child: clearButton),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentSummaryLine(String label, double value,
      {bool prominent = false}) {
    final style = TextStyle(
      color: Colors.white,
      fontSize: prominent ? 14 : 12,
      fontWeight: prominent ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: prominent ? 0 : 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Text(
              NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                  .format(value),
              textAlign: TextAlign.end,
              style: style),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final typeSelector = Container(
          width: compact ? 190 : 160,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _tipoDocumento,
              isExpanded: true,
              isDense: true,
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.white,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              selectedItemBuilder: (context) => const [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('OS', style: TextStyle(color: Colors.white)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'OR\u00c7AMENTO',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
              items: const [
                DropdownMenuItem(value: 'OS', child: Text('OS')),
                DropdownMenuItem(
                  value: 'ORCAMENTO',
                  child: Text('OR\u00c7AMENTO'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _tipoDocumento = value);
              },
            ),
          ),
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 10 : 12,
          ),
          color: const Color(0xFF0F62AC),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.request_quote, color: Colors.white),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nova Venda / Or\u00e7amento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: typeSelector,
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(Icons.request_quote, color: Colors.white),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Nova Venda / Or\u00e7amento',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    typeSelector,
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 850;
                      final customerColumn = Column(
                        children: [
                          _buildCustomerSection(),
                          const SizedBox(height: 12),
                          _buildOrderStatusSection(),
                        ],
                      );
                      final productColumn = Column(
                        children: [
                          _buildProductSection(),
                          const SizedBox(height: 12),
                          if (_mostrarCompositor) ...[
                            _buildCompositorSection(),
                            const SizedBox(height: 12),
                          ],
                          _buildItemsList(),
                          const SizedBox(height: 12),
                          // O pagamento pertence ao pedido já conferido, por
                          // isso fica logo abaixo da relação de itens.
                          _buildPaymentSection(),
                          const SizedBox(height: 12),
                          _buildObservationsSection(),
                        ],
                      );
                      final actions = _buildActionsSection();

                      return SingleChildScrollView(
                        padding: EdgeInsets.all(compact ? 10 : 12),
                        child: compact
                            ? Column(
                                children: [
                                  customerColumn,
                                  const SizedBox(height: 12),
                                  productColumn,
                                  const SizedBox(height: 12),
                                  actions,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      children: [
                                        customerColumn,
                                        const SizedBox(height: 12),
                                        actions,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 3, child: productColumn),
                                ],
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
