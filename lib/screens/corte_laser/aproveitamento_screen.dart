// lib/screens/corte_laser/aproveitamento_screen.dart

import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/retalho_model.dart';
import '../../models/material_model.dart';
import '../../services/retalho_repository.dart';
import '../../services/material_repository.dart';

class AproveitamentoScreen extends StatefulWidget {
  const AproveitamentoScreen({super.key});

  @override
  State<AproveitamentoScreen> createState() => _AproveitamentoScreenState();
}

class _AproveitamentoScreenState extends State<AproveitamentoScreen>
    with BackgroundRefreshMixin<AproveitamentoScreen> {
  final RetalhoRepository _retalhoRepo = RetalhoRepository();
  final MaterialRepository _materialRepo = MaterialRepository();

  List<RetalhoModel> _retalhos = [];
  List<MaterialModel> _materiais = [];
  final List<Map<String, dynamic>> _sugestoes = [];
  bool _isLoading = true;
  double _areaNecessaria = 0;
  String _materialSelecionado = 'todos';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Future<void> refreshInBackground() => _loadData();

  Future<void> _loadData() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      _retalhos = await _retalhoRepo.getDisponiveis();
      _materiais = await _materialRepo.getAll();
      _gerarSugestoes();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erro ao carregar dados: $e');
    }
  }

  void _gerarSugestoes() {
    _sugestoes.clear();

    if (_areaNecessaria <= 0) return;

    // Filtrar materiais
    var retalhosFiltrados = _retalhos;
    if (_materialSelecionado != 'todos') {
      retalhosFiltrados = _retalhos.where((r) {
        final material = _materiais.firstWhere(
          (m) => m.id == r.materialId,
          orElse: () => MaterialModel(
            nome: 'Material não encontrado',
            codigo: 'N/A',
            tipo: 'm2',
            categoria: 'outros',
          ),
        );
        return material.categoria == _materialSelecionado;
      }).toList();
    }

    // Encontrar retalhos que atendem à área necessária
    for (var retalho in retalhosFiltrados) {
      if (retalho.area >= _areaNecessaria) {
        final sobra = retalho.area - _areaNecessaria;
        final material = _materiais.firstWhere(
          (m) => m.id == retalho.materialId,
          orElse: () => MaterialModel(
            nome: 'Material não encontrado',
            codigo: 'N/A',
            tipo: 'm2',
            categoria: 'outros',
          ),
        );

        _sugestoes.add({
          'retalho': retalho,
          'material': material.nome,
          'area': retalho.area,
          'sobra': sobra,
          'aproveitamento': ((_areaNecessaria / retalho.area) * 100),
          'valorEconomizado':
              retalho.valorEstimado * (_areaNecessaria / retalho.area),
        });
      }
    }

    // Ordenar por melhor aproveitamento
    _sugestoes
        .sort((a, b) => b['aproveitamento'].compareTo(a['aproveitamento']));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Aproveitamento de Retalhos'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // FILTROS
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Área Necessária (m²)',
                              prefixIcon: Icon(Icons.square_foot),
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              _areaNecessaria = double.tryParse(v) ?? 0;
                              _gerarSugestoes();
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _materialSelecionado,
                            decoration: const InputDecoration(
                              labelText: 'Material',
                              prefixIcon: Icon(Icons.category),
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: 'todos', child: Text('Todos')),
                              ...MaterialModel.getCategorias().map((cat) {
                                return DropdownMenuItem(
                                  value: cat,
                                  child:
                                      Text(MaterialModel.getCategoriaNome(cat)),
                                );
                              }),
                            ],
                            onChanged: (v) {
                              _materialSelecionado = v!;
                              _gerarSugestoes();
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_areaNecessaria > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: Colors.blue, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Buscando retalhos com área ≥ ${_areaNecessaria.toStringAsFixed(3)} m²',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.blue),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // RESULTADOS
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _areaNecessaria <= 0
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text(
                                'Informe a área necessária',
                                style:
                                    TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'O sistema irá buscar retalhos compatíveis',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                        )
                      : _sugestoes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.warning,
                                      size: 56, color: Colors.orange.shade300),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Nenhum retalho encontrado',
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Não há retalhos disponíveis com área ≥ ${_areaNecessaria.toStringAsFixed(3)} m²',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF999999)),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _sugestoes.length,
                              itemBuilder: (context, index) {
                                final sugestao = _sugestoes[index];
                                final retalho =
                                    sugestao['retalho'] as RetalhoModel;
                                final aproveitamento =
                                    sugestao['aproveitamento'] as double;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: aproveitamento > 80
                                          ? Colors.green
                                          : aproveitamento > 50
                                              ? Colors.orange
                                              : Colors.red,
                                      width: 2,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 36,
                                                    height: 36,
                                                    decoration: BoxDecoration(
                                                      color: aproveitamento > 80
                                                          ? Colors.green
                                                              .withValues(
                                                                  alpha: 0.1)
                                                          : aproveitamento > 50
                                                              ? Colors.orange
                                                                  .withValues(
                                                                      alpha:
                                                                          0.1)
                                                              : Colors.red
                                                                  .withValues(
                                                                      alpha:
                                                                          0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Icon(
                                                      Icons.recycling,
                                                      color: aproveitamento > 80
                                                          ? Colors.green
                                                          : aproveitamento > 50
                                                              ? Colors.orange
                                                              : Colors.red,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          retalho.nome,
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                        Text(
                                                          'Código: ${retalho.codigo}',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 10,
                                                            color: Color(
                                                                0xFF666666),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: aproveitamento > 80
                                                    ? Colors.green
                                                        .withValues(alpha: 0.1)
                                                    : aproveitamento > 50
                                                        ? Colors.orange
                                                            .withValues(
                                                                alpha: 0.1)
                                                        : Colors.red.withValues(
                                                            alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${aproveitamento.toStringAsFixed(0)}%',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: aproveitamento > 80
                                                      ? Colors.green
                                                      : aproveitamento > 50
                                                          ? Colors.orange
                                                          : Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildInfoItem(
                                                'Dimensão',
                                                retalho.getDimensaoString(),
                                              ),
                                            ),
                                            Expanded(
                                              child: _buildInfoItem(
                                                'Área',
                                                '${retalho.area.toStringAsFixed(3)} m²',
                                              ),
                                            ),
                                            Expanded(
                                              child: _buildInfoItem(
                                                'Material',
                                                sugestao['material'] ?? 'N/A',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildInfoItem(
                                                'Valor Estimado',
                                                'R\$ ${retalho.valorEstimado.toStringAsFixed(2)}',
                                                isHighlight: true,
                                              ),
                                            ),
                                            Expanded(
                                              child: _buildInfoItem(
                                                'Economia',
                                                'R\$ ${sugestao['valorEconomizado'].toStringAsFixed(2)}',
                                                isHighlight: true,
                                              ),
                                            ),
                                            Expanded(
                                              child: _buildInfoItem(
                                                'Local',
                                                retalho.localizacao.isNotEmpty
                                                    ? '${retalho.localizacao} - ${retalho.prateleira}'
                                                    : 'Não informado',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Spacer(),
                                            ElevatedButton.icon(
                                              onPressed: () {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Retalho selecionado!'),
                                                    backgroundColor:
                                                        Colors.green,
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.check,
                                                  size: 14),
                                              label: const Text('Selecionar'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF0F62AC),
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6),
                                                textStyle: const TextStyle(
                                                    fontSize: 11),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value,
      {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlight ? 12 : 10,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: isHighlight
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
