// ignore_for_file: public_member_api_docs
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Standard variables ───────────────────────────────────────────────────────

class TemplateVariable {
  const TemplateVariable({required this.key, required this.label, required this.group});
  final String key;
  final String label;
  final String group;
}

const kPreventivo = 'preventivo';
const kFattura = 'fattura';

final kStandardVariables = <TemplateVariable>[
  // Emittente
  TemplateVariable(key: 'emittente.nome',      label: 'Ragione sociale',   group: 'Emittente'),
  TemplateVariable(key: 'emittente.piva',      label: 'P.IVA',             group: 'Emittente'),
  TemplateVariable(key: 'emittente.cf',        label: 'Codice fiscale',    group: 'Emittente'),
  TemplateVariable(key: 'emittente.indirizzo', label: 'Indirizzo',         group: 'Emittente'),
  TemplateVariable(key: 'emittente.cap',       label: 'CAP',               group: 'Emittente'),
  TemplateVariable(key: 'emittente.comune',    label: 'Comune',            group: 'Emittente'),
  TemplateVariable(key: 'emittente.email',     label: 'Email',             group: 'Emittente'),
  TemplateVariable(key: 'emittente.pec',       label: 'PEC',               group: 'Emittente'),
  TemplateVariable(key: 'emittente.telefono',  label: 'Telefono',          group: 'Emittente'),
  // Cliente
  TemplateVariable(key: 'cliente.nome',        label: 'Nome / Rag. soc.',  group: 'Cliente'),
  TemplateVariable(key: 'cliente.piva',        label: 'P.IVA',             group: 'Cliente'),
  TemplateVariable(key: 'cliente.cf',          label: 'Codice fiscale',    group: 'Cliente'),
  TemplateVariable(key: 'cliente.indirizzo',   label: 'Indirizzo',         group: 'Cliente'),
  TemplateVariable(key: 'cliente.cap',         label: 'CAP',               group: 'Cliente'),
  TemplateVariable(key: 'cliente.comune',      label: 'Comune',            group: 'Cliente'),
  TemplateVariable(key: 'cliente.email',       label: 'Email',             group: 'Cliente'),
  // Documento
  TemplateVariable(key: 'documento.numero',    label: 'Numero',            group: 'Documento'),
  TemplateVariable(key: 'documento.data',      label: 'Data emissione',    group: 'Documento'),
  TemplateVariable(key: 'documento.validita',  label: 'Validità offerta',  group: 'Documento'),
  TemplateVariable(key: 'documento.scadenza',  label: 'Data scadenza',     group: 'Documento'),
  TemplateVariable(key: 'documento.totale',    label: 'Totale',            group: 'Documento'),
  TemplateVariable(key: 'documento.pagamento', label: 'Metodo pagamento',  group: 'Documento'),
  TemplateVariable(key: 'documento.iban',      label: 'IBAN',              group: 'Documento'),
  TemplateVariable(key: 'documento.note',      label: 'Note',              group: 'Documento'),
  // Speciali
  TemplateVariable(key: 'righe',               label: 'Tabella righe',     group: 'Speciali'),
  TemplateVariable(key: 'logo',                label: 'Logo emittente',    group: 'Speciali'),
];

// ─── Custom field ─────────────────────────────────────────────────────────────

class TemplateCustomField {
  const TemplateCustomField({
    required this.key,
    required this.label,
    this.inputType = 'text',
  });
  final String key;
  final String label;
  final String inputType; // 'text' | 'textarea' | 'number'

  Map<String, dynamic> toMap() => {'key': key, 'label': label, 'inputType': inputType};

  factory TemplateCustomField.fromMap(Map<String, dynamic> m) => TemplateCustomField(
    key: m['key'] as String? ?? '',
    label: m['label'] as String? ?? '',
    inputType: m['inputType'] as String? ?? 'text',
  );
}

// ─── Element ──────────────────────────────────────────────────────────────────

/// type: 'variable' | 'static_text' | 'image' | 'table' | 'rect'
class TemplateElement {
  const TemplateElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.variableKey,
    this.staticText,
    this.imageUrl,
    this.fontSize = 11,
    this.bold = false,
    this.italic = false,
    this.colorHex = '#1F2937',
    this.textAlign = 'left',
    this.bgColorHex,
    this.borderColorHex,
    this.borderWidth = 0,
    this.borderRadius = 0,
  });

  final String id;
  final String type;
  final double x; // PDF points from left (0-595)
  final double y; // PDF points from top  (0-842)
  final double width;
  final double height;
  final String? variableKey; // for 'variable' type
  final String? staticText;  // for 'static_text' and 'rect' label
  final String? imageUrl;    // for 'image' type
  final double fontSize;
  final bool bold;
  final bool italic;
  final String colorHex;
  final String textAlign;    // 'left' | 'center' | 'right'
  final String? bgColorHex;
  final String? borderColorHex;
  final double borderWidth;
  final double borderRadius;

  String get displayLabel {
    if (type == 'variable' && variableKey != null) {
      try {
        return kStandardVariables.firstWhere((v) => v.key == variableKey!).label;
      } catch (_) {
        // custom field
        return variableKey!.replaceAll('custom.', '');
      }
    }
    if (type == 'static_text') return staticText ?? '';
    if (type == 'image') return 'Immagine';
    if (type == 'table') return 'Tabella righe';
    if (type == 'rect') return 'Rettangolo';
    return type;
  }

  TemplateElement copyWith({
    double? x, double? y, double? width, double? height,
    String? variableKey, String? staticText, String? imageUrl,
    double? fontSize, bool? bold, bool? italic,
    String? colorHex, String? textAlign, String? bgColorHex,
    String? borderColorHex, double? borderWidth, double? borderRadius,
  }) => TemplateElement(
    id: id, type: type,
    x: x ?? this.x, y: y ?? this.y,
    width: width ?? this.width, height: height ?? this.height,
    variableKey: variableKey ?? this.variableKey,
    staticText: staticText ?? this.staticText,
    imageUrl: imageUrl ?? this.imageUrl,
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold, italic: italic ?? this.italic,
    colorHex: colorHex ?? this.colorHex,
    textAlign: textAlign ?? this.textAlign,
    bgColorHex: bgColorHex ?? this.bgColorHex,
    borderColorHex: borderColorHex ?? this.borderColorHex,
    borderWidth: borderWidth ?? this.borderWidth,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type,
    'x': x, 'y': y, 'width': width, 'height': height,
    if (variableKey != null) 'variableKey': variableKey,
    if (staticText  != null) 'staticText':  staticText,
    if (imageUrl    != null) 'imageUrl':    imageUrl,
    'fontSize': fontSize, 'bold': bold, 'italic': italic,
    'colorHex': colorHex, 'textAlign': textAlign,
    if (bgColorHex     != null) 'bgColorHex':     bgColorHex,
    if (borderColorHex != null) 'borderColorHex': borderColorHex,
    'borderWidth': borderWidth, 'borderRadius': borderRadius,
  };

  factory TemplateElement.fromMap(Map<String, dynamic> m) => TemplateElement(
    id: m['id'] as String? ?? '',
    type: m['type'] as String? ?? 'static_text',
    x: (m['x'] as num? ?? 0).toDouble(),
    y: (m['y'] as num? ?? 0).toDouble(),
    width: (m['width'] as num? ?? 150).toDouble(),
    height: (m['height'] as num? ?? 24).toDouble(),
    variableKey: m['variableKey'] as String?,
    staticText:  m['staticText']  as String?,
    imageUrl:    m['imageUrl']    as String?,
    fontSize: (m['fontSize'] as num? ?? 11).toDouble(),
    bold:   m['bold']   as bool? ?? false,
    italic: m['italic'] as bool? ?? false,
    colorHex:   m['colorHex']  as String? ?? '#1F2937',
    textAlign:  m['textAlign'] as String? ?? 'left',
    bgColorHex:     m['bgColorHex']     as String?,
    borderColorHex: m['borderColorHex'] as String?,
    borderWidth:  (m['borderWidth']  as num? ?? 0).toDouble(),
    borderRadius: (m['borderRadius'] as num? ?? 0).toDouble(),
  );
}

// ─── Template ─────────────────────────────────────────────────────────────────

class DocumentTemplate {
  const DocumentTemplate({
    required this.id,
    required this.name,
    required this.category,
    this.backgroundImageUrl,
    required this.elements,
    required this.customFields,
    this.createdAt,
  });

  final String id;
  final String name;
  final String category; // kPreventivo | kFattura
  final String? backgroundImageUrl;
  final List<TemplateElement> elements;
  final List<TemplateCustomField> customFields;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    if (backgroundImageUrl != null) 'backgroundImageUrl': backgroundImageUrl,
    'elements':     elements.map((e) => e.toMap()).toList(),
    'customFields': customFields.map((f) => f.toMap()).toList(),
  };

  factory DocumentTemplate.fromMap(String id, Map<String, dynamic> m) =>
      DocumentTemplate(
        id: id,
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? kPreventivo,
        backgroundImageUrl: m['backgroundImageUrl'] as String?,
        elements: (m['elements'] as List<dynamic>? ?? [])
            .map((e) => TemplateElement.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        customFields: (m['customFields'] as List<dynamic>? ?? [])
            .map((f) => TemplateCustomField.fromMap(Map<String, dynamic>.from(f as Map)))
            .toList(),
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null,
      );
}

// ─── Email Template ──────────────────────────────────────────────────────────

class EmailTemplate {
  const EmailTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.subject,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String name;
  final String category; // kPreventivo | kFattura
  final String subject;  // può contenere {{variabili}}
  final String body;     // può contenere {{variabili}}
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'subject': subject,
    'body': body,
  };

  factory EmailTemplate.fromMap(String id, Map<String, dynamic> m) => EmailTemplate(
    id: id,
    name: m['name'] as String? ?? '',
    category: m['category'] as String? ?? kPreventivo,
    subject: m['subject'] as String? ?? '',
    body: m['body'] as String? ?? '',
    createdAt: m['createdAt'] is Timestamp
        ? (m['createdAt'] as Timestamp).toDate()
        : null,
  );

  /// Sostituisce tutte le {{variabili}} con i valori in [data].
  String renderSubject(Map<String, dynamic> data) => _render(subject, data);
  String renderBody(Map<String, dynamic> data) => _render(body, data);

  static String _render(String template, Map<String, dynamic> data) {
    return template.replaceAllMapped(
      RegExp(r'\{\{([^}]+)\}\}'),
      (m) {
        final key = m.group(1)!.trim();
        return _resolve(key, data);
      },
    );
  }

  static String _resolve(String key, Map<String, dynamic> data) {
    if (key.startsWith('custom.')) {
      final k = key.substring(7);
      final custom = data['custom'] as Map<String, dynamic>?;
      return custom?[k]?.toString() ?? '';
    }
    final parts = key.split('.');
    if (parts.length == 2) {
      final group = data[parts[0]];
      if (group is Map) return group[parts[1]]?.toString() ?? '';
    }
    return data[key]?.toString() ?? '';
  }
}

/// Variabili standard disponibili anche nei template email.
final kEmailVariables = <TemplateVariable>[
  TemplateVariable(key: 'cliente.nome',        label: 'Nome cliente',       group: 'Cliente'),
  TemplateVariable(key: 'cliente.email',       label: 'Email cliente',      group: 'Cliente'),
  TemplateVariable(key: 'emittente.nome',      label: 'Ragione sociale',    group: 'Emittente'),
  TemplateVariable(key: 'emittente.email',     label: 'Email emittente',    group: 'Emittente'),
  TemplateVariable(key: 'emittente.telefono',  label: 'Telefono',           group: 'Emittente'),
  TemplateVariable(key: 'documento.numero',    label: 'Numero documento',   group: 'Documento'),
  TemplateVariable(key: 'documento.data',      label: 'Data emissione',     group: 'Documento'),
  TemplateVariable(key: 'documento.totale',    label: 'Totale',             group: 'Documento'),
  TemplateVariable(key: 'documento.validita',  label: 'Validità offerta',   group: 'Documento'),
  TemplateVariable(key: 'documento.scadenza',  label: 'Data scadenza',      group: 'Documento'),
  TemplateVariable(key: 'documento.note',      label: 'Note',               group: 'Documento'),
];
