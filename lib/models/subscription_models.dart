// ignore_for_file: public_member_api_docs
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// ─── Piano ────────────────────────────────────────────────────────────────────

enum AiTier { none, scout, full }

final _eur = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);

class AppPlan {
  const AppPlan({
    required this.id,
    required this.name,
    required this.pricePerUserMonthly,
    required this.minUsers,
    required this.maxUsers, // -1 = illimitato
    required this.features,
    required this.paymentLink,
    this.aiTier = AiTier.none,
    this.highlight,
  });

  final String id;
  final String name;

  /// Prezzo per singolo utente, fatturato annualmente.
  final double pricePerUserMonthly;

  final int minUsers;
  final int maxUsers;
  final List<String> features;
  final String paymentLink;
  final AiTier aiTier;
  final String? highlight;

  bool get isUnlimited => maxUsers < 0;
  bool get hasAI => aiTier != AiTier.none;

  double monthlyFor(int users) => pricePerUserMonthly * users;
  double yearlyFor(int users) => monthlyFor(users) * 12;

  String pricePerUserLabel() => '${_eur.format(pricePerUserMonthly)}/utente/mese';
  String totalMonthlyLabel(int users) => '${_eur.format(monthlyFor(users))}/mese';
  String totalYearlyLabel(int users) => '${_eur.format(yearlyFor(users))} fatturati annualmente';

  String get licensesLabel =>
      isUnlimited ? 'Utenti illimitati' : 'Max $maxUsers utenti';
}

// Stripe Payment Links
const _kLinkBase       = 'https://buy.stripe.com/test_eVq3cu3QT4NZ7Z3gl7aAw01';
const _kLinkPro        = 'https://buy.stripe.com/test_bJe4gy9bd1BNa7b7OBaAw02';
const _kLinkEnterprise = 'https://buy.stripe.com/test_aFa8wOafh0xJ5QVb0NaAw00';

final kPlans = <AppPlan>[
  const AppPlan(
    id: 'base',
    name: 'Base',
    pricePerUserMonthly: 20,
    minUsers: 2,
    maxUsers: 20,
    paymentLink: _kLinkBase,
    features: [
      'CRM completo — clienti, contatti, deal',
      'Gestione bandi e opportunità',
      'Preventivi, ordini di lavoro, FatturaPA',
      'Segnatempo e task collaborativi',
      'Archivio documentale clienti',
      'Ticket di assistenza clienti',
      'Calendario + sincronizzazione Google',
      'Supporto email (risposta entro 48h)',
    ],
  ),
  const AppPlan(
    id: 'pro',
    name: 'Pro',
    pricePerUserMonthly: 40,
    minUsers: 2,
    maxUsers: 30,
    paymentLink: _kLinkPro,
    aiTier: AiTier.scout,
    highlight: 'Più scelto',
    features: [
      'Tutto del piano Base',
      'AI Scout Bandi — ricerca e matching automatico',
      'AI Alert — notifiche su nuovi bandi rilevanti',
      'AI Summary — sintesi intelligente di ogni bando',
      'Pipeline vendite Kanban avanzata',
      'Report e statistiche avanzate',
      'Template PDF e email personalizzati',
      'Integrazioni API (Google, Stripe…)',
      'Supporto prioritario (risposta entro 8h)',
    ],
  ),
  const AppPlan(
    id: 'enterprise',
    name: 'Enterprise',
    pricePerUserMonthly: 65,
    minUsers: 3,
    maxUsers: -1,
    paymentLink: _kLinkEnterprise,
    aiTier: AiTier.full,
    features: [
      'Tutto del piano Pro',
      'AI Redazione Bandi — scrittura assistita delle domande',
      'AI Compliance Checker — verifica automatica requisiti',
      'AI Success Predictor — analisi probabilità di approvazione',
      'Automazioni e workflow personalizzati',
      'White-label (logo e colori personalizzati)',
      'API & Webhook illimitati',
      'SLA garantito 99,9%',
      'Onboarding e formazione dedicata',
      'Account manager dedicato',
    ],
  ),
];

AppPlan? planById(String? id) {
  if (id == null) return null;
  try {
    return kPlans.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}

// ─── Team Subscription ────────────────────────────────────────────────────────

enum PlanStatus { active, trialing, pastDue, cancelled, none }

class TeamSubscription {
  const TeamSubscription({
    required this.planId,
    required this.status,
    this.licenseCount = 1,
    this.currentPeriodEnd,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.cancelAtPeriodEnd = false,
  });

  final String planId;
  final PlanStatus status;
  final int licenseCount;
  final DateTime? currentPeriodEnd;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final bool cancelAtPeriodEnd;

  static const none = TeamSubscription(planId: '', status: PlanStatus.none);

  bool get isActive =>
      status == PlanStatus.active || status == PlanStatus.trialing;

  AppPlan? get plan => planById(planId);

  double get monthlyTotal => plan?.monthlyFor(licenseCount) ?? 0;
  double get yearlyTotal => plan?.yearlyFor(licenseCount) ?? 0;

  String get statusLabel {
    switch (status) {
      case PlanStatus.active:    return 'Attivo';
      case PlanStatus.trialing:  return 'Prova gratuita';
      case PlanStatus.pastDue:   return 'Pagamento scaduto';
      case PlanStatus.cancelled: return 'Annullato';
      case PlanStatus.none:      return 'Nessun abbonamento';
    }
  }

  Map<String, dynamic> toMap() => {
    'planId': planId,
    'status': status.name,
    'licenseCount': licenseCount,
    if (currentPeriodEnd != null)
      'currentPeriodEnd': Timestamp.fromDate(currentPeriodEnd!),
    if (stripeCustomerId != null) 'stripeCustomerId': stripeCustomerId,
    if (stripeSubscriptionId != null) 'stripeSubscriptionId': stripeSubscriptionId,
    'cancelAtPeriodEnd': cancelAtPeriodEnd,
  };

  factory TeamSubscription.fromMap(Map<String, dynamic>? m) {
    if (m == null) return TeamSubscription.none;
    return TeamSubscription(
      planId: m['planId'] as String? ?? '',
      status: PlanStatus.values.firstWhere(
        (s) => s.name == m['status'],
        orElse: () => PlanStatus.none,
      ),
      licenseCount: m['licenseCount'] as int? ?? 1,
      currentPeriodEnd: m['currentPeriodEnd'] is Timestamp
          ? (m['currentPeriodEnd'] as Timestamp).toDate()
          : null,
      stripeCustomerId:     m['stripeCustomerId']     as String?,
      stripeSubscriptionId: m['stripeSubscriptionId'] as String?,
      cancelAtPeriodEnd: m['cancelAtPeriodEnd'] as bool? ?? false,
    );
  }
}
