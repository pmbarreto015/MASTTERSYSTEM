import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../models/stock_movement_model.dart';
import '../../services/stock_repository.dart';

class StockMovementScreen extends StatefulWidget {
  const StockMovementScreen({super.key, this.productId});

  final int? productId;

  @override
  State<StockMovementScreen> createState() => _StockMovementScreenState();
}

class _StockMovementScreenState extends State<StockMovementScreen>
    with BackgroundRefreshMixin<StockMovementScreen> {
  final StockRepository _repository = StockRepository();
  List<StockMovementModel> _movements = [];
  bool _isLoading = true;
  String _filterType = 'todos';
  String _searchQuery = '';

  final List<String> _tipos = [
    'todos',
    'entrada',
    'saida',
    'ajuste',
    'compra',
    'venda'
  ];

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  @override
  Future<void> refreshInBackground() => _loadMovements();

  Future<void> _loadMovements() async {
    if (!isRefreshingInBackground) setState(() => _isLoading = true);
    try {
      List<StockMovementModel> movements;
      if (widget.productId != null) {
        movements = await _repository.getMovementsByProduct(widget.productId!);
      } else {
        movements = await _repository.getAllMovements();
      }
      setState(() {
        _movements = movements;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Erro ao carregar movimentações: $e');
    }
  }

  List<StockMovementModel> get _filteredMovements {
    return _movements.where((m) {
      if (_filterType != 'todos' && m.type != _filterType) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return m.productName.toLowerCase().contains(query) ||
            m.reason.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.productId != null
              ? 'Histórico do Produto'
              : 'Movimentações de Estoque',
        ),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMovements,
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            // Filtros
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar produto ou motivo...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onChanged: (v) {
                        _searchQuery = v;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      initialValue: _filterType,
                      decoration: InputDecoration(
                        labelText: 'Tipo',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      items: _tipos.map((t) {
                        final label = t == 'todos' ? 'Todos' : _getTypeLabel(t);
                        return DropdownMenuItem(
                          value: t,
                          child:
                              Text(label, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        _filterType = v!;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Resumo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _buildResumoCard(
                      'Total', _movements.length.toString(), Colors.blue),
                  const SizedBox(width: 8),
                  _buildResumoCard(
                    'Entradas',
                    _movements
                        .where((m) => m.type == 'entrada' || m.type == 'compra')
                        .length
                        .toString(),
                    Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildResumoCard(
                    'Saídas',
                    _movements
                        .where((m) => m.type == 'saida' || m.type == 'venda')
                        .length
                        .toString(),
                    Colors.red,
                  ),
                  const SizedBox(width: 8),
                  _buildResumoCard(
                    'Ajustes',
                    _movements
                        .where((m) => m.type == 'ajuste')
                        .length
                        .toString(),
                    Colors.orange,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Lista
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredMovements.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text(
                                'Nenhuma movimentação encontrada',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredMovements.length,
                          itemBuilder: (context, index) {
                            final m = _filteredMovements[index];
                            return _buildMovementCard(m);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementCard(StockMovementModel movement) {
    final isEntry = movement.type == 'entrada' || movement.type == 'compra';
    final isAdjust = movement.type == 'ajuste';
    final color = isEntry
        ? Colors.green
        : isAdjust
            ? Colors.orange
            : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isEntry
                        ? Icons.arrow_downward
                        : isAdjust
                            ? Icons.swap_vert
                            : Icons.arrow_upward,
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movement.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        movement.reason,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      movement.quantidadeFormatada,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                    Text(
                      movement.typeLabel,
                      style: TextStyle(
                        fontSize: 9,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Anterior: ${movement.previousStock.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.arrow_forward,
                  size: 12,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 16),
                Text(
                  'Novo: ${movement.newStock.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  movement.dataFormatada,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeLabel(String type) {
    final labels = {
      'entrada': 'Entrada',
      'saida': 'Saída',
      'ajuste': 'Ajuste',
      'compra': 'Compra',
      'venda': 'Venda',
    };
    return labels[type] ?? type;
  }
}
