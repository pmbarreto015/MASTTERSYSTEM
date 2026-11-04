import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/employee_model.dart';
import '../models/holerite_model.dart';

class FolhaPagamentoService {
  final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  // GERAR FOLHA DE PAGAMENTO COMPLETA
  Future<Uint8List> gerarFolhaPagamento(
    List<EmployeeModel> funcionarios,
    List<HoleriteModel> holerites,
    String mesReferencia,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'FOLHA DE PAGAMENTO',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Mês de Referência: ${_formatarMesReferencia(mesReferencia)}',
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Divider(),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            _buildResumoFolha(funcionarios, holerites),
            pw.SizedBox(height: 16),
            _buildTabelaFolha(funcionarios, holerites),
            pw.SizedBox(height: 16),
            _buildRodapeFolha(funcionarios, holerites),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // GERAR HOLERITE INDIVIDUAL
  Future<Uint8List> gerarHoleriteIndividual(
    EmployeeModel funcionario,
    HoleriteModel holerite,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          // CORREÇÃO: Retornar um Column com os filhos
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildCabecalhoHolerite(funcionario, holerite),
              pw.Divider(),
              _buildDadosHolerite(holerite),
              pw.Divider(),
              _buildResumoHolerite(holerite),
              pw.Divider(),
              _buildRodapeHolerite(),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // CABEÇALHO DO HOLERITE
  pw.Widget _buildCabecalhoHolerite(
    EmployeeModel funcionario,
    HoleriteModel holerite,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Text(
            'HOLERITE',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'Mês: ${_formatarMesReferencia(holerite.mesReferencia)}',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Funcionário: ${funcionario.name}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Cargo: ${funcionario.position}'),
                  pw.Text('CPF: ${funcionario.document}'),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                      'Data Admissão: ${_data.format(funcionario.hireDate ?? DateTime.now())}'),
                  pw.Text(
                      'Status: ${funcionario.active ? "Ativo" : "Inativo"}'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // DADOS DO HOLERITE
  pw.Widget _buildDadosHolerite(HoleriteModel holerite) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Detalhamento',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        _buildLinhaHolerite('Salário Base', holerite.salarioBaseFormatado),
        _buildLinhaHolerite('Horas Trabalhadas',
            '${holerite.horasTrabalhadas.toStringAsFixed(2)}h'),
        _buildLinhaHolerite(
            'Horas Extras', '${holerite.horasExtras.toStringAsFixed(2)}h'),
        _buildLinhaHolerite('Valor Hora', _moeda.format(holerite.valorHora)),
        _buildLinhaHolerite(
            'Valor Hora Extra', _moeda.format(holerite.valorHoraExtra)),
        _buildLinhaHolerite(
            'Total Horas Extras', _moeda.format(holerite.totalHorasExtras)),
        pw.Divider(),
        _buildLinhaHolerite('Salário Bruto', holerite.salarioBrutoFormatado,
            bold: true),
        _buildLinhaHolerite('INSS', holerite.inssFormatado),
        _buildLinhaHolerite('IRRF', holerite.irrfFormatado),
        _buildLinhaHolerite('Descontos', holerite.descontosFormatado),
        pw.Divider(),
        _buildLinhaHolerite('Salário Líquido', holerite.salarioLiquidoFormatado,
            bold: true, color: PdfColors.green),
      ],
    );
  }

  // RESUMO DO HOLERITE
  pw.Widget _buildResumoHolerite(HoleriteModel holerite) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Resumo',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Salário Base:'),
              pw.Text(holerite.salarioBaseFormatado),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Horas Extras:'),
              pw.Text(_moeda.format(holerite.totalHorasExtras)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Descontos:'),
              pw.Text(holerite.descontosFormatado),
            ],
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Salário Líquido:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                holerite.salarioLiquidoFormatado,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Status:'),
              pw.Text(
                holerite.pago ? 'PAGO' : 'PENDENTE',
                style: pw.TextStyle(
                  color: holerite.pago ? PdfColors.green : PdfColors.orange,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // RODAPÉ DO HOLERITE
  pw.Widget _buildRodapeHolerite() {
    return pw.Column(
      children: [
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              children: [
                pw.Container(
                  width: 150,
                  height: 30,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black),
                    ),
                  ),
                ),
                pw.Text('Assinatura do Funcionário',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            pw.Column(
              children: [
                pw.Container(
                  width: 150,
                  height: 30,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black),
                    ),
                  ),
                ),
                pw.Text('Assinatura da Empresa',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Documento gerado eletronicamente - ${DateTime.now().toIso8601String().split('T')[0]}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
      ],
    );
  }

  // RESUMO DA FOLHA
  pw.Widget _buildResumoFolha(
    List<EmployeeModel> funcionarios,
    List<HoleriteModel> holerites,
  ) {
    final totalBruto = holerites.fold(0.0, (sum, h) => sum + h.salarioBruto);
    final totalLiquido =
        holerites.fold(0.0, (sum, h) => sum + h.salarioLiquido);
    final totalDescontos = holerites.fold(0.0, (sum, h) => sum + h.descontos);
    final totalInss = holerites.fold(0.0, (sum, h) => sum + h.inss);
    final totalIrrf = holerites.fold(0.0, (sum, h) => sum + h.irrf);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Resumo Geral',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Funcionários:'),
              pw.Text('${funcionarios.length}'),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Salário Bruto:'),
              // CORREÇÃO: Remover const
              pw.Text(_moeda.format(totalBruto)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total INSS:'),
              pw.Text(_moeda.format(totalInss)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total IRRF:'),
              pw.Text(_moeda.format(totalIrrf)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Descontos:'),
              pw.Text(_moeda.format(totalDescontos)),
            ],
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Salário Líquido:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                _moeda.format(totalLiquido),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // TABELA DA FOLHA
  pw.Widget _buildTabelaFolha(
    List<EmployeeModel> funcionarios,
    List<HoleriteModel> holerites,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          'Detalhamento por Funcionário',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.5),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(1),
          },
          children: [
            // Cabeçalho
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColors.blue100,
              ),
              children: [
                _buildCell('Funcionário',
                    bold: true, align: pw.Alignment.center),
                _buildCell('Salário Base',
                    bold: true, align: pw.Alignment.center),
                _buildCell('Bruto', bold: true, align: pw.Alignment.center),
                _buildCell('Descontos', bold: true, align: pw.Alignment.center),
                _buildCell('Líquido', bold: true, align: pw.Alignment.center),
                _buildCell('Status', bold: true, align: pw.Alignment.center),
              ],
            ),
            ...holerites.map((h) {
              final emp = funcionarios.firstWhere(
                (e) => e.id == h.employeeId,
                orElse: () => EmployeeModel.create(
                  name: h.employeeName,
                  document: '',
                  phone: '',
                  email: '',
                  position: '',
                ),
              );
              return pw.TableRow(
                children: [
                  _buildCell(emp.name, align: pw.Alignment.centerLeft),
                  _buildCell(_moeda.format(h.salarioBase),
                      align: pw.Alignment.centerRight),
                  _buildCell(_moeda.format(h.salarioBruto),
                      align: pw.Alignment.centerRight),
                  _buildCell(_moeda.format(h.descontos),
                      align: pw.Alignment.centerRight),
                  _buildCell(_moeda.format(h.salarioLiquido),
                      align: pw.Alignment.centerRight, color: PdfColors.green),
                  _buildCell(
                    h.pago ? 'Pago' : 'Pendente',
                    align: pw.Alignment.center,
                    color: h.pago ? PdfColors.green : PdfColors.orange,
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  // RODAPÉ DA FOLHA
  pw.Widget _buildRodapeFolha(
    List<EmployeeModel> funcionarios,
    List<HoleriteModel> holerites,
  ) {
    final totalLiquido =
        holerites.fold(0.0, (sum, h) => sum + h.salarioLiquido);
    final pagos = holerites.where((h) => h.pago).length;
    final pendentes = holerites.where((h) => !h.pago).length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Resumo Final',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total a Pagar:'),
              pw.Text(_moeda.format(totalLiquido),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Pagos:'),
              pw.Text('$pagos funcionários',
                  style: const pw.TextStyle(color: PdfColors.green)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Pendentes:'),
              pw.Text('$pendentes funcionários',
                  style: const pw.TextStyle(color: PdfColors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  // HELPERS
  pw.Widget _buildCell(String text,
      {bool bold = false,
      pw.Alignment align = pw.Alignment.centerLeft,
      PdfColor? color}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
          fontSize: 9,
        ),
      ),
    );
  }

  pw.Widget _buildLinhaHolerite(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatarMesReferencia(String mesRef) {
    try {
      final parts = mesRef.split('-');
      final mes = int.parse(parts[1]);
      final ano = int.parse(parts[0]);
      final meses = [
        'Janeiro',
        'Fevereiro',
        'Março',
        'Abril',
        'Maio',
        'Junho',
        'Julho',
        'Agosto',
        'Setembro',
        'Outubro',
        'Novembro',
        'Dezembro'
      ];
      return '${meses[mes - 1]} de $ano';
    } catch (e) {
      return mesRef;
    }
  }

  // MÉTODOS DE IMPRESSÃO
  Future<void> imprimirFolhaPagamento(
    List<EmployeeModel> funcionarios,
    List<HoleriteModel> holerites,
    String mesReferencia,
  ) async {
    final bytes =
        await gerarFolhaPagamento(funcionarios, holerites, mesReferencia);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

  Future<void> imprimirHolerite(
    EmployeeModel funcionario,
    HoleriteModel holerite,
  ) async {
    final bytes = await gerarHoleriteIndividual(funcionario, holerite);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }
}
