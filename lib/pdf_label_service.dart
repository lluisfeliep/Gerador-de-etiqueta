import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Gera a etiqueta em PDF e abre no aplicativo padrão do Windows
/// (normalmente o navegador, quando ele é o leitor de PDF padrão).
/// Serve como alternativa à impressão direta na Zebra: o usuário pode
/// visualizar/imprimir esse PDF em qualquer impressora.
class PdfLabelService {
  static Future<String> generateAndOpen({
    required String nome,
    required String cc,
    required String dataNascimento,
    required String medico,
    required int widthMm,
    required int heightMm,
  }) async {
    final pageFormat = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginAll: 3 * PdfPageFormat.mm,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Nome: $nome',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Text('CC: $cc', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Text('D/N: $dataNascimento', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.Text(
              'Dr(a). $medico',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    final dir = await Directory.systemTemp.createTemp('etiqueta_');
    final file = File('${dir.path}${Platform.pathSeparator}etiqueta_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);

    await Process.start('explorer', [file.path]);

    return file.path;
  }
}
