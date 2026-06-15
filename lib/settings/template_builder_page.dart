import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../brand_config.dart';
import '../models/template_models.dart';
import '../services/asset_upload_service.dart';
import 'pdf_generator.dart';

// ─── Costanti foglio A4 (punti PDF) ──────────────────────────────────────────

const double kA4W = 595;
const double kA4H = 842;

/// Soglia magnetica in punti pagina.
const double _kSnapThreshold = 5;

// ─── Pagina builder ──────────────────────────────────────────────────────────

class TemplateBuilderPage extends StatefulWidget {
  const TemplateBuilderPage({
    super.key,
    required this.template,
    required this.userId,
    required this.onSave,
  });

  final DocumentTemplate template;
  final String userId;
  final Future<void> Function(DocumentTemplate) onSave;

  @override
  State<TemplateBuilderPage> createState() => _TemplateBuilderPageState();
}

class _TemplateBuilderPageState extends State<TemplateBuilderPage> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.template.name,
  );
  late String _category = widget.template.category;
  late List<TemplateElement> _elements = List.of(widget.template.elements);
  late List<TemplateCustomField> _customFields = List.of(
    widget.template.customFields,
  );
  late String? _backgroundImageUrl = widget.template.backgroundImageUrl;

  String? _selectedId;
  bool _saving = false;
  bool _previewLoading = false;
  bool _dirty = false;

  // Canvas / griglia
  bool _snapEnabled = true;
  bool _gridVisible = true;
  bool _sampleData = true;
  double _gridStep = 10;
  double _margin = 36; // ~12,7 mm
  double _zoom = 0; // 0 = adatta, altrimenti fattore (1.0, 1.25, 1.5)

  // Guide magnetiche attive durante il drag (coordinate pagina).
  double? _guideX;
  double? _guideY;

  // Stato drag corrente (posizioni "grezze" non snappate).
  Offset? _dragRawPos;
  Size? _dragRawSize;

  final FocusNode _canvasFocus = FocusNode();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  // ─── Selezione & mutazioni ─────────────────────────────────────────────────

  TemplateElement? get _selected => _selectedId == null
      ? null
      : _elements.where((e) => e.id == _selectedId).firstOrNull;

  void _mutate(VoidCallback fn) {
    setState(() {
      fn();
      _dirty = true;
    });
  }

  void _updateSelected(TemplateElement Function(TemplateElement) fn) {
    _mutate(() {
      _elements = _elements
          .map((e) => e.id == _selectedId ? fn(e) : e)
          .toList();
    });
  }

  String _newId() => 'el_${DateTime.now().microsecondsSinceEpoch}';

  void _addElement(
    String type, {
    String? variableKey,
    String? staticText,
    double? w,
    double? h,
    String? bgColorHex,
  }) {
    double width = w ?? 200, height = h ?? 22;
    if (w == null) {
      if (type == 'table') {
        width = kA4W - _margin * 2;
        height = 200;
      }
      if (type == 'image') {
        width = 120;
        height = 56;
      }
      if (type == 'rect') {
        width = 200;
        height = 40;
      }
    }
    final el = TemplateElement(
      id: _newId(),
      type: type,
      x: _margin,
      y: _margin,
      width: width,
      height: height,
      variableKey: variableKey,
      staticText: staticText ?? (type == 'static_text' ? 'Testo' : null),
      bgColorHex: bgColorHex,
      fontSize: type == 'table' ? 9 : 11,
    );
    _mutate(() {
      _elements.add(el);
      _selectedId = el.id;
    });
    _canvasFocus.requestFocus();
  }

  void _duplicateSelected() {
    final el = _selected;
    if (el == null) return;
    final copy = TemplateElement(
      id: _newId(),
      type: el.type,
      x: min(el.x + 12, kA4W - el.width),
      y: min(el.y + 12, kA4H - el.height),
      width: el.width,
      height: el.height,
      variableKey: el.variableKey,
      staticText: el.staticText,
      imageUrl: el.imageUrl,
      fontSize: el.fontSize,
      bold: el.bold,
      italic: el.italic,
      colorHex: el.colorHex,
      textAlign: el.textAlign,
      bgColorHex: el.bgColorHex,
      borderColorHex: el.borderColorHex,
      borderWidth: el.borderWidth,
      borderRadius: el.borderRadius,
    );
    _mutate(() {
      _elements.add(copy);
      _selectedId = copy.id;
    });
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    _mutate(() {
      _elements.removeWhere((e) => e.id == _selectedId);
      _selectedId = null;
    });
  }

  void _moveZ(int delta) {
    final index = _elements.indexWhere((e) => e.id == _selectedId);
    if (index < 0) return;
    final next = (index + delta).clamp(0, _elements.length - 1);
    if (next == index) return;
    _mutate(() {
      final el = _elements.removeAt(index);
      _elements.insert(next, el);
    });
  }

  void _nudgeSelected(double dx, double dy) {
    final el = _selected;
    if (el == null) return;
    _updateSelected(
      (e) => e.copyWith(
        x: (e.x + dx).clamp(0, kA4W - e.width),
        y: (e.y + dy).clamp(0, kA4H - e.height),
      ),
    );
  }

  // ─── Magnetismo ────────────────────────────────────────────────────────────

  /// Candidati verticali (valori X) e orizzontali (valori Y) a cui agganciarsi.
  List<double> get _vCandidates => [_margin, kA4W - _margin, kA4W / 2];
  List<double> get _hCandidates => [_margin, kA4H - _margin, kA4H / 2];

  /// Aggancia [value] (es. bordo sinistro) considerando anche il bordo opposto
  /// [value]+[extent]. Ritorna (valoreSnappato, guidaAttiva).
  (double, double?) _snapAxis(
    double value,
    double extent,
    List<double> candidates,
  ) {
    if (!_snapEnabled) return (value, null);
    double best = value;
    double? guide;
    double bestDist = _kSnapThreshold + 1;

    void consider(double target, double snappedStart) {
      final d1 = (value - target).abs();
      final d2 = (value + extent - target).abs();
      if (d1 < bestDist && d1 <= _kSnapThreshold) {
        bestDist = d1;
        best = target;
        guide = target;
      }
      if (d2 < bestDist && d2 <= _kSnapThreshold) {
        bestDist = d2;
        best = target - extent;
        guide = target;
      }
    }

    for (final c in candidates) {
      consider(c, c);
    }
    if (guide == null && _gridStep > 0) {
      final snapped = (value / _gridStep).round() * _gridStep;
      if ((snapped - value).abs() <= _kSnapThreshold) best = snapped;
    }
    return (best, guide);
  }

  // ─── Sfondo / salvataggio / anteprima ──────────────────────────────────────

  Future<void> _uploadElementImage(TemplateElement el) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      final url = await uploadAssetImage(
        bytes: bytes,
        filename: result.files.first.name,
        folder: 'template',
      );
      if (!mounted) return;
      _updateSelected((e) => e.copyWith(imageUrl: url));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento immagine: $error')),
      );
    }
  }

  Future<void> _uploadBackground() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      final url = await uploadAssetImage(
        bytes: bytes,
        filename: result.files.first.name,
        folder: 'template',
      );
      if (!mounted) return;
      _mutate(() => _backgroundImageUrl = url);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento sfondo: $error')),
      );
    }
  }

  DocumentTemplate get _currentTemplate => DocumentTemplate(
    id: widget.template.id,
    name: _nameCtrl.text.trim().isEmpty ? 'Template' : _nameCtrl.text.trim(),
    category: _category,
    backgroundImageUrl: _backgroundImageUrl,
    elements: _elements,
    customFields: _customFields,
  );

  Future<void> _save({bool close = false}) async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_currentTemplate);
      _dirty = false;
      if (!mounted) return;
      if (close) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Template salvato.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifiche non salvate'),
        content: const Text(
          'Hai modifiche non salvate. Vuoi salvarle prima di uscire?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Esci senza salvare'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop(false);
              await _save(close: true);
            },
            child: const Text('Salva ed esci'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _preview() async {
    setState(() => _previewLoading = true);
    try {
      final data = _buildSampleData();
      await prefetchTemplateAssets(_currentTemplate, data);
      final bytes = await generatePdf(_currentTemplate, data);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PdfPreviewPage(bytes: bytes, name: _nameCtrl.text),
        ),
      );
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Map<String, dynamic> _buildSampleData() => {
    'emittente': {
      'nome': 'Gussoni Consulenze SRL',
      'piva': 'IT01234567890',
      'cf': 'ABCDEF12G34H567I',
      'indirizzo': 'Via Roma 1',
      'cap': '20100',
      'comune': 'Milano',
      'email': 'info@gussoniconsulenze.it',
      'pec': 'pec@gussoniconsulenze.it',
      'telefono': '+39 02 1234567',
    },
    'cliente': {
      'nome': 'Cliente Demo SRL',
      'piva': 'IT09876543210',
      'cf': 'ZZZYYW88X99Z000A',
      'indirizzo': 'Via Verdi 10',
      'cap': '00100',
      'comune': 'Roma',
      'email': 'cliente@email.it',
    },
    'documento': {
      'numero': _category == kFattura ? 'FT-2026-014' : 'PRV-2026-021',
      'data': '11/06/2026',
      'validita': '30 giorni',
      'scadenza': '11/07/2026',
      'totale': '€ 4.880,00',
      'pagamento': 'Bonifico bancario 30 gg d.f.',
      'iban': 'IT60 X054 2811 1010 0000 0123 456',
      'note': 'Nota di esempio sul documento.',
    },
    'righe': [
      {
        'descrizione': 'Analisi del bisogno e istruttoria bando',
        'qta': '1',
        'prezzo': '1.800,00',
        'totale': '1.800,00',
      },
      {
        'descrizione': 'Redazione business plan',
        'qta': '1',
        'prezzo': '2.200,00',
        'totale': '2.200,00',
      },
      {
        'descrizione': 'Rendicontazione (acconto)',
        'qta': '2',
        'prezzo': '440,00',
        'totale': '880,00',
      },
    ],
    'custom': {for (final f in _customFields) f.key: '[${f.label}]'},
  };

  // ─── Layout di partenza brand Gussoni ──────────────────────────────────────

  Future<void> _applyStarterLayout() async {
    if (_elements.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Applicare il layout di base?'),
          content: const Text(
            'Gli elementi attuali verranno sostituiti dal layout di base Gussoni.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sostituisci'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _mutate(() {
      _elements = _starterElements(_category, _margin);
      _selectedId = null;
    });
  }

  List<TemplateElement> _starterElements(String category, double m) {
    const bordeaux = '#5B1205';
    const charcoal = '#1C1D1F';
    const muted = '#8C8478';
    const hairline = '#E9E5DF';
    final contentW = kA4W - m * 2;
    final isFattura = category == kFattura;
    var i = 0;
    String id() => 'st_${DateTime.now().microsecondsSinceEpoch}_${i++}';

    TemplateElement text(
      double x,
      double y,
      double w,
      double h,
      String key, {
      bool variable = true,
      String? value,
      double size = 10,
      bool bold = false,
      String color = charcoal,
      String align = 'left',
    }) => TemplateElement(
      id: id(),
      type: variable ? 'variable' : 'static_text',
      x: x,
      y: y,
      width: w,
      height: h,
      variableKey: variable ? key : null,
      staticText: variable ? null : (value ?? key),
      fontSize: size,
      bold: bold,
      colorHex: color,
      textAlign: align,
    );

    return [
      // Logo + emittente
      TemplateElement(
        id: id(),
        type: 'image',
        x: m,
        y: m,
        width: 130,
        height: 48,
        variableKey: 'logo',
      ),
      text(
        kA4W - m - 240,
        m,
        240,
        14,
        'emittente.nome',
        size: 11,
        bold: true,
        align: 'right',
      ),
      text(
        kA4W - m - 240,
        m + 15,
        240,
        12,
        'emittente.indirizzo',
        size: 8.5,
        color: muted,
        align: 'right',
      ),
      text(
        kA4W - m - 240,
        m + 27,
        240,
        12,
        'emittente.comune',
        size: 8.5,
        color: muted,
        align: 'right',
      ),
      text(
        kA4W - m - 240,
        m + 39,
        240,
        12,
        'emittente.piva',
        size: 8.5,
        color: muted,
        align: 'right',
      ),
      text(
        kA4W - m - 240,
        m + 51,
        240,
        12,
        'emittente.email',
        size: 8.5,
        color: muted,
        align: 'right',
      ),

      // Titolo
      text(
        m,
        m + 84,
        300,
        30,
        isFattura ? 'FATTURA' : 'PREVENTIVO',
        variable: false,
        size: 24,
        bold: true,
        color: bordeaux,
      ),
      TemplateElement(
        id: id(),
        type: 'rect',
        x: m,
        y: m + 118,
        width: contentW,
        height: 2,
        bgColorHex: bordeaux,
      ),

      // Cliente
      text(
        m,
        m + 136,
        120,
        12,
        'Spett.le',
        variable: false,
        size: 8.5,
        color: muted,
      ),
      text(m, m + 149, 280, 15, 'cliente.nome', size: 12, bold: true),
      text(m, m + 165, 280, 12, 'cliente.indirizzo', size: 9, color: muted),
      text(m, m + 178, 280, 12, 'cliente.comune', size: 9, color: muted),
      text(m, m + 191, 280, 12, 'cliente.piva', size: 9, color: muted),

      // Meta documento (destra)
      text(
        kA4W - m - 180,
        m + 136,
        90,
        12,
        'Numero',
        variable: false,
        size: 8.5,
        color: muted,
      ),
      text(
        kA4W - m - 90,
        m + 136,
        90,
        12,
        'documento.numero',
        size: 9.5,
        bold: true,
        align: 'right',
      ),
      text(
        kA4W - m - 180,
        m + 152,
        90,
        12,
        'Data',
        variable: false,
        size: 8.5,
        color: muted,
      ),
      text(
        kA4W - m - 90,
        m + 152,
        90,
        12,
        'documento.data',
        size: 9.5,
        align: 'right',
      ),
      text(
        kA4W - m - 180,
        m + 168,
        90,
        12,
        isFattura ? 'Scadenza' : 'Validità',
        variable: false,
        size: 8.5,
        color: muted,
      ),
      text(
        kA4W - m - 90,
        m + 168,
        90,
        12,
        isFattura ? 'documento.scadenza' : 'documento.validita',
        size: 9.5,
        align: 'right',
      ),

      // Tabella righe
      TemplateElement(
        id: id(),
        type: 'table',
        x: m,
        y: m + 224,
        width: contentW,
        height: 300,
        variableKey: 'righe',
        fontSize: 9,
        colorHex: charcoal,
        bgColorHex: '#F0EDE8',
        borderColorHex: hairline,
        borderWidth: .5,
      ),

      // Totale
      text(
        kA4W - m - 220,
        m + 540,
        120,
        18,
        'Totale',
        variable: false,
        size: 11,
        bold: true,
        align: 'right',
      ),
      text(
        kA4W - m - 100,
        m + 538,
        100,
        20,
        'documento.totale',
        size: 14,
        bold: true,
        color: bordeaux,
        align: 'right',
      ),

      // Note
      text(
        m,
        m + 580,
        120,
        12,
        'Note',
        variable: false,
        size: 8.5,
        color: muted,
        bold: true,
      ),
      text(m, m + 593, contentW, 40, 'documento.note', size: 9),

      // Footer
      TemplateElement(
        id: id(),
        type: 'rect',
        x: m,
        y: kA4H - m - 42,
        width: contentW,
        height: 1,
        bgColorHex: hairline,
      ),
      text(
        m,
        kA4H - m - 34,
        300,
        12,
        'documento.pagamento',
        size: 8.5,
        color: muted,
      ),
      text(
        m,
        kA4H - m - 21,
        300,
        12,
        'documento.iban',
        size: 8.5,
        color: muted,
      ),
      text(
        kA4W - m - 240,
        kA4H - m - 34,
        240,
        12,
        'emittente.pec',
        size: 8.5,
        color: muted,
        align: 'right',
      ),
      text(
        kA4W - m - 240,
        kA4H - m - 21,
        240,
        12,
        'emittente.telefono',
        size: 8.5,
        color: muted,
        align: 'right',
      ),
    ];
  }

  // ─── Tastiera ──────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_selected == null) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final step = shift ? 10.0 : 1.0;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _nudgeSelected(-step, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _nudgeSelected(step, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _nudgeSelected(0, -step);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _nudgeSelected(0, step);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _deleteSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
        if (meta) {
          _duplicateSelected();
          return KeyEventResult.handled;
        }
    }
    return KeyEventResult.ignored;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: GussoniBrand.scaffoldBg,
        appBar: AppBar(
          backgroundColor: GussoniBrand.surface,
          elevation: 0,
          titleSpacing: 0,
          shape: const Border(bottom: BorderSide(color: GussoniBrand.border)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: GussoniBrand.textPrimary),
            onPressed: () async {
              if (await _confirmLeave() && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Row(
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => _dirty = true,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'Nome template',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: kPreventivo, label: Text('Preventivo')),
                  ButtonSegment(value: kFattura, label: Text('Fattura')),
                ],
                selected: {_category},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (s) => _mutate(() => _category = s.first),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _applyStarterLayout,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
              label: const Text('Layout di base'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _previewLoading ? null : _preview,
              icon: _previewLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 17),
              label: const Text('Anteprima PDF'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : () => _save(),
              child: Text(_saving ? 'Salvataggio…' : 'Salva'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLeftPanel(),
            Expanded(
              child: Column(
                children: [
                  _buildCanvasToolbar(),
                  Expanded(child: _buildCanvas()),
                ],
              ),
            ),
            _buildRightPanel(),
          ],
        ),
      ),
    );
  }

  // ─── Pannello sinistro ─────────────────────────────────────────────────────

  Widget _buildLeftPanel() {
    return Container(
      width: 210,
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(right: BorderSide(color: GussoniBrand.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('Aggiungi elemento'),
          _addBtn(
            Icons.text_fields_outlined,
            'Testo',
            () => _addElement('static_text'),
          ),
          _addBtn(Icons.data_object_rounded, 'Variabile', _showVariablePicker),
          _addBtn(
            Icons.table_chart_outlined,
            'Tabella righe',
            () => _addElement('table', variableKey: 'righe'),
          ),
          _addBtn(
            Icons.image_outlined,
            'Logo',
            () => _addElement('image', variableKey: 'logo'),
          ),
          _addBtn(
            Icons.rectangle_outlined,
            'Riquadro',
            () => _addElement('rect'),
          ),
          _addBtn(
            Icons.horizontal_rule_rounded,
            'Linea',
            () => _addElement('rect', w: 200, h: 2, bgColorHex: '#5B1205'),
          ),
          const Divider(height: 16, color: GussoniBrand.borderSubtle),
          _panelHeader('Sfondo pagina'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadBackground,
                    icon: const Icon(Icons.upload_outlined, size: 15),
                    label: const Text('Carica', style: TextStyle(fontSize: 12)),
                  ),
                ),
                if (_backgroundImageUrl != null)
                  IconButton(
                    tooltip: 'Rimuovi sfondo',
                    onPressed: () => _mutate(() => _backgroundImageUrl = null),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 17,
                      color: GussoniBrand.error,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 16, color: GussoniBrand.borderSubtle),
          _panelHeader('Livelli (alto = sopra)'),
          Expanded(
            child: _elements.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nessun elemento.\nUsa "Layout di base" per partire dal modello Gussoni.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: GussoniBrand.textMuted,
                        height: 1.4,
                      ),
                    ),
                  )
                : ReorderableListView(
                    buildDefaultDragHandles: true,
                    onReorder: (o, n) {
                      // La lista mostra l'ordine invertito (primo = sopra).
                      final from = _elements.length - 1 - o;
                      var to = _elements.length - 1 - n;
                      if (n > o) to += 1;
                      _mutate(() {
                        final el = _elements.removeAt(from);
                        _elements.insert(to.clamp(0, _elements.length), el);
                      });
                    },
                    children: _elements.reversed.map((el) {
                      final selected = el.id == _selectedId;
                      return Material(
                        key: ValueKey(el.id),
                        color: selected
                            ? GussoniBrand.primaryBg
                            : Colors.transparent,
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            el.displayLabel.isEmpty
                                ? '(vuoto)'
                                : el.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? GussoniBrand.primary
                                  : GussoniBrand.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            _typeLabel(el.type),
                            style: const TextStyle(
                              fontSize: 10,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                          onTap: () => setState(() => _selectedId = el.id),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
    'variable' => 'Variabile',
    'static_text' => 'Testo',
    'image' => 'Immagine',
    'table' => 'Tabella',
    'rect' => 'Riquadro',
    _ => type,
  };

  Widget _panelHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: GussoniBrand.textMuted,
        letterSpacing: .8,
      ),
    ),
  );

  Widget _addBtn(IconData icon, String label, VoidCallback onTap) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: Icon(icon, size: 17, color: GussoniBrand.primary),
    title: Text(label, style: const TextStyle(fontSize: 12.5)),
    onTap: onTap,
  );

  void _showVariablePicker() {
    final allVars = [
      ...kStandardVariables.where((v) => v.key != 'righe' && v.key != 'logo'),
      ..._customFields.map(
        (f) => TemplateVariable(
          key: 'custom.${f.key}',
          label: f.label,
          group: 'Campi personalizzati',
        ),
      ),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final groups = allVars.map((v) => v.group).toSet().toList();
        return AlertDialog(
          title: const Text('Inserisci variabile'),
          content: SizedBox(
            width: 360,
            height: 440,
            child: ListView(
              children: groups
                  .map(
                    (g) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                          child: Text(
                            g.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: GussoniBrand.textMuted,
                              letterSpacing: .8,
                            ),
                          ),
                        ),
                        ...allVars
                            .where((v) => v.group == g)
                            .map(
                              (v) => ListTile(
                                dense: true,
                                title: Text(
                                  v.label,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '{{${v.key}}}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: GussoniBrand.textMuted,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _addElement('variable', variableKey: v.key);
                                },
                              ),
                            ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annulla'),
            ),
          ],
        );
      },
    );
  }

  // ─── Toolbar canvas ────────────────────────────────────────────────────────

  Widget _buildCanvasToolbar() {
    Widget toggle(
      IconData icon,
      String tooltip,
      bool active,
      VoidCallback onTap,
    ) => Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active ? GussoniBrand.primaryBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 17,
            color: active ? GussoniBrand.primary : GussoniBrand.textMuted,
          ),
        ),
      ),
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(bottom: BorderSide(color: GussoniBrand.border)),
      ),
      child: Row(
        children: [
          toggle(
            Icons.attractions_rounded,
            'Magnetismo (griglia e margini)',
            _snapEnabled,
            () => setState(() => _snapEnabled = !_snapEnabled),
          ),
          const SizedBox(width: 4),
          toggle(
            Icons.grid_4x4_rounded,
            'Mostra griglia',
            _gridVisible,
            () => setState(() => _gridVisible = !_gridVisible),
          ),
          const SizedBox(width: 4),
          toggle(
            Icons.visibility_outlined,
            'Dati di esempio',
            _sampleData,
            () => setState(() => _sampleData = !_sampleData),
          ),
          const SizedBox(width: 14),
          const Text(
            'Griglia',
            style: TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
          ),
          const SizedBox(width: 6),
          DropdownButton<double>(
            value: _gridStep,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(
              fontSize: 12,
              color: GussoniBrand.textPrimary,
            ),
            items: const [
              DropdownMenuItem(value: 5.0, child: Text('5 pt')),
              DropdownMenuItem(value: 10.0, child: Text('10 pt')),
              DropdownMenuItem(value: 20.0, child: Text('20 pt')),
            ],
            onChanged: (v) => setState(() => _gridStep = v ?? 10),
          ),
          const SizedBox(width: 14),
          const Text(
            'Margini',
            style: TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
          ),
          const SizedBox(width: 6),
          DropdownButton<double>(
            value: _margin,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(
              fontSize: 12,
              color: GussoniBrand.textPrimary,
            ),
            items: const [
              DropdownMenuItem(value: 24.0, child: Text('8,5 mm')),
              DropdownMenuItem(value: 36.0, child: Text('12,7 mm')),
              DropdownMenuItem(value: 48.0, child: Text('17 mm')),
              DropdownMenuItem(value: 57.0, child: Text('20 mm')),
            ],
            onChanged: (v) => setState(() => _margin = v ?? 36),
          ),
          const Spacer(),
          const Text(
            'Zoom',
            style: TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
          ),
          const SizedBox(width: 6),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Adatta')),
              ButtonSegment(value: 1.0, label: Text('100%')),
              ButtonSegment(value: 1.5, label: Text('150%')),
            ],
            selected: {_zoom},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (s) => setState(() => _zoom = s.first),
          ),
        ],
      ),
    );
  }

  // ─── Canvas ────────────────────────────────────────────────────────────────

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitScale = min(
          (constraints.maxWidth - 48) / kA4W,
          (constraints.maxHeight - 48) / kA4H,
        );
        final scale = _zoom == 0 ? fitScale : fitScale * _zoom;
        final canvasW = kA4W * scale;
        final canvasH = kA4H * scale;

        final page = Focus(
          focusNode: _canvasFocus,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onTap: () {
              _canvasFocus.requestFocus();
              setState(() => _selectedId = null);
            },
            child: Container(
              width: canvasW,
              height: canvasH,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  if (_backgroundImageUrl != null)
                    Positioned.fill(
                      child: Image.network(
                        _backgroundImageUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  // Griglia + margini
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GridPainter(
                          scale: scale,
                          gridStep: _gridStep,
                          margin: _margin,
                          showGrid: _gridVisible,
                          guideX: _guideX,
                          guideY: _guideY,
                        ),
                      ),
                    ),
                  ),
                  ..._elements.map((el) => _buildElementOnCanvas(el, scale)),
                  if (_elements.isEmpty) _buildEmptyCanvasHint(),
                ],
              ),
            ),
          ),
        );

        // A zoom "Adatta" il foglio entra nello schermo: niente scroll, così
        // il drag degli elementi non compete mai con lo scorrimento.
        final physics = _zoom == 0
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics();
        return Container(
          color: GussoniBrand.surfaceMuted,
          alignment: Alignment.center,
          child: SingleChildScrollView(
            physics: physics,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              physics: physics,
              scrollDirection: Axis.horizontal,
              child: Padding(padding: const EdgeInsets.all(24), child: page),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyCanvasHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: GussoniBrand.scaffoldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GussoniBrand.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_fix_high_outlined,
              size: 28,
              color: GussoniBrand.primary,
            ),
            const SizedBox(height: 10),
            const Text(
              'Foglio vuoto',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GussoniBrand.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Parti dal layout di base Gussoni e personalizzalo, '
              'oppure aggiungi elementi dal pannello a sinistra.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: GussoniBrand.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _applyStarterLayout,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
              label: const Text('Layout di base'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementOnCanvas(TemplateElement el, double scale) {
    final selected = el.id == _selectedId;
    final color = hexToColor(el.colorHex) ?? GussoniBrand.textPrimary;
    final sample = _buildSampleData();

    Widget child;
    switch (el.type) {
      case 'image':
        final url = el.imageUrl;
        child = url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: GussoniBrand.textMuted,
                  ),
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: GussoniBrand.surfaceSubtle,
                  border: Border.all(color: GussoniBrand.border),
                ),
                child: Center(
                  child: Text(
                    el.variableKey == 'logo' ? 'LOGO' : 'IMMAGINE',
                    style: TextStyle(
                      fontSize: 10 * scale + 4,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ),
              );
        break;
      case 'table':
        final headerBg =
            hexToColor(el.bgColorHex ?? '') ?? GussoniBrand.surfaceSubtle;
        final borderColor =
            hexToColor(el.borderColorHex ?? '') ?? GussoniBrand.border;
        final fs = el.fontSize * scale;
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: headerBg,
              padding: EdgeInsets.symmetric(
                horizontal: 4 * scale,
                vertical: 3 * scale,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Descrizione',
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Qtà',
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Prezzo',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Totale',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...(sample['righe'] as List)
                .take(4)
                .map(
                  (r) => Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4 * scale,
                      vertical: 2.5 * scale,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: borderColor, width: .5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            (r as Map)['descrizione'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: fs, color: color),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r['qta'] as String,
                            style: TextStyle(fontSize: fs, color: color),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            r['prezzo'] as String,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: fs, color: color),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            r['totale'] as String,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: fs, color: color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
        break;
      case 'rect':
        child = const SizedBox.shrink();
        break;
      default:
        final String text;
        if (el.type == 'variable') {
          text = _sampleData
              ? _resolveSample(el.variableKey ?? '', sample)
              : '{{${el.variableKey ?? ''}}}';
        } else {
          text = el.staticText ?? '';
        }
        child = Text(
          text,
          textAlign: _textAlign(el.textAlign),
          style: TextStyle(
            fontSize: el.fontSize * scale,
            height: 1.18,
            fontWeight: el.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: el.italic ? FontStyle.italic : FontStyle.normal,
            color: color,
          ),
          overflow: TextOverflow.clip,
        );
        if (el.textAlign != 'left') {
          child = SizedBox(width: double.infinity, child: child);
        }
    }

    return Positioned(
      left: el.x * scale,
      top: el.y * scale,
      width: el.width * scale,
      height: el.height * scale,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _canvasFocus.requestFocus();
            setState(() => _selectedId = el.id);
          },
          onPanStart: (_) {
            _canvasFocus.requestFocus();
            setState(() {
              _selectedId = el.id;
              _dragRawPos = Offset(el.x, el.y);
            });
          },
          onPanUpdate: (details) {
            final raw =
                (_dragRawPos ?? Offset(el.x, el.y)) + details.delta / scale;
            _dragRawPos = raw;
            final (sx, gx) = _snapAxis(raw.dx, el.width, _vCandidates);
            final (sy, gy) = _snapAxis(raw.dy, el.height, _hCandidates);
            _guideX = gx;
            _guideY = gy;
            _updateSelected(
              (e) => e.copyWith(
                x: sx.clamp(0, kA4W - e.width),
                y: sy.clamp(0, kA4H - e.height),
              ),
            );
          },
          onPanEnd: (_) => setState(() {
            _dragRawPos = null;
            _guideX = null;
            _guideY = null;
          }),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: el.bgColorHex != null
                        ? hexToColor(el.bgColorHex!)
                        : null,
                    border: selected
                        ? Border.all(color: GussoniBrand.primary, width: 1.4)
                        : (el.borderWidth > 0 && el.borderColorHex != null
                              ? Border.all(
                                  color:
                                      hexToColor(el.borderColorHex!) ??
                                      GussoniBrand.border,
                                  width: max(el.borderWidth * scale, .5),
                                )
                              : null),
                    borderRadius: el.borderRadius > 0
                        ? BorderRadius.circular(el.borderRadius * scale)
                        : null,
                  ),
                  child: ClipRect(child: child),
                ),
              ),
              if (selected) ...[
                // Maniglia ridimensionamento
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      onPanStart: (_) =>
                          _dragRawSize = Size(el.width, el.height),
                      onPanUpdate: (d) {
                        final raw = Size(
                          (_dragRawSize?.width ?? el.width) +
                              d.delta.dx / scale,
                          (_dragRawSize?.height ?? el.height) +
                              d.delta.dy / scale,
                        );
                        _dragRawSize = raw;
                        var w = max(14.0, raw.width);
                        var h = max(8.0, raw.height);
                        if (_snapEnabled) {
                          final (rx, gx) = _snapAxis(el.x + w, 0, _vCandidates);
                          if (gx != null) w = rx - el.x;
                          final (ry, gy) = _snapAxis(el.y + h, 0, _hCandidates);
                          if (gy != null) h = ry - el.y;
                          _guideX = gx;
                          _guideY = gy;
                        }
                        _updateSelected(
                          (e) => e.copyWith(
                            width: min(w, kA4W - e.x),
                            height: min(h, kA4H - e.y),
                          ),
                        );
                      },
                      onPanEnd: (_) => setState(() {
                        _dragRawSize = null;
                        _guideX = null;
                        _guideY = null;
                      }),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: GussoniBrand.primary,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                // Badge dimensioni durante il drag
                if (_dragRawPos != null || _dragRawSize != null)
                  Positioned(
                    left: 0,
                    top: -22,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: GussoniBrand.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${el.x.round()}, ${el.y.round()}  ·  '
                        '${el.width.round()}×${el.height.round()}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _resolveSample(String key, Map<String, dynamic> data) {
    if (key.startsWith('custom.')) {
      final custom = data['custom'] as Map<String, dynamic>?;
      return custom?[key.substring(7)]?.toString() ?? '';
    }
    return resolveVar(key, data);
  }

  // ─── Pannello destro: proprietà ────────────────────────────────────────────

  Widget _buildRightPanel() {
    return Container(
      width: 252,
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(left: BorderSide(color: GussoniBrand.border)),
      ),
      child: _selected == null
          ? _buildCustomFieldsPanel()
          : _buildPropsPanel(_selected!),
    );
  }

  Widget _buildPropsPanel(TemplateElement el) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                el.displayLabel.isEmpty ? _typeLabel(el.type) : el.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Duplica (⌘D)',
              onPressed: _duplicateSelected,
              icon: const Icon(
                Icons.copy_rounded,
                size: 16,
                color: GussoniBrand.textSecondary,
              ),
            ),
            IconButton(
              tooltip: 'Porta sopra',
              onPressed: () => _moveZ(1),
              icon: const Icon(
                Icons.flip_to_front_rounded,
                size: 16,
                color: GussoniBrand.textSecondary,
              ),
            ),
            IconButton(
              tooltip: 'Porta sotto',
              onPressed: () => _moveZ(-1),
              icon: const Icon(
                Icons.flip_to_back_rounded,
                size: 16,
                color: GussoniBrand.textSecondary,
              ),
            ),
            IconButton(
              tooltip: 'Elimina (Canc)',
              onPressed: _deleteSelected,
              icon: const Icon(
                Icons.delete_outline,
                size: 17,
                color: GussoniBrand.error,
              ),
            ),
          ],
        ),
        const Divider(height: 16, color: GussoniBrand.borderSubtle),
        _propLabel('Posizione (pt)'),
        Row(
          children: [
            _propNumField(
              'X',
              el.x,
              (v) => _updateSelected((e) => e.copyWith(x: v)),
            ),
            const SizedBox(width: 8),
            _propNumField(
              'Y',
              el.y,
              (v) => _updateSelected((e) => e.copyWith(y: v)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _propLabel('Dimensioni (pt)'),
        Row(
          children: [
            _propNumField(
              'L',
              el.width,
              (v) => _updateSelected((e) => e.copyWith(width: v)),
            ),
            const SizedBox(width: 8),
            _propNumField(
              'H',
              el.height,
              (v) => _updateSelected((e) => e.copyWith(height: v)),
            ),
          ],
        ),
        if (el.type == 'image') ...[
          const SizedBox(height: 10),
          _propLabel('Immagine'),
          if (el.imageUrl == null || el.imageUrl!.isEmpty)
            Text(
              el.variableKey == 'logo'
                  ? 'Senza immagine caricata, in PDF viene usato il logo di '
                        'Impostazioni → Branding.'
                  : 'Nessuna immagine: carica un file per mostrarla nel PDF.',
              style: const TextStyle(
                fontSize: 11,
                color: GussoniBrand.textMuted,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _uploadElementImage(el),
                  icon: const Icon(Icons.upload_outlined, size: 15),
                  label: Text(
                    el.imageUrl == null || el.imageUrl!.isEmpty
                        ? 'Carica immagine'
                        : 'Sostituisci',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (el.imageUrl != null && el.imageUrl!.isNotEmpty)
                IconButton(
                  tooltip: 'Rimuovi immagine',
                  onPressed: () =>
                      _updateSelected((e) => e.copyWith(imageUrl: '')),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 17,
                    color: GussoniBrand.error,
                  ),
                ),
            ],
          ),
        ],
        if (el.type == 'static_text') ...[
          const SizedBox(height: 10),
          _propLabel('Testo'),
          TextFormField(
            key: ValueKey('txt-${el.id}'),
            initialValue: el.staticText ?? '',
            onChanged: (v) => _updateSelected((e) => e.copyWith(staticText: v)),
            maxLines: 3,
            style: const TextStyle(fontSize: 13),
          ),
        ],
        if (el.type != 'rect' && el.type != 'image') ...[
          const SizedBox(height: 10),
          _propLabel('Carattere'),
          Row(
            children: [
              _propNumField(
                'pt',
                el.fontSize,
                (v) => _updateSelected((e) => e.copyWith(fontSize: v)),
              ),
              const SizedBox(width: 8),
              _propToggle(
                'B',
                el.bold,
                (v) => _updateSelected((e) => e.copyWith(bold: v)),
              ),
              const SizedBox(width: 4),
              _propToggle(
                'I',
                el.italic,
                (v) => _updateSelected((e) => e.copyWith(italic: v)),
              ),
            ],
          ),
          if (el.type != 'table') ...[
            const SizedBox(height: 10),
            _propLabel('Allineamento'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'left',
                  icon: Icon(Icons.format_align_left, size: 14),
                ),
                ButtonSegment(
                  value: 'center',
                  icon: Icon(Icons.format_align_center, size: 14),
                ),
                ButtonSegment(
                  value: 'right',
                  icon: Icon(Icons.format_align_right, size: 14),
                ),
              ],
              selected: {el.textAlign},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  _updateSelected((e) => e.copyWith(textAlign: s.first)),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _propLabel('Colore testo'),
          _colorField(
            el.colorHex,
            (v) => _updateSelected((e) => e.copyWith(colorHex: v)),
          ),
        ],
        const SizedBox(height: 10),
        _propLabel(el.type == 'table' ? 'Sfondo intestazione' : 'Sfondo'),
        _colorFieldNullable(
          el.bgColorHex,
          (v) => _updateSelected((e) => e.copyWith(bgColorHex: v)),
        ),
        const SizedBox(height: 10),
        _propLabel('Bordo'),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _colorFieldNullable(
                el.borderColorHex,
                (v) => _updateSelected((e) => e.copyWith(borderColorHex: v)),
              ),
            ),
            const SizedBox(width: 8),
            _propNumField(
              'pt',
              el.borderWidth,
              (v) => _updateSelected((e) => e.copyWith(borderWidth: v)),
            ),
          ],
        ),
        if (el.type == 'rect') ...[
          const SizedBox(height: 10),
          _propLabel('Arrotondamento'),
          Row(
            children: [
              _propNumField(
                'pt',
                el.borderRadius,
                (v) => _updateSelected((e) => e.copyWith(borderRadius: v)),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => setState(() => _selectedId = null),
          icon: const Icon(Icons.tune_rounded, size: 15),
          label: const Text('Campi personalizzati'),
        ),
      ],
    );
  }

  Widget _propLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: GussoniBrand.textMuted,
      ),
    ),
  );

  Widget _propNumField(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) => Expanded(
    child: TextFormField(
      key: ValueKey('$label-$_selectedId-${value.toStringAsFixed(1)}'),
      initialValue: value.toStringAsFixed(
        value == value.roundToDouble() ? 0 : 1,
      ),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      style: const TextStyle(fontSize: 12.5),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onFieldSubmitted: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null) onChanged(parsed);
      },
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null) onChanged(parsed);
      },
    ),
  );

  Widget _propToggle(String label, bool value, ValueChanged<bool> onChanged) =>
      InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? GussoniBrand.primary : GussoniBrand.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value ? GussoniBrand.primary : GussoniBrand.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: value ? Colors.white : GussoniBrand.textMuted,
              fontStyle: label == 'I' ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      );

  // ─── Colori ────────────────────────────────────────────────────────────────

  static const List<String> _brandSwatches = [
    '#5B1205',
    '#8B1A1A',
    '#B08948',
    '#D2B48C',
    '#1C1D1F',
    '#54595F',
    '#8C8478',
    '#E9E5DF',
    '#F0EDE8',
    '#FFFFFF',
    '#2E7D4F',
    '#A8332C',
  ];

  Widget _colorField(String hex, ValueChanged<String> onChanged) {
    final color = hexToColor(hex) ?? GussoniBrand.textPrimary;
    return InkWell(
      onTap: () => _pickColor(hex, onChanged),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: GussoniBrand.border),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hex.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _colorFieldNullable(String? hex, ValueChanged<String?> onChanged) {
    return Row(
      children: [
        InkWell(
          onTap: () => _pickColor(hex ?? '#FFFFFF', (v) => onChanged(v)),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: hex != null ? hexToColor(hex) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: GussoniBrand.border),
            ),
            child: hex == null
                ? const Icon(
                    Icons.block,
                    size: 14,
                    color: GussoniBrand.textMuted,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hex?.toUpperCase() ?? 'Nessuno',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (hex != null)
          InkWell(
            onTap: () => onChanged(null),
            child: const Icon(
              Icons.close,
              size: 15,
              color: GussoniBrand.textMuted,
            ),
          ),
      ],
    );
  }

  Future<void> _pickColor(
    String current,
    ValueChanged<String> onChanged,
  ) async {
    final ctrl = TextEditingController(text: current);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colore'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _brandSwatches
                    .map(
                      (hex) => InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onChanged(hex);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hexToColor(hex),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: GussoniBrand.border),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'HEX personalizzato',
                  hintText: '#5B1205',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onChanged(ctrl.text.trim());
            },
            child: const Text('Applica'),
          ),
        ],
      ),
    );
  }

  // ─── Campi personalizzati ──────────────────────────────────────────────────

  Widget _buildCustomFieldsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 6, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Campi personalizzati',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  size: 20,
                  color: GussoniBrand.primary,
                ),
                onPressed: _addCustomField,
                tooltip: 'Aggiungi campo',
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Variabili extra da compilare alla generazione del documento. '
            'Seleziona un elemento sul foglio per modificarne le proprietà.',
            style: TextStyle(
              fontSize: 11,
              color: GussoniBrand.textMuted,
              height: 1.4,
            ),
          ),
        ),
        Expanded(
          child: _customFields.isEmpty
              ? const Center(
                  child: Text(
                    'Nessun campo personalizzato',
                    style: TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _customFields.length,
                  itemBuilder: (_, i) {
                    final f = _customFields[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: GussoniBrand.scaffoldBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: GussoniBrand.borderSubtle),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          f.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '{{custom.${f.key}}} · ${f.inputType}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: GussoniBrand.textMuted,
                          ),
                          onPressed: () =>
                              _mutate(() => _customFields.removeAt(i)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addCustomField() async {
    final labelCtrl = TextEditingController();
    var inputType = 'text';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Nuovo campo personalizzato'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome campo (es. Oggetto della fornitura)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: inputType,
                decoration: const InputDecoration(labelText: 'Tipo input'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Testo breve')),
                  DropdownMenuItem(
                    value: 'textarea',
                    child: Text('Testo lungo'),
                  ),
                  DropdownMenuItem(value: 'number', child: Text('Numero')),
                ],
                onChanged: (v) => setSt(() => inputType = v ?? 'text'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                final key = label
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                    .replaceAll(RegExp(r'^_+|_+$'), '');
                Navigator.of(ctx).pop();
                _mutate(
                  () => _customFields.add(
                    TemplateCustomField(
                      key: key,
                      label: label,
                      inputType: inputType,
                    ),
                  ),
                );
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  TextAlign _textAlign(String a) => switch (a) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    _ => TextAlign.left,
  };
}

// ─── Painter griglia + margini + guide ───────────────────────────────────────

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.scale,
    required this.gridStep,
    required this.margin,
    required this.showGrid,
    this.guideX,
    this.guideY,
  });

  final double scale;
  final double gridStep;
  final double margin;
  final bool showGrid;
  final double? guideX;
  final double? guideY;

  @override
  void paint(Canvas canvas, Size size) {
    // Griglia
    if (showGrid && gridStep > 0) {
      final gridPaint = Paint()
        ..color = const Color(0x141C1D1F)
        ..strokeWidth = .5;
      for (double x = 0; x <= kA4W; x += gridStep) {
        canvas.drawLine(
          Offset(x * scale, 0),
          Offset(x * scale, size.height),
          gridPaint,
        );
      }
      for (double y = 0; y <= kA4H; y += gridStep) {
        canvas.drawLine(
          Offset(0, y * scale),
          Offset(size.width, y * scale),
          gridPaint,
        );
      }
    }

    // Margini A4 (tratteggio bordeaux)
    final marginPaint = Paint()
      ..color = const Color(0x665B1205)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromLTRB(
      margin * scale,
      margin * scale,
      (kA4W - margin) * scale,
      (kA4H - margin) * scale,
    );
    _dashedRect(canvas, rect, marginPaint);

    // Guide magnetiche attive
    final guidePaint = Paint()
      ..color = const Color(0xFFB08948)
      ..strokeWidth = 1;
    if (guideX != null) {
      canvas.drawLine(
        Offset(guideX! * scale, 0),
        Offset(guideX! * scale, size.height),
        guidePaint,
      );
    }
    if (guideY != null) {
      canvas.drawLine(
        Offset(0, guideY! * scale),
        Offset(size.width, guideY! * scale),
        guidePaint,
      );
    }
  }

  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    void dashedLine(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      double covered = 0;
      while (covered < total) {
        final next = min(covered + dash, total);
        canvas.drawLine(a + dir * covered, a + dir * next, paint);
        covered = next + gap;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.scale != scale ||
      old.gridStep != gridStep ||
      old.margin != margin ||
      old.showGrid != showGrid ||
      old.guideX != guideX ||
      old.guideY != guideY;
}

// ─── Anteprima PDF ───────────────────────────────────────────────────────────

class _PdfPreviewPage extends StatelessWidget {
  const _PdfPreviewPage({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Anteprima: $name')),
      body: PdfPreview(
        build: (_) async => bytes,
        allowPrinting: true,
        allowSharing: true,
        canDebug: false,
      ),
    );
  }
}
