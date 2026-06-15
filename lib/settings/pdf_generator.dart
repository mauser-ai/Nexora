import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/template_models.dart';

/// Scarica gli asset remoti del template (sfondo pagina e immagini dei
/// singoli elementi) e li inserisce in [data] per [generatePdf]:
/// - sfondo  → data['__bgBytes']
/// - immagini → data['__images'][elementId]
Future<void> prefetchTemplateAssets(
  DocumentTemplate template,
  Map<String, dynamic> data,
) async {
  Future<Uint8List?> fetch(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  final bgUrl = template.backgroundImageUrl;
  if (bgUrl != null && bgUrl.isNotEmpty && data['__bgBytes'] == null) {
    data['__bgBytes'] = await fetch(bgUrl);
  }
  final images = <String, Uint8List>{};
  for (final el in template.elements) {
    final url = el.imageUrl;
    if (el.type == 'image' && url != null && url.isNotEmpty) {
      final bytes = await fetch(url);
      if (bytes != null) images[el.id] = bytes;
    }
  }
  data['__images'] = images;
}

/// Risolve una variabile nel mappa dati passata.
/// [data] può contenere chiavi piatte come 'emittente.nome' oppure mappe annidate.
String resolveVar(String key, Map<String, dynamic> data) {
  if (data.containsKey(key)) return data[key]?.toString() ?? '';
  final parts = key.split('.');
  if (parts.length == 2) {
    final group = data[parts[0]];
    if (group is Map) return group[parts[1]]?.toString() ?? '';
  }
  return '';
}

PdfColor _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 6) {
    final r = int.parse(h.substring(0, 2), radix: 16) / 255;
    final g = int.parse(h.substring(2, 4), radix: 16) / 255;
    final b = int.parse(h.substring(4, 6), radix: 16) / 255;
    return PdfColor(r, g, b);
  }
  return PdfColors.black;
}

pw.TextAlign _align(String a) {
  switch (a) {
    case 'center':
      return pw.TextAlign.center;
    case 'right':
      return pw.TextAlign.right;
    default:
      return pw.TextAlign.left;
  }
}

/// Genera un PDF a partire da [template] sostituendo le variabili con i valori in [data].
/// [data] struttura attesa:
/// {
///   'emittente': { 'nome': '...', ... },
///   'cliente':   { 'nome': '...', ... },
///   'documento': { 'numero': '...', ... },
///   'righe': [ { 'descrizione': '', 'qta': '', 'prezzo': '', 'totale': '' }, ... ],
///   'custom': { 'mioField': '...' },
///   'logo': Uint8List?,
/// }
Future<Uint8List> generatePdf(
  DocumentTemplate template,
  Map<String, dynamic> data,
) async {
  final pdf = pw.Document();

  pw.MemoryImage? bgImage;
  if (template.backgroundImageUrl != null &&
      template.backgroundImageUrl!.isNotEmpty) {
    // backgroundImageUrl già come Uint8List passato in data['__bgBytes']
    final bgBytes = data['__bgBytes'] as Uint8List?;
    if (bgBytes != null) bgImage = pw.MemoryImage(bgBytes);
  }

  pw.MemoryImage? logoImage;
  final logoBytes = data['logo'] as Uint8List?;
  if (logoBytes != null) logoImage = pw.MemoryImage(logoBytes);
  final elementImages =
      (data['__images'] as Map<String, Uint8List>?) ?? const {};

  // ── Paginazione ────────────────────────────────────────────────────────────
  // Se la tabella righe non entra nello spazio assegnatole, il documento
  // viene spezzato su più pagine: gli elementi SOPRA la tabella si ripetono
  // come intestazione su ogni pagina, quelli SOTTO (totale, note, footer)
  // compaiono solo sull'ultima. Numero pagina automatico se le pagine sono >1.
  final tableEl = template.elements.where((e) => e.type == 'table').firstOrNull;
  final righe = (data['righe'] as List<dynamic>?) ?? const [];

  List<List<dynamic>> chunks = [righe];
  if (tableEl != null && righe.isNotEmpty) {
    chunks = _paginateRows(tableEl, righe);
  }
  final totalPages = chunks.length;

  final headerEls = <TemplateElement>[];
  final bottomEls = <TemplateElement>[];
  for (final el in template.elements) {
    if (el.type == 'table') continue;
    if (tableEl != null && el.y + el.height <= tableEl.y + 2) {
      headerEls.add(el);
    } else {
      bottomEls.add(el);
    }
  }

  for (var page = 0; page < totalPages; page++) {
    final isLast = page == totalPages - 1;
    final chunk = chunks[page];
    // Sulle pagine intermedie la tabella può estendersi fino a fondo pagina.
    final tableHeight = tableEl == null
        ? 0.0
        : (isLast ? tableEl.height : kPdfPageH - tableEl.y - 56);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          return pw.Stack(
            children: [
              // Sfondo (ripetuto su ogni pagina)
              if (bgImage != null)
                pw.Positioned(
                  left: 0,
                  top: 0,
                  child: pw.SizedBox(
                    width: kPdfPageW,
                    height: kPdfPageH,
                    child: pw.Image(bgImage, fit: pw.BoxFit.cover),
                  ),
                ),
              // Intestazione (ripetuta) — su pagina singola è tutto.
              ...headerEls.map(
                (el) => _buildElement(el, data, logoImage, elementImages),
              ),
              // Tabella con le righe di questa pagina
              if (tableEl != null)
                _buildElement(
                  tableEl,
                  data,
                  logoImage,
                  elementImages,
                  tableRows: chunk,
                  tableHeightOverride: tableHeight,
                ),
              // Elementi sotto la tabella: solo ultima pagina
              if (isLast)
                ...bottomEls.map(
                  (el) => _buildElement(el, data, logoImage, elementImages),
                ),
              // Numero pagina automatico
              if (totalPages > 1)
                pw.Positioned(
                  left: kPdfPageW - 136,
                  top: kPdfPageH - 26,
                  child: pw.SizedBox(
                    width: 100,
                    child: pw.Text(
                      'Pagina ${page + 1} di $totalPages',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  return pdf.save();
}

const double kPdfPageW = 595;
const double kPdfPageH = 842;

/// Stima l'altezza di una riga tabella considerando il wrapping della
/// descrizione (stima prudente, con margine di sicurezza).
double _estimateRowHeight(TemplateElement el, Map<String, dynamic> row) {
  final descWidth = el.width * 3 / 7 - 10; // colonna descrizione (flex 3/7)
  final charWidth = el.fontSize * 0.52;
  final charsPerLine = (descWidth / charWidth).clamp(8, 200);
  final desc = row['descrizione']?.toString() ?? '';
  final lines = (desc.length / charsPerLine).ceil().clamp(1, 30);
  return (el.fontSize + 4.4) * lines + 6;
}

/// Spezza le righe in pagine: la prima e l'ultima rispettano l'altezza
/// disegnata nel template, le intermedie possono usare la pagina intera.
List<List<dynamic>> _paginateRows(TemplateElement el, List<dynamic> righe) {
  final headerH = el.fontSize + 10;
  final firstCapacity = el.height - headerH;
  final contCapacity = (kPdfPageH - el.y - 56) - headerH;

  // Tutte le righe entrano nella prima pagina → documento a pagina singola.
  double total = 0;
  for (final r in righe) {
    total += _estimateRowHeight(el, Map<String, dynamic>.from(r as Map));
  }
  if (total * 1.12 <= firstCapacity) return [righe];

  final chunks = <List<dynamic>>[];
  var current = <dynamic>[];
  var used = 0.0;
  var capacity = firstCapacity;
  for (final r in righe) {
    final h =
        _estimateRowHeight(el, Map<String, dynamic>.from(r as Map)) * 1.12;
    if (current.isNotEmpty && used + h > capacity) {
      chunks.add(current);
      current = <dynamic>[];
      used = 0;
      capacity = contCapacity;
    }
    current.add(r);
    used += h;
  }
  if (current.isNotEmpty) chunks.add(current);

  // L'ultimo blocco deve rientrare nell'altezza disegnata (sotto ci sono
  // totale/note): se sborda, sposta righe in una pagina intermedia in più.
  while (chunks.length > 1) {
    final last = chunks.last;
    double lastH = 0;
    for (final r in last) {
      lastH +=
          _estimateRowHeight(el, Map<String, dynamic>.from(r as Map)) * 1.12;
    }
    if (lastH + headerH <= el.height) break;
    // Trabocca: lascia nell'ultima solo le righe che entrano.
    final keep = <dynamic>[];
    var h = 0.0;
    for (final r in last.reversed) {
      final rh =
          _estimateRowHeight(el, Map<String, dynamic>.from(r as Map)) * 1.12;
      if (h + rh + headerH > el.height) break;
      keep.insert(0, r);
      h += rh;
    }
    if (keep.isEmpty || keep.length == last.length) break;
    final overflowCount = last.length - keep.length;
    chunks[chunks.length - 1] = last.sublist(0, overflowCount);
    chunks.add(keep);
  }

  return chunks;
}

pw.Widget _buildElement(
  TemplateElement el,
  Map<String, dynamic> data,
  pw.MemoryImage? logoImage,
  Map<String, Uint8List> elementImages, {
  List<dynamic>? tableRows,
  double? tableHeightOverride,
}) {
  final left = el.x;
  final top = el.y;

  pw.Widget content;

  switch (el.type) {
    case 'image':
      // Priorità all'immagine caricata sull'elemento; altrimenti, per il
      // segnaposto "logo", usa il logo del Branding passato in data['logo'].
      final customBytes = elementImages[el.id];
      if (customBytes != null) {
        content = pw.Image(pw.MemoryImage(customBytes), fit: pw.BoxFit.contain);
      } else if (logoImage != null && el.variableKey == 'logo') {
        content = pw.Image(logoImage, fit: pw.BoxFit.contain);
      } else {
        content = pw.SizedBox(width: 0, height: 0);
      }
      break;

    case 'table':
      final righe = tableRows ?? data['righe'] as List<dynamic>? ?? [];
      content = _buildTable(el, righe);
      break;

    case 'rect':
      content = pw.Container(
        decoration: pw.BoxDecoration(
          color: el.bgColorHex != null ? _hexColor(el.bgColorHex!) : null,
          border: el.borderWidth > 0 && el.borderColorHex != null
              ? pw.Border.all(
                  color: _hexColor(el.borderColorHex!),
                  width: el.borderWidth,
                )
              : null,
          borderRadius: el.borderRadius > 0
              ? pw.BorderRadius.circular(el.borderRadius)
              : null,
        ),
      );
      break;

    default: // 'variable' | 'static_text'
      final rawText = el.type == 'variable' && el.variableKey != null
          ? _resolveVarFromData(el.variableKey!, data)
          : (el.staticText ?? '');

      content = pw.Text(
        rawText,
        textAlign: _align(el.textAlign),
        style: pw.TextStyle(
          fontSize: el.fontSize,
          fontWeight: el.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: el.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          color: _hexColor(el.colorHex),
        ),
      );

      if (el.bgColorHex != null || el.borderWidth > 0) {
        content = pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2),
          decoration: pw.BoxDecoration(
            color: el.bgColorHex != null ? _hexColor(el.bgColorHex!) : null,
            border: el.borderWidth > 0 && el.borderColorHex != null
                ? pw.Border.all(
                    color: _hexColor(el.borderColorHex!),
                    width: el.borderWidth,
                  )
                : null,
          ),
          child: content,
        );
      }
  }

  return pw.Positioned(
    left: left,
    top: top,
    child: pw.SizedBox(
      width: el.width,
      height: tableHeightOverride ?? el.height,
      child: pw.ClipRect(child: content),
    ),
  );
}

String _resolveVarFromData(String key, Map<String, dynamic> data) {
  if (key.startsWith('custom.')) {
    final customKey = key.substring(7);
    final custom = data['custom'] as Map<String, dynamic>?;
    return custom?[customKey]?.toString() ?? '';
  }
  return resolveVar(key, data);
}

pw.Widget _buildTable(TemplateElement el, List<dynamic> righe) {
  final headers = ['Descrizione', 'Qtà', 'Prezzo', 'Totale'];
  final rows = righe.map((r) {
    final row = r as Map<String, dynamic>;
    return [
      row['descrizione']?.toString() ?? '',
      row['qta']?.toString() ?? '',
      row['prezzo']?.toString() ?? '',
      row['totale']?.toString() ?? '',
    ];
  }).toList();

  // Stili presi dall'elemento: colorHex = testo, bgColorHex = sfondo
  // intestazione, borderColorHex/borderWidth = bordi tabella.
  final textColor = _hexColor(el.colorHex);
  final headerBg = el.bgColorHex != null
      ? _hexColor(el.bgColorHex!)
      : PdfColors.grey200;
  final borderColor = el.borderColorHex != null
      ? _hexColor(el.borderColorHex!)
      : PdfColors.grey300;
  final borderWidth = el.borderWidth > 0 ? el.borderWidth : 0.5;
  final fontSize = el.fontSize;
  final alignRight = [false, false, true, true];

  return pw.Table(
    border: pw.TableBorder.all(color: borderColor, width: borderWidth),
    columnWidths: {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(1.5),
      3: const pw.FlexColumnWidth(1.5),
    },
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          for (var i = 0; i < headers.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 4,
              ),
              child: pw.Text(
                headers[i],
                textAlign: alignRight[i]
                    ? pw.TextAlign.right
                    : pw.TextAlign.left,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: fontSize,
                  color: textColor,
                ),
              ),
            ),
        ],
      ),
      ...rows.map(
        (row) => pw.TableRow(
          children: [
            for (var i = 0; i < row.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 3,
                ),
                child: pw.Text(
                  row[i],
                  textAlign: alignRight[i]
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                  style: pw.TextStyle(fontSize: fontSize, color: textColor),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
