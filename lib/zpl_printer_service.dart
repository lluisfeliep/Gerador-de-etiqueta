import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Envia comandos ZPL diretamente para uma impressora instalada no Windows,
/// em modo RAW (sem passar pelo driver gráfico). É a forma padrão de
/// imprimir etiquetas ZPL em impressoras Zebra (ex: GC420T).
class ZplPrinterService {
  /// Lista os nomes das impressoras instaladas no Windows.
  static Future<List<String>> listPrinters() async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Get-Printer | Select-Object -ExpandProperty Name',
    ]);
    if (result.exitCode != 0) return [];
    return (result.stdout as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Envia o [zpl] em modo RAW para a impressora [printerName].
  /// Lança uma [Exception] com uma mensagem legível em caso de falha.
  static Future<void> printZpl(String printerName, String zpl) async {
    final bytes = Uint8List.fromList(utf8.encode(zpl));

    using((arena) {
      final phPrinter = arena<Pointer>();
      final namePtr = printerName.toNativeUtf16(allocator: arena);

      final openResult = OpenPrinter(PCWSTR(namePtr), phPrinter, nullptr);
      if (!openResult.value) {
        throw Exception(
          'Não foi possível abrir a impressora "$printerName" '
          '(código de erro ${openResult.error.code}).',
        );
      }
      final hPrinter = PRINTER_HANDLE(phPrinter.value);

      final docInfo = arena<DOC_INFO_1>();
      docInfo.ref
        ..pDocName = PWSTR('Etiqueta'.toNativeUtf16(allocator: arena))
        ..pOutputFile = PWSTR(nullptr)
        ..pDatatype = PWSTR('RAW'.toNativeUtf16(allocator: arena));

      final jobId = StartDocPrinter(hPrinter, 1, docInfo);
      if (jobId == 0) {
        ClosePrinter(hPrinter);
        throw Exception('Falha ao iniciar o trabalho de impressão.');
      }

      if (!StartPagePrinter(hPrinter)) {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        throw Exception('Falha ao iniciar a página de impressão.');
      }

      final buffer = arena<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final writtenPtr = arena<Uint32>();

      final ok = WritePrinter(hPrinter, buffer.cast(), bytes.length, writtenPtr);

      EndPagePrinter(hPrinter);
      EndDocPrinter(hPrinter);
      ClosePrinter(hPrinter);

      if (!ok) {
        throw Exception('Falha ao enviar os dados para a impressora.');
      }
    });
  }

  /// Remove caracteres de controle do ZPL (`^` e `~`) de textos livres,
  /// para não quebrar os comandos da etiqueta.
  static String _sanitize(String value) =>
      value.replaceAll('^', '').replaceAll('~', '');

  /// Monta o ZPL da etiqueta do paciente.
  ///
  /// [widthMm] e [heightMm] são o tamanho da etiqueta em milímetros.
  /// Assume-se 203 dpi (8 pontos por mm), padrão da Zebra GC420T.
  static String buildPatientLabel({
    required String nome,
    required String cc,
    required String dataNascimento,
    required String medico,
    int widthMm = 50,
    int heightMm = 30,
  }) {
    const dotsPerMm = 8;
    final width = widthMm * dotsPerMm;
    final height = heightMm * dotsPerMm;
    final textWidth = width - 40;

    final nomeS = _sanitize(nome);
    final ccS = _sanitize(cc);
    final dnS = _sanitize(dataNascimento);
    final medicoS = _sanitize(medico);

    return '^XA\n'
        '^CI28\n'
        '^PW$width\n'
        '^LL$height\n'
        '^FO20,20^A0N,28,28^FB$textWidth,2,0,L,0^FDNome: $nomeS^FS\n'
        '^FO20,100^A0N,24,24^FDCC: $ccS^FS\n'
        '^FO20,135^A0N,24,24^FDD/N: $dnS^FS\n'
        '^FO20,${height - 55}^A0N,26,26^FB$textWidth,1,0,L,0^FDDr(a). $medicoS^FS\n'
        '^XZ\n';
  }
}
