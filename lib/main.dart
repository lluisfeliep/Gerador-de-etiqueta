import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_label_service.dart';
import 'zpl_printer_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gerador de Etiquetas',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const LabelFormPage(),
    );
  }
}

class LabelFormPage extends StatefulWidget {
  const LabelFormPage({super.key});

  @override
  State<LabelFormPage> createState() => _LabelFormPageState();
}

class _LabelFormPageState extends State<LabelFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _ccController = TextEditingController();
  final _dnController = TextEditingController();
  final _medicoController = TextEditingController();

  List<String> _printers = [];
  String? _selectedPrinter;
  int _widthMm = 50;
  int _heightMm = 30;
  bool _loadingPrinters = true;
  bool _printing = false;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _ccController.dispose();
    _dnController.dispose();
    _medicoController.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    final printers = await ZplPrinterService.listPrinters();
    if (!mounted) return;
    setState(() {
      _printers = printers;
      _selectedPrinter = printers.firstWhere(
        (p) => p.toLowerCase().contains('zebra') || p.toLowerCase().contains('gc420'),
        orElse: () => printers.isNotEmpty ? printers.first : '',
      );
      if (_selectedPrinter!.isEmpty) _selectedPrinter = null;
      _loadingPrinters = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Data de nascimento',
    );
    if (picked != null) {
      final dd = picked.day.toString().padLeft(2, '0');
      final mm = picked.month.toString().padLeft(2, '0');
      _dnController.text = '$dd/$mm/${picked.year}';
    }
  }

  Future<void> _openSettings() async {
    final widthController = TextEditingController(text: _widthMm.toString());
    final heightController = TextEditingController(text: _heightMm.toString());
    String? tempPrinter = _selectedPrinter;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configurações da etiqueta'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _printers.contains(tempPrinter) ? tempPrinter : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Impressora'),
                  items: _printers
                      .map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => tempPrinter = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widthController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Largura (mm)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: heightController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Altura (mm)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _selectedPrinter = tempPrinter;
                  _widthMm = int.tryParse(widthController.text) ?? _widthMm;
                  _heightMm = int.tryParse(heightController.text) ?? _heightMm;
                });
                Navigator.of(context).pop();
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _imprimirNaZebra() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPrinter == null || _selectedPrinter!.isEmpty) {
      _showMessage('Nenhuma impressora selecionada. Abra as configurações para escolher uma.');
      return;
    }

    setState(() => _printing = true);
    try {
      final zpl = ZplPrinterService.buildPatientLabel(
        nome: _nomeController.text.trim(),
        cc: _ccController.text.trim(),
        dataNascimento: _dnController.text.trim(),
        medico: _medicoController.text.trim(),
        widthMm: _widthMm,
        heightMm: _heightMm,
      );
      await ZplPrinterService.printZpl(_selectedPrinter!, zpl);
      if (!mounted) return;
      _showMessage('Etiqueta enviada para a impressora Zebra.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Erro ao imprimir: $e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _gerarPdf() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _generatingPdf = true);
    try {
      await PdfLabelService.generateAndOpen(
        nome: _nomeController.text.trim(),
        cc: _ccController.text.trim(),
        dataNascimento: _dnController.text.trim(),
        medico: _medicoController.text.trim(),
        widthMm: _widthMm,
        heightMm: _heightMm,
      );
      if (!mounted) return;
      _showMessage('PDF gerado e aberto para impressão.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Erro ao gerar PDF: $e');
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerador de Etiquetas'),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loadingPrinters)
                    const LinearProgressIndicator()
                  else if (_printers.isEmpty)
                    const Text(
                      'Nenhuma impressora encontrada no Windows.',
                      style: TextStyle(color: Colors.red),
                    )
                  else
                    Text('Impressora: ${_selectedPrinter ?? "nenhuma selecionada"}'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do paciente',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome do paciente' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _ccController,
                    decoration: const InputDecoration(
                      labelText: 'CC (Cartão de Cidadão)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 7,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o CC' : null,
                  ),
                  TextFormField(
                    controller: _dnController,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: const InputDecoration(
                      labelText: 'D/N (Data de nascimento)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a data de nascimento' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _medicoController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do médico',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome do médico' : null,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _printing ? null : _imprimirNaZebra,
                          icon: _printing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.print),
                          label: Text(_printing ? 'Imprimindo...' : 'Imprimir na Zebra'),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _generatingPdf ? null : _gerarPdf,
                          icon: _generatingPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf),
                          label: Text(_generatingPdf ? 'Gerando...' : 'Gerar PDF'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
