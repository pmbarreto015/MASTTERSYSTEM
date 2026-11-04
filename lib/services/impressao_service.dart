import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../models/customer_model.dart';
import '../models/seller_model.dart';
import 'package:intl/intl.dart';

class ImpressaoService {
  factory ImpressaoService() => _instance;
  ImpressaoService._internal();
  static final ImpressaoService _instance = ImpressaoService._internal();

  Map<String, String> _empresa = {};
  Uint8List? _logoBytes;

  Future<void> _carregarDadosEmpresa() async {
    final prefs = await SharedPreferences.getInstance();
    _empresa = {
      'nome': prefs.getString('company_name') ?? 'MatterdiSistem Gráfica',
      'cnpj': prefs.getString('company_cnpj') ?? '12.345.678/0001-99',
      'telefone': prefs.getString('company_phone') ?? '(15) 98104-9471',
      'endereco': prefs.getString('company_address') ??
          'SEU ENDEREÇO - SEU BAIRRO - SUA CIDADE-UF',
      'email':
          prefs.getString('company_email') ?? 'suportemastersystem@gmail.com',
      'website': prefs.getString('company_website') ?? 'www.matterdi.com.br',
    };

    final logoPath = prefs.getString('company_logo');
    if (logoPath != null && File(logoPath).existsSync()) {
      try {
        _logoBytes = await File(logoPath).readAsBytes();
      } catch (e) {
        _logoBytes = null;
      }
    } else {
      _logoBytes = null;
    }
  }

  String _formatarMoeda(double valor) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);

  String _formatarDataSimples(DateTime data) =>
      DateFormat('dd/MM/yyyy').format(data);

  String _formatarDataString(String dataStr) {
    try {
      final data = DateTime.parse(dataStr);
      return DateFormat('dd/MM/yyyy').format(data);
    } catch (e) {
      return dataStr;
    }
  }

  Future<Uint8List> gerarPdfBytes(
    OrderModel pedido,
    CustomerModel cliente,
    SellerModel vendedor,
  ) async {
    await _carregarDadosEmpresa();
    final totalProdutos = pedido.itens.fold<double>(
      0,
      (sum, item) => sum + item.subtotal,
    );

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(14),
        build: (pw.Context context) {
          return [
            // ==================== CABEÇALHO COM LOGO ====================
            pw.Row(
              children: [
                if (_logoBytes != null)
                  pw.Container(
                    width: 120,
                    height: 90,
                    child: pw.Image(
                      pw.MemoryImage(_logoBytes!),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        _empresa['nome']!.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'CNPJ: ${_empresa['cnpj']!}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            _empresa['endereco']!,
                            style: const pw.TextStyle(
                                fontSize: 7, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            _empresa['telefone']!,
                            style: const pw.TextStyle(
                                fontSize: 7, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            _empresa['email']!,
                            style: const pw.TextStyle(
                                fontSize: 7, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            _empresa['website']!,
                            style: const pw.TextStyle(
                                fontSize: 7, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              height: 1.5,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 4),

            // Título
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'PEDIDO DE VENDA ${pedido.numero} / ${pedido.tipo == 'OS' ? 'OS' : 'ORÇAMENTO'}',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Hora: ${DateFormat('HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      'Data: ${_formatarDataSimples(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 4),

            // ==================== DADOS DO CLIENTE ====================
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Cliente   : ${cliente.name.isNotEmpty ? cliente.name : pedido.clienteNome ?? 'Não informado'}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Endereço  : ${cliente.address ?? 'Não informado'}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'CPF/Cnpj  : ${cliente.document ?? 'Não informado'}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Contato : ${cliente.phone.isNotEmpty ? cliente.phone : 'Não informado'}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Bairro  : -',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Cidade  : -   UF: -    CEP: -',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 4),

            // ==================== TABELA DE ITENS ====================
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text('Descrição do Item',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Unit',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Quant',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Larg.\n(mm)',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Alt.\n(mm)',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Área\n(m²)',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Vlr. Unit.',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Total',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 8),
                        textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ),
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 2),

            // Linhas da tabela com dimensões
            ...pedido.itens.asMap().entries.map((entry) {
              final itemIndex = entry.key + 1;
              final item = entry.value;
              String largura = '';
              String altura = '';
              String mt2 = '';
              double areaCalculada = 0;

              if (item.largura > 0 && item.altura > 0) {
                largura = item.largura.toStringAsFixed(0);
                altura = item.altura.toStringAsFixed(0);
                areaCalculada = (item.largura * item.altura) / 1000000;
                mt2 = (areaCalculada * item.quantidade).toStringAsFixed(3);
              } else if (item.especificacoes.isNotEmpty) {
                final regex = RegExp(r'(\d+)\s*[xX]\s*(\d+)');
                final match = regex.firstMatch(item.especificacoes);
                if (match != null) {
                  final w = double.tryParse(match.group(1) ?? '0') ?? 0;
                  final h = double.tryParse(match.group(2) ?? '0') ?? 0;
                  if (w > 0 && h > 0) {
                    largura = w.toStringAsFixed(0);
                    altura = h.toStringAsFixed(0);
                    areaCalculada = (w * h) / 1000000;
                    mt2 = (areaCalculada * item.quantidade).toStringAsFixed(3);
                  }
                }
              }

              return pw.Column(
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 4,
                        child: pw.Text(
                          'Item ${itemIndex.toString().padLeft(2, '0')} - ${item.produtoNome}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          _getUnidade(item),
                          style: const pw.TextStyle(fontSize: 7),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          item.quantidade.toString(),
                          style: const pw.TextStyle(fontSize: 7),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          largura,
                          style: const pw.TextStyle(fontSize: 7),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          altura,
                          style: const pw.TextStyle(fontSize: 7),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          mt2,
                          style: const pw.TextStyle(fontSize: 7),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          _formatarMoeda(item.precoUnitario),
                          style: const pw.TextStyle(fontSize: 7),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          _formatarMoeda(item.subtotal),
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  if (item.especificacoes.trim().isNotEmpty)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.only(
                        left: 4,
                        top: 2,
                        right: 4,
                        bottom: 3,
                      ),
                      color: PdfColors.grey100,
                      child: pw.Text(
                        'Obs. do item: ${item.especificacoes.trim()}',
                        style: pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey800,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ),
                  if (_detalhesTecnicos(item).isNotEmpty)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.only(
                        left: 4,
                        top: 3,
                        right: 4,
                        bottom: 4,
                      ),
                      color: PdfColors.blue50,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Composição e materiais:',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                          pw.Text(
                            _detalhesTecnicos(item),
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ],
                      ),
                    ),
                  pw.Container(
                    height: 0.3,
                    color: PdfColors.grey300,
                  ),
                ],
              );
            }),

            pw.SizedBox(height: 4),

            if (pedido.observacoes.trim().isNotEmpty) ...[
              pw.Text(
                'OBSERVAÇÕES GERAIS:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              ),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                ),
                child: pw.Text(
                  pedido.observacoes.trim(),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 4),

            // ==================== DADOS DA OS COM VENDEDOR ====================
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Dados da Ordem de Serviço',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Vendedor: ${vendedor.name}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Data Aprovação: ${_formatarDataSimples(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Data Entrega: ${pedido.dataEntrega != null ? _formatarDataString(pedido.dataEntrega!) : 'Não definida'}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 4),

            // ==================== CONDIÇÕES DE PAGAMENTO E TOTAIS ====================
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Condições de Pagamento:',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      ..._getCondicoesPagamento(pedido)
                          .map((condicao) => pw.Text(
                                condicao,
                                style: const pw.TextStyle(fontSize: 8),
                              )),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            'VALOR PRODUTOS : ',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            _formatarMoeda(totalProdutos),
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (pedido.outrosValores > 0)
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text(
                              'OUTROS VALORES : ',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.Text(
                              _formatarMoeda(pedido.outrosValores),
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            'VALOR DE ENTRADA: ',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            _formatarMoeda(pedido.entrada),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            'VALOR DESCONTO : ',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            _formatarMoeda(pedido.desconto),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                      pw.Container(
                        height: 1,
                        color: PdfColors.black,
                        width: 180,
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            'VALOR TOTAL    : ',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            _formatarMoeda(pedido.valorTotal),
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            'VALOR RESTANTE: ',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            _formatarMoeda(
                              (pedido.valorTotal - pedido.entrada)
                                  .clamp(0.0, double.infinity)
                                  .toDouble(),
                            ),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 8),

            // ==================== AVISO IMPORTANTE ====================
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                color: PdfColors.grey50,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ATENÇÃO:',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 9,
                      color: PdfColors.red,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Confira atentamente todos os dados, textos, medidas, cores, quantidades e informações do pedido antes da aprovação. Após a aprovação, alterações poderão gerar novos custos e prazos.',
                    style: const pw.TextStyle(fontSize: 7, height: 1.5),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'A produção será iniciada somente após a confirmação do pedido e aprovação da arte.',
                    style: pw.TextStyle(
                        fontSize: 7,
                        height: 1.5,
                        fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Prazos de entrega são contados a partir da aprovação e confirmação do pagamento. A empresa não se responsabiliza por erros existentes nas informações ou arquivos aprovados pelo cliente.',
                    style: const pw.TextStyle(fontSize: 7, height: 1.5),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Obrigado pela preferência!',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // ==================== ASSINATURA ====================
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      height: 25,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom:
                              pw.BorderSide(color: PdfColors.black, width: 0.5),
                        ),
                      ),
                    ),
                    pw.Text(
                      'Visto________________________',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              height: 1,
              color: PdfColors.black,
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Documento interno para a equipe de produção. Não inclui preços,
  /// custos, entradas ou condições de pagamento.
  Future<Uint8List> gerarPdfProducaoBytes(
    OrderModel pedido,
    CustomerModel cliente,
    SellerModel vendedor,
  ) async {
    await _carregarDadosEmpresa();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(14),
        header: (context) => pw.Column(
          children: [
            pw.Row(
              children: [
                if (_logoBytes != null)
                  pw.Container(
                    width: 85,
                    height: 55,
                    child: pw.Image(
                      pw.MemoryImage(_logoBytes!),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ORDEM DE PRODUÇÃO',
                        style: pw.TextStyle(
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.Text(
                        '${_empresa['nome']}  •  Documento de uso interno',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue900),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        pedido.numero,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Entrega: ${pedido.dataEntrega == null ? 'Não definida' : _formatarDataString(pedido.dataEntrega!)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(color: PdfColors.blue900, thickness: 1.2),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Uso interno — sem informações financeiras',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (context) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Cliente: ${cliente.name.isNotEmpty ? cliente.name : pedido.clienteNome ?? 'Não informado'}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  'Vendedor: ${vendedor.name}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          ...pedido.itens.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final item = entry.value;
            final details = _detalhesTecnicos(item);
            final dimensions = item.largura > 0 && item.altura > 0
                ? '${item.largura.toStringAsFixed(0)} x ${item.altura.toStringAsFixed(0)} mm'
                : 'Não informadas';

            return pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: .7),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue100,
                      borderRadius: pw.BorderRadius.only(
                        topLeft: pw.Radius.circular(4),
                        topRight: pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            'ITEM ${index.toString().padLeft(2, '0')} — ${item.produtoNome}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Text(
                          'Quantidade: ${item.quantidade}',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Medidas: $dimensions',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        if (item.especificacoes.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Especificações / cores / acabamento:',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            item.especificacoes.trim(),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                        if (details.isNotEmpty) ...[
                          pw.SizedBox(height: 5),
                          pw.Text(
                            'Materiais da composição:',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Container(
                            width: double.infinity,
                            margin: const pw.EdgeInsets.only(top: 2),
                            padding: const pw.EdgeInsets.all(6),
                            color: PdfColors.grey100,
                            child: pw.Text(
                              details,
                              style:
                                  const pw.TextStyle(fontSize: 8, height: 1.35),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (pedido.observacoes.trim().isNotEmpty) ...[
            pw.Text(
              'OBSERVAÇÕES GERAIS PARA PRODUÇÃO',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 3),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500),
              ),
              child: pw.Text(
                pedido.observacoes.trim(),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Row(
            children: [
              _campoProducao('Produzido por'),
              pw.SizedBox(width: 12),
              _campoProducao('Conferido por'),
              pw.SizedBox(width: 12),
              _campoProducao('Data / hora'),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _campoProducao(String label) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              height: 24,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.black, width: .5),
                ),
              ),
            ),
            pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      );

  /// Remove somente informações financeiras da descrição da
  /// composição, preservando materiais, quantidades, códigos e medidas.
  String _detalhesTecnicos(OrderItemModel item) {
    if (item.detalhesCusto.trim().isEmpty) return '';

    return item.detalhesCusto
        .split('\n')
        .map((line) => line
            .replaceAll(
              RegExp(r'\s*\|\s*Custo\s+R\$\s*[\d.,]+', caseSensitive: false),
              '',
            )
            .replaceAll(
              RegExp(r'\s*\|\s*Venda\s+R\$\s*[\d.,]+', caseSensitive: false),
              '',
            )
            .trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  String _getUnidade(OrderItemModel item) {
    if ((item.largura > 0 && item.altura > 0) ||
        item.produtoNome.toLowerCase().contains('m²') ||
        item.produtoNome.toLowerCase().contains('metro') ||
        item.produtoNome.toLowerCase().contains('banner') ||
        item.produtoNome.toLowerCase().contains('lona') ||
        item.produtoNome.toLowerCase().contains('adesivo') ||
        item.produtoNome.toLowerCase().contains('placa') ||
        item.produtoNome.toLowerCase().contains('letreiro')) {
      return 'MT2';
    }
    if (item.produtoNome.toLowerCase().contains('cartão') ||
        item.produtoNome.toLowerCase().contains('panfleto') ||
        item.produtoNome.toLowerCase().contains('flyer')) {
      return 'MIL';
    }
    return 'UNI';
  }

  // MÉTODO CORRIGIDO PARA EXIBIR AS CONDIÇÕES DE PAGAMENTO
  List<String> _getCondicoesPagamento(OrderModel pedido) {
    final condicoes = <String>[];
    final totalLiquido = pedido.valorTotal - pedido.entrada;

    // PARCELADO LOJA - COM DATAS DAS PARCELAS
    if (pedido.formaPagamento == 'Parcelado Loja') {
      final entrada = pedido.entrada;

      // Mostra a entrada se houver
      if (entrada > 0) {
        condicoes.add(
          'Entrada: ${_formatarMoeda(entrada)} - ${_formatarDataSimples(DateTime.now())}',
        );
      }

      // Mostra cada parcela com sua data
      for (var i = 0; i < pedido.parcelas.length; i++) {
        String dataParcela;
        if (i < pedido.parcelasDatas.length &&
            pedido.parcelasDatas[i].isNotEmpty) {
          dataParcela = _formatarDataString(pedido.parcelasDatas[i]);
        } else {
          // Fallback: data padrão (30 dias após a data atual)
          final data = DateTime.now().add(Duration(days: (i + 1) * 30));
          dataParcela = _formatarDataSimples(data);
        }
        condicoes.add(
          '${(i + 1).toString().padLeft(2, '0')}-Parcela: ${_formatarMoeda(pedido.parcelas[i])} - $dataParcela',
        );
      }

      // Se não houver parcelas, mostra o total líquido
      if (pedido.parcelas.isEmpty) {
        condicoes.add(
          'Pagamento: ${pedido.formaPagamento} - ${_formatarMoeda(totalLiquido)}',
        );
      }
    }
    // 50% no ato + 50% na entrega
    else if (pedido.formaPagamento == '50% no ato + 50% na entrega') {
      final entrada = pedido.entrada;
      final restante = pedido.valorTotal - entrada;

      condicoes.add(
        '1ª Parcela (Entrada): ${_formatarMoeda(entrada)} - ${_formatarDataSimples(DateTime.now())}',
      );

      String dataEntrega = 'Data a definir';
      if (pedido.dataEntrega != null && pedido.dataEntrega!.isNotEmpty) {
        dataEntrega = _formatarDataString(pedido.dataEntrega!);
      }
      condicoes.add(
        '2ª Parcela (Entrega): ${_formatarMoeda(restante)} - $dataEntrega',
      );
    }
    // OUTROS MÉTODOS DE PAGAMENTO
    else {
      condicoes.add(
        'Pagamento: ${pedido.formaPagamento} - ${_formatarMoeda(totalLiquido)}',
      );
    }

    return condicoes;
  }

  // ==================== MÉTODOS DE IMPRESSÃO ====================

  Future<void> imprimirPdf(Uint8List bytes) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

  Future<void> exibirPreviaPdf(Uint8List bytes) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

  Future<Map<String, dynamic>> salvarPdfEmDisco(
    OrderModel pedido,
    CustomerModel cliente,
    SellerModel vendedor,
  ) async {
    try {
      final bytes = await gerarPdfBytes(pedido, cliente, vendedor);

      final directory = Directory.current;
      final pastaPedidos = Directory('${directory.path}/pedidos_impressao');
      if (!pastaPedidos.existsSync()) {
        pastaPedidos.createSync(recursive: true);
      }

      final hoje = DateTime.now().toIso8601String().split('T')[0];
      final pastaHoje = Directory('${pastaPedidos.path}/$hoje');
      if (!pastaHoje.existsSync()) {
        pastaHoje.createSync(recursive: true);
      }

      final hora = DateTime.now()
          .toIso8601String()
          .split('T')[1]
          .split('.')[0]
          .replaceAll(':', '-');
      final nomeArquivo = '${pedido.numero}_$hora.pdf';
      final caminhoArquivo = '${pastaHoje.path}/$nomeArquivo';

      final file = File(caminhoArquivo);
      await file.writeAsBytes(bytes);

      return {
        'sucesso': true,
        'caminho': caminhoArquivo,
        'nome': nomeArquivo,
        'bytes': bytes,
      };
    } catch (e) {
      return {
        'sucesso': false,
        'erro': e.toString(),
      };
    }
  }
}
