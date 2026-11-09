import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/pos_repository.dart';
import '../../data/workspace_snapshot.dart';
import '../../models/domain_models.dart';
import '../../models/pos_models.dart';
import '../../services/stripe_connect_service.dart';
import '../../services/tap_to_pay_bridge_service.dart';
import '../widgets/g_table.dart';

class NexoraPosScreen extends StatefulWidget {
  const NexoraPosScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.scopeLabel,
  });

  final WorkspaceSnapshot workspace;
  final String userId;
  final String scopeLabel;

  @override
  State<NexoraPosScreen> createState() => _NexoraPosScreenState();
}

class _NexoraPosScreenState extends State<NexoraPosScreen> {
  final _repo = PosRepository();
  final _stripeService = StripeConnectService();
  final _tapBridge = TapToPayBridgeService();
  final _money = NumberFormat.currency(locale: 'it_IT', symbol: 'EUR ');

  PosOverview? _overview;
  bool _loading = true;
  bool _saving = false;
  bool _stripeBusy = false;
  String? _error;
  StripeConnectSnapshot? _stripeSnapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _repo.load(),
        _stripeService.fetchStatus(),
      ]);
      final overview = results[0] as PosOverview;
      final stripeSnapshot = results[1] as StripeConnectSnapshot?;
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _stripeSnapshot = stripeSnapshot;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateIntent() async {
    if (!_posReady) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CreatePosIntentDialog(companies: widget.workspace.companies),
    );
    if (created == true) {
      await _load();
    }
  }

  bool get _isMobileTapToPaySurface {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> _openTapToPay() async {
    if (!_posReady) return;
    final availability = await _tapBridge.checkAvailability();
    if (!mounted) return;
    if (!availability.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            availability.reason ??
                'Tap to Pay non ancora disponibile su questo dispositivo.',
          ),
        ),
      );
      return;
    }
    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => _TapToPayDialog(
        companies: widget.workspace.companies,
        invoices: widget.workspace.invoiceDrafts,
        bridge: _tapBridge,
      ),
    );
    if (completed == true) {
      await _load();
    }
  }

  Future<void> _saveDevicePreset() async {
    if (!_posReady) return;
    setState(() => _saving = true);
    try {
      await _repo.saveDevice(
        label: 'Merchant phone',
        platform: 'flutter',
        provider: 'stripe_terminal',
        status: 'ready',
        capabilities: const [
          'tap_to_pay_ios',
          'tap_to_pay_android',
          'manual_capture',
          'refunds_planned',
        ],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio dispositivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markDemoPaid(PosPaymentIntent intent) async {
    if (!_posReady) return;
    setState(() => _saving = true);
    try {
      await _repo.markDemoPaid(intent.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore demo payment: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelIntent(PosPaymentIntent intent) async {
    if (!_posReady) return;
    setState(() => _saving = true);
    try {
      await _repo.cancelIntent(intent.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore annullamento intent: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _posReady => _stripeSnapshot?.canAcceptPayments ?? false;

  String get _stripeGateDescription {
    final snapshot = _stripeSnapshot;
    if (snapshot == null) {
      return 'Prima di usare Nexora POS dobbiamo collegare l\'account Stripe del team. Da qui fai l\'onboarding e, appena Stripe abilita incassi e payout, il POS si sblocca.';
    }
    if (!snapshot.configReady) {
      return 'La configurazione backend di Stripe non e ancora disponibile sul server. Appena viene caricata, da questa schermata potrai collegare l\'account e attivare il POS.';
    }
    switch (snapshot.status) {
      case 'active':
        return 'Stripe e attivo: il POS puo preparare e incassare pagamenti sul conto collegato del team.';
      case 'pending_requirements':
        final outstanding = snapshot.currentlyDueCount + snapshot.pastDueCount;
        if (outstanding > 0) {
          return 'Il collegamento esiste, ma Stripe richiede ancora $outstanding dato/i per attivare gli incassi. Completa il setup per sbloccare il POS.';
        }
        if ((snapshot.disabledReason ?? '').trim().isNotEmpty) {
          return 'Il collegamento esiste e i dati risultano completi, ma Stripe non ha ancora abilitato gli incassi. Stato attuale: ${snapshot.disabledReason}. Apri il dashboard Stripe per verificare e completare l\'attivazione.';
        }
        return 'Il collegamento esiste e i dati risultano completi, ma Stripe non ha ancora abilitato incassi e payout. In genere significa che l\'account e in verifica o in attesa di attivazione finale.';
      case 'onboarding':
        return 'Hai gia iniziato il collegamento Stripe. Rientra nell\'onboarding e chiudilo per poter usare Nexora POS.';
      case 'disconnected':
        return 'L\'account Stripe del team e stato scollegato. Riattivalo da qui per tornare a incassare.';
      default:
        return 'Collega l\'account Stripe del team: e il passaggio obbligatorio prima di usare Nexora POS.';
    }
  }

  Future<void> _openStripeFlow({required bool dashboard}) async {
    setState(() => _stripeBusy = true);
    try {
      final result = dashboard
          ? await _stripeService.createDashboardLink(originUrl: Uri.base.origin)
          : await _stripeService.createOnboardingLink(
              originUrl: Uri.base.origin,
            );
      if (!mounted) return;
      if (result.snapshot != null) {
        setState(() => _stripeSnapshot = result.snapshot);
      }
      final url = result.url.trim();
      if (url.isEmpty) {
        throw Exception('Stripe non ha restituito un URL valido.');
      }
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dashboard
                ? 'Dashboard Stripe aperta in una nuova scheda.'
                : 'Onboarding Stripe aperto in una nuova scheda.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore Stripe: $e')));
    } finally {
      if (mounted) {
        setState(() => _stripeBusy = false);
      }
    }
  }

  Future<void> _disconnectStripe() async {
    setState(() => _stripeBusy = true);
    try {
      final snapshot = await _stripeService.disconnect();
      if (!mounted) return;
      setState(() => _stripeSnapshot = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account Stripe scollegato.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore Stripe: $e')));
    } finally {
      if (mounted) {
        setState(() => _stripeBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final posReady = _posReady;
    return GScreenLayout(
      title: 'Nexora POS',
      subtitle:
          'Incassi in presenza, mobile checkout e ponte futuro verso Tap to Pay',
      count: overview?.intents.length ?? 0,
      searchHint: 'Ricerca POS in arrivo',
      onSearch: (_) {},
      action: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: _saving || !posReady
                ? null
                : () {
                    _saveDevicePreset();
                  },
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.smartphone_rounded, size: 16),
            label: const Text('Collega dispositivo'),
          ),
          FilledButton.icon(
            onPressed: _saving || !posReady
                ? null
                : () {
                    _openCreateIntent();
                  },
            icon: const Icon(Icons.point_of_sale_rounded, size: 16),
            label: const Text('Nuovo incasso'),
          ),
          if (_isMobileTapToPaySurface)
            FilledButton.tonalIcon(
              onPressed: _saving || !posReady
                  ? null
                  : () {
                      _openTapToPay();
                    },
              icon: const Icon(Icons.contactless_rounded, size: 16),
              label: const Text('Tap to Pay'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _PosErrorState(error: _error!, onRetry: _load)
          : _PosBody(
              overview: overview!,
              workspace: widget.workspace,
              scopeLabel: widget.scopeLabel,
              money: _money,
              onTapToPay: _isMobileTapToPaySurface ? _openTapToPay : null,
              stripeSnapshot: _stripeSnapshot,
              stripeBusy: _stripeBusy,
              onCreateIntent: _openCreateIntent,
              onDemoPaid: _markDemoPaid,
              onCancelIntent: _cancelIntent,
              stripeReady: posReady,
              stripeDescription: _stripeGateDescription,
              onConnectStripe: () => _openStripeFlow(dashboard: false),
              onOpenStripeDashboard: () => _openStripeFlow(dashboard: true),
              onDisconnectStripe: _disconnectStripe,
            ),
    );
  }
}

class _PosBody extends StatelessWidget {
  const _PosBody({
    required this.overview,
    required this.workspace,
    required this.scopeLabel,
    required this.money,
    required this.onTapToPay,
    required this.stripeSnapshot,
    required this.stripeBusy,
    required this.onCreateIntent,
    required this.onDemoPaid,
    required this.onCancelIntent,
    required this.stripeReady,
    required this.stripeDescription,
    required this.onConnectStripe,
    required this.onOpenStripeDashboard,
    required this.onDisconnectStripe,
  });

  final PosOverview overview;
  final WorkspaceSnapshot workspace;
  final String scopeLabel;
  final NumberFormat money;
  final Future<void> Function()? onTapToPay;
  final StripeConnectSnapshot? stripeSnapshot;
  final bool stripeBusy;
  final Future<void> Function() onCreateIntent;
  final Future<void> Function(PosPaymentIntent intent) onDemoPaid;
  final Future<void> Function(PosPaymentIntent intent) onCancelIntent;
  final bool stripeReady;
  final String stripeDescription;
  final Future<void> Function() onConnectStripe;
  final Future<void> Function() onOpenStripeDashboard;
  final Future<void> Function() onDisconnectStripe;

  @override
  Widget build(BuildContext context) {
    final pending = overview.intents
        .where((item) => item.isDraft || item.isPending)
        .toList();
    final completed = overview.intents
        .where((item) => item.isCompleted)
        .toList();
    final topCompanies = <String, int>{};
    for (final intent in completed) {
      final company = intent.companyName?.trim();
      if (company != null && company.isNotEmpty) {
        topCompanies[company] = (topCompanies[company] ?? 0) + 1;
      }
    }
    final bestCompanies = topCompanies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        _PosHero(
          scopeLabel: scopeLabel,
          overview: overview,
          money: money,
          onCreateIntent: onCreateIntent,
          onTapToPay: onTapToPay,
          stripeReady: stripeReady,
        ),
        const SizedBox(height: 16),
        if (!stripeReady) ...[
          _PosStripeGateCard(
            snapshot: stripeSnapshot,
            description: stripeDescription,
            busy: stripeBusy,
            onConnect: onConnectStripe,
            onDashboard: onOpenStripeDashboard,
            onDisconnect: onDisconnectStripe,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 980;
              if (mobile) {
                return ListView(
                  children: [
                    _PosDevicesCard(devices: overview.devices),
                    const SizedBox(height: 14),
                    _PosPipelineCard(
                      pending: pending,
                      money: money,
                      onDemoPaid: onDemoPaid,
                      onCancelIntent: onCancelIntent,
                    ),
                    const SizedBox(height: 14),
                    _PosRecentTable(intents: completed, money: money),
                    const SizedBox(height: 14),
                    _PosRoadmapCard(bestCompanies: bestCompanies),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        _PosPipelineCard(
                          pending: pending,
                          money: money,
                          onDemoPaid: onDemoPaid,
                          onCancelIntent: onCancelIntent,
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _PosRecentTable(
                            intents: completed,
                            money: money,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _PosDevicesCard(devices: overview.devices),
                        const SizedBox(height: 14),
                        _PosRoadmapCard(bestCompanies: bestCompanies),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PosHero extends StatelessWidget {
  const _PosHero({
    required this.scopeLabel,
    required this.overview,
    required this.money,
    required this.onCreateIntent,
    required this.onTapToPay,
    required this.stripeReady,
  });

  final String scopeLabel;
  final PosOverview overview;
  final NumberFormat money;
  final Future<void> Function() onCreateIntent;
  final Future<void> Function()? onTapToPay;
  final bool stripeReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: GussoniBrand.glassPanel(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: GussoniBrand.primaryBg,
                  border: Border.all(color: GussoniBrand.primaryBorder),
                ),
                child: Icon(
                  Icons.contactless_rounded,
                  size: 28,
                  color: GussoniBrand.primary,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POS operativo per $scopeLabel',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      overview.demoMode
                          ? 'Il modulo vive gia nel tuo MySQL: intenti, storico e dispositivi sono condivisi col team. Il prossimo step e sostituire il motore demo con Stripe Terminal e Tap to Pay.'
                          : 'Motore pagamento attivo.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: GussoniBrand.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: stripeReady
                    ? () {
                        onCreateIntent();
                      }
                    : null,
                icon: const Icon(Icons.add_card_rounded, size: 16),
                label: Text(
                  stripeReady
                      ? 'Prepara incasso'
                      : 'Collega Stripe per iniziare',
                ),
              ),
              if (onTapToPay != null)
                FilledButton.tonalIcon(
                  onPressed: stripeReady
                      ? () {
                          onTapToPay!();
                        }
                      : null,
                  icon: const Icon(Icons.contactless_rounded, size: 16),
                  label: const Text('Tap to Pay'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                label: 'Incassato totale',
                value: money.format(overview.totalSucceededAmount),
                icon: Icons.payments_rounded,
                accent: GussoniBrand.success,
              ),
              _MetricCard(
                label: 'Incassato oggi',
                value: money.format(overview.todaySucceededAmount),
                icon: Icons.today_rounded,
                accent: GussoniBrand.info,
              ),
              _MetricCard(
                label: 'Richieste pendenti',
                value: '${overview.pendingCount}',
                icon: Icons.timelapse_rounded,
                accent: GussoniBrand.warning,
              ),
              _MetricCard(
                label: 'Dispositivi pronti',
                value:
                    '${overview.devices.where((d) => d.isOnline || d.status == 'ready').length}',
                icon: Icons.phonelink_ring_rounded,
                accent: GussoniBrand.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: GussoniBrand.surface,
        border: Border.all(color: GussoniBrand.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accent.withValues(alpha: .12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: GussoniBrand.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosStripeGateCard extends StatelessWidget {
  const _PosStripeGateCard({
    required this.snapshot,
    required this.description,
    required this.busy,
    required this.onConnect,
    required this.onDashboard,
    required this.onDisconnect,
  });

  final StripeConnectSnapshot? snapshot;
  final String description;
  final bool busy;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDashboard;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final status = snapshot?.status ?? 'not_connected';
    final canOpenDashboard =
        snapshot != null &&
        (status == 'active' ||
            status == 'onboarding' ||
            status == 'pending_requirements');
    final needsCompletion =
        status == 'onboarding' || status == 'pending_requirements';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: GussoniBrand.surface,
        border: Border.all(
          color: needsCompletion
              ? GussoniBrand.warning.withValues(alpha: .28)
              : GussoniBrand.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1002332A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFF635BFF).withValues(alpha: .12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Color(0xFF635BFF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attiva il wallet del team',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Nexora POS si sblocca solo dopo il collegamento Stripe Connect.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: GussoniBrand.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: switch (status) {
                  'active' => 'attivo',
                  'pending_requirements' => 'dati mancanti',
                  'onboarding' => 'setup in corso',
                  'disconnected' => 'scollegato',
                  _ => 'non collegato',
                },
                color: switch (status) {
                  'active' => GussoniBrand.success,
                  'pending_requirements' => GussoniBrand.warning,
                  'onboarding' => GussoniBrand.info,
                  'disconnected' => GussoniBrand.error,
                  _ => GussoniBrand.textMuted,
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: GussoniBrand.textSecondary,
            ),
          ),
          if (snapshot != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if ((snapshot!.accountEmail ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.alternate_email_rounded,
                    label: snapshot!.accountEmail!,
                  ),
                _InfoChip(
                  icon: Icons.schedule_rounded,
                  label: 'Setup ${snapshot!.setupEstimate}',
                ),
                _InfoChip(icon: Icons.flag_rounded, label: snapshot!.country),
                if (snapshot!.currentlyDueCount > 0 ||
                    snapshot!.pastDueCount > 0)
                  _InfoChip(
                    icon: Icons.rule_folder_rounded,
                    label:
                        '${snapshot!.currentlyDueCount + snapshot!.pastDueCount} dati da completare',
                  ),
                if ((snapshot!.disabledReason ?? '').trim().isNotEmpty)
                  _InfoChip(
                    icon: Icons.info_outline_rounded,
                    label: snapshot!.disabledReason!,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        if (needsCompletion) {
                          onDashboard();
                        } else {
                          onConnect();
                        }
                      },
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded, size: 16),
                label: Text(
                  needsCompletion
                      ? 'Completa collegamento'
                      : 'Collega il tuo account Stripe',
                ),
              ),
              if (canOpenDashboard)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          onDashboard();
                        },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Apri dashboard'),
                ),
              if (snapshot != null && status != 'not_connected')
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          onDisconnect();
                        },
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Scollega'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: GussoniBrand.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GussoniBrand.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: GussoniBrand.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosDevicesCard extends StatelessWidget {
  const _PosDevicesCard({required this.devices});

  final List<PosDevice> devices;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: GussoniBrand.glassPanel(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dispositivi e bridge',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Qui collegheremo il telefono merchant e le capability native del bridge Flutter.',
            style: TextStyle(fontSize: 12.5, color: GussoniBrand.textSecondary),
          ),
          const SizedBox(height: 16),
          if (devices.isEmpty)
            const _PlainEmptyState(
              icon: Icons.smartphone_outlined,
              title: 'Nessun dispositivo registrato',
              body:
                  'Salva un primo device preset. Quando collegheremo Stripe Terminal, qui vedrai readiness, ultimo ping e capability NFC.',
            )
          else
            ...devices.map(
              (device) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: GussoniBrand.surface,
                  border: Border.all(color: GussoniBrand.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: GussoniBrand.primaryBg,
                          ),
                          child: Icon(
                            Icons.phone_iphone_rounded,
                            size: 18,
                            color: GussoniBrand.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: GussoniBrand.textPrimary,
                                ),
                              ),
                              Text(
                                '${device.platform} · ${device.provider}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: GussoniBrand.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusPill(
                          label: device.status,
                          color: device.isOnline || device.status == 'ready'
                              ? GussoniBrand.success
                              : GussoniBrand.warning,
                        ),
                      ],
                    ),
                    if (device.capabilities.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: device.capabilities
                            .map(
                              (capability) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: GussoniBrand.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: GussoniBrand.borderSubtle,
                                  ),
                                ),
                                child: Text(
                                  capability.replaceAll('_', ' '),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: GussoniBrand.textSecondary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PosPipelineCard extends StatelessWidget {
  const _PosPipelineCard({
    required this.pending,
    required this.money,
    required this.onDemoPaid,
    required this.onCancelIntent,
  });

  final List<PosPaymentIntent> pending;
  final NumberFormat money;
  final Future<void> Function(PosPaymentIntent intent) onDemoPaid;
  final Future<void> Function(PosPaymentIntent intent) onCancelIntent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: GussoniBrand.glassPanel(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pipeline incassi',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ogni intent e un incasso pronto da lanciare dal telefono o dal modulo desktop.',
            style: TextStyle(fontSize: 12.5, color: GussoniBrand.textSecondary),
          ),
          const SizedBox(height: 16),
          if (pending.isEmpty)
            const _PlainEmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Nessun incasso in attesa',
              body:
                  'Crea un nuovo incasso per preparare importo, cliente e note operative prima di collegare il provider.',
            )
          else
            ...pending.map(
              (intent) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: GussoniBrand.surface,
                  border: Border.all(color: GussoniBrand.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                intent.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: GussoniBrand.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if (intent.companyName != null)
                                    intent.companyName!,
                                  intent.provider,
                                  intent.isDemo ? 'demo mode' : intent.source,
                                ].join(' · '),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: GussoniBrand.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              money.format(intent.amount),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: GussoniBrand.textPrimary,
                              ),
                            ),
                            _StatusPill(
                              label: intent.status,
                              color: GussoniBrand.warning,
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (intent.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          intent.description,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: GussoniBrand.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            onCancelIntent(intent);
                          },
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Annulla'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: intent.isDemo
                              ? () {
                                  onDemoPaid(intent);
                                }
                              : null,
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                          ),
                          label: Text(
                            intent.isDemo
                                ? 'Segna come incassato'
                                : 'In attesa provider',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PosRecentTable extends StatelessWidget {
  const _PosRecentTable({required this.intents, required this.money});

  final List<PosPaymentIntent> intents;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return GTable<PosPaymentIntent>(
      columns: [
        GCol(
          label: 'Incasso',
          flex: 3,
          cell: (item) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              if ((item.companyName ?? '').isNotEmpty)
                Text(
                  item.companyName!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: GussoniBrand.textMuted,
                  ),
                ),
            ],
          ),
        ),
        GCol(
          label: 'Provider',
          flex: 2,
          cell: (item) => Text(
            item.provider,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: GussoniBrand.textSecondary,
            ),
          ),
        ),
        GCol(
          label: 'Importo',
          flex: 2,
          cell: (item) => Text(
            money.format(item.amount),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textPrimary,
            ),
          ),
        ),
        GCol(
          label: 'Stato',
          flex: 2,
          cell: (item) => Align(
            alignment: Alignment.centerLeft,
            child: _StatusPill(
              label: item.status,
              color: item.isCompleted
                  ? GussoniBrand.success
                  : item.status == 'cancelled'
                  ? GussoniBrand.error
                  : GussoniBrand.warning,
            ),
          ),
        ),
        GCol(
          label: 'Chiusura',
          flex: 2,
          cell: (item) => Text(
            item.completedAt == null
                ? '—'
                : DateFormat('dd/MM HH:mm').format(item.completedAt!),
            style: const TextStyle(
              fontSize: 12.5,
              color: GussoniBrand.textSecondary,
            ),
          ),
        ),
      ],
      rows: intents,
      emptyLabel: 'Nessun incasso completato.',
      rowsPerPage: 8,
    );
  }
}

class _PosRoadmapCard extends StatelessWidget {
  const _PosRoadmapCard({required this.bestCompanies});

  final List<MapEntry<String, int>> bestCompanies;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: GussoniBrand.glassPanel(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Roadmap operativo',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          const _RoadmapStep(
            title: '1. Modulo POS condiviso',
            body:
                'Intents, dispositivi e storico vivono gia nel backend team-wide.',
            done: true,
          ),
          const _RoadmapStep(
            title: '2. Bridge Flutter → iOS / Android',
            body:
                'Collegheremo platform channels per Stripe Terminal e Tap to Pay.',
          ),
          const _RoadmapStep(
            title: '3. Riconciliazione con fatture e ordini',
            body:
                'Ogni incasso potra agganciarsi a preventivi, fatture, ticket e lavori sul campo.',
          ),
          const SizedBox(height: 14),
          if (bestCompanies.isNotEmpty) ...[
            const Text(
              'Clienti con piu incassi demo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            ...bestCompanies
                .take(4)
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value} incassi',
                          style: const TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _RoadmapStep extends StatelessWidget {
  const _RoadmapStep({
    required this.title,
    required this.body,
    this.done = false,
  });

  final String title;
  final String body;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (done ? GussoniBrand.success : GussoniBrand.warning)
                  .withValues(alpha: .14),
            ),
            child: Icon(
              done ? Icons.check_rounded : Icons.circle_outlined,
              size: 14,
              color: done ? GussoniBrand.success : GussoniBrand.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: GussoniBrand.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _PlainEmptyState extends StatelessWidget {
  const _PlainEmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: GussoniBrand.surface,
        border: Border.all(color: GussoniBrand.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: GussoniBrand.textMuted, size: 24),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              color: GussoniBrand.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosErrorState extends StatelessWidget {
  const _PosErrorState({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(24),
        decoration: GussoniBrand.glassPanel(radius: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: GussoniBrand.error,
              size: 36,
            ),
            const SizedBox(height: 14),
            const Text(
              'POS non disponibile',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: GussoniBrand.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: GussoniBrand.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePosIntentDialog extends StatefulWidget {
  const _CreatePosIntentDialog({required this.companies});

  final List<Company> companies;

  @override
  State<_CreatePosIntentDialog> createState() => _CreatePosIntentDialogState();
}

class _CreatePosIntentDialogState extends State<_CreatePosIntentDialog> {
  final _repo = PosRepository();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _companyId;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(
      _amountCtrl.text.replaceAll(',', '.').trim(),
    );
    if (_titleCtrl.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci titolo e importo validi.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.createIntent(
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        amount: amount,
        currency: 'EUR',
        companyId: _companyId,
        companyName: widget.companies
            .where((company) => company.id == _companyId)
            .firstOrNull
            ?.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore creazione incasso: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NexoraDialog(
      title: 'Nuovo incasso',
      icon: Icons.point_of_sale_rounded,
      width: 520,
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.point_of_sale_rounded, size: 16),
          label: const Text('Salva intent'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prepariamo subito un intent POS salvato sul tuo server.',
            style: TextStyle(fontSize: 12.5, color: GussoniBrand.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Titolo incasso'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Importo'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Company?>(
            initialValue: widget.companies
                .where((company) => company.id == _companyId)
                .firstOrNull,
            decoration: const InputDecoration(labelText: 'Cliente collegato'),
            items: [
              const DropdownMenuItem<Company?>(
                value: null,
                child: Text('Nessun cliente'),
              ),
              ...widget.companies.map(
                (company) => DropdownMenuItem<Company?>(
                  value: company,
                  child: Text(company.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _companyId = value?.id),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note operative',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _TapToPayDialog extends StatefulWidget {
  const _TapToPayDialog({
    required this.companies,
    required this.invoices,
    required this.bridge,
  });

  final List<Company> companies;
  final List<InvoiceDraft> invoices;
  final TapToPayBridgeService bridge;

  @override
  State<_TapToPayDialog> createState() => _TapToPayDialogState();
}

class _TapToPayDialogState extends State<_TapToPayDialog> {
  final _repo = PosRepository();
  final _amountCtrl = TextEditingController();
  final _titleCtrl = TextEditingController(text: 'Incasso in presenza');
  final _descriptionCtrl = TextEditingController();

  String _mode = 'spot';
  String? _companyId;
  String? _invoiceId;
  bool _autoInvoiceAfterPayment = true;
  bool _submitting = false;

  List<InvoiceDraft> get _availableInvoices {
    final invoices =
        widget.invoices
            .where(
              (invoice) =>
                  invoice.status != InvoiceStatus.exported &&
                  (invoice.residualAmount > 0.009 || invoice.isPartiallyPaid),
            )
            .toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
              a.createdAt ?? DateTime(2000),
            ),
          );
    if (_companyId == null || _companyId!.trim().isEmpty) {
      return invoices;
    }
    return invoices
        .where((invoice) => invoice.companyId == _companyId)
        .toList();
  }

  Company? get _selectedCompany =>
      widget.companies.where((company) => company.id == _companyId).firstOrNull;

  InvoiceDraft? get _selectedInvoice =>
      widget.invoices.where((invoice) => invoice.id == _invoiceId).firstOrNull;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final company = _selectedCompany;
    if (company == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona prima il cliente.')),
      );
      return;
    }

    final amount = double.tryParse(
      _amountCtrl.text.replaceAll(',', '.').trim(),
    );
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un importo valido.')),
      );
      return;
    }

    if (_mode != 'spot' && _selectedInvoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona la fattura da incassare.')),
      );
      return;
    }

    final invoice = _selectedInvoice;
    if (invoice != null && amount - invoice.residualAmount > 0.009) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'L\'importo supera il residuo della fattura ${invoice.number}.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    PosMobilePaymentSession? session;
    try {
      final connectionToken = await _repo.createConnectionToken();
      session = await _repo.prepareMobilePayment(
        paymentMode: _mode,
        amount: amount,
        companyId: company.id,
        companyName: company.name,
        invoiceId: invoice?.id,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        autoInvoiceAfterPayment: _mode == 'spot' && _autoInvoiceAfterPayment,
      );
      await widget.bridge.startPayment(
        connectionToken: connectionToken,
        session: session,
      );
      final result = await _repo.completeMobilePayment(session.localIntentId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.generatedInvoiceId != null
                ? 'Pagamento registrato. Ho creato anche la fattura ${result.generatedInvoiceId}.'
                : 'Pagamento registrato correttamente.',
          ),
        ),
      );
    } catch (e) {
      if (session != null) {
        try {
          await _repo.markMobilePaymentFailed(
            session.localIntentId,
            reason: '$e',
          );
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tap to Pay non completato: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _selectedInvoice;
    final companyInvoices = _availableInvoices;
    return NexoraDialog(
      title: 'Tap to Pay',
      icon: Icons.contactless_rounded,
      width: 620,
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.contactless_rounded, size: 16),
          label: const Text('Avvia Tap to Pay'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Incasso nativo da smartphone: pagamento su fattura, acconto o spot con fattura automatica post-pagamento.',
            style: TextStyle(
              fontSize: 12.5,
              color: GussoniBrand.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Modalita'),
            items: const [
              DropdownMenuItem(value: 'spot', child: Text('Pagamento spot')),
              DropdownMenuItem(
                value: 'invoice_full',
                child: Text('Saldo fattura'),
              ),
              DropdownMenuItem(
                value: 'invoice_partial',
                child: Text('Pagamento parziale fattura'),
              ),
              DropdownMenuItem(value: 'deposit', child: Text('Acconto su fattura')),
            ],
            onChanged: (value) {
              setState(() {
                _mode = value ?? 'spot';
                if (_mode == 'spot') {
                  _invoiceId = null;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Company>(
            initialValue: _selectedCompany,
            decoration: const InputDecoration(labelText: 'Cliente'),
            items: widget.companies
                .map(
                  (company) => DropdownMenuItem<Company>(
                    value: company,
                    child: Text(company.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _companyId = value?.id;
                if (_invoiceId != null &&
                    _availableInvoices.every(
                      (candidate) => candidate.id != _invoiceId,
                    )) {
                  _invoiceId = null;
                }
              });
            },
          ),
          if (_mode != 'spot') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<InvoiceDraft>(
              initialValue: invoice,
              decoration: const InputDecoration(labelText: 'Fattura'),
              items: companyInvoices
                  .map(
                    (item) => DropdownMenuItem<InvoiceDraft>(
                      value: item,
                      child: Text(
                        '${item.number} • residuo ${item.residualAmount.toStringAsFixed(2)} EUR',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _invoiceId = value?.id;
                  if (value != null) {
                    _companyId = value.companyId;
                    if (_mode == 'invoice_full') {
                      _amountCtrl.text = value.residualAmount.toStringAsFixed(2);
                    }
                  }
                });
              },
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              if (stacked) {
                return Column(
                  children: [
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Importo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: 'Titolo'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Importo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: 'Titolo'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descrizione operazione',
              alignLabelWithHint: true,
            ),
          ),
          if (_mode == 'spot') ...[
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _autoInvoiceAfterPayment,
              contentPadding: EdgeInsets.zero,
              title: const Text('Genera fattura automatica dopo il pagamento'),
              subtitle: const Text(
                'La fattura verra creata subito come saldata, usando il template fattura del team se presente.',
              ),
              onChanged: (value) {
                setState(() => _autoInvoiceAfterPayment = value);
              },
            ),
          ],
          if (invoice != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: GussoniBrand.primaryBg,
                border: Border.all(color: GussoniBrand.primaryBorder),
              ),
              child: Text(
                'Fattura ${invoice.number} • totale ${invoice.amount.toStringAsFixed(2)} EUR • gia pagato ${invoice.paidAmount.toStringAsFixed(2)} EUR • residuo ${invoice.residualAmount.toStringAsFixed(2)} EUR',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: GussoniBrand.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
