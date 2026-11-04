import 'package:xml/xml.dart';
import '../models/financial_model.dart';
import '../models/product_model.dart';
import '../models/insumo_model.dart';
import '../models/supplier_model.dart';
import '../services/financial_repository.dart';
import '../services/product_repository.dart';
import '../services/insumo_repository.dart';
import '../services/supplier_repository.dart';

class XmlImportService {
  final FinancialRepository _financialRepo = FinancialRepository();
  final ProductRepository _productRepo = ProductRepository();
  final InsumoRepository _insumoRepo = InsumoRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();

  // PALAVRAS-CHAVE PARA IDENTIFICAR INSUMOS (MATÉRIA-PRIMA)
  static const List<String> _insumoKeywords = [
    'rolo',
    'lona',
    'adesivo',
    'tinta',
    'verniz',
    'solvente',
    'filme',
    'placa',
    'pvc',
    'acrílico',
    'poliéster',
    'nylon',
    'tecido',
    'couro',
    'espuma',
    'madeira',
    'mdf',
    'compensado',
    'cartolina',
    'papel',
    'couché',
    'offset',
    'perfurado',
    'vinil',
    'frontlight',
    'blockout',
    'backlight',
    'transparente',
    'metálico',
    'pintura',
    'cola',
    'fita',
    'velcro',
    'ímã',
    'metal',
    'alumínio',
    'aço',
    'inox',
    'cobre',
    'latão',
    'chapa',
    'bobina',
    'resma',
    'grama',
    'kg',
    'litro',
    'galão',
    'balde',
  ];

  // CATEGORIAS DE INSUMOS
  static const Map<String, String> _insumoCategorias = {
    'rolo': 'materiais',
    'lona': 'materiais',
    'adesivo': 'adesivos',
    'tinta': 'tintas',
    'verniz': 'tintas',
    'solvente': 'tintas',
    'filme': 'materiais',
    'placa': 'materiais',
    'pvc': 'materiais',
    'acrílico': 'materiais',
    'papel': 'papelaria',
    'cartolina': 'papelaria',
    'couché': 'papelaria',
    'offset': 'papelaria',
    'vinil': 'adesivos',
    'frontlight': 'materiais',
    'blockout': 'materiais',
    'perfurado': 'adesivos',
    'tecido': 'costura',
    'couro': 'costura',
    'chapa': 'materiais',
    'bobina': 'materiais',
    'resma': 'papelaria',
    'fita': 'materiais',
    'cola': 'materiais',
    'metal': 'materiais',
    'alumínio': 'materiais',
  };

  // ==================== DETECÇÃO DE TIPO ====================

  /// Detecta o tipo do XML (NF-e ou NFS-e)
  String _detectarTipoXml(String xmlContent) {
    try {
      final document = XmlDocument.parse(xmlContent);

      if (document.findAllElements('nfeProc').isNotEmpty ||
          document.findAllElements('NFe').isNotEmpty) {
        return 'nfe';
      }

      if (document.findAllElements('NFSe').isNotEmpty ||
          document.findAllElements('infNFSe').isNotEmpty) {
        return 'nfse';
      }

      if (document.findAllElements('infDPS').isNotEmpty) {
        return 'nfse';
      }

      return 'desconhecido';
    } catch (e) {
      return 'desconhecido';
    }
  }

  /// Verifica se o item é um insumo
  bool _isInsumo(String nome) {
    final nomeLower = nome.toLowerCase();
    for (var keyword in _insumoKeywords) {
      if (nomeLower.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// Identifica a categoria do insumo
  String _identificarCategoria(String nome) {
    final nomeLower = nome.toLowerCase();
    for (var entry in _insumoCategorias.entries) {
      if (nomeLower.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'materiais';
  }

  /// Identifica a unidade do insumo
  String _identificarUnidade(String nome, String unidadeOriginal) {
    final nomeLower = nome.toLowerCase();
    if (nomeLower.contains('kg') || nomeLower.contains('quilo')) return 'kg';
    if (nomeLower.contains('litro') || nomeLower.contains('l')) return 'L';
    if (nomeLower.contains('metro') || nomeLower.contains('m²')) return 'm²';
    if (nomeLower.contains('rolo')) return 'rolo';
    if (nomeLower.contains('chapa')) return 'chapa';
    if (nomeLower.contains('resma')) return 'resma';
    if (nomeLower.contains('bobina')) return 'bobina';
    return unidadeOriginal.isNotEmpty ? unidadeOriginal : 'un';
  }

  // ==================== ANÁLISE DO XML ====================

  /// Analisa o XML e retorna os dados sem importar
  Future<Map<String, dynamic>> analisarXml(String xmlContent) async {
    final tipo = _detectarTipoXml(xmlContent);

    switch (tipo) {
      case 'nfe':
        return _analisarNFe(xmlContent);
      case 'nfse':
        return _analisarNFSe(xmlContent);
      default:
        throw Exception('Tipo de XML não reconhecido.');
    }
  }

  // ==================== IMPORTAÇÃO PRINCIPAL ====================

  /// Importa o XML com opções de escolha do usuário
  Future<Map<String, dynamic>> importarXmlComOpcoes(
    String xmlContent, {
    required bool importarProdutos,
    required bool importarInsumos,
    required bool importarFornecedor,
  }) async {
    final tipo = _detectarTipoXml(xmlContent);

    switch (tipo) {
      case 'nfe':
        return _importarNFeComOpcoes(
            xmlContent, importarProdutos, importarInsumos, importarFornecedor);
      case 'nfse':
        return _importarNFSeComOpcoes(
            xmlContent, importarProdutos, importarInsumos, importarFornecedor);
      default:
        throw Exception('Tipo de XML não reconhecido.');
    }
  }

  /// Importa XML automaticamente (sem perguntas)
  Future<Map<String, dynamic>> importarXml(String xmlContent) async {
    return importarXmlComOpcoes(
      xmlContent,
      importarProdutos: true,
      importarInsumos: true,
      importarFornecedor: true,
    );
  }

  // ==================== ANÁLISE NF-e ====================

  Future<Map<String, dynamic>> _analisarNFe(String xmlContent) async {
    try {
      final document = XmlDocument.parse(xmlContent);
      final infNFe = document.findAllElements('infNFe').first;
      final emit = infNFe.findAllElements('emit').first;
      final dest = infNFe.findAllElements('dest').first;
      final total = infNFe.findAllElements('total').first;
      final icmsTot = total.findAllElements('ICMSTot').first;

      final fornecedor = emit.findAllElements('xNome').first.innerText;
      final cnpj = emit.findAllElements('CNPJ').first.innerText;

      String clienteNome = '';
      try {
        clienteNome = dest.findAllElements('xNome').first.innerText;
      } catch (e) {}

      final vNF =
          double.tryParse(icmsTot.findAllElements('vNF').first.innerText) ??
              0.0;

      String numero = '';
      try {
        numero = infNFe.findAllElements('nNF').first.innerText;
      } catch (e) {}

      final produtos = <Map<String, dynamic>>[];
      final insumos = <Map<String, dynamic>>[];

      final dets = infNFe.findAllElements('det');

      for (var det in dets) {
        final prod = det.findAllElements('prod').first;
        final xProd = prod.findAllElements('xProd').first.innerText;
        final qCom =
            double.tryParse(prod.findAllElements('qCom').first.innerText) ??
                0.0;
        final vUnCom =
            double.tryParse(prod.findAllElements('vUnCom').first.innerText) ??
                0.0;
        final cProd = prod.findAllElements('cProd').first.innerText;
        final uCom = prod.findAllElements('uCom').first.innerText;

        final item = {
          'nome': xProd,
          'codigo': cProd,
          'quantidade': qCom,
          'valor_unitario': vUnCom,
          'unidade': uCom,
        };

        if (_isInsumo(xProd)) {
          item['categoria'] = _identificarCategoria(xProd);
          item['unidade'] = _identificarUnidade(xProd, uCom);
          insumos.add(item);
        } else {
          produtos.add(item);
        }
      }

      return <String, dynamic>{
        'tipo': 'NF-e',
        'fornecedor': fornecedor,
        'cnpj': cnpj,
        'numero': numero,
        'valor': vNF,
        'cliente': clienteNome,
        'produtos': produtos,
        'insumos': insumos,
        'total_produtos': produtos.length,
        'total_insumos': insumos.length,
        'total_itens': produtos.length + insumos.length,
        'temInsumos': insumos.isNotEmpty,
      };
    } catch (e) {
      throw Exception('Erro ao analisar NF-e: $e');
    }
  }

  // ==================== ANÁLISE NFS-e ====================

  Future<Map<String, dynamic>> _analisarNFSe(String xmlContent) async {
    try {
      final document = XmlDocument.parse(xmlContent);

      XmlElement? infNFSe;
      XmlElement? infDPS;

      try {
        infNFSe = document.findAllElements('infNFSe').first;
      } catch (e) {}

      try {
        infDPS = document.findAllElements('infDPS').first;
      } catch (e) {}

      if (infNFSe == null && infDPS == null) {
        throw Exception('Estrutura NFS-e não reconhecida');
      }

      String fornecedor = '';
      String cnpj = '';
      String ie = '';
      String enderecoFornecedor = '';
      String telefoneFornecedor = '';
      String emailFornecedor = '';

      String clienteNome = '';
      String clienteCpf = '';
      String clienteEndereco = '';
      String clienteCep = '';
      String clienteCidade = '';
      String clienteUf = '';

      double valor = 0.0;
      double valorIssqn = 0.0;
      double aliquota = 0.0;
      String numero = '';
      String descricaoServico = '';
      String infoComplementar = '';
      String dataEmissao = '';
      String dataCompetencia = '';
      String serie = '';
      String nDPS = '';

      // ==================== EXTRAIR DO infNFSe ====================
      if (infNFSe != null) {
        try {
          numero = infNFSe.findAllElements('nNFSe').first.innerText;
        } catch (e) {}

        try {
          final emit = infNFSe.findAllElements('emit').first;
          fornecedor = emit.findAllElements('xNome').first.innerText;
          cnpj = emit.findAllElements('CNPJ').first.innerText;

          try {
            ie = emit.findAllElements('IM').first.innerText;
          } catch (e) {}

          try {
            final enderNac = emit.findAllElements('enderNac').first;
            final xLgr = enderNac.findAllElements('xLgr').first.innerText;
            final nro = enderNac.findAllElements('nro').first.innerText;
            final xBairro = enderNac.findAllElements('xBairro').first.innerText;
            final cMun = enderNac.findAllElements('cMun').first.innerText;
            final uf = enderNac.findAllElements('UF').first.innerText;
            final cep = enderNac.findAllElements('CEP').first.innerText;
            enderecoFornecedor =
                '$xLgr, $nro - $xBairro - $cMun/$uf - CEP: $cep';
          } catch (e) {}

          try {
            emailFornecedor = emit.findAllElements('email').first.innerText;
          } catch (e) {}
        } catch (e) {}

        try {
          final valores = infNFSe.findAllElements('valores').first;
          final vBCStr = valores.findAllElements('vBC').first.innerText;
          valor = double.tryParse(vBCStr.replaceAll(',', '.')) ?? 0.0;

          final vISSQNStr = valores.findAllElements('vISSQN').first.innerText;
          valorIssqn = double.tryParse(vISSQNStr.replaceAll(',', '.')) ?? 0.0;

          final pAliqStr =
              valores.findAllElements('pAliqAplic').first.innerText;
          aliquota = double.tryParse(pAliqStr.replaceAll(',', '.')) ?? 0.0;
        } catch (e) {}

        try {
          final xTribNac = infNFSe.findAllElements('xTribNac').first.innerText;
          if (descricaoServico.isEmpty) {
            descricaoServico = xTribNac;
          }
        } catch (e) {}
      }

      // ==================== EXTRAIR DO infDPS ====================
      if (infDPS != null) {
        try {
          dataEmissao = infDPS.findAllElements('dhEmi').first.innerText;
        } catch (e) {}

        try {
          dataCompetencia = infDPS.findAllElements('dCompet').first.innerText;
        } catch (e) {}

        try {
          serie = infDPS.findAllElements('serie').first.innerText;
        } catch (e) {}

        try {
          nDPS = infDPS.findAllElements('nDPS').first.innerText;
        } catch (e) {}

        // TOMADOR (Cliente)
        try {
          final toma = infDPS.findAllElements('toma').first;
          clienteNome = toma.findAllElements('xNome').first.innerText;

          try {
            clienteCpf = toma.findAllElements('CPF').first.innerText;
          } catch (e) {}

          try {
            final end = toma.findAllElements('end').first;
            final xLgr = end.findAllElements('xLgr').first.innerText;
            final nro = end.findAllElements('nro').first.innerText;
            final xBairro = end.findAllElements('xBairro').first.innerText;

            try {
              final endNac = end.findAllElements('endNac').first;
              clienteCep = endNac.findAllElements('CEP').first.innerText;
              clienteCidade = endNac.findAllElements('cMun').first.innerText;
            } catch (e) {}

            clienteEndereco = '$xLgr, $nro - $xBairro';
          } catch (e) {}
        } catch (e) {}

        // SERVIÇO
        try {
          final serv = infDPS.findAllElements('serv').first;

          try {
            final cServ = serv.findAllElements('cServ').first;
            descricaoServico =
                cServ.findAllElements('xDescServ').first.innerText;
          } catch (e) {}

          try {
            final infoCompl = serv.findAllElements('infoCompl').first;
            infoComplementar =
                infoCompl.findAllElements('xInfComp').first.innerText;
          } catch (e) {}
        } catch (e) {}

        // VALORES
        try {
          final valores = infDPS.findAllElements('valores').first;
          final vServ = valores.findAllElements('vServPrest').first;
          final vServStr = vServ.findAllElements('vServ').first.innerText;
          valor = double.tryParse(vServStr.replaceAll(',', '.')) ?? valor;
        } catch (e) {}
      }

      // Se ainda não tem fornecedor, tentar no prest
      if (fornecedor.isEmpty && infDPS != null) {
        try {
          final prest = infDPS.findAllElements('prest').first;
          cnpj = prest.findAllElements('CNPJ').first.innerText;
          fornecedor = prest.findAllElements('xNome').first.innerText;
          emailFornecedor = prest.findAllElements('email').first.innerText;
        } catch (e) {}
      }

      // ==================== FORMATAR ITENS ====================
      final produtos = <Map<String, dynamic>>[];
      final insumos = <Map<String, dynamic>>[];

      final descricaoCompleta = infoComplementar.isNotEmpty
          ? infoComplementar.replaceAll('\\', '')
          : descricaoServico;

      if (descricaoCompleta.isNotEmpty) {
        final isInsumo = _isInsumo(descricaoCompleta);
        final categoria =
            isInsumo ? _identificarCategoria(descricaoCompleta) : null;
        final unidade =
            isInsumo ? _identificarUnidade(descricaoCompleta, 'un') : 'un';

        final item = {
          'nome': descricaoCompleta.length > 80
              ? descricaoCompleta.substring(0, 80)
              : descricaoCompleta,
          'codigo':
              'NFS-${numero.isEmpty ? DateTime.now().millisecondsSinceEpoch : numero}',
          'quantidade': 1.0,
          'valor_unitario': valor,
          'unidade': unidade,
          'categoria': categoria,
        };

        if (isInsumo) {
          insumos.add(item);
        } else {
          produtos.add(item);
        }
      }

      return <String, dynamic>{
        'tipo': 'NFS-e',
        'fornecedor': fornecedor,
        'cnpj': cnpj,
        'ie': ie,
        'endereco_fornecedor': enderecoFornecedor,
        'telefone_fornecedor': telefoneFornecedor,
        'email_fornecedor': emailFornecedor,
        'numero': numero,
        'serie': serie,
        'nDPS': nDPS,
        'valor': valor,
        'valor_issqn': valorIssqn,
        'aliquota': aliquota,
        'cliente': clienteNome,
        'cliente_cpf': clienteCpf,
        'cliente_endereco': clienteEndereco,
        'cliente_cep': clienteCep,
        'cliente_cidade': clienteCidade,
        'cliente_uf': clienteUf,
        'descricao_servico': descricaoServico,
        'info_complementar': infoComplementar.replaceAll('\\', ''),
        'data_emissao': dataEmissao,
        'data_competencia': dataCompetencia,
        'produtos': produtos,
        'insumos': insumos,
        'total_produtos': produtos.length,
        'total_insumos': insumos.length,
        'total_itens': produtos.length + insumos.length,
        'temInsumos': insumos.isNotEmpty,
      };
    } catch (e) {
      throw Exception('Erro ao analisar NFS-e: $e');
    }
  }

  // ==================== IMPORTAÇÃO NF-e COM OPÇÕES ====================

  Future<Map<String, dynamic>> _importarNFeComOpcoes(
    String xmlContent,
    bool importarProdutos,
    bool importarInsumos,
    bool importarFornecedor,
  ) async {
    try {
      final dados = await _analisarNFe(xmlContent);

      int produtosImportados = 0;
      int insumosImportados = 0;

      // IMPORTAR FORNECEDOR
      if (importarFornecedor && dados['fornecedor'].isNotEmpty) {
        await _importarFornecedor(
          dados['fornecedor'],
          dados['cnpj'],
        );
      }

      // IMPORTAR INSUMOS (MATÉRIA-PRIMA)
      if (importarInsumos && dados['insumos'].isNotEmpty) {
        for (var item in dados['insumos']) {
          try {
            final importado = await _importarInsumo(
              nome: item['nome'],
              codigo: item['codigo'],
              quantidade: item['quantidade'] ?? 0,
              valorUnitario: item['valor_unitario'] ?? 0,
              categoria: item['categoria'] ?? 'materiais',
              unidade: item['unidade'] ?? 'un',
              fornecedor: dados['fornecedor'] ?? '',
              numeroNota: dados['numero'] ?? '',
            );
            if (importado) insumosImportados++;
          } catch (e) {
            print('Erro ao importar insumo: $e');
          }
        }
      }

      // IMPORTAR PRODUTOS (PRODUTOS ACABADOS)
      if (importarProdutos && dados['produtos'].isNotEmpty) {
        for (var item in dados['produtos']) {
          try {
            final importado = await _importarProduto(
              nome: item['nome'],
              codigo: item['codigo'],
              valorUnitario: item['valor_unitario'] ?? 0,
              unidade: item['unidade'] ?? 'un',
            );
            if (importado) produtosImportados++;
          } catch (e) {
            print('Erro ao importar produto: $e');
          }
        }
      }

      // CRIAR CONTA A PAGAR
      final financial = FinancialModel(
        description: 'NF-e ${dados['numero']} - ${dados['fornecedor']}',
        amount: dados['valor'] ?? 0,
        type: 'pagar',
        dueDate: DateTime.now().add(const Duration(days: 30)),
        isPaid: false,
        notes:
            'NF-e importada\nFornecedor: ${dados['fornecedor']}\nCNPJ: ${dados['cnpj']}\n'
            'Insumos: $insumosImportados\nProdutos: $produtosImportados',
        categoria: 'materiais',
        formaPagamento: 'Boleto',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _financialRepo.create(financial);

      return {
        'sucesso': true,
        'tipo': 'NF-e',
        'fornecedor': dados['fornecedor'],
        'cnpj': dados['cnpj'],
        'valor': dados['valor'],
        'numero': dados['numero'],
        'produtos': produtosImportados,
        'insumos': insumosImportados,
        'total_itens': produtosImportados + insumosImportados,
        'mensagem':
            'NF-e importada com sucesso!\n$insumosImportados insumos e $produtosImportados produtos importados',
      };
    } catch (e) {
      throw Exception('Erro ao importar NF-e: $e');
    }
  }

  // ==================== IMPORTAÇÃO NFS-e COM OPÇÕES ====================

  Future<Map<String, dynamic>> _importarNFSeComOpcoes(
    String xmlContent,
    bool importarProdutos,
    bool importarInsumos,
    bool importarFornecedor,
  ) async {
    try {
      final dados = await _analisarNFSe(xmlContent);

      int produtosImportados = 0;
      int insumosImportados = 0;

      // IMPORTAR FORNECEDOR
      if (importarFornecedor && dados['fornecedor'].isNotEmpty) {
        await _importarFornecedor(
          dados['fornecedor'],
          dados['cnpj'],
          endereco: dados['endereco_fornecedor'],
          email: dados['email_fornecedor'],
        );
      }

      // IMPORTAR INSUMOS
      if (importarInsumos && dados['insumos'].isNotEmpty) {
        for (var item in dados['insumos']) {
          try {
            final importado = await _importarInsumo(
              nome: item['nome'],
              codigo: item['codigo'],
              quantidade: item['quantidade'] ?? 0,
              valorUnitario: item['valor_unitario'] ?? 0,
              categoria: item['categoria'] ?? 'materiais',
              unidade: item['unidade'] ?? 'un',
              fornecedor: dados['fornecedor'] ?? '',
              numeroNota: dados['numero'] ?? '',
            );
            if (importado) insumosImportados++;
          } catch (e) {
            print('Erro ao importar insumo: $e');
          }
        }
      }

      // IMPORTAR PRODUTOS
      if (importarProdutos && dados['produtos'].isNotEmpty) {
        for (var item in dados['produtos']) {
          try {
            final importado = await _importarProduto(
              nome: item['nome'],
              codigo: item['codigo'],
              valorUnitario: item['valor_unitario'] ?? 0,
              unidade: item['unidade'] ?? 'un',
            );
            if (importado) produtosImportados++;
          } catch (e) {
            print('Erro ao importar produto: $e');
          }
        }
      }

      // CRIAR CONTA A PAGAR
      final valorFinal = dados['valor'] is int
          ? (dados['valor'] as int).toDouble()
          : dados['valor'].toDouble();

      String descricao = 'NFS-e ${dados['numero']} - ${dados['fornecedor']}';
      if (dados['info_complementar'].isNotEmpty) {
        final info = dados['info_complementar'].toString();
        descricao =
            'NFS-e ${dados['numero']} - ${info.length > 50 ? info.substring(0, 50) : info}';
      }

      final financial = FinancialModel(
        description: descricao,
        amount: valorFinal,
        type: 'pagar',
        dueDate: DateTime.now().add(const Duration(days: 30)),
        isPaid: false,
        notes:
            'NFS-e importada\nFornecedor: ${dados['fornecedor']}\nCNPJ: ${dados['cnpj']}\n'
            'Insumos: $insumosImportados\nProdutos: $produtosImportados\n'
            'Cliente: ${dados['cliente']}\nDescrição: ${dados['descricao_servico']}',
        categoria: 'terceirizacao',
        formaPagamento: 'Boleto',
        customerName: dados['cliente'] ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _financialRepo.create(financial);

      return {
        'sucesso': true,
        'tipo': 'NFS-e',
        'fornecedor': dados['fornecedor'],
        'cnpj': dados['cnpj'],
        'valor': valorFinal,
        'numero': dados['numero'],
        'produtos': produtosImportados,
        'insumos': insumosImportados,
        'total_itens': produtosImportados + insumosImportados,
        'cliente': dados['cliente'],
        'mensagem':
            'NFS-e importada com sucesso!\n$insumosImportados insumos e $produtosImportados produtos importados',
      };
    } catch (e) {
      throw Exception('Erro ao importar NFS-e: $e');
    }
  }

  // ==================== UTILITÁRIOS ====================

  /// IMPORTAR INSUMO (MATÉRIA-PRIMA)
  Future<bool> _importarInsumo({
    required String nome,
    required String codigo,
    required double quantidade,
    required double valorUnitario,
    required String categoria,
    required String unidade,
    required String fornecedor,
    required String numeroNota,
  }) async {
    try {
      final existing = await _insumoRepo.search(nome);

      if (existing.isNotEmpty) {
        final insumo = existing.first;
        final newQuantity = insumo.quantidade + quantidade;
        final updated = insumo.copyWith(
          quantidade: newQuantity,
          precoUnitario:
              valorUnitario > 0 ? valorUnitario : insumo.precoUnitario,
          fornecedor: fornecedor.isNotEmpty ? fornecedor : insumo.fornecedor,
          observacoes: insumo.observacoes.isNotEmpty
              ? '${insumo.observacoes}\n+ $quantidade $unidade - NF-e $numeroNota'
              : 'Importado da NF-e $numeroNota - $quantidade $unidade',
        );
        await _insumoRepo.update(updated);
        return true;
      } else {
        final insumo = InsumoModel(
          codigo: codigo.isNotEmpty
              ? codigo
              : 'INS-${DateTime.now().millisecondsSinceEpoch}',
          nome: nome.length > 80 ? nome.substring(0, 80) : nome,
          categoria: categoria.isNotEmpty ? categoria : 'materiais',
          quantidade: quantidade,
          unidade: unidade.isNotEmpty ? unidade : 'un',
          precoUnitario: valorUnitario,
          fornecedor: fornecedor,
          estoqueMinimo: 0,
          estoqueMaximo: 0,
          observacoes: 'Importado da NF-e $numeroNota',
        );
        await _insumoRepo.create(insumo);
        return true;
      }
    } catch (e) {
      print('Erro ao importar insumo: $e');
      return false;
    }
  }

  /// IMPORTAR PRODUTO (PRODUTO ACABADO)
  Future<bool> _importarProduto({
    required String nome,
    required String codigo,
    required double valorUnitario,
    required String unidade,
  }) async {
    try {
      final existing = await _productRepo.search(codigo);

      if (existing.isNotEmpty) {
        // ProductModel não possui copyWith; o produto já existente é mantido.
        return true;
      } else {
        final product = ProductModel(
          codigo: codigo.isNotEmpty
              ? codigo
              : 'PRD-${DateTime.now().millisecondsSinceEpoch}',
          nome: nome.length > 80 ? nome.substring(0, 80) : nome,
          preco: valorUnitario * 1.3,
          cost: valorUnitario,
          estoque: 0,
          categoria: 'outros',
          descricao: 'Importado da NF-e',
          unidade: unidade.isNotEmpty ? unidade : 'un',
        );
        await _productRepo.insert(product);
        return true;
      }
    } catch (e) {
      print('Erro ao importar produto: $e');
      return false;
    }
  }

  /// IMPORTAR FORNECEDOR
  Future<void> _importarFornecedor(
    String nome,
    String cnpj, {
    String? endereco,
    String? email,
  }) async {
    try {
      final existing = await _supplierRepo.search(nome);
      if (existing.isNotEmpty) return;

      final supplier = SupplierModel.create(
        name: nome,
        document: cnpj,
        address: endereco ?? '',
        email: email ?? '',
        product: 'Importado da NF-e',
        active: true,
      );
      await _supplierRepo.create(supplier);
    } catch (e) {
      print('Erro ao importar fornecedor: $e');
    }
  }

  // ==================== MÉTODO DE TESTE ====================

  /// Testa o XML e retorna o tipo detectado
  String testarXml(String xmlContent) {
    try {
      final tipo = _detectarTipoXml(xmlContent);
      return 'Tipo detectado: $tipo';
    } catch (e) {
      return 'Erro ao analisar XML: $e';
    }
  }
}
