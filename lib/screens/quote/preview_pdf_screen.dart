import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum _PrintLayout { twoCopiesOnA4, selectedCopyOnA4 }

class PreviewPdfScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String titulo;
  final Uint8List? productionPdfBytes;
  final String productionTitle;

  const PreviewPdfScreen({
    super.key,
    required this.pdfBytes,
    this.titulo = 'Pré-visualização',
    this.productionPdfBytes,
    this.productionTitle = 'Ordem de produção',
  });

  @override
  State<PreviewPdfScreen> createState() => _PreviewPdfScreenState();
}

class _PreviewPdfScreenState extends State<PreviewPdfScreen> {
  bool _productionCopy = false;

  Uint8List get _currentBytes =>
      _productionCopy && widget.productionPdfBytes != null
          ? widget.productionPdfBytes!
          : widget.pdfBytes;

  String get _currentTitle =>
      _productionCopy ? widget.productionTitle : widget.titulo;

  Future<pw.MemoryImage> _rasterFirstPage(Uint8List bytes) async {
    const printDpi = 300.0;
    final page = await Printing.raster(
      bytes,
      pages: [0],
      dpi: printDpi,
    ).first;
    return pw.MemoryImage(await page.toPng());
  }

  Future<Uint8List> _bytesForPrint(_PrintLayout layout) async {
    // A4 mede 29,7 x 21 cm. A margem externa de 1 cm e o espaço central
    // deixam as duas vias alinhadas, centralizadas e sem corte na impressão.
    const margin = 10.0 * PdfPageFormat.mm;
    final document = pw.Document();

    if (layout == _PrintLayout.selectedCopyOnA4 ||
        widget.productionPdfBytes == null) {
      final image = await _rasterFirstPage(_currentBytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(margin),
          build: (_) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
      return document.save();
    }

    final customerImage = await _rasterFirstPage(widget.pdfBytes);
    final productionImage = await _rasterFirstPage(widget.productionPdfBytes!);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Row(
          children: [
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(customerImage, fit: pw.BoxFit.contain),
              ),
            ),
            pw.Container(
              width: 4 * PdfPageFormat.mm,
              alignment: pw.Alignment.center,
              child: pw.Container(width: .5, color: PdfColors.grey500),
            ),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(productionImage, fit: pw.BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  Future<void> _print(_PrintLayout layout) async {
    try {
      final bytes = await _bytesForPrint(layout);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível preparar a impressão: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualização do pedido'),
        backgroundColor: const Color(0xFF0F62AC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F62AC), Color(0xFF123E68)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0x33FFFFFF),
                  child: Icon(Icons.description_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.productionPdfBytes == null
                            ? 'Documento pronto para visualização e impressão.'
                            : 'Veja cada via separadamente. A impressão coloca as duas em uma folha A4.',
                        style: const TextStyle(
                            color: Color(0xD9FFFFFF), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _print(
                        widget.productionPdfBytes == null
                            ? _PrintLayout.selectedCopyOnA4
                            : _PrintLayout.twoCopiesOnA4,
                      ),
                      icon: const Icon(Icons.print_outlined),
                      label: Text(widget.productionPdfBytes == null
                          ? 'A4'
                          : '2 vias A4'),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFF0F62AC),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    PopupMenuButton<_PrintLayout>(
                      tooltip: 'Opções de impressão',
                      color: Colors.white,
                      onSelected: _print,
                      itemBuilder: (_) => [
                        if (widget.productionPdfBytes != null)
                          const PopupMenuItem(
                            value: _PrintLayout.twoCopiesOnA4,
                            child: ListTile(
                              leading: Icon(Icons.view_week_outlined),
                              title: Text('Duas vias na A4'),
                              subtitle: Text('Lado a lado, margem de 1 cm'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: _PrintLayout.selectedCopyOnA4,
                          child: ListTile(
                            leading: Icon(Icons.crop_portrait_outlined),
                            title: Text('Via selecionada em A4'),
                            subtitle: Text('Uma via centralizada na folha'),
                          ),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_drop_down, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.productionPdfBytes != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.person_outline),
                      label: Text('Via do cliente'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.precision_manufacturing_outlined),
                      label: Text('Ordem de produção (sem valores)'),
                    ),
                  ],
                  selected: {_productionCopy},
                  onSelectionChanged: (selection) {
                    setState(() => _productionCopy = selection.first);
                  },
                ),
              ),
            ),
          Expanded(
            child: PdfPreview(
              key: ValueKey(_productionCopy),
              build: (format) => _currentBytes,
              allowSharing: true,
              allowPrinting: false,
              pdfFileName: _productionCopy
                  ? 'ordem_producao_${DateTime.now().millisecondsSinceEpoch}.pdf'
                  : 'pedido_cliente_${DateTime.now().millisecondsSinceEpoch}.pdf',
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              dpi: 180,
              maxPageWidth: 720,
              padding: const EdgeInsets.all(24),
              previewPageMargin: const EdgeInsets.symmetric(vertical: 12),
              scrollViewDecoration: const BoxDecoration(
                color: Color(0xFF0B1622),
              ),
              pdfPreviewPageDecoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              onError: (context, error) {
                debugPrint('Falha ao carregar PDF: $error');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text(
                        'Não foi possível abrir este documento.',
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Voltar'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
