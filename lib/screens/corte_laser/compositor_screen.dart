// lib/screens/corte_laser/compositor_screen.dart

import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/maquina_model.dart';
import '../../models/customer_model.dart';
import '../../models/composicao_model.dart';
import '../../services/maquina_repository.dart';
import '../../services/customer_repository.dart';
import '../../services/composicao_repository.dart';
import '../../services/product_repository.dart';

class CompositorScreen extends StatefulWidget {
  const CompositorScreen({
    super.key,
    this.produtoId,
    this.produtoNome,
    this.customer, // NOVO PARÂMETRO
  });

  final int? produtoId;
  final String? produtoNome;
  final CustomerModel? customer; // NOVO

  @override
  State<CompositorScreen> createState() => _CompositorScreenState();
}

class _CompositorScreenState extends State<CompositorScreen>
    with BackgroundRefreshMixin<CompositorScreen> {
  final MaquinaRepository _maquinaRepo = MaquinaRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final ComposicaoRepository _composicaoRepo = ComposicaoRepository();
  final ProductRepository _productRepo = ProductRepository();

  // Dados
  List<MaquinaModel> _maquinas = [];
  List<CustomerModel> _customers = [];

  // Seleções
  CustomerModel? _selectedCustomer;
  MaquinaModel? _selectedMaquina;

  // Dimensões
  double _tempoEstimado = 0;

  // Composição
  final List<Map<String, dynamic>> _materiaisSelecionados = [];
  final List<Map<String, dynamic>> _servicosSelecionados = [];

  // Totais
  double _custoTotalMateriais = 0;
  double _custoTotalMaquina = 0;
  double _custoTotalServicos = 0;
  double _custoTotal = 0;
  double _margemLucro = 40;
  double _precoVenda = 0;

  // Controladores
  final TextEditingController _tempoController = TextEditingController();
  final TextEditingController _margemController =
      TextEditingController(text: '40');
  final TextEditingController _observacoesController = TextEditingController();

  bool _isLoading = true;
  int? _composicaoId;

  @override
  void initState() {
    super.initState();

    // USA O CLIENTE RECEBIDO
    _selectedCustomer = widget.customer;

    _loadData();
    if (widget.produtoId != null) {
      _carregarComposicaoExistente();
    }
  }

  @override
  void dispose() {
    _tempoController.dispose();
    _margemController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshInBackground() => _loadData();

  Future<void> _loadData() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      _maquinas = await _maquinaRepo.getAll();
      _customers = await _customerRepo.getAll();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erro ao carregar dados: $e');
    }
  }

  // CARREGAR COMPOSIÇÃO EXISTENTE
  Future<void> _carregarComposicaoExistente() async {
    if (widget.produtoId == null) return;

    try {
      final composicao = await _composicaoRepo.getByProduto(widget.produtoId!);
      if (composicao != null) {
        setState(() {
          _composicaoId = composicao.id;

          for (var item in composicao.materiais) {
            _materiaisSelecionados.add({
              'tipo': 'material',
              'material': item.descricao,
              'materialId': item.itemOriginalId,
              'area': item.quantidade,
              'areaComPerda': item.quantidade,
              'custo': item.valorTotal,
              'quantidade': 1,
            });
          }

          for (var item in composicao.maquinas) {
            final maquina = _maquinas.firstWhere(
              (m) => m.id == item.itemOriginalId,
              orElse: () => MaquinaModel(
                nome: item.descricao,
                tipo: 'laser',
                modelo: '',
                fabricante: '',
              ),
            );
            _selectedMaquina = maquina;
            _tempoEstimado = item.quantidade;
            _tempoController.text = item.quantidade.toString();
          }

          for (var item in composicao.servicos) {
            _servicosSelecionados.add({
              'descricao': item.descricao,
              'custo': item.valorTotal,
            });
          }

          _margemLucro = composicao.margemLucro;
          _margemController.text = composicao.margemLucro.toString();
          _observacoesController.text = composicao.observacoes;

          _recalcularTotais();
        });
      }
    } catch (e) {
      print('Erro ao carregar composição: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  // ============================================================
  // CÁLCULO DE ÁREA
  // ============================================================
  // ============================================================
  // RECALCULAR TOTAIS
  // ============================================================
  void _recalcularTotais() {
    _custoTotalMateriais = _materiaisSelecionados.fold(
      0,
      (sum, item) => sum + (item['custo'] as double),
    );

    if (_selectedMaquina != null && _tempoEstimado > 0) {
      _custoTotalMaquina = _selectedMaquina!.custoTotalMinuto * _tempoEstimado;
    } else {
      _custoTotalMaquina = 0;
    }

    _custoTotalServicos = _servicosSelecionados.fold(
      0,
      (sum, item) => sum + (item['custo'] as double),
    );

    _custoTotal =
        _custoTotalMateriais + _custoTotalMaquina + _custoTotalServicos;

    if (_custoTotal > 0 && _margemLucro > 0) {
      _precoVenda = _custoTotal * (1 + _margemLucro / 100);
    } else {
      _precoVenda = _custoTotal;
    }

    setState(() {});
  }

  // ============================================================
  // ADICIONAR MATERIAL À COMPOSIÇÃO
  // ============================================================
  // ============================================================
  // ADICIONAR SERVIÇO
  // ============================================================
  // ============================================================
  // REMOVER MATERIAL DA COMPOSIÇÃO
  // ============================================================
  // ============================================================
  // SELECIONAR CLIENTE (caso não tenha vindo da tela)
  // ============================================================
  Future<void> _selectCustomer() async {
    if (_selectedCustomer != null) {
      // Já tem cliente, não precisa selecionar
      return;
    }

    if (_customers.isEmpty) {
      _showError('Nenhum cliente cadastrado');
      return;
    }

    final customer = await showDialog<CustomerModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecionar Cliente'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: _customers.length,
            itemBuilder: (context, index) {
              final c = _customers[index];
              return ListTile(
                title: Text(c.name),
                subtitle: Text(c.phone),
                onTap: () => Navigator.pop(context, c),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (customer != null) {
      setState(() => _selectedCustomer = customer);
    }
  }

  // ============================================================
  // SALVAR COMPOSIÇÃO
  // ============================================================
  Future<void> _salvarComposicao() async {
    // SE NÃO TIVER CLIENTE, PERMITE SELECIONAR
    if (_selectedCustomer == null) {
      await _selectCustomer();
      if (_selectedCustomer == null) {
        _showError('Selecione um cliente');
        return;
      }
    }

    if (_materiaisSelecionados.isEmpty) {
      _showError('Adicione pelo menos um material');
      return;
    }

    if (_custoTotal <= 0) {
      _showError('Calcule o custo total primeiro');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final materiaisItems = <ComposicaoItem>[];
      for (var item in _materiaisSelecionados) {
        materiaisItems.add(
          ComposicaoItem(
            tipo: 'material',
            descricao: item['material'] ?? '',
            quantidade: item['area'] ?? 0,
            unidade: 'm²',
            valorUnitario: (item['custo'] ?? 0) /
                ((item['area'] ?? 1) > 0 ? item['area'] : 1),
            valorTotal: item['custo'] ?? 0,
            itemId: item['materialId'],
            itemOriginalId: item['materialId'],
          ),
        );
      }

      final maquinasItems = <ComposicaoItem>[];
      if (_selectedMaquina != null && _tempoEstimado > 0) {
        maquinasItems.add(
          ComposicaoItem(
            tipo: 'maquina',
            descricao: _selectedMaquina!.nome,
            quantidade: _tempoEstimado,
            unidade: 'min',
            valorUnitario: _selectedMaquina!.custoTotalMinuto,
            valorTotal: _selectedMaquina!.custoTotalMinuto * _tempoEstimado,
            itemId: _selectedMaquina!.id,
            itemOriginalId: _selectedMaquina!.id,
          ),
        );
      }

      final servicosItems = <ComposicaoItem>[];
      for (var item in _servicosSelecionados) {
        servicosItems.add(
          ComposicaoItem(
            tipo: 'servico',
            descricao: item['descricao'] ?? '',
            quantidade: 1,
            unidade: 'un',
            valorUnitario: item['custo'] ?? 0,
            valorTotal: item['custo'] ?? 0,
          ),
        );
      }

      final composicao = ComposicaoModel(
        id: _composicaoId,
        produtoId: widget.produtoId,
        pedidoId: null,
        orcamentoId: null,
        materiais: materiaisItems,
        maquinas: maquinasItems,
        servicos: servicosItems,
        custoTotalMateriais: _custoTotalMateriais,
        custoTotalMaquinas: _custoTotalMaquina,
        custoTotalServicos: _custoTotalServicos,
        custoTotal: _custoTotal,
        margemLucro: _margemLucro,
        precoVenda: _precoVenda,
        observacoes: _observacoesController.text,
      );

      ComposicaoModel savedComposicao;

      if (_composicaoId != null) {
        savedComposicao = await _composicaoRepo.update(composicao);
        _showSuccess('Composição atualizada com sucesso!');
      } else {
        savedComposicao = await _composicaoRepo.create(composicao);
        _showSuccess('Composição salva com sucesso!');
      }

      setState(() {
        _composicaoId = savedComposicao.id;
        _isLoading = false;
      });

      if (widget.produtoId != null) {
        await _atualizarPrecoProduto(
            widget.produtoId!, savedComposicao.precoVenda);
      }

      Navigator.pop(context, {
        'composicaoId': savedComposicao.id,
        'custoTotal': _custoTotal,
        'precoVenda': _precoVenda,
        'margem': _margemLucro,
        'materiais': _materiaisSelecionados.length,
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erro ao salvar composição: $e');
    }
  }

  // ============================================================
  // ATUALIZAR PREÇO DO PRODUTO
  // ============================================================
  Future<void> _atualizarPrecoProduto(int produtoId, double preco) async {
    try {
      final product = await _productRepo.getById(produtoId);
      if (product != null) {
        final updatedProduct = product.copyWith(
          preco: preco,
          cost: _custoTotal,
        );
        await _productRepo.update(updatedProduct);
        print('Preço do produto atualizado: R\$ ${preco.toStringAsFixed(2)}');
      }
    } catch (e) {
      print('Erro ao atualizar preço do produto: $e');
    }
  }

  // ============================================================
  // WIDGETS
  // ============================================================

  Widget _buildMaterialSelector() {
    // ... (código existente)
    return Container();
  }

  Widget _buildMaquinaSelector() {
    // ... (código existente)
    return Container();
  }

  Widget _buildServicos() {
    // ... (código existente)
    return Container();
  }

  Widget _buildResumo() {
    // ... (código existente)
    return Container();
  }

  Widget _buildMateriaisSelecionados() {
    // ... (código existente)
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.produtoNome != null
              ? 'Compositor - ${widget.produtoNome}'
              : 'Compositor de Orçamento - Corte a Laser',
        ),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _salvarComposicao,
            tooltip: 'Salvar Composição',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        // Cliente
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person,
                                  color: Color(0xFF0F62AC)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedCustomer != null
                                      ? _selectedCustomer!.name
                                      : widget.customer != null
                                          ? widget.customer!.name
                                          : 'Nenhum cliente selecionado',
                                  style: TextStyle(
                                    color: _selectedCustomer != null ||
                                            widget.customer != null
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (_selectedCustomer == null &&
                                  widget.customer == null)
                                ElevatedButton(
                                  onPressed: _selectCustomer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F62AC),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    textStyle: const TextStyle(fontSize: 11),
                                  ),
                                  child: const Text('Selecionar'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Materiais
                        _buildMaterialSelector(),
                        const SizedBox(height: 12),

                        // Máquina
                        _buildMaquinaSelector(),
                        const SizedBox(height: 12),

                        // Serviços
                        _buildServicos(),
                        const SizedBox(height: 12),

                        // Materiais Selecionados
                        _buildMateriaisSelecionados(),
                        const SizedBox(height: 12),

                        // Observações
                        TextFormField(
                          controller: _observacoesController,
                          decoration: const InputDecoration(
                            labelText: 'Observações do Orçamento',
                            prefixIcon: Icon(Icons.description),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _buildResumo(),
                  ),
                ],
              ),
            ),
    );
  }
}
