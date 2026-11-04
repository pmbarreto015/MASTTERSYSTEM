// lib/services/composicao_repository.dart

import 'package:sqflite/sqflite.dart';
import '../models/composicao_model.dart';
import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';

class ComposicaoRepository {
  final AppDatabase _db = AppDatabase();

  // ============================================================
  // CRUD BÁSICO
  // ============================================================

  /// Buscar todas as composições
  Future<List<ComposicaoModel>> getAll() async {
    final database = await _db.database;
    final result = await database.query(
      'composicoes',
      orderBy: 'created_at DESC',
    );
    final composicoes = <ComposicaoModel>[];
    for (var map in result) {
      final composicao = await _fromMapCompleto(map);
      composicoes.add(composicao);
    }
    return composicoes;
  }

  /// Buscar composição por ID
  Future<ComposicaoModel?> getById(int id) async {
    final database = await _db.database;
    final result = await database.query(
      'composicoes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return await _fromMapCompleto(result.first);
  }

  /// NOVO: Buscar composição por produto
  Future<ComposicaoModel?> getByProduto(int produtoId) async {
    final database = await _db.database;
    final result = await database.query(
      'composicoes',
      where: 'produto_id = ?',
      whereArgs: [produtoId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return await _fromMapCompleto(result.first);
  }

  /// Buscar composições por pedido
  Future<List<ComposicaoModel>> getByPedido(int pedidoId) async {
    final database = await _db.database;
    final result = await database.query(
      'composicoes',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
      orderBy: 'created_at DESC',
    );
    final composicoes = <ComposicaoModel>[];
    for (var map in result) {
      final composicao = await _fromMapCompleto(map);
      composicoes.add(composicao);
    }
    return composicoes;
  }

  /// Buscar composições por orçamento
  Future<List<ComposicaoModel>> getByOrcamento(int orcamentoId) async {
    final database = await _db.database;
    final result = await database.query(
      'composicoes',
      where: 'orcamento_id = ?',
      whereArgs: [orcamentoId],
      orderBy: 'created_at DESC',
    );
    final composicoes = <ComposicaoModel>[];
    for (var map in result) {
      final composicao = await _fromMapCompleto(map);
      composicoes.add(composicao);
    }
    return composicoes;
  }

  // ============================================================
  // CRIAR / ATUALIZAR / DELETAR
  // ============================================================

  /// Criar nova composição
  Future<ComposicaoModel> create(ComposicaoModel composicao) async {
    final database = await _db.database;

    // Recalcular totais
    composicao.recalcularTotais();
    composicao.calcularPrecoVenda();

    // Salvar cabeçalho
    final map = _toMap(composicao);
    map.remove('id');
    if (database is SupabaseDatabase) {
      final id = await database.rpc('matterdi_composition_save', {
        'p_id': null,
        'p_header': map,
        'p_items': _cloudItems(composicao),
      });
      return composicao.copyWith(id: (id as num).toInt());
    }
    final id = await database.insert('composicoes', map);

    // Salvar itens
    for (var item in composicao.materiais) {
      await _salvarItem(database, id, item, 'material');
    }
    for (var item in composicao.maquinas) {
      await _salvarItem(database, id, item, 'maquina');
    }
    for (var item in composicao.servicos) {
      await _salvarItem(database, id, item, 'servico');
    }

    final created = await getById(id);
    return created!;
  }

  /// Atualizar composição
  Future<ComposicaoModel> update(ComposicaoModel composicao) async {
    final database = await _db.database;

    // Recalcular totais
    composicao.recalcularTotais();
    composicao.calcularPrecoVenda();

    // Atualizar cabeçalho
    final map = _toMap(composicao);
    map.remove('id');
    if (database is SupabaseDatabase) {
      if (composicao.id == null) {
        throw ArgumentError('Composição sem identificador.');
      }
      final id = await database.rpc('matterdi_composition_save', {
        'p_id': composicao.id,
        'p_header': map,
        'p_items': _cloudItems(composicao),
      });
      return composicao.copyWith(id: (id as num).toInt());
    }
    await database.update(
      'composicoes',
      map,
      where: 'id = ?',
      whereArgs: [composicao.id],
    );

    // Remover itens antigos
    await database.delete(
      'composicao_itens',
      where: 'composicao_id = ?',
      whereArgs: [composicao.id],
    );

    // Salvar novos itens
    for (var item in composicao.materiais) {
      await _salvarItem(database, composicao.id!, item, 'material');
    }
    for (var item in composicao.maquinas) {
      await _salvarItem(database, composicao.id!, item, 'maquina');
    }
    for (var item in composicao.servicos) {
      await _salvarItem(database, composicao.id!, item, 'servico');
    }

    final updated = await getById(composicao.id!);
    return updated!;
  }

  /// Deletar composição
  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'composicoes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // MÉTODOS AUXILIARES
  // ============================================================

  /// Converter ComposicaoModel para Map
  Map<String, dynamic> _toMap(ComposicaoModel composicao) {
    return {
      'pedido_id': composicao.pedidoId,
      'orcamento_id': composicao.orcamentoId,
      'produto_id': composicao.produtoId, // NOVO
      'custo_total_materiais': composicao.custoTotalMateriais,
      'custo_total_maquinas': composicao.custoTotalMaquinas,
      'custo_total_servicos': composicao.custoTotalServicos,
      'custo_total': composicao.custoTotal,
      'margem_lucro': composicao.margemLucro,
      'preco_venda': composicao.precoVenda,
      'observacoes': composicao.observacoes,
      'created_at': composicao.dataCriacao,
      'updated_at': composicao.dataAtualizacao,
    };
  }

  List<Map<String, dynamic>> _cloudItems(ComposicaoModel composicao) {
    Map<String, dynamic> itemMap(ComposicaoItem item, String tipo) => {
          'tipo': tipo,
          'descricao': item.descricao,
          'quantidade': item.quantidade,
          'unidade': item.unidade,
          'valor_unitario': item.valorUnitario,
          'valor_total': item.valorTotal,
          'observacoes': item.observacoes,
          'item_id': item.itemId,
          'item_original_id': item.itemOriginalId,
          'created_at': DateTime.now().toIso8601String(),
        };

    return [
      ...composicao.materiais.map((item) => itemMap(item, 'material')),
      ...composicao.maquinas.map((item) => itemMap(item, 'maquina')),
      ...composicao.servicos.map((item) => itemMap(item, 'servico')),
    ];
  }

  /// Converter Map para ComposicaoModel completo
  Future<ComposicaoModel> _fromMapCompleto(Map<String, dynamic> map) async {
    final database = await _db.database;

    // Buscar itens
    final itemsResult = await database.query(
      'composicao_itens',
      where: 'composicao_id = ?',
      whereArgs: [map['id']],
    );

    final materiais = <ComposicaoItem>[];
    final maquinas = <ComposicaoItem>[];
    final servicos = <ComposicaoItem>[];

    for (var item in itemsResult) {
      final tipo = item['tipo'] as String;
      final composicaoItem = ComposicaoItem.fromMap(item);

      switch (tipo) {
        case 'material':
          materiais.add(composicaoItem);
          break;
        case 'maquina':
          maquinas.add(composicaoItem);
          break;
        case 'servico':
          servicos.add(composicaoItem);
          break;
      }
    }

    return ComposicaoModel(
      id: map['id'],
      pedidoId: map['pedido_id'],
      orcamentoId: map['orcamento_id'],
      produtoId: map['produto_id'], // NOVO
      materiais: materiais,
      maquinas: maquinas,
      servicos: servicos,
      custoTotalMateriais: (map['custo_total_materiais'] ?? 0).toDouble(),
      custoTotalMaquinas: (map['custo_total_maquinas'] ?? 0).toDouble(),
      custoTotalServicos: (map['custo_total_servicos'] ?? 0).toDouble(),
      custoTotal: (map['custo_total'] ?? 0).toDouble(),
      margemLucro: (map['margem_lucro'] ?? 0).toDouble(),
      precoVenda: (map['preco_venda'] ?? 0).toDouble(),
      observacoes: map['observacoes'] ?? '',
      dataCriacao: map['created_at'],
      dataAtualizacao: map['updated_at'],
    );
  }

  /// Salvar item da composição
  Future<void> _salvarItem(
      Database db, int composicaoId, ComposicaoItem item, String tipo) async {
    await db.insert('composicao_itens', {
      'composicao_id': composicaoId,
      'tipo': tipo,
      'descricao': item.descricao,
      'quantidade': item.quantidade,
      'unidade': item.unidade,
      'valor_unitario': item.valorUnitario,
      'valor_total': item.valorTotal,
      'observacoes': item.observacoes,
      'item_id': item.itemId,
      'item_original_id': item.itemOriginalId,
    });
  }

  // ============================================================
  // ESTATÍSTICAS
  // ============================================================

  /// Total de composições
  Future<int> getTotal() async {
    final database = await _db.database;
    final result =
        await database.rawQuery('SELECT COUNT(*) as total FROM composicoes');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Média de margem de lucro
  Future<double> getMargemMedia() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT AVG(margem_lucro) as media
      FROM composicoes
    ''');
    return (result.first['media'] as num?)?.toDouble() ?? 0;
  }

  /// Custo total de todas as composições
  Future<double> getCustoTotal() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT SUM(custo_total) as total
      FROM composicoes
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Valor total de venda de todas as composições
  Future<double> getVendaTotal() async {
    final database = await _db.database;
    final result = await database.rawQuery('''
      SELECT SUM(preco_venda) as total
      FROM composicoes
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
}
