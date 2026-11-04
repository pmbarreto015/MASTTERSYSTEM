import 'dart:io';
import 'package:excel/excel.dart' as excel;
import '../models/product_model.dart';
import '../services/product_repository.dart';

class CsvImportService {
  final ProductRepository _productRepo = ProductRepository();

  // ==================== DETECTAR FORMATO ====================
  String _detectarFormato(String caminho) {
    final extensao = caminho.split('.').last.toLowerCase();
    switch (extensao) {
      case 'csv':
        return 'csv';
      case 'xlsx':
        return 'xlsx';
      case 'xls':
        return 'xls';
      case 'pdf':
        return 'pdf';
      default:
        return 'desconhecido';
    }
  }

  // ==================== LER ARQUIVO ====================
  Future<List<Map<String, dynamic>>> lerArquivo(String caminho) async {
    final formato = _detectarFormato(caminho);

    switch (formato) {
      case 'csv':
        return await _lerCsv(caminho);
      case 'xlsx':
        return await _lerExcelXlsx(caminho);
      case 'xls':
        return await _lerXls(caminho);
      case 'pdf':
        return await _lerPdf(caminho);
      default:
        throw Exception('Formato não suportado. Use CSV, XLSX ou PDF.');
    }
  }

  // ==================== LER CSV ====================
  Future<List<Map<String, dynamic>>> _lerCsv(String caminho) async {
    try {
      final file = File(caminho);
      final content = await file.readAsString();

      String separador = ';';
      if (content.contains(',') && !content.contains(';')) {
        separador = ',';
      }

      final lines =
          content.split('\n').where((l) => l.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        throw Exception('Arquivo CSV vazio');
      }

      int headerIndex = -1;
      for (var i = 0; i < lines.length && i < 20; i++) {
        final linha = lines[i].toLowerCase();
        if (linha.contains('código') ||
            linha.contains('codigo') ||
            (linha.contains('descrição') && linha.contains('cores'))) {
          headerIndex = i;
          break;
        }
      }

      if (headerIndex == -1) {
        headerIndex = 0;
      }

      final headerLine = lines[headerIndex];
      final headers = headerLine
          .split(separador)
          .map((h) => h.trim().toLowerCase())
          .toList();

      final colunas = {
        'codigo':
            _encontrarColuna(headers, ['código', 'codigo', 'code', 'ref']),
        'categoria': _encontrarColuna(headers, ['categoria', 'category']),
        'descricao': _encontrarColuna(headers,
            ['descrição do serviço', 'descrição', 'description', 'serviço']),
        'cores': _encontrarColuna(headers, ['cores', 'cor']),
        'peso': _encontrarColuna(headers, ['peso']),
        'quantidade': _encontrarColuna(headers, ['qtde', 'quantidade', 'qtd']),
        'tamanho': _encontrarColuna(headers, ['tam', 'tamanho', 'size']),
        'prazo': _encontrarColuna(headers, ['prazo', 'prazo entrega']),
        'preco': _encontrarColuna(
            headers, ['preço r\$', 'preço', 'price', 'preco', 'valor']),
      };

      final produtos = <Map<String, dynamic>>[];

      for (var i = headerIndex + 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(separador);
        if (parts.length < 2) continue;

        final produto = <String, dynamic>{};

        void addValue(String key, int? index) {
          if (index != null && index >= 0 && index < parts.length) {
            final valor = parts[index].trim();
            if (valor.isNotEmpty) {
              produto[key] = valor;
            }
          }
        }

        addValue('codigo', colunas['codigo']);
        addValue('categoria', colunas['categoria']);
        addValue('descricao', colunas['descricao']);
        addValue('cores', colunas['cores']);
        addValue('peso', colunas['peso']);
        addValue('tamanho', colunas['tamanho']);
        addValue('prazo', colunas['prazo']);

        if (colunas['quantidade'] != null &&
            colunas['quantidade']! >= 0 &&
            colunas['quantidade']! < parts.length) {
          final valor =
              parts[colunas['quantidade']!].trim().replaceAll(',', '.');
          produto['quantidade'] = double.tryParse(valor) ?? 0;
        }

        if (colunas['preco'] != null &&
            colunas['preco']! >= 0 &&
            colunas['preco']! < parts.length) {
          String valor = parts[colunas['preco']!].trim();
          valor = valor.replaceAll('R\$', '').replaceAll('R\$', '').trim();
          valor = valor.replaceAll(',', '.');
          produto['custo'] = double.tryParse(valor) ?? 0;
        }

        if (produto['codigo'] == null || produto['codigo'].toString().isEmpty) {
          produto['codigo'] = 'IMP_${DateTime.now().millisecondsSinceEpoch}_$i';
        }

        if (produto['categoria'] == null ||
            produto['categoria'].toString().isEmpty) {
          produto['categoria'] = 'outros';
        }

        // CONSTRUIR NOME COMPLETO DO PRODUTO
        String nomeProduto = '';

        // 1. Categoria (ex: MINI CARTÃO)
        if (produto['categoria'] != null &&
            produto['categoria'].toString().isNotEmpty) {
          nomeProduto += produto['categoria'].toString();
        }

        // 2. Descrição (ex: COUCHE BRILHO - 250g)
        if (produto['descricao'] != null &&
            produto['descricao'].toString().isNotEmpty) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' ';
          nomeProduto += produto['descricao'].toString();
        }

        // 3. Cores (ex: 4X0, 4X1, 4X4)
        if (produto['cores'] != null &&
            produto['cores'].toString().isNotEmpty) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' ';
          nomeProduto += produto['cores'].toString();
        }

        // 4. Tamanho (ex: 45.5 x 51)
        if (produto['tamanho'] != null &&
            produto['tamanho'].toString().isNotEmpty) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' - ';
          nomeProduto += produto['tamanho'].toString();
        }

        // 5. Quantidade (ex: 1000 UN)
        final qtd = produto['quantidade']?.toDouble() ?? 0;
        if (qtd > 0) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' - ';
          nomeProduto += '${qtd.toInt()} UN';
        }

        // 6. Peso (ex: 580g)
        if (produto['peso'] != null && produto['peso'].toString().isNotEmpty) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' ';
          nomeProduto += '(${produto['peso']}g)';
        }

        // Se o nome ficou vazio, usar o código
        if (nomeProduto.isEmpty) {
          nomeProduto = produto['codigo'].toString();
        }

        final novoProduto = {
          'codigo': produto['codigo'],
          'nome': nomeProduto,
          'categoria': _mapearCategoria(produto['categoria'] ?? 'outros'),
          'custo': produto['custo'] ?? 0,
          'estoque': qtd,
          'unidade': 'un',
          'descricao': produto['descricao'] ?? '',
          'cores': produto['cores'] ?? '',
          'tamanho': produto['tamanho'] ?? '',
          'prazo': produto['prazo'] ?? '',
          'peso': produto['peso'] ?? '',
        };

        // Verificar duplicatas dentro do próprio arquivo
        final exists =
            produtos.any((p) => p['codigo'] == novoProduto['codigo']);
        if (!exists && novoProduto['codigo'].toString().isNotEmpty) {
          produtos.add(novoProduto);
        }
      }

      if (produtos.isEmpty) {
        throw Exception('Nenhum produto encontrado no arquivo CSV.');
      }

      return produtos;
    } catch (e) {
      throw Exception('Erro ao ler CSV: $e');
    }
  }

  // ==================== LER XLS ====================
  Future<List<Map<String, dynamic>>> _lerXls(String caminho) async {
    try {
      final produtos = await _lerCsv(caminho);
      if (produtos.isNotEmpty) {
        return produtos;
      }
    } catch (e) {}

    try {
      final produtos = await _lerXlsComoTexto(caminho);
      if (produtos.isNotEmpty) {
        return produtos;
      }
    } catch (e) {}

    throw Exception('Não foi possível ler o arquivo XLS.\n\n'
        'Salve o arquivo como CSV ou XLSX e tente novamente.');
  }

  // ==================== LER XLS COMO TEXTO ====================
  Future<List<Map<String, dynamic>>> _lerXlsComoTexto(String caminho) async {
    try {
      final file = File(caminho);
      final content = await file.readAsString();
      final linhas =
          content.split('\n').where((l) => l.trim().isNotEmpty).toList();

      if (linhas.isEmpty) {
        return [];
      }

      final produtos = <Map<String, dynamic>>[];

      for (var linha in linhas) {
        final partes = linha.split(RegExp(r'\s{2,}|\t|;'));
        if (partes.length >= 3) {
          final codigo = partes[0].trim();
          final descricao = partes[1].trim();
          final preco = double.tryParse(
              partes.last.replaceAll(',', '.').replaceAll('R\$', '').trim());

          if (codigo.isNotEmpty &&
              descricao.isNotEmpty &&
              preco != null &&
              preco > 0) {
            produtos.add({
              'codigo': codigo,
              'nome': descricao,
              'categoria': 'outros',
              'custo': preco,
              'estoque': 0,
              'unidade': 'un',
              'descricao': descricao,
            });
          }
        }
      }

      return produtos;
    } catch (e) {
      return [];
    }
  }

  // ==================== LER EXCEL (XLSX) ====================
  Future<List<Map<String, dynamic>>> _lerExcelXlsx(String caminho) async {
    try {
      final file = File(caminho);
      final bytes = await file.readAsBytes();
      final excelFile = excel.Excel.decodeBytes(bytes);

      if (excelFile.tables.isEmpty) {
        throw Exception('Arquivo Excel vazio');
      }

      final sheet = excelFile.tables.values.first;
      if (sheet.rows.isEmpty) {
        throw Exception('Planilha vazia');
      }

      int headerIndex = 0;
      for (var i = 0; i < sheet.rows.length && i < 20; i++) {
        final row = sheet.rows[i];
        final firstCell =
            row.isNotEmpty ? row[0]?.value?.toString().toLowerCase() ?? '' : '';
        if (firstCell.contains('código') || firstCell.contains('codigo')) {
          headerIndex = i;
          break;
        }
      }

      final headerRow = sheet.rows[headerIndex];
      final headers = headerRow
          .map((cell) => cell?.value?.toString().toLowerCase() ?? '')
          .toList();

      final colunas = {
        'codigo':
            _encontrarColuna(headers, ['código', 'codigo', 'code', 'ref']),
        'categoria': _encontrarColuna(headers, ['categoria', 'category']),
        'descricao': _encontrarColuna(headers,
            ['descrição do serviço', 'descrição', 'description', 'serviço']),
        'cores': _encontrarColuna(headers, ['cores', 'cor']),
        'quantidade': _encontrarColuna(headers, ['qtde', 'quantidade', 'qtd']),
        'preco': _encontrarColuna(
            headers, ['preço r\$', 'preço', 'price', 'preco', 'valor']),
      };

      final produtos = <Map<String, dynamic>>[];

      for (var i = headerIndex + 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final produto = <String, dynamic>{};

        void addValue(String key, int? index) {
          if (index != null && index >= 0 && index < row.length) {
            final cell = row[index];
            final valor = cell?.value?.toString().trim() ?? '';
            if (valor.isNotEmpty) {
              produto[key] = valor;
            }
          }
        }

        addValue('codigo', colunas['codigo']);
        addValue('categoria', colunas['categoria']);
        addValue('descricao', colunas['descricao']);
        addValue('cores', colunas['cores']);

        if (colunas['quantidade'] != null &&
            colunas['quantidade']! >= 0 &&
            colunas['quantidade']! < row.length) {
          final cell = row[colunas['quantidade']!];
          final valor = cell?.value?.toString().replaceAll(',', '.') ?? '0';
          produto['quantidade'] = double.tryParse(valor) ?? 0;
        }

        if (colunas['preco'] != null &&
            colunas['preco']! >= 0 &&
            colunas['preco']! < row.length) {
          String valor =
              row[colunas['preco']!]?.value?.toString().trim() ?? '0';
          valor = valor.replaceAll('R\$', '').replaceAll('R\$', '').trim();
          valor = valor.replaceAll(',', '.');
          produto['custo'] = double.tryParse(valor) ?? 0;
        }

        if (produto['codigo'] == null || produto['codigo'].toString().isEmpty) {
          produto['codigo'] = 'IMP_${DateTime.now().millisecondsSinceEpoch}_$i';
        }

        if (produto['categoria'] == null ||
            produto['categoria'].toString().isEmpty) {
          produto['categoria'] = 'outros';
        }

        // CONSTRUIR NOME COMPLETO DO PRODUTO
        String nomeProduto = '';

        if (produto['categoria'] != null &&
            produto['categoria'].toString().isNotEmpty) {
          nomeProduto += produto['categoria'].toString();
        }

        if (produto['descricao'] != null &&
            produto['descricao'].toString().isNotEmpty) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' ';
          nomeProduto += produto['descricao'].toString();
        }

        if (produto['cores'] != null &&
            produto['cores'].toString().isNotEmpty) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' ';
          nomeProduto += produto['cores'].toString();
        }

        if (produto['tamanho'] != null &&
            produto['tamanho']?.toString().isNotEmpty == true) {
          String tamanho = produto['tamanho'].toString();
          if (!tamanho.contains('x') && produto['descricao'] != null) {
            final desc = produto['descricao'].toString();
            final regex = RegExp(r'(\d+[.,]\d+)\s*[xX]\s*(\d+[.,]\d+)');
            final match = regex.firstMatch(desc);
            if (match != null) {
              tamanho = '${match.group(1)} x ${match.group(2)}';
            }
          }
          if (nomeProduto.isNotEmpty) nomeProduto += ' - ';
          nomeProduto += tamanho;
        }

        final qtd = produto['quantidade']?.toDouble() ?? 0;
        if (qtd > 0) {
          if (nomeProduto.isNotEmpty) nomeProduto += ' - ';
          nomeProduto += '${qtd.toInt()} UN';
        }

        if (nomeProduto.isEmpty) {
          nomeProduto = produto['codigo'].toString();
        }

        produto['nome'] = nomeProduto;
        produto['estoque'] = qtd;
        produto['unidade'] = 'un';

        final exists = produtos.any((p) => p['codigo'] == produto['codigo']);
        if (!exists && produto['codigo'].toString().isNotEmpty) {
          produtos.add(produto);
        }
      }

      if (produtos.isEmpty) {
        throw Exception('Nenhum produto encontrado no arquivo Excel.');
      }

      return produtos;
    } catch (e) {
      if (e.toString().contains('Excel format unsupported')) {
        throw Exception('Formato XLS (Excel antigo) não é suportado.');
      }
      throw Exception('Erro ao ler arquivo Excel: $e');
    }
  }

  // ==================== LER PDF ====================
  Future<List<Map<String, dynamic>>> _lerPdf(String caminho) async {
    try {
      final file = File(caminho);

      try {
        final text = await file.readAsString();
        final linhas = text.split('\n');
        final produtos = <Map<String, dynamic>>[];

        for (var linha in linhas) {
          final partes = linha.split(RegExp(r'\s+'));
          if (partes.length >= 2) {
            final nome = partes[0].trim();
            final valor = double.tryParse(
                partes.last.replaceAll(',', '.').replaceAll('R\$', '').trim());

            if (nome.isNotEmpty && valor != null && valor > 0) {
              produtos.add({
                'nome': nome,
                'codigo':
                    'PDF_${DateTime.now().millisecondsSinceEpoch}_${produtos.length + 1}',
                'categoria': 'outros',
                'custo': valor,
                'estoque': 0,
                'unidade': 'un',
              });
            }
          }
        }

        if (produtos.isNotEmpty) {
          return produtos;
        }
      } catch (e) {}

      throw Exception('Não foi possível extrair dados do PDF.');
    } catch (e) {
      throw Exception('Erro ao ler PDF: $e');
    }
  }

  // ==================== UTILITÁRIOS ====================
  int _encontrarColuna(List<String> headers, List<String> possiveis) {
    for (var i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase().trim();
      for (var possivel in possiveis) {
        if (header.contains(possivel)) {
          return i;
        }
      }
    }
    return -1;
  }

  // ==================== CALCULAR PREÇO DE VENDA ====================
  double calcularPrecoVenda(double custo, double margemLucro) {
    if (custo <= 0) return custo;

    final multiplicador = 1 + (margemLucro / 100);
    return custo * multiplicador;
  }

  // ==================== IMPORTAR PRODUTOS ====================
  Future<int> importarProdutos(
    List<Map<String, dynamic>> produtos,
    double margemLucro,
  ) async {
    int importados = 0;
    int atualizados = 0;
    int erros = 0;

    final produtosExistentes = await _productRepo.getAll();
    final codigosExistentes = produtosExistentes.map((p) => p.codigo).toList();

    for (var prod in produtos) {
      try {
        final codigo = prod['codigo'] ??
            'IMP_${DateTime.now().millisecondsSinceEpoch}_${importados + 1}';
        final custo = prod['custo']?.toDouble() ?? 0;
        final precoVenda = calcularPrecoVenda(custo, margemLucro);
        final nome = prod['nome'] ?? 'Produto sem nome';
        final categoria = _mapearCategoria(prod['categoria'] ?? 'outros');
        final estoque = prod['estoque']?.toDouble() ?? 0;
        final unidade = _mapearUnidade(prod['unidade'] ?? 'un');
        final descricao = prod['descricao'] ?? '';

        final exists = codigosExistentes.contains(codigo);

        if (exists) {
          final produtoExistente =
              produtosExistentes.firstWhere((p) => p.codigo == codigo);
          final produtoAtualizado = ProductModel(
            id: produtoExistente.id,
            nome: nome,
            codigo: produtoExistente.codigo,
            preco: precoVenda,
            cost: custo,
            descricao: descricao,
            categoria: categoria,
            estoque: estoque,
            unidade: unidade,
          );
          await _productRepo.update(produtoAtualizado);
          atualizados++;
        } else {
          final novoProduto = ProductModel(
            codigo: codigo,
            nome: nome,
            preco: precoVenda,
            cost: custo,
            descricao: descricao,
            categoria: categoria,
            estoque: estoque,
            unidade: unidade,
          );
          await _productRepo.insert(novoProduto);
          importados++;
          codigosExistentes.add(codigo);
        }
      } catch (e) {
        erros++;
        print('Erro ao importar produto ${prod['nome']}: $e');
      }
    }

    if (importados == 0 && atualizados == 0 && erros > 0) {
      throw Exception(
          'Nenhum produto foi importado. $erros erro(s) ocorreram.');
    }

    return importados + atualizados;
  }

  String _mapearCategoria(String categoria) {
    final mapa = {
      'mini cartão': 'papelaria',
      'mini car': 'papelaria',
      'cartão': 'papelaria',
      'cartao': 'papelaria',
      'comunicacao_visual': 'comunicacao_visual',
      'com. visual': 'comunicacao_visual',
      'banner': 'comunicacao_visual',
      'lona': 'comunicacao_visual',
      'adesivo': 'adesivos',
      'adesivos': 'adesivos',
      'vestuario': 'vestuario',
      'camiseta': 'vestuario',
      'presente': 'presentes',
      'presentes': 'presentes',
      'papelaria': 'papelaria',
      'papel': 'papelaria',
    };
    final chave = categoria.toLowerCase().trim();
    return mapa[chave] ?? 'outros';
  }

  String _mapearUnidade(String unidade) {
    final mapa = {
      'm²': 'm²',
      'm2': 'm²',
      'metro': 'm²',
      'metros': 'm²',
      'un': 'un',
      'unidade': 'un',
      'unidades': 'un',
      'pç': 'un',
      'pc': 'un',
    };
    return mapa[unidade.toLowerCase().trim()] ?? 'un';
  }

  // ==================== IMPORTAR CSV (MANTIDO PARA COMPATIBILIDADE) ====================
  Future<void> importProductsFromCsv(String csvContent) async {
    final lines = csvContent.split('\n');
    final produtos = <Map<String, dynamic>>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(';');
      if (parts.length < 2) continue;

      produtos.add({
        'codigo': parts[0].trim(),
        'nome': parts.length > 2 ? parts[2].trim() : 'Produto',
        'custo': double.tryParse(
                parts.last.replaceAll('R\$', '').replaceAll(',', '.').trim()) ??
            0,
        'categoria': parts.length > 1 ? parts[1].trim() : 'outros',
      });
    }

    if (produtos.isNotEmpty) {
      await importarProdutos(produtos, 30);
    }
  }
}
