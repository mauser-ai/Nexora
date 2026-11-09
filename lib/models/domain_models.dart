import 'package:cloud_firestore/cloud_firestore.dart';

import 'custom_field_models.dart';

// ─────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────

enum TaskStatus { backlog, planned, inProgress, done }

enum InvoiceStatus { draft, readyForXml, exported }

enum TicketStatus { newTicket, open, waitingCustomer, closed }

enum TicketEntryType { internalNote, outboundEmail, inboundEmail }

/// Stato del ciclo di vita di un'Opportunità — valori allineati al Gestionale GC
enum OpportunityStatus {
  inAttesa, // "in attesa" — valutazione iniziale / risposta cliente
  preventivazione, // "preventivazione" — in fase di redazione preventivo
  accettata, // "accettata" — cliente ha accettato con firma
  accettataSenzaFirma, // "accettata senza firma" — accordo verbale/mail
  inAttesaRinnovoAutomatico, // "in attesa rinnovo automatico" — rinnovo consulenza annuale
  presaInCarico, // "presa in carico" — progetto creato, in lavorazione
  persa, // "persa" — opportunità persa o rifiutata
}

/// Tipologia progetto: Profit (investimenti/macchinari) o No-Profit (narrativa/sociale)
enum ProjectType { profit, noProfit }

/// Stato del progetto lungo il ciclo di vita
enum ProjectStatus {
  draft, // creato ma non ancora pianificato
  planning, // in fase di pianificazione
  inProgress, // esecuzione tecnica in corso
  pendingResult, // in attesa di esito
  approved, // esito positivo → trigger fatturazione
  rejected, // esito negativo
  closed, // chiuso (fatturato/archiviato)
}

/// Stato di una fase di progetto
enum PhaseStatus { notStarted, inProgress, done }

/// Stato di un preventivo
enum PreventivoStatus { draft, sent, accepted, rejected }

/// Tipologia soggetto: Profit / Non-Profit / Pubblica Amministrazione / altro
enum CompanyType { profit, nonProfit, pa, pf }

/// Dimensione impresa (classificazione UE)
enum CompanySize { micro, piccola, media, grande }

/// Avanzamento pratica bando
enum AvanzamentoPratica { none, presentata, inEsecuzione, conclusa }

/// Esito pratica bando
enum EsitoPratica {
  none,
  accolta,
  respinta,
  rinunciata,
  nonAmmissibile,
  inAttesa,
}

/// Stato rendicontazione post-concessione
enum StatoRendicontazione { none, aperta, chiusa }

// ─────────────────────────────────────────────
// Parse helpers
// ─────────────────────────────────────────────

TaskStatus parseTaskStatus(String? raw) => TaskStatus.values.firstWhere(
  (v) => v.name == raw,
  orElse: () => TaskStatus.backlog,
);

InvoiceStatus parseInvoiceStatus(String? raw) => InvoiceStatus.values
    .firstWhere((v) => v.name == raw, orElse: () => InvoiceStatus.draft);

TicketStatus parseTicketStatus(String? raw) {
  switch (raw) {
    case 'new':
    case 'newTicket':
      return TicketStatus.newTicket;
    case 'open':
      return TicketStatus.open;
    case 'waitingCustomer':
    case 'pending':
      return TicketStatus.waitingCustomer;
    case 'closed':
      return TicketStatus.closed;
  }
  return TicketStatus.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => TicketStatus.newTicket,
  );
}

TicketEntryType parseTicketEntryType(String? raw) {
  switch (raw) {
    case 'internalNote':
      return TicketEntryType.internalNote;
    case 'outboundEmail':
      return TicketEntryType.outboundEmail;
    case 'inboundEmail':
    case 'inbound':
      return TicketEntryType.inboundEmail;
  }
  return TicketEntryType.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => TicketEntryType.internalNote,
  );
}

OpportunityStatus parseOpportunityStatus(String? raw) {
  switch (raw) {
    // Valori nuovi (allineati al Gestionale GC)
    case 'inAttesa':
      return OpportunityStatus.inAttesa;
    case 'preventivazione':
      return OpportunityStatus.preventivazione;
    case 'accettata':
      return OpportunityStatus.accettata;
    case 'accettataSenzaFirma':
      return OpportunityStatus.accettataSenzaFirma;
    case 'inAttesaRinnovoAutomatico':
      return OpportunityStatus.inAttesaRinnovoAutomatico;
    case 'presaInCarico':
      return OpportunityStatus.presaInCarico;
    case 'persa':
      return OpportunityStatus.persa;
    // Backward compat con vecchi valori Firestore
    case 'new_':
      return OpportunityStatus.inAttesa;
    case 'analysis':
      return OpportunityStatus.preventivazione;
    case 'quoted':
      return OpportunityStatus.preventivazione;
    case 'accepted':
      return OpportunityStatus.accettata;
    case 'rejected':
      return OpportunityStatus.persa;
    case 'lost':
      return OpportunityStatus.persa;
    default:
      return OpportunityStatus.inAttesa;
  }
}

ProjectStatus parseProjectStatus(String? raw) => ProjectStatus.values
    .firstWhere((v) => v.name == raw, orElse: () => ProjectStatus.draft);

PhaseStatus parsePhaseStatus(String? raw) => PhaseStatus.values.firstWhere(
  (v) => v.name == raw,
  orElse: () => PhaseStatus.notStarted,
);

PreventivoStatus parsePreventivoStatus(String? raw) => PreventivoStatus.values
    .firstWhere((v) => v.name == raw, orElse: () => PreventivoStatus.draft);

ProjectType parseProjectType(String? raw) => ProjectType.values.firstWhere(
  (v) => v.name == raw,
  orElse: () => ProjectType.profit,
);

CompanyType parseCompanyType(String? raw) => CompanyType.values.firstWhere(
  (v) => v.name == raw,
  orElse: () => CompanyType.profit,
);

CompanySize? parseCompanySize(String? raw) {
  if (raw == null) return null;
  return CompanySize.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => CompanySize.piccola,
  );
}

AvanzamentoPratica parseAvanzamentoPratica(String? raw) => AvanzamentoPratica
    .values
    .firstWhere((v) => v.name == raw, orElse: () => AvanzamentoPratica.none);

EsitoPratica parseEsitoPratica(String? raw) => EsitoPratica.values.firstWhere(
  (v) => v.name == raw,
  orElse: () => EsitoPratica.none,
);

StatoRendicontazione parseStatoRendicontazione(String? raw) =>
    StatoRendicontazione.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => StatoRendicontazione.none,
    );

DateTime parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

// ─────────────────────────────────────────────
// AreaInvestimento (sezione del dataset aziendale)
// ─────────────────────────────────────────────

class AreaInvestimento {
  const AreaInvestimento({
    required this.categoria,
    this.descrizione = '',
    this.valoreStimato,
  });

  final String
  categoria; // es. "MACCHINARI ATTREZZATURE", "TRANSIZIONE ENERGETICA"
  final String descrizione; // breve descrizione libera
  final double? valoreStimato;

  factory AreaInvestimento.fromMap(Map<String, dynamic> map) =>
      AreaInvestimento(
        categoria: map['categoria'] as String? ?? '',
        descrizione: map['descrizione'] as String? ?? '',
        valoreStimato: (map['valoreStimato'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
    'categoria': categoria,
    'descrizione': descrizione,
    if (valoreStimato != null) 'valoreStimato': valoreStimato,
  };

  AreaInvestimento copyWith({
    String? categoria,
    String? descrizione,
    double? valoreStimato,
  }) => AreaInvestimento(
    categoria: categoria ?? this.categoria,
    descrizione: descrizione ?? this.descrizione,
    valoreStimato: valoreStimato ?? this.valoreStimato,
  );
}

// ─────────────────────────────────────────────
// Company (Anagrafica Cliente)
// ─────────────────────────────────────────────

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.vatNumber,
    required this.taxCode,
    required this.pec,
    required this.sdiCode,
    required this.email,
    required this.phone,
    required this.website,
    required this.addressLine,
    required this.city,
    required this.postalCode,
    required this.country,
    required this.contactPerson,
    required this.notes,
    // campi originali mantenuti
    this.isNonProfit = false,
    this.annualRevenue,
    this.employeesCount,
    this.legalRepresentative = '',
    this.incorporationDate,
    // ── nuovi campi da Excel ─────────────────────
    this.companyType = CompanyType.profit,
    this.riferimentoInterno = '',
    this.provincia = '',
    this.regione = '',
    this.sedeOperativaVia = '',
    this.sedeOperativaCap = '',
    this.sedeOperativaCitta = '',
    this.sedeOperativaProvincia = '',
    this.sedeOperativaRegione = '',
    this.dataInizioAttivita,
    this.lettereAteco = '',
    this.atecoPrimario = '',
    this.atecoSecondario = '',
    this.atecoTerziario = '',
    this.controllata = false,
    this.controllante = false,
    this.dimensioneImpresa,
    this.ula,
    this.export = false,
    this.percentualeExport,
    this.areeInvestimento = const [],
    this.ricaviAnnui = const {},
    this.customFields = const {},
  });

  final String id;
  final String name;
  final String vatNumber;
  final String taxCode;
  final String pec;
  final String sdiCode;
  final String email;
  final String phone;
  final String website;
  final String addressLine;
  final String city;
  final String postalCode;
  final String country;
  final String contactPerson;
  final String notes;
  final bool isNonProfit;
  final double? annualRevenue;
  final int? employeesCount;
  final String legalRepresentative;
  final DateTime? incorporationDate;

  // ── nuovi ──────────────────────────────────
  final CompanyType companyType;
  final String
  riferimentoInterno; // referente interno (es. "Silvio", "Stefano")
  final String provincia; // sede legale
  final String regione; // sede legale
  final String sedeOperativaVia;
  final String sedeOperativaCap;
  final String sedeOperativaCitta;
  final String sedeOperativaProvincia;
  final String sedeOperativaRegione;
  final DateTime? dataInizioAttivita;
  final String
  lettereAteco; // lettera categoria (es. "C. ATTIVITÀ MANIFATTURIERE")
  final String atecoPrimario;
  final String atecoSecondario;
  final String atecoTerziario;
  final bool controllata;
  final bool controllante;
  final CompanySize? dimensioneImpresa; // MICRO / PICCOLA / MEDIA / GRANDE
  final int? ula; // unità lavorative annue
  final bool export;
  final double? percentualeExport;
  final List<AreaInvestimento> areeInvestimento;
  final Map<int, double> ricaviAnnui; // {anno: ricavo} es. {2022: 500000.0}
  final Map<String, dynamic> customFields;

  double? get mediaRicavi {
    if (ricaviAnnui.isEmpty) return annualRevenue;
    final vals = ricaviAnnui.values.toList();
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  factory Company.fromMap(String id, Map<String, dynamic> map) {
    final rawAree = map['areeInvestimento'];
    final areeList = (rawAree is List) ? rawAree : <dynamic>[];
    // PHP può restituire [] invece di {} per mappe vuote
    final rawRicavi = map['ricaviAnnui'];
    final ricaviMap = (rawRicavi is Map)
        ? Map<String, dynamic>.from(rawRicavi)
        : <String, dynamic>{};
    return Company(
      id: id,
      name: map['name'] as String? ?? '',
      vatNumber: map['vatNumber'] as String? ?? '',
      taxCode: map['taxCode'] as String? ?? '',
      pec: map['pec'] as String? ?? '',
      sdiCode: map['sdiCode'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      website: map['website'] as String? ?? '',
      addressLine: map['addressLine'] as String? ?? '',
      city: map['city'] as String? ?? '',
      postalCode: map['postalCode'] as String? ?? '',
      country: map['country'] as String? ?? '',
      contactPerson: map['contactPerson'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      isNonProfit: map['isNonProfit'] as bool? ?? false,
      annualRevenue: (map['annualRevenue'] as num?)?.toDouble(),
      employeesCount: map['employeesCount'] as int?,
      legalRepresentative: map['legalRepresentative'] as String? ?? '',
      incorporationDate: map['incorporationDate'] != null
          ? parseDate(map['incorporationDate'])
          : null,
      companyType: parseCompanyType(map['companyType'] as String?),
      riferimentoInterno: map['riferimentoInterno'] as String? ?? '',
      provincia: map['provincia'] as String? ?? '',
      regione: map['regione'] as String? ?? '',
      sedeOperativaVia: map['sedeOperativaVia'] as String? ?? '',
      sedeOperativaCap: map['sedeOperativaCap'] as String? ?? '',
      sedeOperativaCitta: map['sedeOperativaCitta'] as String? ?? '',
      sedeOperativaProvincia: map['sedeOperativaProvincia'] as String? ?? '',
      sedeOperativaRegione: map['sedeOperativaRegione'] as String? ?? '',
      dataInizioAttivita: map['dataInizioAttivita'] != null
          ? parseDate(map['dataInizioAttivita'])
          : null,
      lettereAteco: map['lettereAteco'] as String? ?? '',
      atecoPrimario: map['atecoPrimario'] as String? ?? '',
      atecoSecondario: map['atecoSecondario'] as String? ?? '',
      atecoTerziario: map['atecoTerziario'] as String? ?? '',
      controllata: map['controllata'] as bool? ?? false,
      controllante: map['controllante'] as bool? ?? false,
      dimensioneImpresa: parseCompanySize(map['dimensioneImpresa'] as String?),
      ula: map['ula'] as int?,
      export: map['export'] as bool? ?? false,
      percentualeExport: (map['percentualeExport'] as num?)?.toDouble(),
      areeInvestimento: areeList
          .whereType<Map>()
          .map((e) => AreaInvestimento.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      ricaviAnnui: ricaviMap.map(
        (k, v) => MapEntry(int.tryParse(k) ?? 0, (v as num).toDouble()),
      ),
      customFields: normalizeCustomFieldValues(map['customFields']),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'vatNumber': vatNumber,
    'taxCode': taxCode,
    'pec': pec,
    'sdiCode': sdiCode,
    'email': email,
    'phone': phone,
    'website': website,
    'addressLine': addressLine,
    'city': city,
    'postalCode': postalCode,
    'country': country,
    'contactPerson': contactPerson,
    'notes': notes,
    'isNonProfit': isNonProfit,
    if (annualRevenue != null) 'annualRevenue': annualRevenue,
    if (employeesCount != null) 'employeesCount': employeesCount,
    'legalRepresentative': legalRepresentative,
    if (incorporationDate != null)
      'incorporationDate': Timestamp.fromDate(incorporationDate!),
    'companyType': companyType.name,
    'riferimentoInterno': riferimentoInterno,
    'provincia': provincia,
    'regione': regione,
    'sedeOperativaVia': sedeOperativaVia,
    'sedeOperativaCap': sedeOperativaCap,
    'sedeOperativaCitta': sedeOperativaCitta,
    'sedeOperativaProvincia': sedeOperativaProvincia,
    'sedeOperativaRegione': sedeOperativaRegione,
    if (dataInizioAttivita != null)
      'dataInizioAttivita': Timestamp.fromDate(dataInizioAttivita!),
    'lettereAteco': lettereAteco,
    'atecoPrimario': atecoPrimario,
    'atecoSecondario': atecoSecondario,
    'atecoTerziario': atecoTerziario,
    'controllata': controllata,
    'controllante': controllante,
    if (dimensioneImpresa != null) 'dimensioneImpresa': dimensioneImpresa!.name,
    if (ula != null) 'ula': ula,
    'export': export,
    if (percentualeExport != null) 'percentualeExport': percentualeExport,
    'areeInvestimento': areeInvestimento.map((a) => a.toMap()).toList(),
    'ricaviAnnui': ricaviAnnui.map((k, v) => MapEntry(k.toString(), v)),
    'customFields': customFields,
  };

  Company copyWith({
    String? id,
    String? name,
    String? vatNumber,
    String? taxCode,
    String? pec,
    String? sdiCode,
    String? email,
    String? phone,
    String? website,
    String? addressLine,
    String? city,
    String? postalCode,
    String? country,
    String? contactPerson,
    String? notes,
    bool? isNonProfit,
    double? annualRevenue,
    int? employeesCount,
    String? legalRepresentative,
    DateTime? incorporationDate,
    CompanyType? companyType,
    String? riferimentoInterno,
    String? provincia,
    String? regione,
    String? sedeOperativaVia,
    String? sedeOperativaCap,
    String? sedeOperativaCitta,
    String? sedeOperativaProvincia,
    String? sedeOperativaRegione,
    DateTime? dataInizioAttivita,
    String? lettereAteco,
    String? atecoPrimario,
    String? atecoSecondario,
    String? atecoTerziario,
    bool? controllata,
    bool? controllante,
    CompanySize? dimensioneImpresa,
    int? ula,
    bool? export,
    double? percentualeExport,
    List<AreaInvestimento>? areeInvestimento,
    Map<int, double>? ricaviAnnui,
    Map<String, dynamic>? customFields,
  }) => Company(
    id: id ?? this.id,
    name: name ?? this.name,
    vatNumber: vatNumber ?? this.vatNumber,
    taxCode: taxCode ?? this.taxCode,
    pec: pec ?? this.pec,
    sdiCode: sdiCode ?? this.sdiCode,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    website: website ?? this.website,
    addressLine: addressLine ?? this.addressLine,
    city: city ?? this.city,
    postalCode: postalCode ?? this.postalCode,
    country: country ?? this.country,
    contactPerson: contactPerson ?? this.contactPerson,
    notes: notes ?? this.notes,
    isNonProfit: isNonProfit ?? this.isNonProfit,
    annualRevenue: annualRevenue ?? this.annualRevenue,
    employeesCount: employeesCount ?? this.employeesCount,
    legalRepresentative: legalRepresentative ?? this.legalRepresentative,
    incorporationDate: incorporationDate ?? this.incorporationDate,
    companyType: companyType ?? this.companyType,
    riferimentoInterno: riferimentoInterno ?? this.riferimentoInterno,
    provincia: provincia ?? this.provincia,
    regione: regione ?? this.regione,
    sedeOperativaVia: sedeOperativaVia ?? this.sedeOperativaVia,
    sedeOperativaCap: sedeOperativaCap ?? this.sedeOperativaCap,
    sedeOperativaCitta: sedeOperativaCitta ?? this.sedeOperativaCitta,
    sedeOperativaProvincia:
        sedeOperativaProvincia ?? this.sedeOperativaProvincia,
    sedeOperativaRegione: sedeOperativaRegione ?? this.sedeOperativaRegione,
    dataInizioAttivita: dataInizioAttivita ?? this.dataInizioAttivita,
    lettereAteco: lettereAteco ?? this.lettereAteco,
    atecoPrimario: atecoPrimario ?? this.atecoPrimario,
    atecoSecondario: atecoSecondario ?? this.atecoSecondario,
    atecoTerziario: atecoTerziario ?? this.atecoTerziario,
    controllata: controllata ?? this.controllata,
    controllante: controllante ?? this.controllante,
    dimensioneImpresa: dimensioneImpresa ?? this.dimensioneImpresa,
    ula: ula ?? this.ula,
    export: export ?? this.export,
    percentualeExport: percentualeExport ?? this.percentualeExport,
    areeInvestimento: areeInvestimento ?? this.areeInvestimento,
    ricaviAnnui: ricaviAnnui ?? this.ricaviAnnui,
    customFields: customFields ?? this.customFields,
  );
}

// ─────────────────────────────────────────────
// Opportunity (Richiesta → Opportunità)
// ─────────────────────────────────────────────

class Opportunity {
  const Opportunity({
    required this.id,
    required this.companyId,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.createdByUserId,
    this.bandoReference = '',
    this.bandoSource = '',
    this.bandoDeadline,
    this.estimatedValue,
    this.notes = '',
    this.assignedAnalystId,
    this.analysisNotes = '',
    this.updatedAt,
    // ── campi commerciali da Excel ───────────────
    this.contactId,
    this.rifOfferta = '',
    this.contattoCommerciale = '',
    this.dataInvioPreventivo,
    this.dataConfermaPreventivo,
    this.presaInCarico = false,
    this.daFaturareA = '',
    this.partnerCommerciale = '',
    this.fornitore = '',
    this.scadenzaPresentazione,
    this.scadenzaOperativa,
    // ── campi pratica (bando) ────────────────────
    this.avanzamentoPratica = AvanzamentoPratica.none,
    this.esitoPratica = EsitoPratica.none,
    this.dataStato,
    this.totaleProgetto,
    this.totaleBeneficioEconomicoRichiesto,
    this.contributoRichiesto,
    this.finanziamentoRichiesto,
    this.garanziaRichiesta,
    this.creditoImpostaRichiesto,
    this.totaleProgettoRidefinito,
    this.totaleBeneficioEconomicoRicevuto,
    this.contributoRicevuto,
    this.finanziamentoRicevuto,
    this.garanziaRicevuta,
    this.creditoImpostaRicevuto,
    // ── rendicontazione ──────────────────────────
    this.termineRendicontazione,
    this.statoRendicontazione = StatoRendicontazione.none,
    this.noteRendicontazione = '',
    this.customFields = const {},
  });

  final String id;
  final String companyId;
  final String title;
  final OpportunityStatus status;
  final DateTime createdAt;
  final String createdByUserId;
  final String bandoReference;
  final String bandoSource;
  final DateTime? bandoDeadline;
  final double? estimatedValue;
  final String notes;
  final String? assignedAnalystId;
  final String analysisNotes;
  final DateTime? updatedAt;

  // ── campi commerciali ──────────────────────
  final String? contactId;
  final String rifOfferta; // es. "01.2025"
  final String
  contattoCommerciale; // iniziali/nome del commerciale (es. "SC", "SG")
  final DateTime? dataInvioPreventivo;
  final DateTime? dataConfermaPreventivo;
  final bool presaInCarico;
  final String daFaturareA; // "Beneficiario", nome partner, ecc.
  final String partnerCommerciale; // es. "Cna BG", "De Giorgi", "Pasotti"
  final String fornitore;
  final DateTime? scadenzaPresentazione;
  final DateTime? scadenzaOperativa;

  // ── campi pratica (bando) ──────────────────
  final AvanzamentoPratica avanzamentoPratica;
  final EsitoPratica esitoPratica;
  final DateTime? dataStato;
  final double? totaleProgetto;
  final double? totaleBeneficioEconomicoRichiesto;
  final double? contributoRichiesto;
  final double? finanziamentoRichiesto;
  final double? garanziaRichiesta;
  final double? creditoImpostaRichiesto;
  final double? totaleProgettoRidefinito;
  final double? totaleBeneficioEconomicoRicevuto;
  final double? contributoRicevuto;
  final double? finanziamentoRicevuto;
  final double? garanziaRicevuta;
  final double? creditoImpostaRicevuto;

  // ── rendicontazione ────────────────────────
  final DateTime? termineRendicontazione;
  final StatoRendicontazione statoRendicontazione;
  final String noteRendicontazione;
  final Map<String, dynamic> customFields;

  factory Opportunity.fromMap(String id, Map<String, dynamic> map) {
    return Opportunity(
      id: id,
      companyId: map['companyId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      status: parseOpportunityStatus(map['status'] as String?),
      createdAt: parseDate(map['createdAt']),
      createdByUserId: map['createdByUserId'] as String? ?? '',
      bandoReference: map['bandoReference'] as String? ?? '',
      bandoSource: map['bandoSource'] as String? ?? '',
      bandoDeadline: map['bandoDeadline'] != null
          ? parseDate(map['bandoDeadline'])
          : null,
      estimatedValue: (map['estimatedValue'] as num?)?.toDouble(),
      notes: map['notes'] as String? ?? '',
      assignedAnalystId: map['assignedAnalystId'] as String?,
      analysisNotes: map['analysisNotes'] as String? ?? '',
      updatedAt: map['updatedAt'] != null ? parseDate(map['updatedAt']) : null,
      contactId: map['contactId'] as String?,
      rifOfferta: map['rifOfferta'] as String? ?? '',
      contattoCommerciale: map['contattoCommerciale'] as String? ?? '',
      dataInvioPreventivo: map['dataInvioPreventivo'] != null
          ? parseDate(map['dataInvioPreventivo'])
          : null,
      dataConfermaPreventivo: map['dataConfermaPreventivo'] != null
          ? parseDate(map['dataConfermaPreventivo'])
          : null,
      presaInCarico: map['presaInCarico'] as bool? ?? false,
      daFaturareA: map['daFaturareA'] as String? ?? '',
      partnerCommerciale: map['partnerCommerciale'] as String? ?? '',
      fornitore: map['fornitore'] as String? ?? '',
      scadenzaPresentazione: map['scadenzaPresentazione'] != null
          ? parseDate(map['scadenzaPresentazione'])
          : null,
      scadenzaOperativa: map['scadenzaOperativa'] != null
          ? parseDate(map['scadenzaOperativa'])
          : null,
      avanzamentoPratica: parseAvanzamentoPratica(
        map['avanzamentoPratica'] as String?,
      ),
      esitoPratica: parseEsitoPratica(map['esitoPratica'] as String?),
      dataStato: map['dataStato'] != null ? parseDate(map['dataStato']) : null,
      totaleProgetto: (map['totaleProgetto'] as num?)?.toDouble(),
      totaleBeneficioEconomicoRichiesto:
          (map['totaleBeneficioEconomicoRichiesto'] as num?)?.toDouble(),
      contributoRichiesto: (map['contributoRichiesto'] as num?)?.toDouble(),
      finanziamentoRichiesto: (map['finanziamentoRichiesto'] as num?)
          ?.toDouble(),
      garanziaRichiesta: (map['garanziaRichiesta'] as num?)?.toDouble(),
      creditoImpostaRichiesto: (map['creditoImpostaRichiesto'] as num?)
          ?.toDouble(),
      totaleProgettoRidefinito: (map['totaleProgettoRidefinito'] as num?)
          ?.toDouble(),
      totaleBeneficioEconomicoRicevuto:
          (map['totaleBeneficioEconomicoRicevuto'] as num?)?.toDouble(),
      contributoRicevuto: (map['contributoRicevuto'] as num?)?.toDouble(),
      finanziamentoRicevuto: (map['finanziamentoRicevuto'] as num?)?.toDouble(),
      garanziaRicevuta: (map['garanziaRicevuta'] as num?)?.toDouble(),
      creditoImpostaRicevuto: (map['creditoImpostaRicevuto'] as num?)
          ?.toDouble(),
      termineRendicontazione: map['termineRendicontazione'] != null
          ? parseDate(map['termineRendicontazione'])
          : null,
      statoRendicontazione: parseStatoRendicontazione(
        map['statoRendicontazione'] as String?,
      ),
      noteRendicontazione: map['noteRendicontazione'] as String? ?? '',
      customFields: normalizeCustomFieldValues(map['customFields']),
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'title': title,
    'status': status.name,
    'createdAt': Timestamp.fromDate(createdAt),
    'createdByUserId': createdByUserId,
    'bandoReference': bandoReference,
    'bandoSource': bandoSource,
    if (bandoDeadline != null)
      'bandoDeadline': Timestamp.fromDate(bandoDeadline!),
    if (estimatedValue != null) 'estimatedValue': estimatedValue,
    'notes': notes,
    if (assignedAnalystId != null) 'assignedAnalystId': assignedAnalystId,
    'analysisNotes': analysisNotes,
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    if (contactId != null) 'contactId': contactId,
    'rifOfferta': rifOfferta,
    'contattoCommerciale': contattoCommerciale,
    if (dataInvioPreventivo != null)
      'dataInvioPreventivo': Timestamp.fromDate(dataInvioPreventivo!),
    if (dataConfermaPreventivo != null)
      'dataConfermaPreventivo': Timestamp.fromDate(dataConfermaPreventivo!),
    'presaInCarico': presaInCarico,
    'daFaturareA': daFaturareA,
    'partnerCommerciale': partnerCommerciale,
    'fornitore': fornitore,
    if (scadenzaPresentazione != null)
      'scadenzaPresentazione': Timestamp.fromDate(scadenzaPresentazione!),
    if (scadenzaOperativa != null)
      'scadenzaOperativa': Timestamp.fromDate(scadenzaOperativa!),
    'avanzamentoPratica': avanzamentoPratica.name,
    'esitoPratica': esitoPratica.name,
    if (dataStato != null) 'dataStato': Timestamp.fromDate(dataStato!),
    if (totaleProgetto != null) 'totaleProgetto': totaleProgetto,
    if (totaleBeneficioEconomicoRichiesto != null)
      'totaleBeneficioEconomicoRichiesto': totaleBeneficioEconomicoRichiesto,
    if (contributoRichiesto != null) 'contributoRichiesto': contributoRichiesto,
    if (finanziamentoRichiesto != null)
      'finanziamentoRichiesto': finanziamentoRichiesto,
    if (garanziaRichiesta != null) 'garanziaRichiesta': garanziaRichiesta,
    if (creditoImpostaRichiesto != null)
      'creditoImpostaRichiesto': creditoImpostaRichiesto,
    if (totaleProgettoRidefinito != null)
      'totaleProgettoRidefinito': totaleProgettoRidefinito,
    if (totaleBeneficioEconomicoRicevuto != null)
      'totaleBeneficioEconomicoRicevuto': totaleBeneficioEconomicoRicevuto,
    if (contributoRicevuto != null) 'contributoRicevuto': contributoRicevuto,
    if (finanziamentoRicevuto != null)
      'finanziamentoRicevuto': finanziamentoRicevuto,
    if (garanziaRicevuta != null) 'garanziaRicevuta': garanziaRicevuta,
    if (creditoImpostaRicevuto != null)
      'creditoImpostaRicevuto': creditoImpostaRicevuto,
    if (termineRendicontazione != null)
      'termineRendicontazione': Timestamp.fromDate(termineRendicontazione!),
    'statoRendicontazione': statoRendicontazione.name,
    'noteRendicontazione': noteRendicontazione,
    'customFields': customFields,
  };

  Opportunity copyWith({
    String? id,
    String? companyId,
    String? title,
    OpportunityStatus? status,
    DateTime? createdAt,
    String? createdByUserId,
    String? bandoReference,
    String? bandoSource,
    DateTime? bandoDeadline,
    double? estimatedValue,
    String? notes,
    String? assignedAnalystId,
    String? analysisNotes,
    DateTime? updatedAt,
    String? contactId,
    String? rifOfferta,
    String? contattoCommerciale,
    DateTime? dataInvioPreventivo,
    DateTime? dataConfermaPreventivo,
    bool? presaInCarico,
    String? daFaturareA,
    String? partnerCommerciale,
    String? fornitore,
    DateTime? scadenzaPresentazione,
    DateTime? scadenzaOperativa,
    AvanzamentoPratica? avanzamentoPratica,
    EsitoPratica? esitoPratica,
    DateTime? dataStato,
    double? totaleProgetto,
    double? totaleBeneficioEconomicoRichiesto,
    double? contributoRichiesto,
    double? finanziamentoRichiesto,
    double? garanziaRichiesta,
    double? creditoImpostaRichiesto,
    double? totaleProgettoRidefinito,
    double? totaleBeneficioEconomicoRicevuto,
    double? contributoRicevuto,
    double? finanziamentoRicevuto,
    double? garanziaRicevuta,
    double? creditoImpostaRicevuto,
    DateTime? termineRendicontazione,
    StatoRendicontazione? statoRendicontazione,
    String? noteRendicontazione,
    Map<String, dynamic>? customFields,
  }) => Opportunity(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    title: title ?? this.title,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    createdByUserId: createdByUserId ?? this.createdByUserId,
    bandoReference: bandoReference ?? this.bandoReference,
    bandoSource: bandoSource ?? this.bandoSource,
    bandoDeadline: bandoDeadline ?? this.bandoDeadline,
    estimatedValue: estimatedValue ?? this.estimatedValue,
    notes: notes ?? this.notes,
    assignedAnalystId: assignedAnalystId ?? this.assignedAnalystId,
    analysisNotes: analysisNotes ?? this.analysisNotes,
    updatedAt: updatedAt ?? this.updatedAt,
    contactId: contactId ?? this.contactId,
    rifOfferta: rifOfferta ?? this.rifOfferta,
    contattoCommerciale: contattoCommerciale ?? this.contattoCommerciale,
    dataInvioPreventivo: dataInvioPreventivo ?? this.dataInvioPreventivo,
    dataConfermaPreventivo:
        dataConfermaPreventivo ?? this.dataConfermaPreventivo,
    presaInCarico: presaInCarico ?? this.presaInCarico,
    daFaturareA: daFaturareA ?? this.daFaturareA,
    partnerCommerciale: partnerCommerciale ?? this.partnerCommerciale,
    fornitore: fornitore ?? this.fornitore,
    scadenzaPresentazione: scadenzaPresentazione ?? this.scadenzaPresentazione,
    scadenzaOperativa: scadenzaOperativa ?? this.scadenzaOperativa,
    avanzamentoPratica: avanzamentoPratica ?? this.avanzamentoPratica,
    esitoPratica: esitoPratica ?? this.esitoPratica,
    dataStato: dataStato ?? this.dataStato,
    totaleProgetto: totaleProgetto ?? this.totaleProgetto,
    totaleBeneficioEconomicoRichiesto:
        totaleBeneficioEconomicoRichiesto ??
        this.totaleBeneficioEconomicoRichiesto,
    contributoRichiesto: contributoRichiesto ?? this.contributoRichiesto,
    finanziamentoRichiesto:
        finanziamentoRichiesto ?? this.finanziamentoRichiesto,
    garanziaRichiesta: garanziaRichiesta ?? this.garanziaRichiesta,
    creditoImpostaRichiesto:
        creditoImpostaRichiesto ?? this.creditoImpostaRichiesto,
    totaleProgettoRidefinito:
        totaleProgettoRidefinito ?? this.totaleProgettoRidefinito,
    totaleBeneficioEconomicoRicevuto:
        totaleBeneficioEconomicoRicevuto ??
        this.totaleBeneficioEconomicoRicevuto,
    contributoRicevuto: contributoRicevuto ?? this.contributoRicevuto,
    finanziamentoRicevuto: finanziamentoRicevuto ?? this.finanziamentoRicevuto,
    garanziaRicevuta: garanziaRicevuta ?? this.garanziaRicevuta,
    creditoImpostaRicevuto:
        creditoImpostaRicevuto ?? this.creditoImpostaRicevuto,
    termineRendicontazione:
        termineRendicontazione ?? this.termineRendicontazione,
    statoRendicontazione: statoRendicontazione ?? this.statoRendicontazione,
    noteRendicontazione: noteRendicontazione ?? this.noteRendicontazione,
    customFields: customFields ?? this.customFields,
  );
}

// ─────────────────────────────────────────────
// Quotation (Preventivo)
// ─────────────────────────────────────────────

class PreventivoLine {
  const PreventivoLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.notes = '',
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final String notes;

  double get total => quantity * unitPrice;

  factory PreventivoLine.fromMap(Map<String, dynamic> map) => PreventivoLine(
    description: map['description'] as String? ?? '',
    quantity: (map['quantity'] as num? ?? 1).toDouble(),
    unitPrice: (map['unitPrice'] as num? ?? 0).toDouble(),
    notes: map['notes'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'description': description,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'notes': notes,
  };
}

class Preventivo {
  const Preventivo({
    required this.id,
    required this.opportunityId,
    required this.companyId,
    required this.status,
    required this.createdAt,
    required this.lines,
    this.istruttoriaFee = 0,
    this.successFeePercent,
    this.notes = '',
    this.sentAt,
    this.acceptedAt,
    this.expiresAt,
  });

  final String id;
  final String opportunityId;
  final String companyId;
  final PreventivoStatus status;
  final DateTime createdAt;
  final List<PreventivoLine> lines;
  final double istruttoriaFee;
  final double? successFeePercent; // override manuale; default griglia 9%/8%
  final String notes;
  final DateTime? sentAt;
  final DateTime? acceptedAt;
  final DateTime? expiresAt;

  double get subtotal => lines.fold(0, (s, l) => s + l.total);
  double get total => subtotal + istruttoriaFee;

  /// Success fee calcolata sugli scaglioni contrattuali.
  double calculateSuccessFee(double grantAmount) {
    if (successFeePercent != null) {
      return grantAmount * successFeePercent! / 100;
    }
    if (grantAmount <= 50000) return grantAmount * 0.09;
    return grantAmount * 0.08;
  }

  factory Preventivo.fromMap(String id, Map<String, dynamic> map) {
    final rawLines = map['lines'] as List<dynamic>? ?? const [];
    return Preventivo(
      id: id,
      opportunityId: map['opportunityId'] as String? ?? '',
      companyId: map['companyId'] as String? ?? '',
      status: parsePreventivoStatus(map['status'] as String?),
      createdAt: parseDate(map['createdAt']),
      lines: rawLines
          .whereType<Map>()
          .map((l) => PreventivoLine.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
      istruttoriaFee: (map['istruttoriaFee'] as num? ?? 0).toDouble(),
      successFeePercent: (map['successFeePercent'] as num?)?.toDouble(),
      notes: map['notes'] as String? ?? '',
      sentAt: map['sentAt'] != null ? parseDate(map['sentAt']) : null,
      acceptedAt: map['acceptedAt'] != null
          ? parseDate(map['acceptedAt'])
          : null,
      expiresAt: map['expiresAt'] != null ? parseDate(map['expiresAt']) : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'opportunityId': opportunityId,
    'companyId': companyId,
    'status': status.name,
    'createdAt': Timestamp.fromDate(createdAt),
    'lines': lines.map((l) => l.toMap()).toList(),
    'istruttoriaFee': istruttoriaFee,
    if (successFeePercent != null) 'successFeePercent': successFeePercent,
    'notes': notes,
    if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt!),
    if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt!),
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
  };

  Preventivo copyWith({
    String? id,
    String? opportunityId,
    String? companyId,
    PreventivoStatus? status,
    DateTime? createdAt,
    List<PreventivoLine>? lines,
    double? istruttoriaFee,
    double? successFeePercent,
    String? notes,
    DateTime? sentAt,
    DateTime? acceptedAt,
    DateTime? expiresAt,
  }) => Preventivo(
    id: id ?? this.id,
    opportunityId: opportunityId ?? this.opportunityId,
    companyId: companyId ?? this.companyId,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    lines: lines ?? this.lines,
    istruttoriaFee: istruttoriaFee ?? this.istruttoriaFee,
    successFeePercent: successFeePercent ?? this.successFeePercent,
    notes: notes ?? this.notes,
    sentAt: sentAt ?? this.sentAt,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
}

// ─────────────────────────────────────────────
// Project (Commessa)
// ─────────────────────────────────────────────

/// Fasi standard con i task relativi — create automaticamente alla creazione del progetto.
const List<String> kDefaultPhaseNames = [
  'Istruttoria',
  'Invio Documentazione',
  'Gestione Integrazioni',
  'Attesa Istruttoria',
  'Esito Domanda',
  'Fatturazione Premialità',
  'Rendicontazione',
];

/// Definizione completa di ogni fase standard con i task associati.
const kProjectPhaseDefinitions = <({String name, List<String> tasks})>[
  (
    name: 'Istruttoria',
    tasks: [
      'Richiesta documentazione amministrativa al cliente',
      'Richiesta documentazione tecnica specifica del progetto',
      'Raccolta e verifica completezza documentale',
      'Analisi normativa e requisiti del bando',
      'Predisposizione modulistica e allegati',
      'Redazione documenti progettuali',
      'Coordinamento con fornitori e partner',
      'Preparazione documenti per caricamento su portale',
    ],
  ),
  (
    name: 'Invio Documentazione',
    tasks: [
      'Accesso piattaforma mediante delega o SPID',
      'Caricamento documenti e modulistica',
      'Invio domanda / istruttoria',
      'Verifica ricezione e conferma invio',
      'Fatturazione se prevista in fase di presentazione',
    ],
  ),
  (
    name: 'Gestione Integrazioni',
    tasks: [
      'Ricezione richieste di integrazione dall\'ente',
      'Analisi richieste',
      'Raccolta documenti integrativi',
      'Predisposizione risposte tecniche',
      'Invio integrazioni via PEC o portale',
    ],
  ),
  (
    name: 'Attesa Istruttoria',
    tasks: [
      'Monitoraggio stato domanda',
      'Interazioni con ente istruttore se necessario',
    ],
  ),
  (
    name: 'Esito Domanda',
    tasks: [
      'Ricezione esito (positivo / negativo)',
      'Comunicazione esito al cliente',
      'In caso negativo: chiusura pratica o valutazione alternative',
      'In caso positivo: avvio fase di gestione beneficio',
    ],
  ),
  (
    name: 'Fatturazione Premialità',
    tasks: [
      'Calcolo beneficio ottenuto dall\'azienda',
      'Emissione fattura a premialità / successo',
    ],
  ),
  (
    name: 'Rendicontazione',
    tasks: [
      '12A — Raccolta documenti di spesa e pagamento',
      '12A — Verifica conformità amministrativa e tecnica',
      '12B — Predisposizione report rendicontazione',
      '12B — Compilazione modelli ente',
      '12B — Verifica finale con cliente',
      '12C — Caricamento documenti su portale',
      '12C — Invio rendicontazione finale',
    ],
  ),
];

/// Configurazione di una fase durante la creazione guidata del progetto.
class PhaseConfig {
  const PhaseConfig({
    required this.phaseName,
    required this.taskNames,
    this.startDate,
    this.endDate,
    this.assigneeId,
  });

  final String phaseName;
  final List<String> taskNames;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? assigneeId;

  PhaseConfig copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? assigneeId,
  }) => PhaseConfig(
    phaseName: phaseName,
    taskNames: taskNames,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    assigneeId: assigneeId ?? this.assigneeId,
  );
}

class ProjectTemplatePhase {
  const ProjectTemplatePhase({required this.name, required this.tasks});

  final String name;
  final List<String> tasks;

  factory ProjectTemplatePhase.fromMap(Map<String, dynamic> map) =>
      ProjectTemplatePhase(
        name: map['name'] as String? ?? '',
        tasks: ((map['tasks'] as List?) ?? const [])
            .map((item) => item?.toString() ?? '')
            .where((item) => item.trim().isNotEmpty)
            .toList(),
      );

  Map<String, dynamic> toMap() => {'name': name, 'tasks': tasks};

  ProjectTemplatePhase copyWith({String? name, List<String>? tasks}) =>
      ProjectTemplatePhase(name: name ?? this.name, tasks: tasks ?? this.tasks);
}

class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.phases,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final List<ProjectTemplatePhase> phases;
  final bool isDefault;

  factory ProjectTemplate.fromMap(Map<String, dynamic> map) => ProjectTemplate(
    id: map['id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    phases: ((map['phases'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ProjectTemplatePhase.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList(),
    isDefault: map['isDefault'] == true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phases': phases.map((phase) => phase.toMap()).toList(),
    'isDefault': isDefault,
  };

  List<PhaseConfig> toPhaseConfigs() => phases
      .map(
        (phase) => PhaseConfig(phaseName: phase.name, taskNames: phase.tasks),
      )
      .toList();

  ProjectTemplate copyWith({
    String? id,
    String? name,
    List<ProjectTemplatePhase>? phases,
    bool? isDefault,
  }) => ProjectTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    phases: phases ?? this.phases,
    isDefault: isDefault ?? this.isDefault,
  );
}

final ProjectTemplate kStandardProjectTemplate = ProjectTemplate(
  id: 'standard',
  name: 'Template standard',
  isDefault: true,
  phases: kProjectPhaseDefinitions
      .map(
        (def) => ProjectTemplatePhase(
          name: def.name,
          tasks: List<String>.from(def.tasks),
        ),
      )
      .toList(),
);

class Project {
  const Project({
    required this.id,
    required this.companyId,
    required this.name,
    required this.code,
    required this.status,
    this.type = ProjectType.profit,
    this.createdAt,
    this.opportunityId,
    this.quotationId,
    this.dealId,
    this.grantAmount,
    this.successFeeAmount,
    this.notes = '',
    this.closedAt,
    this.anticipoEmesso = false,
    // ── nuovi campi da Excel ─────────────────────
    this.rifProgetto = '',
    this.rifCaricamento = '',
    this.idProgettoEsterno = '',
    this.titoloProgetto = '',
    this.dataInizioProgetto,
    this.dataFineProgetto,
    this.daFaturareA = '',
    // importi richiesti
    this.totaleProgetto,
    this.totaleBeneficioEconomicoRichiesto,
    this.contributoRichiesto,
    this.finanziamentoRichiesto,
    this.garanziaRichiesta,
    this.creditoImpostaRichiesto,
    // avanzamento e esito pratica
    this.avanzamentoPratica = AvanzamentoPratica.none,
    this.esitoPratica = EsitoPratica.none,
    this.dataStato,
    // importi ricevuti (post-concessione)
    this.totaleProgettoRidefinito,
    this.totaleBeneficioEconomicoRicevuto,
    this.contributoRicevuto,
    this.finanziamentoRicevuto,
    this.garanziaRicevuta,
    this.creditoImpostaRicevuto,
    // rendicontazione
    this.termineRendicontazione,
    this.statoRendicontazione = StatoRendicontazione.none,
    this.customFields = const {},
  });

  final String id;
  final String companyId;
  final String name;
  final String code;
  final String status;
  final ProjectType type;
  final DateTime? createdAt;
  final String? opportunityId;
  final String? quotationId;
  final String? dealId;
  final double? grantAmount;
  final double? successFeeAmount;
  final String notes;
  final DateTime? closedAt;
  final bool
  anticipoEmesso; // true = fattura anticipo/avvio servizio già emessa

  // ── nuovi ──────────────────────────────────
  final String rifProgetto; // es. "SC", "SP", "LC" (tipo portale/percorso)
  final String rifCaricamento; // riferimento per il caricamento documentale
  final String idProgettoEsterno; // ID assegnato dall'ente (es. "TR5-28136")
  final String titoloProgetto; // titolo ufficiale del progetto presso l'ente
  final DateTime? dataInizioProgetto;
  final DateTime? dataFineProgetto;
  final String daFaturareA; // "Beneficiario", nome partner, ecc.

  // importi richiesti al momento della domanda
  final double? totaleProgetto;
  final double? totaleBeneficioEconomicoRichiesto;
  final double? contributoRichiesto;
  final double? finanziamentoRichiesto;
  final double? garanziaRichiesta;
  final double? creditoImpostaRichiesto;

  // stato avanzamento
  final AvanzamentoPratica avanzamentoPratica;
  final EsitoPratica esitoPratica;
  final DateTime? dataStato;

  // importi effettivamente ricevuti (post-concessione)
  final double? totaleProgettoRidefinito;
  final double? totaleBeneficioEconomicoRicevuto;
  final double? contributoRicevuto;
  final double? finanziamentoRicevuto;
  final double? garanziaRicevuta;
  final double? creditoImpostaRicevuto;

  // rendicontazione
  final DateTime? termineRendicontazione;
  final StatoRendicontazione statoRendicontazione;
  final Map<String, dynamic> customFields;

  ProjectStatus get projectStatus => parseProjectStatus(status);

  factory Project.fromMap(String id, Map<String, dynamic> map) {
    return Project(
      id: id,
      companyId: map['companyId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      code: map['code'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      type: parseProjectType(map['type'] as String?),
      createdAt: map['createdAt'] != null ? parseDate(map['createdAt']) : null,
      opportunityId: map['opportunityId'] as String?,
      quotationId: map['quotationId'] as String?,
      dealId: map['dealId'] as String?,
      grantAmount: (map['grantAmount'] as num?)?.toDouble(),
      successFeeAmount: (map['successFeeAmount'] as num?)?.toDouble(),
      notes: map['notes'] as String? ?? '',
      closedAt: map['closedAt'] != null ? parseDate(map['closedAt']) : null,
      anticipoEmesso: map['anticipoEmesso'] as bool? ?? false,
      rifProgetto: map['rifProgetto'] as String? ?? '',
      rifCaricamento: map['rifCaricamento'] as String? ?? '',
      idProgettoEsterno: map['idProgettoEsterno'] as String? ?? '',
      titoloProgetto: map['titoloProgetto'] as String? ?? '',
      dataInizioProgetto: map['dataInizioProgetto'] != null
          ? parseDate(map['dataInizioProgetto'])
          : null,
      dataFineProgetto: map['dataFineProgetto'] != null
          ? parseDate(map['dataFineProgetto'])
          : null,
      daFaturareA: map['daFaturareA'] as String? ?? '',
      totaleProgetto: (map['totaleProgetto'] as num?)?.toDouble(),
      totaleBeneficioEconomicoRichiesto:
          (map['totaleBeneficioEconomicoRichiesto'] as num?)?.toDouble(),
      contributoRichiesto: (map['contributoRichiesto'] as num?)?.toDouble(),
      finanziamentoRichiesto: (map['finanziamentoRichiesto'] as num?)
          ?.toDouble(),
      garanziaRichiesta: (map['garanziaRichiesta'] as num?)?.toDouble(),
      creditoImpostaRichiesto: (map['creditoImpostaRichiesto'] as num?)
          ?.toDouble(),
      avanzamentoPratica: parseAvanzamentoPratica(
        map['avanzamentoPratica'] as String?,
      ),
      esitoPratica: parseEsitoPratica(map['esitoPratica'] as String?),
      dataStato: map['dataStato'] != null ? parseDate(map['dataStato']) : null,
      totaleProgettoRidefinito: (map['totaleProgettoRidefinito'] as num?)
          ?.toDouble(),
      totaleBeneficioEconomicoRicevuto:
          (map['totaleBeneficioEconomicoRicevuto'] as num?)?.toDouble(),
      contributoRicevuto: (map['contributoRicevuto'] as num?)?.toDouble(),
      finanziamentoRicevuto: (map['finanziamentoRicevuto'] as num?)?.toDouble(),
      garanziaRicevuta: (map['garanziaRicevuta'] as num?)?.toDouble(),
      creditoImpostaRicevuto: (map['creditoImpostaRicevuto'] as num?)
          ?.toDouble(),
      termineRendicontazione: map['termineRendicontazione'] != null
          ? parseDate(map['termineRendicontazione'])
          : null,
      statoRendicontazione: parseStatoRendicontazione(
        map['statoRendicontazione'] as String?,
      ),
      customFields: normalizeCustomFieldValues(map['customFields']),
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'name': name,
    'code': code,
    'status': status,
    'type': type.name,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    if (opportunityId != null) 'opportunityId': opportunityId,
    if (quotationId != null) 'quotationId': quotationId,
    if (dealId != null) 'dealId': dealId,
    if (grantAmount != null) 'grantAmount': grantAmount,
    if (successFeeAmount != null) 'successFeeAmount': successFeeAmount,
    'notes': notes,
    if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
    'anticipoEmesso': anticipoEmesso,
    'rifProgetto': rifProgetto,
    'rifCaricamento': rifCaricamento,
    'idProgettoEsterno': idProgettoEsterno,
    'titoloProgetto': titoloProgetto,
    if (dataInizioProgetto != null)
      'dataInizioProgetto': Timestamp.fromDate(dataInizioProgetto!),
    if (dataFineProgetto != null)
      'dataFineProgetto': Timestamp.fromDate(dataFineProgetto!),
    'daFaturareA': daFaturareA,
    if (totaleProgetto != null) 'totaleProgetto': totaleProgetto,
    if (totaleBeneficioEconomicoRichiesto != null)
      'totaleBeneficioEconomicoRichiesto': totaleBeneficioEconomicoRichiesto,
    if (contributoRichiesto != null) 'contributoRichiesto': contributoRichiesto,
    if (finanziamentoRichiesto != null)
      'finanziamentoRichiesto': finanziamentoRichiesto,
    if (garanziaRichiesta != null) 'garanziaRichiesta': garanziaRichiesta,
    if (creditoImpostaRichiesto != null)
      'creditoImpostaRichiesto': creditoImpostaRichiesto,
    'avanzamentoPratica': avanzamentoPratica.name,
    'esitoPratica': esitoPratica.name,
    if (dataStato != null) 'dataStato': Timestamp.fromDate(dataStato!),
    if (totaleProgettoRidefinito != null)
      'totaleProgettoRidefinito': totaleProgettoRidefinito,
    if (totaleBeneficioEconomicoRicevuto != null)
      'totaleBeneficioEconomicoRicevuto': totaleBeneficioEconomicoRicevuto,
    if (contributoRicevuto != null) 'contributoRicevuto': contributoRicevuto,
    if (finanziamentoRicevuto != null)
      'finanziamentoRicevuto': finanziamentoRicevuto,
    if (garanziaRicevuta != null) 'garanziaRicevuta': garanziaRicevuta,
    if (creditoImpostaRicevuto != null)
      'creditoImpostaRicevuto': creditoImpostaRicevuto,
    if (termineRendicontazione != null)
      'termineRendicontazione': Timestamp.fromDate(termineRendicontazione!),
    'statoRendicontazione': statoRendicontazione.name,
    'customFields': customFields,
  };

  Project copyWith({
    String? companyId,
    String? name,
    String? code,
    String? status,
    ProjectType? type,
    String? dealId,
    double? grantAmount,
    double? successFeeAmount,
    String? notes,
    DateTime? closedAt,
    bool? anticipoEmesso,
    String? rifProgetto,
    String? rifCaricamento,
    String? idProgettoEsterno,
    String? titoloProgetto,
    DateTime? dataInizioProgetto,
    DateTime? dataFineProgetto,
    String? daFaturareA,
    double? totaleProgetto,
    double? totaleBeneficioEconomicoRichiesto,
    double? contributoRichiesto,
    double? finanziamentoRichiesto,
    double? garanziaRichiesta,
    double? creditoImpostaRichiesto,
    AvanzamentoPratica? avanzamentoPratica,
    EsitoPratica? esitoPratica,
    DateTime? dataStato,
    double? totaleProgettoRidefinito,
    double? totaleBeneficioEconomicoRicevuto,
    double? contributoRicevuto,
    double? finanziamentoRicevuto,
    double? garanziaRicevuta,
    double? creditoImpostaRicevuto,
    DateTime? termineRendicontazione,
    StatoRendicontazione? statoRendicontazione,
    Map<String, dynamic>? customFields,
  }) => Project(
    id: id,
    companyId: companyId ?? this.companyId,
    name: name ?? this.name,
    code: code ?? this.code,
    status: status ?? this.status,
    type: type ?? this.type,
    createdAt: createdAt,
    opportunityId: opportunityId,
    quotationId: quotationId,
    dealId: dealId ?? this.dealId,
    grantAmount: grantAmount ?? this.grantAmount,
    successFeeAmount: successFeeAmount ?? this.successFeeAmount,
    notes: notes ?? this.notes,
    closedAt: closedAt ?? this.closedAt,
    anticipoEmesso: anticipoEmesso ?? this.anticipoEmesso,
    rifProgetto: rifProgetto ?? this.rifProgetto,
    rifCaricamento: rifCaricamento ?? this.rifCaricamento,
    idProgettoEsterno: idProgettoEsterno ?? this.idProgettoEsterno,
    titoloProgetto: titoloProgetto ?? this.titoloProgetto,
    dataInizioProgetto: dataInizioProgetto ?? this.dataInizioProgetto,
    dataFineProgetto: dataFineProgetto ?? this.dataFineProgetto,
    daFaturareA: daFaturareA ?? this.daFaturareA,
    totaleProgetto: totaleProgetto ?? this.totaleProgetto,
    totaleBeneficioEconomicoRichiesto:
        totaleBeneficioEconomicoRichiesto ??
        this.totaleBeneficioEconomicoRichiesto,
    contributoRichiesto: contributoRichiesto ?? this.contributoRichiesto,
    finanziamentoRichiesto:
        finanziamentoRichiesto ?? this.finanziamentoRichiesto,
    garanziaRichiesta: garanziaRichiesta ?? this.garanziaRichiesta,
    creditoImpostaRichiesto:
        creditoImpostaRichiesto ?? this.creditoImpostaRichiesto,
    avanzamentoPratica: avanzamentoPratica ?? this.avanzamentoPratica,
    esitoPratica: esitoPratica ?? this.esitoPratica,
    dataStato: dataStato ?? this.dataStato,
    totaleProgettoRidefinito:
        totaleProgettoRidefinito ?? this.totaleProgettoRidefinito,
    totaleBeneficioEconomicoRicevuto:
        totaleBeneficioEconomicoRicevuto ??
        this.totaleBeneficioEconomicoRicevuto,
    contributoRicevuto: contributoRicevuto ?? this.contributoRicevuto,
    finanziamentoRicevuto: finanziamentoRicevuto ?? this.finanziamentoRicevuto,
    garanziaRicevuta: garanziaRicevuta ?? this.garanziaRicevuta,
    creditoImpostaRicevuto:
        creditoImpostaRicevuto ?? this.creditoImpostaRicevuto,
    termineRendicontazione:
        termineRendicontazione ?? this.termineRendicontazione,
    statoRendicontazione: statoRendicontazione ?? this.statoRendicontazione,
    customFields: customFields ?? this.customFields,
  );
}

// ─────────────────────────────────────────────
// ProjectPhase (Fase progetto)
// ─────────────────────────────────────────────

class ProjectPhase {
  const ProjectPhase({
    required this.id,
    required this.projectId,
    required this.name,
    required this.order,
    this.status = PhaseStatus.notStarted,
    this.assignedUserId,
    this.startDate,
    this.deadline,
    this.notes = '',
    this.isCustom = false,
  });

  final String id;
  final String projectId;
  final String name;
  final int order;
  final PhaseStatus status;
  final String? assignedUserId;
  final DateTime? startDate;
  final DateTime? deadline;
  final String notes;
  final bool isCustom; // true = fase aggiunta manualmente

  factory ProjectPhase.fromMap(String id, Map<String, dynamic> map) {
    return ProjectPhase(
      id: id,
      projectId: map['projectId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      order: map['order'] as int? ?? 0,
      status: parsePhaseStatus(map['status'] as String?),
      assignedUserId: map['assignedUserId'] as String?,
      startDate: map['startDate'] != null ? parseDate(map['startDate']) : null,
      deadline: map['deadline'] != null ? parseDate(map['deadline']) : null,
      notes: map['notes'] as String? ?? '',
      isCustom: map['isCustom'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'projectId': projectId,
    'name': name,
    'order': order,
    'status': status.name,
    if (assignedUserId != null) 'assignedUserId': assignedUserId,
    if (startDate != null) 'startDate': Timestamp.fromDate(startDate!),
    if (deadline != null) 'deadline': Timestamp.fromDate(deadline!),
    'notes': notes,
    'isCustom': isCustom,
  };

  ProjectPhase copyWith({
    String? name,
    int? order,
    PhaseStatus? status,
    String? assignedUserId,
    DateTime? startDate,
    DateTime? deadline,
    String? notes,
  }) => ProjectPhase(
    id: id,
    projectId: projectId,
    name: name ?? this.name,
    order: order ?? this.order,
    status: status ?? this.status,
    assignedUserId: assignedUserId ?? this.assignedUserId,
    startDate: startDate ?? this.startDate,
    deadline: deadline ?? this.deadline,
    notes: notes ?? this.notes,
    isCustom: isCustom,
  );
}

// ─────────────────────────────────────────────
// DMS – Document Management System
// ─────────────────────────────────────────────

/// Le 4 cartelle standard obbligatorie per ogni progetto.
enum DmsFolder {
  istituzionali, // 01 – Visure, bilanci, documenti identità, atti costitutivi
  commerciale, // 02 – Preventivi, contratti, corrispondenza tariffaria
  progettazione, // 03 – Modelli progetto, documentazione tecnica, narrativa
  istruttoria, // 04 – Documenti inviati (P7M/Digital Sign), ricevute portali
}

extension DmsFolderExt on DmsFolder {
  String get label {
    switch (this) {
      case DmsFolder.istituzionali:
        return '01 – Istituzionali';
      case DmsFolder.commerciale:
        return '02 – Commerciale';
      case DmsFolder.progettazione:
        return '03 – Progettazione';
      case DmsFolder.istruttoria:
        return '04 – Istruttoria';
    }
  }

  String get storagePath {
    switch (this) {
      case DmsFolder.istituzionali:
        return '01_istituzionali';
      case DmsFolder.commerciale:
        return '02_commerciale';
      case DmsFolder.progettazione:
        return '03_progettazione';
      case DmsFolder.istruttoria:
        return '04_istruttoria';
    }
  }
}

// ─────────────────────────────────────────────
// WorkTask
// ─────────────────────────────────────────────

class WorkTask {
  const WorkTask({
    required this.id,
    required this.companyId,
    required this.projectId,
    required this.phaseId,
    required this.assigneeId,
    required this.name,
    required this.estimatedHours,
    required this.loggedHours,
    required this.startDate,
    required this.deadline,
    required this.status,
    required this.billable,
  });

  final String id;
  final String companyId;
  final String projectId;
  final String phaseId;
  final String assigneeId;
  final String name;
  final double estimatedHours;
  final double loggedHours;
  final DateTime startDate;
  final DateTime deadline;
  final TaskStatus status;
  final bool billable;

  double get remainingHours =>
      (estimatedHours - loggedHours).clamp(0, estimatedHours).toDouble();

  factory WorkTask.fromMap(String id, Map<String, dynamic> map) {
    final deadline = parseDate(map['deadline']);
    return WorkTask(
      id: id,
      companyId: map['companyId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      phaseId: map['phaseId'] as String? ?? '',
      assigneeId: map['assigneeId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      estimatedHours: (map['estimatedHours'] as num? ?? 0).toDouble(),
      loggedHours: (map['loggedHours'] as num? ?? 0).toDouble(),
      startDate: parseDate(map['startDate'] ?? deadline),
      deadline: deadline,
      status: parseTaskStatus(map['status'] as String?),
      billable: map['billable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'projectId': projectId,
    'phaseId': phaseId,
    'assigneeId': assigneeId,
    'name': name,
    'estimatedHours': estimatedHours,
    'loggedHours': loggedHours,
    'startDate': Timestamp.fromDate(startDate),
    'deadline': Timestamp.fromDate(deadline),
    'status': status.name,
    'billable': billable,
  };

  WorkTask copyWith({
    String? id,
    String? companyId,
    String? projectId,
    String? phaseId,
    String? assigneeId,
    String? name,
    double? estimatedHours,
    double? loggedHours,
    DateTime? startDate,
    DateTime? deadline,
    TaskStatus? status,
    bool? billable,
  }) => WorkTask(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    projectId: projectId ?? this.projectId,
    phaseId: phaseId ?? this.phaseId,
    assigneeId: assigneeId ?? this.assigneeId,
    name: name ?? this.name,
    estimatedHours: estimatedHours ?? this.estimatedHours,
    loggedHours: loggedHours ?? this.loggedHours,
    startDate: startDate ?? this.startDate,
    deadline: deadline ?? this.deadline,
    status: status ?? this.status,
    billable: billable ?? this.billable,
  );
}

// ─────────────────────────────────────────────
// InvoiceDraft (Fattura in bozza)
// ─────────────────────────────────────────────

class InvoiceLine {
  const InvoiceLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.vatPercent = 22.0,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double vatPercent;

  double get net => quantity * unitPrice;
  double get vat => net * vatPercent / 100;
  double get gross => net + vat;

  factory InvoiceLine.fromMap(Map<String, dynamic> map) => InvoiceLine(
    description: map['description'] as String? ?? '',
    quantity: (map['quantity'] as num? ?? 1).toDouble(),
    unitPrice: (map['unitPrice'] as num? ?? 0).toDouble(),
    vatPercent: (map['vatPercent'] as num? ?? 22).toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'description': description,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'vatPercent': vatPercent,
  };
}

class InvoiceDraft {
  const InvoiceDraft({
    required this.id,
    required this.companyId,
    required this.number,
    required this.amount,
    required this.status,
    this.projectId,
    this.lines = const [],
    this.isSuccessFee = false,
    this.grantAmount,
    this.notes = '',
    this.paymentStatus = 'unpaid',
    this.paidAmount = 0,
    this.balanceDue,
    this.paidAt,
    this.posOriginPaymentId,
    this.createdAt,
    this.sentAt,
  });

  final String id;
  final String companyId;
  final String number;
  final double amount;
  final InvoiceStatus status;
  final String? projectId;
  final List<InvoiceLine> lines;
  final bool isSuccessFee; // true = fattura di premialità
  final double? grantAmount; // contributo su cui è calcolata la success fee
  final String notes;
  final String paymentStatus;
  final double paidAmount;
  final double? balanceDue;
  final DateTime? paidAt;
  final String? posOriginPaymentId;
  final DateTime? createdAt;
  final DateTime? sentAt;

  bool get isPaid => paymentStatus == 'paid';
  bool get isPartiallyPaid => paymentStatus == 'partially_paid';
  double get residualAmount => balanceDue ?? (amount - paidAmount);

  factory InvoiceDraft.fromMap(String id, Map<String, dynamic> map) {
    final rawLines = map['lines'] as List<dynamic>? ?? const [];
    return InvoiceDraft(
      id: id,
      companyId: map['companyId'] as String? ?? '',
      number: map['number'] as String? ?? '',
      amount: (map['amount'] as num? ?? 0).toDouble(),
      status: parseInvoiceStatus(map['status'] as String?),
      projectId: map['projectId'] as String?,
      lines: rawLines
          .whereType<Map>()
          .map((l) => InvoiceLine.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
      isSuccessFee: map['isSuccessFee'] as bool? ?? false,
      grantAmount: (map['grantAmount'] as num?)?.toDouble(),
      notes: map['notes'] as String? ?? '',
      paymentStatus:
          (map['paymentStatus'] as String? ?? 'unpaid').trim().isEmpty
          ? 'unpaid'
          : (map['paymentStatus'] as String? ?? 'unpaid'),
      paidAmount: (map['paidAmount'] as num? ?? 0).toDouble(),
      balanceDue: (map['balanceDue'] as num?)?.toDouble(),
      paidAt: map['paidAt'] != null ? parseDate(map['paidAt']) : null,
      posOriginPaymentId: (() {
        final raw = (map['posOriginPaymentId'] as String?)?.trim() ?? '';
        return raw.isEmpty ? null : raw;
      })(),
      createdAt: map['createdAt'] != null ? parseDate(map['createdAt']) : null,
      sentAt: map['sentAt'] != null ? parseDate(map['sentAt']) : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'number': number,
    'amount': amount,
    'status': status.name,
    if (projectId != null) 'projectId': projectId,
    'lines': lines.map((l) => l.toMap()).toList(),
    'isSuccessFee': isSuccessFee,
    if (grantAmount != null) 'grantAmount': grantAmount,
    'notes': notes,
    'paymentStatus': paymentStatus,
    'paidAmount': paidAmount,
    if (balanceDue != null) 'balanceDue': balanceDue,
    if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
    if (posOriginPaymentId != null) 'posOriginPaymentId': posOriginPaymentId,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt!),
  };

  InvoiceDraft copyWith({
    String? id,
    String? companyId,
    String? number,
    double? amount,
    InvoiceStatus? status,
    String? projectId,
    List<InvoiceLine>? lines,
    bool? isSuccessFee,
    double? grantAmount,
    String? notes,
    String? paymentStatus,
    double? paidAmount,
    double? balanceDue,
    DateTime? paidAt,
    String? posOriginPaymentId,
    DateTime? createdAt,
    DateTime? sentAt,
  }) => InvoiceDraft(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    number: number ?? this.number,
    amount: amount ?? this.amount,
    status: status ?? this.status,
    projectId: projectId ?? this.projectId,
    lines: lines ?? this.lines,
    isSuccessFee: isSuccessFee ?? this.isSuccessFee,
    grantAmount: grantAmount ?? this.grantAmount,
    notes: notes ?? this.notes,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paidAmount: paidAmount ?? this.paidAmount,
    balanceDue: balanceDue ?? this.balanceDue,
    paidAt: paidAt ?? this.paidAt,
    posOriginPaymentId: posOriginPaymentId ?? this.posOriginPaymentId,
    createdAt: createdAt ?? this.createdAt,
    sentAt: sentAt ?? this.sentAt,
  );
}

// ─────────────────────────────────────────────
// Models ereditati da nexora (invariati)
// ─────────────────────────────────────────────

class UserAvailability {
  const UserAvailability({
    required this.weekday,
    required this.hours,
    required this.isOff,
  });
  final int weekday;
  final double hours;
  final bool isOff;

  factory UserAvailability.fromMap(String id, Map<String, dynamic> map) =>
      UserAvailability(
        weekday: map['weekday'] as int? ?? int.tryParse(id) ?? DateTime.monday,
        hours: (map['hours'] as num? ?? 0).toDouble(),
        isOff: map['isOff'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
    'weekday': weekday,
    'hours': hours,
    'isOff': isOff,
  };
}

class VacationPeriod {
  const VacationPeriod({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.label = '',
  });
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String label;

  factory VacationPeriod.fromMap(String id, Map<String, dynamic> map) =>
      VacationPeriod(
        id: id,
        startDate: parseDate(map['startDate']),
        endDate: parseDate(map['endDate']),
        label: map['label'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
    'startDate': Timestamp.fromDate(startDate),
    'endDate': Timestamp.fromDate(endDate),
    'label': label,
  };

  bool includes(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }
}

class TimelineSlot {
  const TimelineSlot({
    required this.id,
    required this.taskId,
    required this.date,
    required this.plannedHours,
    required this.startHour,
  });
  final String id;
  final String taskId;
  final DateTime date;
  final double plannedHours;
  final double startHour;

  factory TimelineSlot.fromMap(String id, Map<String, dynamic> map) =>
      TimelineSlot(
        id: id,
        taskId: map['taskId'] as String? ?? '',
        date: parseDate(map['date']),
        plannedHours: (map['plannedHours'] as num? ?? 0).toDouble(),
        startHour: (map['startHour'] as num? ?? 9).toDouble(),
      );

  Map<String, dynamic> toMap() => {
    'taskId': taskId,
    'date': Timestamp.fromDate(date),
    'plannedHours': plannedHours,
    'startHour': startHour,
  };

  TimelineSlot copyWith({
    String? id,
    String? taskId,
    DateTime? date,
    double? plannedHours,
    double? startHour,
  }) => TimelineSlot(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    date: date ?? this.date,
    plannedHours: plannedHours ?? this.plannedHours,
    startHour: startHour ?? this.startHour,
  );
}

/// Tipi di attività predefiniti per il segnatempo.
const kTaskTypes = [
  'GEN — Generale',
  'MO — Manutenzione Ordinaria',
  'SV — Sviluppo',
  'CS — Consulenza',
  'RI — Riunione Interna',
  'RC — Riunione Cliente',
  'FOR — Formazione',
  'ADM — Amministrazione',
  'COM — Commerciale',
  'REN — Rendicontazione',
];

class TimeTrack {
  const TimeTrack({
    required this.id,
    required this.taskId,
    required this.name,
    required this.companyId,
    required this.projectId,
    required this.startAt,
    required this.endAt,
    this.userId = '',
    this.description = '',
    this.billable = true,
    this.tipo = '',
    this.hourlyRate,
  });
  final String id;
  final String taskId;
  final String name;
  final String companyId;
  final String projectId;
  final DateTime startAt;
  final DateTime endAt;
  final String userId;
  final String description;
  final bool billable;
  final String tipo; // es. "MO — Manutenzione Ordinaria"
  final double? hourlyRate; // €/h per calcolo importo fatturabile

  double get hours => endAt.difference(startAt).inMinutes / 60.0;
  double get billableAmount => billable ? hours * (hourlyRate ?? 0) : 0;

  factory TimeTrack.fromMap(String id, Map<String, dynamic> map) => TimeTrack(
    id: id,
    taskId: map['taskId'] as String? ?? '',
    name: map['name'] as String? ?? '',
    companyId: map['companyId'] as String? ?? '',
    projectId: map['projectId'] as String? ?? '',
    startAt: parseDate(map['startAt']),
    endAt: parseDate(map['endAt']),
    userId: map['userId'] as String? ?? '',
    description: map['description'] as String? ?? '',
    billable: map['billable'] as bool? ?? true,
    tipo: map['tipo'] as String? ?? '',
    hourlyRate: (map['hourlyRate'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'taskId': taskId,
    'name': name,
    'companyId': companyId,
    'projectId': projectId,
    'startAt': Timestamp.fromDate(startAt),
    'endAt': Timestamp.fromDate(endAt),
    if (userId.isNotEmpty) 'userId': userId,
    'description': description,
    'billable': billable,
    'tipo': tipo,
    if (hourlyRate != null) 'hourlyRate': hourlyRate,
  };

  TimeTrack copyWith({
    String? taskId,
    String? name,
    String? companyId,
    String? projectId,
    DateTime? startAt,
    DateTime? endAt,
    String? userId,
    String? description,
    bool? billable,
    String? tipo,
    double? hourlyRate,
  }) => TimeTrack(
    id: id,
    taskId: taskId ?? this.taskId,
    name: name ?? this.name,
    companyId: companyId ?? this.companyId,
    projectId: projectId ?? this.projectId,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    userId: userId ?? this.userId,
    description: description ?? this.description,
    billable: billable ?? this.billable,
    tipo: tipo ?? this.tipo,
    hourlyRate: hourlyRate ?? this.hourlyRate,
  );
}

// ─────────────────────────────────────────────
// TaskComment (Messaggi interni su un task)
// ─────────────────────────────────────────────

class TaskComment {
  const TaskComment({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  factory TaskComment.fromMap(String id, Map<String, dynamic> map) =>
      TaskComment(
        id: id,
        taskId: map['taskId'] as String? ?? '',
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        body: map['body'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );

  Map<String, dynamic> toMap() => {
    'taskId': taskId,
    'authorId': authorId,
    'authorName': authorName,
    'body': body,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class BillingProfile {
  const BillingProfile({
    required this.businessName,
    required this.vatNumber,
    required this.taxCode,
    required this.addressLine,
    required this.postalCode,
    required this.city,
    required this.countryCode,
    required this.regimeFiscale,
    required this.reaOffice,
    required this.reaNumber,
    required this.email,
    required this.pec,
    required this.phone,
  });
  final String businessName;
  final String vatNumber;
  final String taxCode;
  final String addressLine;
  final String postalCode;
  final String city;
  final String countryCode;
  final String regimeFiscale;
  final String reaOffice;
  final String reaNumber;
  final String email;
  final String pec;
  final String phone;

  static const empty = BillingProfile(
    businessName: '',
    vatNumber: '',
    taxCode: '',
    addressLine: '',
    postalCode: '',
    city: '',
    countryCode: 'IT',
    regimeFiscale: 'RF01',
    reaOffice: '',
    reaNumber: '',
    email: '',
    pec: '',
    phone: '',
  );

  bool get isConfigured =>
      businessName.isNotEmpty &&
      vatNumber.isNotEmpty &&
      taxCode.isNotEmpty &&
      addressLine.isNotEmpty &&
      postalCode.isNotEmpty &&
      city.isNotEmpty &&
      countryCode.isNotEmpty &&
      regimeFiscale.isNotEmpty;

  factory BillingProfile.fromMap(Map<String, dynamic>? map) {
    if (map == null) return BillingProfile.empty;
    return BillingProfile(
      businessName: map['businessName'] as String? ?? '',
      vatNumber: map['vatNumber'] as String? ?? '',
      taxCode: map['taxCode'] as String? ?? '',
      addressLine: map['addressLine'] as String? ?? '',
      postalCode: map['postalCode'] as String? ?? '',
      city: map['city'] as String? ?? '',
      countryCode: map['countryCode'] as String? ?? 'IT',
      regimeFiscale: map['regimeFiscale'] as String? ?? 'RF01',
      reaOffice: map['reaOffice'] as String? ?? '',
      reaNumber: map['reaNumber'] as String? ?? '',
      email: map['email'] as String? ?? '',
      pec: map['pec'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'businessName': businessName,
    'vatNumber': vatNumber,
    'taxCode': taxCode,
    'addressLine': addressLine,
    'postalCode': postalCode,
    'city': city,
    'countryCode': countryCode,
    'regimeFiscale': regimeFiscale,
    'reaOffice': reaOffice,
    'reaNumber': reaNumber,
    'email': email,
    'pec': pec,
    'phone': phone,
  };

  BillingProfile copyWith({
    String? businessName,
    String? vatNumber,
    String? taxCode,
    String? addressLine,
    String? postalCode,
    String? city,
    String? countryCode,
    String? regimeFiscale,
    String? reaOffice,
    String? reaNumber,
    String? email,
    String? pec,
    String? phone,
  }) => BillingProfile(
    businessName: businessName ?? this.businessName,
    vatNumber: vatNumber ?? this.vatNumber,
    taxCode: taxCode ?? this.taxCode,
    addressLine: addressLine ?? this.addressLine,
    postalCode: postalCode ?? this.postalCode,
    city: city ?? this.city,
    countryCode: countryCode ?? this.countryCode,
    regimeFiscale: regimeFiscale ?? this.regimeFiscale,
    reaOffice: reaOffice ?? this.reaOffice,
    reaNumber: reaNumber ?? this.reaNumber,
    email: email ?? this.email,
    pec: pec ?? this.pec,
    phone: phone ?? this.phone,
  );
}

class YouDoxConfig {
  const YouDoxConfig({
    required this.username,
    required this.password,
    required this.clientId,
    this.projectTemplates = const [],
  });
  final String username;
  final String password;
  final String clientId;
  final List<ProjectTemplate> projectTemplates;

  static const empty = YouDoxConfig(
    username: '',
    password: '',
    clientId: '',
    projectTemplates: [],
  );

  bool get isConfigured =>
      username.isNotEmpty && password.isNotEmpty && clientId.isNotEmpty;

  factory YouDoxConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return YouDoxConfig.empty;
    return YouDoxConfig(
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      clientId: map['clientId'] as String? ?? '',
      projectTemplates: ((map['projectTemplates'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => ProjectTemplate.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'username': username,
    'password': password,
    'clientId': clientId,
    'projectTemplates': projectTemplates
        .map((template) => template.toMap())
        .toList(),
  };

  YouDoxConfig copyWith({
    String? username,
    String? password,
    String? clientId,
    List<ProjectTemplate>? projectTemplates,
  }) => YouDoxConfig(
    username: username ?? this.username,
    password: password ?? this.password,
    clientId: clientId ?? this.clientId,
    projectTemplates: projectTemplates ?? this.projectTemplates,
  );
}

class CompanyContact {
  const CompanyContact({
    required this.id,
    required this.companyId,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.customFields = const {},
  });
  final String id;
  final String companyId;
  final String name;
  final String email;
  final String phone;
  final String role;
  final Map<String, dynamic> customFields;

  factory CompanyContact.fromMap(String id, Map<String, dynamic> map) =>
      CompanyContact(
        id: id,
        companyId: map['companyId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        role: map['role'] as String? ?? '',
        customFields: normalizeCustomFieldValues(map['customFields']),
      );

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role,
    'customFields': customFields,
  };

  CompanyContact copyWith({
    String? id,
    String? companyId,
    String? name,
    String? email,
    String? phone,
    String? role,
    Map<String, dynamic>? customFields,
  }) => CompanyContact(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    name: name ?? this.name,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    customFields: customFields ?? this.customFields,
  );
}

class TicketEntry {
  const TicketEntry({
    required this.id,
    required this.type,
    required this.body,
    required this.createdAt,
    required this.authorName,
    this.recipientEmail = '',
    this.subject = '',
    this.attachmentPaths = const [],
  });
  final String id;
  final TicketEntryType type;
  final String body;
  final DateTime createdAt;
  final String authorName;
  final String recipientEmail;
  final String subject;
  final List<String> attachmentPaths;

  factory TicketEntry.fromMap(Map<String, dynamic> map) {
    final rawAttachments = map['attachmentPaths'] as List<dynamic>? ?? const [];
    return TicketEntry(
      id: map['id'] as String? ?? '',
      type: parseTicketEntryType(map['type'] as String?),
      body: map['body'] as String? ?? '',
      createdAt: parseDate(map['createdAt']),
      authorName: map['authorName'] as String? ?? '',
      recipientEmail: map['recipientEmail'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      attachmentPaths: rawAttachments
          .map((item) => (item as String?) ?? '')
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'body': body,
    'createdAt': Timestamp.fromDate(createdAt),
    'authorName': authorName,
    'recipientEmail': recipientEmail,
    'subject': subject,
    'attachmentPaths': attachmentPaths,
  };
}

class Ticket {
  const Ticket({
    required this.id,
    required this.companyId,
    required this.title,
    required this.recipientEmail,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.entries,
  });
  final String id;
  final String companyId;
  final String title;
  final String recipientEmail;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TicketEntry> entries;

  factory Ticket.fromMap(String id, Map<String, dynamic> map) {
    final rawEntries = map['entries'] as List<dynamic>? ?? const [];
    return Ticket(
      id: id,
      companyId: map['companyId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      recipientEmail: map['recipientEmail'] as String? ?? '',
      status: parseTicketStatus(map['status'] as String?),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      entries:
          rawEntries
              .whereType<Map>()
              .map(
                (item) => TicketEntry.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'title': title,
    'recipientEmail': recipientEmail,
    'status': status.name,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'entries': entries.map((e) => e.toMap()).toList(),
  };

  Ticket copyWith({
    String? id,
    String? companyId,
    String? title,
    String? recipientEmail,
    TicketStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<TicketEntry>? entries,
  }) => Ticket(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    title: title ?? this.title,
    recipientEmail: recipientEmail ?? this.recipientEmail,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    entries: entries ?? this.entries,
  );
}
