// lib/screens/corte_laser/maquinas_screen.dart

import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/maquina_model.dart';
import '../../services/maquina_repository.dart';

class MaquinasScreen extends StatefulWidget {
  const MaquinasScreen({super.key});

  @override
  State<MaquinasScreen> createState() => _MaquinasScreenState();
}

class _MaquinasScreenState extends State<MaquinasScreen>
    with BackgroundRefreshMixin<MaquinasScreen> {
  final MaquinaRepository _repository = MaquinaRepository();

  List<MaquinaModel> _maquinas = [];
  List<MaquinaModel> _filteredMaquinas = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMaquinas();
  }

  @override
  Future<void> refreshInBackground() => _loadMaquinas();

  Future<void> _loadMaquinas() async {
    if (!mounted) return;
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      final maquinas = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _maquinas = maquinas;
        _applyMaquinaFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro ao carregar máquinas: $e');
    }
  }

  void _filterMaquinas() {
    setState(_applyMaquinaFilters);
  }

  void _applyMaquinaFilters() {
    _filteredMaquinas = _maquinas.where((m) {
      return _searchQuery.isEmpty ||
          m.nome.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.modelo.toLowerCase().contains(_searchQuery.toLowerCase());
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

  // DIALOG DE CADASTRO/EDIÇÃO DE MÁQUINA
  void _showMaquinaDialog({MaquinaModel? maquina}) {
    final isEdit = maquina != null;
    final formKey = GlobalKey<FormState>();

    final nomeController = TextEditingController(text: maquina?.nome ?? '');
    final modeloController = TextEditingController(text: maquina?.modelo ?? '');
    final fabricanteController =
        TextEditingController(text: maquina?.fabricante ?? '');
    final observacoesController =
        TextEditingController(text: maquina?.observacoes ?? '');

    final larguraController = TextEditingController(
      text: maquina?.areaUtilLargura.toString() ?? '',
    );
    final alturaController = TextEditingController(
      text: maquina?.areaUtilAltura.toString() ?? '',
    );
    final energiaController = TextEditingController(
      text: maquina?.custoEnergiaHora.toString() ?? '',
    );
    final manutencaoController = TextEditingController(
      text: maquina?.custoManutencaoHora.toString() ?? '',
    );
    final depreciacaoController = TextEditingController(
      text: maquina?.custoDepreciacaoHora.toString() ?? '',
    );
    final operadorController = TextEditingController(
      text: maquina?.custoOperadorHora.toString() ?? '',
    );
    final outrosController = TextEditingController(
      text: maquina?.custoOutrosHora.toString() ?? '',
    );

    var selectedTipo = maquina?.tipo ?? 'laser';
    bool isActive = maquina?.active ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final energia = double.tryParse(energiaController.text) ?? 0;
          final manutencao = double.tryParse(manutencaoController.text) ?? 0;
          final depreciacao = double.tryParse(depreciacaoController.text) ?? 0;
          final operador = double.tryParse(operadorController.text) ?? 0;
          final outros = double.tryParse(outrosController.text) ?? 0;

          final totalHora =
              energia + manutencao + depreciacao + operador + outros;
          final totalMinuto = totalHora / 60;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
                    isEdit ? Icons.edit : Icons.precision_manufacturing,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Editar Máquina' : 'Nova Máquina',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: SizedBox(
                  width: 600,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // NOME E TIPO
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: nomeController,
                              decoration: const InputDecoration(
                                labelText: 'Nome da Máquina *',
                                prefixIcon: Icon(Icons.precision_manufacturing),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) =>
                                  v!.isEmpty ? 'Obrigatório' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedTipo,
                              decoration: const InputDecoration(
                                labelText: 'Tipo *',
                                prefixIcon: Icon(Icons.category),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: MaquinaModel.getTipos().map((tipo) {
                                return DropdownMenuItem<String>(
                                  value: tipo,
                                  child: Text(MaquinaModel.getTipoNome(tipo)),
                                );
                              }).toList(),
                              onChanged: (v) => selectedTipo = v!,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // MODELO E FABRICANTE
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: modeloController,
                              decoration: const InputDecoration(
                                labelText: 'Modelo',
                                prefixIcon: Icon(Icons.model_training),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: fabricanteController,
                              decoration: const InputDecoration(
                                labelText: 'Fabricante',
                                prefixIcon: Icon(Icons.factory),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ÁREA ÚTIL
                      const Text(
                        'Área Útil',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F62AC),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: larguraController,
                              decoration: const InputDecoration(
                                labelText: 'Largura (mm)',
                                prefixIcon: Icon(Icons.width_wide),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: alturaController,
                              decoration: const InputDecoration(
                                labelText: 'Altura (mm)',
                                prefixIcon: Icon(Icons.height),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // CUSTOS
                      const Text(
                        'Custos por Hora',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F62AC),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: energiaController,
                              decoration: const InputDecoration(
                                labelText: 'Energia (R\$)',
                                prefixIcon: Icon(Icons.bolt),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: manutencaoController,
                              decoration: const InputDecoration(
                                labelText: 'Manutenção (R\$)',
                                prefixIcon: Icon(Icons.build),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: depreciacaoController,
                              decoration: const InputDecoration(
                                labelText: 'Depreciação (R\$)',
                                prefixIcon: Icon(Icons.trending_down),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: operadorController,
                              decoration: const InputDecoration(
                                labelText: 'Operador (R\$)',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: outrosController,
                              decoration: const InputDecoration(
                                labelText: 'Outros (R\$)',
                                prefixIcon: Icon(Icons.more_horiz),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F62AC)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF0F62AC)
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    'R\$ ${totalHora.toStringAsFixed(2)}/h',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F62AC),
                                    ),
                                  ),
                                  Text(
                                    'R\$ ${totalMinuto.toStringAsFixed(2)}/min',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // OBSERVAÇÕES E STATUS
                      TextFormField(
                        controller: observacoesController,
                        decoration: const InputDecoration(
                          labelText: 'Observações',
                          prefixIcon: Icon(Icons.description),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: (v) => isActive = v,
                            activeThumbColor: const Color(0xFF0F62AC),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isActive ? 'Ativa' : 'Inativa',
                            style: TextStyle(
                              color: isActive ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
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
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final maquinaData = MaquinaModel(
                      id: isEdit ? maquina.id : null,
                      nome: nomeController.text.trim(),
                      tipo: selectedTipo,
                      modelo: modeloController.text.trim(),
                      fabricante: fabricanteController.text.trim(),
                      areaUtilLargura:
                          double.tryParse(larguraController.text) ?? 0,
                      areaUtilAltura:
                          double.tryParse(alturaController.text) ?? 0,
                      custoEnergiaHora:
                          double.tryParse(energiaController.text) ?? 0,
                      custoManutencaoHora:
                          double.tryParse(manutencaoController.text) ?? 0,
                      custoDepreciacaoHora:
                          double.tryParse(depreciacaoController.text) ?? 0,
                      custoOperadorHora:
                          double.tryParse(operadorController.text) ?? 0,
                      custoOutrosHora:
                          double.tryParse(outrosController.text) ?? 0,
                      observacoes: observacoesController.text.trim(),
                      active: isActive,
                    );
                    maquinaData.recalcularCustos();

                    if (isEdit) {
                      await _repository.update(maquinaData);
                      _showSuccess('Máquina atualizada!');
                    } else {
                      await _repository.create(maquinaData);
                      _showSuccess('Máquina criada!');
                    }
                    Navigator.pop(context);
                    _loadMaquinas();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F62AC),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(isEdit ? 'Atualizar' : 'Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  // DELETAR MÁQUINA
  Future<void> _deleteMaquina(MaquinaModel maquina) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Excluir "${maquina.nome}"?'),
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
      await _repository.delete(maquina.id!);
      _loadMaquinas();
      _showSuccess('Máquina excluída!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Máquinas para Corte a Laser'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showMaquinaDialog(),
            tooltip: 'Nova Máquina',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMaquinas,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // BARRA DE PESQUISA
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar máquina por nome ou modelo...',
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
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _filterMaquinas();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showMaquinaDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F62AC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // LISTA DE MÁQUINAS
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMaquinas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.precision_manufacturing,
                                size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhuma máquina cadastrada'
                                  : 'Nenhuma máquina encontrada',
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            if (_searchQuery.isEmpty)
                              ElevatedButton.icon(
                                onPressed: () => _showMaquinaDialog(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar Máquina'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F62AC),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMaquinas,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredMaquinas.length,
                          itemBuilder: (context, index) {
                            final maquina = _filteredMaquinas[index];
                            final totalMinuto =
                                maquina.calcularCustoTotalMinuto();

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: maquina.active
                                      ? const Color(0xFFE0E0E0)
                                      : Colors.red.shade300,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: maquina.active
                                        ? const Color(0xFF0F62AC)
                                            .withValues(alpha: 0.1)
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.precision_manufacturing,
                                    color: maquina.active
                                        ? const Color(0xFF0F62AC)
                                        : Colors.grey,
                                  ),
                                ),
                                title: Text(
                                  maquina.nome,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: maquina.active
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${maquina.modelo} | ${maquina.fabricante}',
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
                                            color: Colors.green
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            MaquinaModel.getTipoNome(
                                                maquina.tipo),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.green),
                                          ),
                                        ),
                                        if (maquina.areaUtil > 0)
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
                                              '${maquina.areaUtil.toStringAsFixed(2)} m²',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue),
                                            ),
                                          ),
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
                                            'R\$ ${totalMinuto.toStringAsFixed(2)}/min',
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
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 18, color: Colors.grey),
                                      onPressed: () =>
                                          _showMaquinaDialog(maquina: maquina),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      onPressed: () => _deleteMaquina(maquina),
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
