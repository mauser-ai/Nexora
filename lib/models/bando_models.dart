import 'package:cloud_firestore/cloud_firestore.dart';

import 'domain_models.dart';

/// ─── Modulo Bandi (Centro Studi) ─────────────────────────────────────────────
/// Anagrafica bandi/incentivi con requisiti e matching automatico sui clienti.

enum BandoStato { aperto, chiuso, archiviato }

BandoStato parseBandoStato(String? raw) => BandoStato.values.firstWhere(
  (s) => s.name == raw,
  orElse: () => BandoStato.aperto,
);

extension BandoStatoX on BandoStato {
  String get label => switch (this) {
    BandoStato.aperto => 'Aperto',
    BandoStato.chiuso => 'Chiuso',
    BandoStato.archiviato => 'Archiviato',
  };
}

/// Regioni italiane (per i requisiti territoriali).
const List<String> kRegioniItaliane = [
  'Abruzzo',
  'Basilicata',
  'Calabria',
  'Campania',
  'Emilia-Romagna',
  'Friuli-Venezia Giulia',
  'Lazio',
  'Liguria',
  'Lombardia',
  'Marche',
  'Molise',
  'Piemonte',
  'Puglia',
  'Sardegna',
  'Sicilia',
  'Toscana',
  'Trentino-Alto Adige',
  'Umbria',
  "Valle d'Aosta",
  'Veneto',
];

extension CompanySizeLabel on CompanySize {
  String get label => switch (this) {
    CompanySize.micro => 'Micro',
    CompanySize.piccola => 'Piccola',
    CompanySize.media => 'Media',
    CompanySize.grande => 'Grande',
  };
}

extension CompanyTypeLabel on CompanyType {
  String get label => switch (this) {
    CompanyType.profit => 'Profit',
    CompanyType.nonProfit => 'No profit',
    CompanyType.pa => 'PA',
    CompanyType.pf => 'Persona fisica',
  };
}

class Bando {
  const Bando({
    required this.id,
    required this.titolo,
    this.ente = '',
    this.descrizione = '',
    this.link = '',
    this.note = '',
    this.stato = BandoStato.aperto,
    this.apertura,
    this.scadenza,
    this.dotazione,
    this.percentualeContributo,
    this.importoMin,
    this.importoMax,
    this.regioni = const [],
    this.codiciAteco = const [],
    this.dimensioni = const [],
    this.tipi = const [],
    this.areeInvestimento = const [],
    this.createdAt,
  });

  final String id;
  final String titolo;
  final String ente;
  final String descrizione;
  final String link;
  final String note;
  final BandoStato stato;
  final DateTime? apertura;
  final DateTime? scadenza;

  /// Dotazione complessiva del bando (€).
  final double? dotazione;

  /// Percentuale di contributo a fondo perduto.
  final double? percentualeContributo;
  final double? importoMin;
  final double? importoMax;

  /// Requisiti (lista vuota = nessun vincolo).
  final List<String> regioni;
  final List<String> codiciAteco; // prefissi, es. "62" o "62.01"
  final List<CompanySize> dimensioni;
  final List<CompanyType> tipi;
  final List<String> areeInvestimento; // categorie testuali

  final DateTime? createdAt;

  bool get inScadenza =>
      stato == BandoStato.aperto &&
      scadenza != null &&
      scadenza!.difference(DateTime.now()).inDays <= 30 &&
      !scadenza!.isBefore(DateTime.now());

  bool get scaduto => scadenza != null && scadenza!.isBefore(DateTime.now());

  Map<String, dynamic> toMap() => {
    'titolo': titolo,
    'ente': ente,
    'descrizione': descrizione,
    'link': link,
    'note': note,
    'stato': stato.name,
    if (apertura != null) 'apertura': Timestamp.fromDate(apertura!),
    if (scadenza != null) 'scadenza': Timestamp.fromDate(scadenza!),
    if (dotazione != null) 'dotazione': dotazione,
    if (percentualeContributo != null)
      'percentualeContributo': percentualeContributo,
    if (importoMin != null) 'importoMin': importoMin,
    if (importoMax != null) 'importoMax': importoMax,
    'regioni': regioni,
    'codiciAteco': codiciAteco,
    'dimensioni': dimensioni.map((d) => d.name).toList(),
    'tipi': tipi.map((t) => t.name).toList(),
    'areeInvestimento': areeInvestimento,
  };

  factory Bando.fromMap(String id, Map<String, dynamic> map) {
    DateTime? date(dynamic v) => v is Timestamp
        ? v.toDate()
        : (v is String ? DateTime.tryParse(v) : null);
    List<String> strings(dynamic v) =>
        (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    return Bando(
      id: id,
      titolo: map['titolo'] as String? ?? '',
      ente: map['ente'] as String? ?? '',
      descrizione: map['descrizione'] as String? ?? '',
      link: map['link'] as String? ?? '',
      note: map['note'] as String? ?? '',
      stato: parseBandoStato(map['stato'] as String?),
      apertura: date(map['apertura']),
      scadenza: date(map['scadenza']),
      dotazione: (map['dotazione'] as num?)?.toDouble(),
      percentualeContributo: (map['percentualeContributo'] as num?)?.toDouble(),
      importoMin: (map['importoMin'] as num?)?.toDouble(),
      importoMax: (map['importoMax'] as num?)?.toDouble(),
      regioni: strings(map['regioni']),
      codiciAteco: strings(map['codiciAteco']),
      dimensioni: strings(map['dimensioni'])
          .map((n) => CompanySize.values.where((s) => s.name == n).firstOrNull)
          .whereType<CompanySize>()
          .toList(),
      tipi: strings(map['tipi'])
          .map((n) => CompanyType.values.where((t) => t.name == n).firstOrNull)
          .whereType<CompanyType>()
          .toList(),
      areeInvestimento: strings(map['areeInvestimento']),
      createdAt: date(map['createdAt']),
    );
  }

  Bando copyWith({
    String? titolo,
    String? ente,
    String? descrizione,
    String? link,
    String? note,
    BandoStato? stato,
    DateTime? apertura,
    DateTime? scadenza,
    double? dotazione,
    double? percentualeContributo,
    double? importoMin,
    double? importoMax,
    List<String>? regioni,
    List<String>? codiciAteco,
    List<CompanySize>? dimensioni,
    List<CompanyType>? tipi,
    List<String>? areeInvestimento,
  }) => Bando(
    id: id,
    titolo: titolo ?? this.titolo,
    ente: ente ?? this.ente,
    descrizione: descrizione ?? this.descrizione,
    link: link ?? this.link,
    note: note ?? this.note,
    stato: stato ?? this.stato,
    apertura: apertura ?? this.apertura,
    scadenza: scadenza ?? this.scadenza,
    dotazione: dotazione ?? this.dotazione,
    percentualeContributo: percentualeContributo ?? this.percentualeContributo,
    importoMin: importoMin ?? this.importoMin,
    importoMax: importoMax ?? this.importoMax,
    regioni: regioni ?? this.regioni,
    codiciAteco: codiciAteco ?? this.codiciAteco,
    dimensioni: dimensioni ?? this.dimensioni,
    tipi: tipi ?? this.tipi,
    areeInvestimento: areeInvestimento ?? this.areeInvestimento,
    createdAt: createdAt,
  );
}

// ─── Matching bando ↔ cliente ────────────────────────────────────────────────

enum MatchOutcome { ok, ko, unknown }

enum BandoMatchLevel { compatibile, parziale, escluso }

extension BandoMatchLevelX on BandoMatchLevel {
  String get label => switch (this) {
    BandoMatchLevel.compatibile => 'Compatibile',
    BandoMatchLevel.parziale => 'Da verificare',
    BandoMatchLevel.escluso => 'Escluso',
  };
}

class BandoMatchCriterio {
  const BandoMatchCriterio(this.label, this.outcome, [this.dettaglio = '']);
  final String label;
  final MatchOutcome outcome;
  final String dettaglio;
}

class BandoMatch {
  const BandoMatch({
    required this.company,
    required this.level,
    required this.criteri,
  });

  final Company company;
  final BandoMatchLevel level;
  final List<BandoMatchCriterio> criteri;
}

/// Normalizza un codice ATECO per il confronto a prefisso ("62.01" → "6201").
String _normAteco(String code) => code.replaceAll(RegExp(r'[^0-9]'), '');

/// Dimensione impresa: usa il campo esplicito, altrimenti la deriva dai dati
/// disponibili secondo le soglie UE (dipendenti/ULA + fatturato).
CompanySize? _effectiveSize(Company c) {
  if (c.dimensioneImpresa != null) return c.dimensioneImpresa;
  final headcount = c.ula ?? c.employeesCount;
  if (headcount == null) return null;
  final revenue = c.annualRevenue;
  if (headcount < 10 && (revenue == null || revenue <= 2e6)) {
    return CompanySize.micro;
  }
  if (headcount < 50 && (revenue == null || revenue <= 10e6)) {
    return CompanySize.piccola;
  }
  if (headcount < 250 && (revenue == null || revenue <= 50e6)) {
    return CompanySize.media;
  }
  return CompanySize.grande;
}

/// Valuta la compatibilità di [company] con i requisiti di [bando].
BandoMatch matchCompany(Bando bando, Company company) {
  final criteri = <BandoMatchCriterio>[];

  // Regione
  if (bando.regioni.isNotEmpty) {
    final candidates = [
      company.regione,
      company.sedeOperativaRegione,
    ].map((r) => r.trim().toLowerCase()).where((r) => r.isNotEmpty).toList();
    if (candidates.isEmpty) {
      criteri.add(
        const BandoMatchCriterio(
          'Regione',
          MatchOutcome.unknown,
          'regione non in anagrafica',
        ),
      );
    } else {
      final ok = bando.regioni.any(
        (r) => candidates.contains(r.trim().toLowerCase()),
      );
      criteri.add(
        BandoMatchCriterio(
          'Regione',
          ok ? MatchOutcome.ok : MatchOutcome.ko,
          candidates.first,
        ),
      );
    }
  }

  // ATECO (match a prefisso su primario/secondario/terziario)
  if (bando.codiciAteco.isNotEmpty) {
    final companyCodes = [
      company.atecoPrimario,
      company.atecoSecondario,
      company.atecoTerziario,
    ].map(_normAteco).where((c) => c.isNotEmpty).toList();
    if (companyCodes.isEmpty) {
      criteri.add(
        const BandoMatchCriterio(
          'ATECO',
          MatchOutcome.unknown,
          'ATECO non in anagrafica',
        ),
      );
    } else {
      final prefixes = bando.codiciAteco.map(_normAteco);
      final ok = companyCodes.any(
        (code) => prefixes.any((p) => p.isNotEmpty && code.startsWith(p)),
      );
      criteri.add(
        BandoMatchCriterio(
          'ATECO',
          ok ? MatchOutcome.ok : MatchOutcome.ko,
          company.atecoPrimario,
        ),
      );
    }
  }

  // Dimensione impresa
  if (bando.dimensioni.isNotEmpty) {
    final size = _effectiveSize(company);
    if (size == null) {
      criteri.add(
        const BandoMatchCriterio(
          'Dimensione',
          MatchOutcome.unknown,
          'dipendenti/fatturato non in anagrafica',
        ),
      );
    } else {
      criteri.add(
        BandoMatchCriterio(
          'Dimensione',
          bando.dimensioni.contains(size) ? MatchOutcome.ok : MatchOutcome.ko,
          size.label,
        ),
      );
    }
  }

  // Tipologia (profit / no profit / PA / PF)
  if (bando.tipi.isNotEmpty) {
    criteri.add(
      BandoMatchCriterio(
        'Tipologia',
        bando.tipi.contains(company.companyType)
            ? MatchOutcome.ok
            : MatchOutcome.ko,
        company.companyType.label,
      ),
    );
  }

  // Aree di investimento dichiarate dal cliente
  if (bando.areeInvestimento.isNotEmpty) {
    final companyAree = company.areeInvestimento
        .map((a) => a.categoria.trim().toLowerCase())
        .where((a) => a.isNotEmpty)
        .toList();
    if (companyAree.isEmpty) {
      criteri.add(
        const BandoMatchCriterio(
          'Investimenti',
          MatchOutcome.unknown,
          'aree investimento non censite',
        ),
      );
    } else {
      final ok = bando.areeInvestimento.any(
        (a) => companyAree.any(
          (c) =>
              c.contains(a.trim().toLowerCase()) ||
              a.trim().toLowerCase().contains(c),
        ),
      );
      criteri.add(
        BandoMatchCriterio(
          'Investimenti',
          ok ? MatchOutcome.ok : MatchOutcome.unknown,
          '',
        ),
      );
    }
  }

  final BandoMatchLevel level;
  if (criteri.any((c) => c.outcome == MatchOutcome.ko)) {
    level = BandoMatchLevel.escluso;
  } else if (criteri.any((c) => c.outcome == MatchOutcome.unknown)) {
    level = BandoMatchLevel.parziale;
  } else {
    level = BandoMatchLevel.compatibile;
  }
  return BandoMatch(company: company, level: level, criteri: criteri);
}

/// Tutti i match per un bando, ordinati: compatibili → da verificare.
/// Gli esclusi sono inclusi solo se [includeExcluded].
List<BandoMatch> matchAllCompanies(
  Bando bando,
  List<Company> companies, {
  bool includeExcluded = false,
}) {
  final matches = companies
      .map((c) => matchCompany(bando, c))
      .where((m) => includeExcluded || m.level != BandoMatchLevel.escluso);
  final sorted = matches.toList()
    ..sort((a, b) {
      final byLevel = a.level.index.compareTo(b.level.index);
      if (byLevel != 0) return byLevel;
      return a.company.name.toLowerCase().compareTo(
        b.company.name.toLowerCase(),
      );
    });
  return sorted;
}
