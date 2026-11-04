// lib/screens/corte_laser/retalhos_screen.dart

import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/retalho_model.dart';
import '../../models/material_model.dart';
import '../../services/retalho_repository.dart';
import '../../services/material_repository.dart';

class RetalhosScreen extends StatefulWidget {
  const RetalhosScreen({super.key});

  @override
  State<RetalhosScreen> createState() => _RetalhosScreenState();
}

class _RetalhosScreenState extends State<RetalhosScreen>
    with BackgroundRefreshMixin<RetalhosScreen> {
  final RetalhoRepository _retalhoRepo = RetalhoRepository();
  final MaterialRepository _materialRepo = MaterialRepository();

  List<RetalhoModel> _retalhos = [];
  List<RetalhoModel> _filteredRetalhos = [];
  List<MaterialModel> _materiais = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'todos';
  final String _filterMaterial = 'todos';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Future<void> refreshInBackground() => _loadData();

  Future<void> _loadData() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final retalhos = await _retalhoRepo.getAll();
      final materiais = await _materialRepo.getAll();
      if (!mounted) return;
      setState(() {
        _retalhos = retalhos;
        _materiais = materiais;
        _applyRetalhoFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar retalhos: $e');
    }
  }

  void _filterRetalhos() {
    setState(_applyRetalhoFilters);
  }

  void _applyRetalhoFilters() {
    _filteredRetalhos = _retalhos.where((r) {
      final matchesSearch = _searchQuery.isEmpty ||
          r.nome.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.codigo.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus =
          _filterStatus == 'todos' || r.status == _filterStatus;
      final material = _materiais.firstWhere(
        (m) => m.id == r.materialId,
        orElse: () => MaterialModel(
          nome: 'Material não encontrado',
          codigo: 'N/A',
          tipo: 'm2',
          categoria: 'outros',
        ),
      );
      final matchesMaterial =
          _filterMaterial == 'todos' || material.categoria == _filterMaterial;
      return matchesSearch && matchesStatus && matchesMaterial;
    }).toList();
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

  // CRIAR RETALHO (usado ao finalizar produção)
  void _showCriarRetalhoDialog() {
    final formKey = GlobalKey<FormState>();
    final codigoController = TextEditingController();
    final nomeController = TextEditingController();
    final larguraController = TextEditingController();
    final alturaController = TextEditingController();
    final localizacaoController = TextEditingController();
    final prateleiraController = TextEditingController();
    final valorController = TextEditingController();

    MaterialModel? selectedMaterial;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.green, Color(0xFF42BE65)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.recycling, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Criar Retalho',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<MaterialModel>(
                    decoration: const InputDecoration(
                      labelText: 'Material *',
                      prefixIcon: Icon(Icons.inventory_2),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _materiais.map((m) {
                      return DropdownMenuItem<MaterialModel>(
                        value: m,
                        child: Text(m.nome),
                      );
                    }).toList(),
                    onChanged: (v) => selectedMaterial = v,
                    validator: (v) =>
                        v == null ? 'Selecione um material' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: codigoController,
                          decoration: const InputDecoration(
                            labelText: 'Código *',
                            prefixIcon: Icon(Icons.tag),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: nomeController,
                          decoration: const InputDecoration(
                            labelText: 'Nome *',
                            prefixIcon: Icon(Icons.inventory_2),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: larguraController,
                          decoration: const InputDecoration(
                            labelText: 'Largura (mm) *',
                            prefixIcon: Icon(Icons.width_wide),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Obrigatório';
                            if (double.tryParse(v) == null) {
                              return 'Número inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: alturaController,
                          decoration: const InputDecoration(
                            labelText: 'Altura (mm) *',
                            prefixIcon: Icon(Icons.height),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Obrigatório';
                            if (double.tryParse(v) == null) {
                              return 'Número inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: localizacaoController,
                          decoration: const InputDecoration(
                            labelText: 'Localização',
                            prefixIcon: Icon(Icons.location_on),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: prateleiraController,
                          decoration: const InputDecoration(
                            labelText: 'Prateleira',
                            prefixIcon: Icon(Icons.shelves),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: valorController,
                    decoration: const InputDecoration(
                      labelText: 'Valor Estimado (R\$)',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
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
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final largura = double.parse(larguraController.text);
                final altura = double.parse(alturaController.text);
                final area = (largura * altura) / 1000000;

                final retalho = RetalhoModel(
                  materialId: selectedMaterial!.id!,
                  codigo: codigoController.text,
                  nome: nomeController.text,
                  largura: largura,
                  altura: altura,
                  area: area,
                  localizacao: localizacaoController.text,
                  prateleira: prateleiraController.text,
                  valorEstimado: double.tryParse(valorController.text) ?? 0,
                  valorVenda: double.tryParse(valorController.text) ?? 0,
                  status: 'disponivel',
                );

                await _retalhoRepo.create(retalho);
                Navigator.pop(context);
                _loadData();
                _showSuccess('Retalho criado com sucesso!');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Criar Retalho'),
          ),
        ],
      ),
    );
  }

  // UTILIZAR RETALHO
  Future<void> _utilizarRetalho(RetalhoModel retalho) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Utilizar Retalho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja utilizar o retalho:'),
            const SizedBox(height: 8),
            Text(retalho.nome,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(retalho.getDimensaoString()),
            Text('${retalho.area.toStringAsFixed(3)} m²'),
            const SizedBox(height: 8),
            const Text('O retalho será marcado como "utilizado".'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Utilizar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = retalho.copyWith(status: 'utilizado');
      await _retalhoRepo.update(updated);
      _loadData();
      _showSuccess('Retalho utilizado!');
    }
  }

  // DESCARTAR RETALHO
  Future<void> _descartarRetalho(RetalhoModel retalho) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar Retalho'),
        content: Text('Deseja descartar o retalho "${retalho.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = retalho.copyWith(status: 'descartado');
      await _retalhoRepo.update(updated);
      _loadData();
      _showSuccess('Retalho descartado');
    }
  }

  // DELETAR RETALHO
  Future<void> _deleteRetalho(RetalhoModel retalho) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir retalho "${retalho.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _retalhoRepo.delete(retalho.id!);
      _loadData();
      _showSuccess('Retalho excluído!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Retalhos - Corte a Laser'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCriarRetalhoDialog,
            tooltip: 'Novo Retalho',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // FILTROS
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar retalho...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _filterRetalhos();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterStatus,
                      icon: const Icon(Icons.arrow_drop_down),
                      items: const [
                        DropdownMenuItem<String>(
                            value: 'todos', child: Text('Todos')),
                        DropdownMenuItem<String>(
                            value: 'disponivel', child: Text('Disponível')),
                        DropdownMenuItem<String>(
                            value: 'reservado', child: Text('Reservado')),
                        DropdownMenuItem<String>(
                            value: 'utilizado', child: Text('Utilizado')),
                        DropdownMenuItem<String>(
                            value: 'descartado', child: Text('Descartado')),
                      ],
                      onChanged: (v) {
                        _filterStatus = v!;
                        _filterRetalhos();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showCriarRetalhoDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // LISTA DE RETALHOS
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRetalhos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.recycling,
                                size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum retalho cadastrado'
                                  : 'Nenhum retalho encontrado',
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: _showCriarRetalhoDialog,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Criar Retalho'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredRetalhos.length,
                          itemBuilder: (context, index) {
                            final retalho = _filteredRetalhos[index];
                            final statusColor = retalho.getStatusColor();

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: statusColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.recycling,
                                    color: statusColor,
                                  ),
                                ),
                                title: Text(
                                  retalho.nome,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Código: ${retalho.codigo}',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            retalho.getDimensaoString(),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.blue),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${retalho.area.toStringAsFixed(3)} m²',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.green),
                                          ),
                                        ),
                                        if (retalho.valorEstimado > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'R\$ ${retalho.valorEstimado.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Status
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color:
                                            statusColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        retalho.getStatusNome(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: statusColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Ações
                                    if (retalho.status == 'disponivel')
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow,
                                            color: Colors.blue, size: 18),
                                        onPressed: () =>
                                            _utilizarRetalho(retalho),
                                        tooltip: 'Utilizar',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    if (retalho.status == 'disponivel' ||
                                        retalho.status == 'reservado')
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red, size: 18),
                                        onPressed: () =>
                                            _descartarRetalho(retalho),
                                        tooltip: 'Descartar',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red, size: 18),
                                      onPressed: () => _deleteRetalho(retalho),
                                      tooltip: 'Excluir',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
