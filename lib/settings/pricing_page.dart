import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand_config.dart';
import '../models/subscription_models.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

class PricingPage extends StatefulWidget {
  const PricingPage({super.key, this.currentPlanId});

  /// ID del piano attivo, per evidenziare il piano corrente.
  final String? currentPlanId;

  @override
  State<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends State<PricingPage> {
  late final Map<String, int> _users = {
    for (final p in kPlans) p.id: p.minUsers,
  };

  void _increment(AppPlan plan) {
    if (plan.isUnlimited || _users[plan.id]! < plan.maxUsers) {
      setState(() => _users[plan.id] = _users[plan.id]! + 1);
    }
  }

  void _decrement(AppPlan plan) {
    if (_users[plan.id]! > plan.minUsers) {
      setState(() => _users[plan.id] = _users[plan.id]! - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GussoniBrand.scaffoldBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Header(),
            const SizedBox(height: 40),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: kPlans.map((p) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: p == kPlans.first ? 0 : 12,
                        right: p == kPlans.last ? 0 : 12,
                      ),
                      child: _PlanCard(
                        plan: p,
                        userCount: _users[p.id]!,
                        isCurrent: p.id == widget.currentPlanId,
                        onIncrement: () => _increment(p),
                        onDecrement: () => _decrement(p),
                      ),
                    ),
                  )).toList(),
                );
              }
              return Column(
                children: kPlans.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _PlanCard(
                    plan: p,
                    userCount: _users[p.id]!,
                    isCurrent: p.id == widget.currentPlanId,
                    onIncrement: () => _increment(p),
                    onDecrement: () => _decrement(p),
                  ),
                )).toList(),
              );
            }),
            const SizedBox(height: 32),
            _Footer(),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'Scegli il piano giusto per il tuo studio',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: GussoniBrand.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Prezzi per utente al mese · Fatturazione annuale · IVA esclusa',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          color: GussoniBrand.textSecondary,
        ),
      ),
    ],
  );
}

// ─── Piano Card ───────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.userCount,
    required this.isCurrent,
    required this.onIncrement,
    required this.onDecrement,
  });

  final AppPlan plan;
  final int userCount;
  final bool isCurrent;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  bool get _isPro => plan.highlight != null;
  bool get _isEnterprise => plan.id == 'enterprise';

  Color get _accentColor {
    if (_isPro) return GussoniBrand.primary;
    if (_isEnterprise) return const Color(0xFF1C1D1F);
    return GussoniBrand.border;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isPro ? GussoniBrand.primary : GussoniBrand.border,
          width: _isPro ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isPro ? 0.08 : 0.04),
            blurRadius: _isPro ? 24 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(plan: plan, accentColor: _accentColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PriceBlock(plan: plan, userCount: userCount),
                const SizedBox(height: 20),
                _UserStepper(
                  plan: plan,
                  userCount: userCount,
                  onIncrement: onIncrement,
                  onDecrement: onDecrement,
                ),
                const SizedBox(height: 24),
                _CtaButton(
                  plan: plan,
                  userCount: userCount,
                  isCurrent: isCurrent,
                  isPro: _isPro,
                ),
                const SizedBox(height: 24),
                _FeatureList(plan: plan),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card header ──────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.plan, required this.accentColor});
  final AppPlan plan;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: plan.highlight != null
            ? GussoniBrand.primaryBg
            : plan.id == 'enterprise'
                ? const Color(0xFFF5F0EB)
                : GussoniBrand.surfaceSubtle,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          Text(
            plan.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: plan.highlight != null
                  ? GussoniBrand.primary
                  : GussoniBrand.textPrimary,
            ),
          ),
          const Spacer(),
          if (plan.highlight != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: GussoniBrand.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                plan.highlight!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          if (plan.hasAI)
            Container(
              margin: EdgeInsets.only(left: plan.highlight != null ? 6 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: GussoniBrand.goldBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: GussoniBrand.gold.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 11, color: GussoniBrand.gold),
                  const SizedBox(width: 3),
                  Text(
                    plan.aiTier == AiTier.full ? 'AI Full' : 'AI Scout',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.gold,
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

// ─── Price block ──────────────────────────────────────────────────────────────

class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.plan, required this.userCount});
  final AppPlan plan;
  final int userCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '€${plan.pricePerUserMonthly.toInt()}',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.textPrimary,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6, left: 4),
                child: Text(
                  '/utente/mese',
                  style: TextStyle(
                    fontSize: 14,
                    color: GussoniBrand.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.totalYearlyLabel(userCount),
            style: const TextStyle(
              fontSize: 12,
              color: GussoniBrand.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── User stepper ─────────────────────────────────────────────────────────────

class _UserStepper extends StatelessWidget {
  const _UserStepper({
    required this.plan,
    required this.userCount,
    required this.onIncrement,
    required this.onDecrement,
  });

  final AppPlan plan;
  final int userCount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  bool get _canDecrement => userCount > plan.minUsers;
  bool get _canIncrement => plan.isUnlimited || userCount < plan.maxUsers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: GussoniBrand.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GussoniBrand.border),
      ),
      child: Row(
        children: [
          _StepButton(
            icon: Icons.remove,
            enabled: _canDecrement,
            onTap: onDecrement,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$userCount',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: GussoniBrand.textPrimary,
                    height: 1.1,
                  ),
                ),
                Text(
                  userCount == 1 ? 'utente' : 'utenti',
                  style: const TextStyle(
                    fontSize: 12,
                    color: GussoniBrand.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.add,
            enabled: _canIncrement,
            onTap: onIncrement,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: enabled ? GussoniBrand.surface : GussoniBrand.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? GussoniBrand.border : GussoniBrand.borderSubtle,
        ),
      ),
      child: Icon(
        icon,
        size: 18,
        color: enabled ? GussoniBrand.textPrimary : GussoniBrand.textDisabled,
      ),
    ),
  );
}

// ─── CTA ──────────────────────────────────────────────────────────────────────

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.plan,
    required this.userCount,
    required this.isCurrent,
    required this.isPro,
  });

  final AppPlan plan;
  final int userCount;
  final bool isCurrent;
  final bool isPro;

  Future<void> _open() async {
    final uri = Uri.tryParse(plan.paymentLink);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: GussoniBrand.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GussoniBrand.border),
        ),
        child: const Text(
          'Piano attuale',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: GussoniBrand.textSecondary,
          ),
        ),
      );
    }

    final totalLabel = plan.totalMonthlyLabel(userCount);

    if (plan.id == 'enterprise') {
      return OutlinedButton(
        onPressed: _open,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: GussoniBrand.textPrimary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          foregroundColor: GussoniBrand.textPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        child: Text('Inizia con $totalLabel'),
      );
    }

    return FilledButton(
      onPressed: _open,
      style: FilledButton.styleFrom(
        backgroundColor: isPro ? GussoniBrand.primary : GussoniBrand.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      child: Text('Inizia con $totalLabel'),
    );
  }
}

// ─── Feature list ─────────────────────────────────────────────────────────────

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.plan});
  final AppPlan plan;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Incluso nel piano',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: GussoniBrand.textMuted,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 12),
      ...plan.features.map((f) {
        final isAi = f.startsWith('AI ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 1),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isAi ? GussoniBrand.goldBg : GussoniBrand.successBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAi ? Icons.auto_awesome : Icons.check,
                  size: 11,
                  color: isAi ? GussoniBrand.gold : GussoniBrand.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 13,
                    color: GussoniBrand.textPrimary,
                    fontWeight: isAi ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    ],
  );
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Divider(),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 32,
        runSpacing: 8,
        children: const [
          _FooterItem(icon: Icons.lock_outline, text: 'Pagamento sicuro via Stripe'),
          _FooterItem(icon: Icons.cancel_outlined, text: 'Cancella quando vuoi'),
          _FooterItem(icon: Icons.support_agent, text: 'Supporto dedicato incluso'),
        ],
      ),
    ],
  );
}

class _FooterItem extends StatelessWidget {
  const _FooterItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: GussoniBrand.textMuted),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(fontSize: 13, color: GussoniBrand.textSecondary),
      ),
    ],
  );
}
