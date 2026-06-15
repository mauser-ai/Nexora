import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../brand_config.dart';
import 'email_template_editor.dart';

import '../admin/admin_repository.dart';
import '../app/nexora_dialog.dart';
import '../app/mb_workflow_app.dart'
    show
        BillingProfileSettingsCard,
        YouDoxSettingsCard,
        EmailSignatureSettingsCard,
        AvailabilityCard,
        VacationSettingsCard;
import '../data/api_client.dart';
import '../data/api_workspace_repository.dart';
import '../data/template_repository.dart';
import '../data/team_repository.dart';
import '../models/domain_models.dart';
import '../models/roles.dart';
import '../models/template_models.dart';
import '../services/archive_integrations.dart';
import '../services/asset_upload_service.dart';
import 'template_builder_page.dart';

// ─── Main settings container ──────────────────────────────────────────────────

class SettingsPageContent extends StatefulWidget {
  const SettingsPageContent({
    super.key,
    required this.workspace,
    required this.userId,
    required this.userEmail,
    required this.teamInfo,
    required this.repository,
    required this.onUpdateBillingProfile,
    required this.onUpdateYoudoxConfig,
    required this.onUpdateEmailSignatureHtml,
    required this.onToggleAvailability,
    required this.onCreateVacation,
    required this.onDeleteVacation,
    required this.onOpenCreateUserDialog,
    this.onRemoveTeamMember,
  });

  final WorkspaceSnapshot workspace;
  final String userId;
  final String userEmail;
  final TeamInfo? teamInfo;
  final ApiWorkspaceRepository repository;
  final Future<void> Function(BillingProfile) onUpdateBillingProfile;
  final Future<void> Function(YouDoxConfig) onUpdateYoudoxConfig;
  final Future<void> Function(String) onUpdateEmailSignatureHtml;
  final Future<void> Function(UserAvailability, bool) onToggleAvailability;
  final Future<void> Function(VacationPeriod) onCreateVacation;
  final Future<void> Function(VacationPeriod) onDeleteVacation;
  final VoidCallback onOpenCreateUserDialog;
  final Future<void> Function(String memberId)? onRemoveTeamMember;

  @override
  State<SettingsPageContent> createState() => _SettingsPageContentState();
}

class _SettingsPageContentState extends State<SettingsPageContent> {
  int _tab = 0;

  // Mobile-only: null = lista principale, non-null = sezione aperta
  int? _mobileSelectedTab;
  bool _mobileSlideForward = true;

  bool get _isOwner => widget.teamInfo?.ownerId == widget.userId;

  List<String> get _tabs {
    final base = [
      'Profilo',
      'Aspetto',
      'Integrazioni',
      'Disponibilità',
      'Template',
    ];
    if (_isOwner) {
      base.add('Branding');
      base.add('Team');
    }
    return base;
  }

  static const List<IconData> _baseTabIcons = [
    Icons.person_rounded,
    Icons.imagesearch_roller_rounded,
    Icons.hub_rounded,
    Icons.calendar_month_rounded,
    Icons.description_rounded,
    Icons.palette_rounded,
    Icons.groups_rounded,
  ];

  static const List<Color> _tabColors = [
    Color(0xFF8B5E34), // Profilo
    Color(0xFF54595F), // Aspetto
    Color(0xFF4A6B8A), // Integrazioni
    Color(0xFFB05A3C), // Disponibilità
    Color(0xFFB97D10), // Template
    Color(0xFF7E3B4F), // Branding
    Color(0xFF4F6D7A), // Team
  ];

  static const List<String> _tabSubtitles = [
    'Account, fatturazione e firma email',
    'Tema, colori e wallpaper',
    'Archiviazione e fatturazione',
    'Orari, ferie e calendario',
    'Email e template progetto',
    'Logo e colori del brand',
    'Collaboratori e piano abbonamento',
  ];

  final _templateRepo = TemplateRepository();

  void _openMobileTab(int index) {
    setState(() {
      _mobileSlideForward = true;
      _mobileSelectedTab = index;
    });
  }

  void _closeMobileTab() {
    setState(() {
      _mobileSlideForward = false;
      _mobileSelectedTab = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildMobileLayout();
        }
        return _buildDesktopLayout();
      },
    );
  }

  // ── Mobile layout ─────────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Container(
      decoration: GussoniBrand.glassPanel(radius: 24, opacity: .86),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) {
          final isDetail = child.key == const ValueKey('detail');
          final offset = isDetail
              ? Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              : Tween<Offset>(begin: const Offset(-0.3, 0), end: Offset.zero);
          return SlideTransition(
            position: offset.animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        child: _mobileSelectedTab != null
            ? KeyedSubtree(
                key: const ValueKey('detail'),
                child: _buildMobileDetail(_mobileSelectedTab!),
              )
            : KeyedSubtree(
                key: const ValueKey('list'),
                child: _buildMobileList(),
              ),
      ),
    );
  }

  Widget _buildMobileList() {
    final tabs = _tabs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: .70),
                Colors.white.withValues(alpha: .40),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: .60)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2CE2CF), Color(0xFF6DA9FF)],
                  ),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Impostazioni',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ],
          ),
        ),
        // Sections
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sezione utente
                _IosSettingsGroup(
                  children: [
                    _IosSettingsRow(
                      icon: _baseTabIcons[0],
                      color: _tabColors[0],
                      label: tabs[0],
                      subtitle: _tabSubtitles[0],
                      onTap: () => _openMobileTab(0),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                // Label sezione
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'PREFERENZE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ),
                _IosSettingsGroup(
                  children: [
                    for (int i = 1; i < tabs.length.clamp(0, 6); i++)
                      _IosSettingsRow(
                        icon: _baseTabIcons[i],
                        color: _tabColors[i],
                        label: tabs[i],
                        subtitle: _tabSubtitles[i],
                        onTap: () => _openMobileTab(i),
                        isLast: i == tabs.length.clamp(0, 6) - 1,
                      ),
                  ],
                ),
                if (_isOwner) ...[
                  const SizedBox(height: 28),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'AMMINISTRAZIONE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ),
                  _IosSettingsGroup(
                    children: [
                      for (int i = 6; i < tabs.length; i++)
                        _IosSettingsRow(
                          icon: _baseTabIcons[i],
                          color: _tabColors[i],
                          label: tabs[i],
                          subtitle: _tabSubtitles[i],
                          onTap: () => _openMobileTab(i),
                          isLast: i == tabs.length - 1,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileDetail(int index) {
    final tabs = _tabs;
    final tabName = tabs[index];
    return Column(
      children: [
        // Nav bar iOS-style
        Container(
          padding: const EdgeInsets.fromLTRB(6, 14, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: .70),
                Colors.white.withValues(alpha: .40),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: .60)),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _closeMobileTab,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chevron_left_rounded,
                        color: GussoniBrand.primary,
                        size: 22,
                      ),
                      Text(
                        'Impostazioni',
                        style: TextStyle(
                          color: GussoniBrand.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  tabName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
              // Azione header se tab 0 (crea utente)
              if (index == 0)
                GestureDetector(
                  onTap: widget.onOpenCreateUserDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: GussoniBrand.primaryBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: GussoniBrand.primaryBorder),
                    ),
                    child: Text(
                      'Crea utente',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GussoniBrand.primary,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 80),
            ],
          ),
        ),
        // Contenuto sezione
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _buildTabContent(index),
          ),
        ),
      ],
    );
  }

  // ── Desktop layout ────────────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    final tabs = _tabs;
    return Container(
      decoration: GussoniBrand.glassPanel(radius: 28, opacity: .82),
      child: Row(
        children: [
          Container(
            width: 250,
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF07111D).withValues(alpha: .07),
              border: Border(
                right: BorderSide(color: Colors.white.withValues(alpha: .42)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2CE2CF), Color(0xFF6DA9FF)],
                          ),
                        ),
                        child: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Generali',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: tabs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final selected = _tab == i;
                      return _SettingsSidebarItem(
                        label: tabs[i],
                        icon: _baseTabIcons[i],
                        selected: selected,
                        onTap: () => setState(() => _tab = i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tabs[_tab],
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: GussoniBrand.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Preferenze Nexora OS, dati utente e strumenti amministrativi.',
                              style: TextStyle(
                                fontSize: 13,
                                color: GussoniBrand.textSecondary.withValues(
                                  alpha: .88,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_tab == 0)
                        OutlinedButton.icon(
                          onPressed: widget.onOpenCreateUserDialog,
                          icon: const Icon(
                            Icons.person_add_alt_1_outlined,
                            size: 16,
                          ),
                          label: const Text('Crea utente'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(child: SingleChildScrollView(child: _buildTab())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab() => _buildTabContent(_tab);

  Widget _buildTabContent(int index) {
    switch (_tabs[index]) {
      case 'Profilo':
        return Column(
          children: [
            _ProfiloTab(
              userId: widget.userId,
              userEmail: widget.userEmail,
              teamInfo: widget.teamInfo,
            ),
            const SizedBox(height: 16),
            BillingProfileSettingsCard(
              profile: widget.workspace.billingProfile,
              onSave: widget.onUpdateBillingProfile,
            ),
            const SizedBox(height: 16),
            EmailSignatureSettingsCard(
              initialHtml: widget.workspace.emailSignatureHtml,
              onSave: widget.onUpdateEmailSignatureHtml,
            ),
          ],
        );
      case 'Aspetto':
        return _AppearanceTab(
          userId: widget.userId,
          userEmail: widget.userEmail,
        );
      case 'Integrazioni':
        return _IntegrationsTab(
          userId: widget.userId,
          youdoxConfig: widget.workspace.youdoxConfig,
          onUpdateYoudoxConfig: widget.onUpdateYoudoxConfig,
        );
      case 'Disponibilità':
        return _DisponibilitaTab(
          workspace: widget.workspace,
          onToggleAvailability: widget.onToggleAvailability,
          onCreateVacation: widget.onCreateVacation,
          onDeleteVacation: widget.onDeleteVacation,
        );
      case 'Template':
        return _TemplateTab(
          userId: widget.userId,
          templateRepo: _templateRepo,
          youdoxConfig: widget.workspace.youdoxConfig,
          onUpdateYoudoxConfig: widget.onUpdateYoudoxConfig,
        );
      case 'Branding':
        return _BrandingTab(userId: widget.userId, teamInfo: widget.teamInfo!);
      case 'Team':
        return _PianoTeamTab(
          userId: widget.userId,
          teamInfo: widget.teamInfo!,
          adminRepo: AdminRepository(),
          onRemoveTeamMember: widget.onRemoveTeamMember,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _IntegrationsTab extends StatefulWidget {
  const _IntegrationsTab({
    required this.userId,
    required this.youdoxConfig,
    required this.onUpdateYoudoxConfig,
  });

  final String userId;
  final YouDoxConfig youdoxConfig;
  final Future<void> Function(YouDoxConfig) onUpdateYoudoxConfig;

  @override
  State<_IntegrationsTab> createState() => _IntegrationsTabState();
}

/// Specifica di un campo credenziale richiesto da un'integrazione.
class _IntegrationField {
  const _IntegrationField(
    this.key,
    this.label, {
    this.hint,
    this.obscure = false,
    this.optional = false,
    this.options,
  });

  final String key;
  final String label;
  final String? hint;
  final bool obscure;
  final bool optional;

  /// Se valorizzato, il campo è una scelta (dropdown) tra queste opzioni.
  final List<String>? options;
}

/// Definizione completa di un'integrazione configurabile con credenziali.
class _IntegrationSpec {
  const _IntegrationSpec({
    required this.key,
    required this.name,
    required this.category,
    required this.description,
    required this.icon,
    required this.color,
    required this.fields,
    required this.help,
    this.helpUrl,
    this.connectedDescription,
  });

  final String key;
  final String name;
  final String category;
  final String description;
  final String? connectedDescription;
  final IconData icon;
  final Color color;
  final List<_IntegrationField> fields;
  final String help;
  final String? helpUrl;
}

/// Categorie nell'ordine di visualizzazione.
const List<(String, IconData)> _integrationCategories = [
  ('Archiviazione', Icons.folder_copy_outlined),
  ('Fatturazione', Icons.receipt_long_outlined),
  ('Anagrafica e dati aziendali', Icons.domain_outlined),
  ('Firma elettronica', Icons.history_edu_outlined),
  ('Comunicazione', Icons.forum_outlined),
  ('Banca e pagamenti', Icons.account_balance_outlined),
];

/// Tutte le integrazioni generiche (credenziali salvate su Firestore).
/// Google Drive (OAuth server) e YouDOX (config workspace) sono gestite a parte.
const List<_IntegrationSpec> _integrationSpecs = [
  // ── Archiviazione ─────────────────────────────────────────────────────
  _IntegrationSpec(
    key: 'dropbox',
    name: 'Dropbox',
    category: 'Archiviazione',
    description:
        'Richiede una app Dropbox (App key, App secret e Access token dalla App Console).',
    connectedDescription: 'Dropbox è collegato ed è visibile nell\'Archivio.',
    icon: Icons.cloud_queue_rounded,
    color: Color(0xFF0061FF),
    fields: [
      _IntegrationField('appKey', 'App key', hint: 'Dalla Dropbox App Console'),
      _IntegrationField('appSecret', 'App secret', obscure: true),
      _IntegrationField(
        'accessToken',
        'Access token',
        hint: 'Generato nella scheda Settings della tua app',
        obscure: true,
      ),
    ],
    help:
        'Crea una app su Dropbox App Console (tipo "Scoped access", permessi '
        'files.content.read e files.content.write), poi genera un Access token '
        'dalla scheda Settings della app e incollalo qui.',
    helpUrl: 'https://www.dropbox.com/developers/apps',
  ),
  _IntegrationSpec(
    key: 'onedrive',
    name: 'Microsoft OneDrive / SharePoint',
    category: 'Archiviazione',
    description:
        'Richiede una app Microsoft Entra (Tenant ID, Client ID e Client secret).',
    icon: Icons.cloud_outlined,
    color: Color(0xFF0F6CBD),
    fields: [
      _IntegrationField(
        'tenantId',
        'Tenant ID (Directory ID)',
        hint: 'Da Microsoft Entra ID — portal.azure.com',
      ),
      _IntegrationField('clientId', 'Application (Client) ID'),
      _IntegrationField('clientSecret', 'Client secret', obscure: true),
    ],
    help:
        'Registra una app su Microsoft Entra ID (portal.azure.com → App '
        'registrations) con permessi Microsoft Graph Files.ReadWrite.All e '
        'Sites.Read.All, crea un Client secret e incolla qui i tre valori.',
    helpUrl: 'https://portal.azure.com',
  ),
  _IntegrationSpec(
    key: 'nextcloud',
    name: 'Nextcloud',
    category: 'Archiviazione',
    description:
        'Storage self-hosted via WebDAV: servono URL del server, utente e app password.',
    icon: Icons.dns_outlined,
    color: Color(0xFF1E6B8C),
    fields: [
      _IntegrationField(
        'serverUrl',
        'URL server',
        hint: 'https://cloud.tuodominio.it',
      ),
      _IntegrationField('username', 'Username'),
      _IntegrationField(
        'appPassword',
        'App password',
        hint: 'Impostazioni → Sicurezza → Crea nuova app password',
        obscure: true,
      ),
    ],
    help:
        'Nel tuo Nextcloud vai su Impostazioni → Sicurezza e genera una '
        '"app password" dedicata (non usare la password principale). '
        'L\'integrazione usa il protocollo WebDAV standard.',
    helpUrl: 'https://docs.nextcloud.com',
  ),
  _IntegrationSpec(
    key: 'docfly',
    name: 'Aruba DocFly — Conservazione a norma',
    category: 'Archiviazione',
    description:
        'Conservazione digitale a norma di fatture e contratti firmati.',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFFE2580E),
    fields: [
      _IntegrationField('username', 'Username DocFly'),
      _IntegrationField('password', 'Password', obscure: true),
    ],
    help:
        'Usa le credenziali del servizio Aruba DocFly. L\'accesso API per '
        'l\'invio automatico dei documenti in conservazione va richiesto ad '
        'Aruba per la tua utenza.',
    helpUrl: 'https://www.pec.it/conservazione-sostitutiva.aspx',
  ),
  _IntegrationSpec(
    key: 'infocert',
    name: 'InfoCert — Conservazione',
    category: 'Archiviazione',
    description: 'Conservazione digitale a norma con piattaforma InfoCert.',
    icon: Icons.shield_outlined,
    color: Color(0xFF00567A),
    fields: [
      _IntegrationField('username', 'Username'),
      _IntegrationField('password', 'Password', obscure: true),
    ],
    help:
        'Credenziali del servizio di conservazione InfoCert. L\'attivazione '
        'dell\'accesso applicativo passa dal tuo referente o partner InfoCert.',
    helpUrl: 'https://www.infocert.it',
  ),

  // ── Fatturazione ──────────────────────────────────────────────────────
  _IntegrationSpec(
    key: 'aruba_fe',
    name: 'Aruba Fatturazione Elettronica',
    category: 'Fatturazione',
    description:
        'Richiede username e password del servizio Fatturazione Elettronica Aruba.',
    icon: Icons.description_rounded,
    color: Color(0xFFE2580E),
    fields: [
      _IntegrationField(
        'username',
        'Username',
        hint: 'Le credenziali del pannello fatturazioneelettronica.aruba.it',
      ),
      _IntegrationField('password', 'Password', obscure: true),
      _IntegrationField(
        'environment',
        'Ambiente',
        options: ['Produzione', 'Demo'],
      ),
    ],
    help:
        'Usa le credenziali del servizio Fatturazione Elettronica Aruba (le '
        'stesse del pannello web). L\'autenticazione avviene via token su '
        'auth.fatturazioneelettronica.aruba.it (POST /auth/signin). Scegli '
        '"Demo" solo se hai un account dell\'ambiente di prova.',
    helpUrl: 'https://fatturazioneelettronica.aruba.it/apidoc/docs.html',
  ),
  _IntegrationSpec(
    key: 'fattureweb',
    name: 'FattureWeb (Sistemi)',
    category: 'Fatturazione',
    description:
        'Richiede le credenziali dell\'account FattureWeb; l\'abilitazione API va richiesta a Sistemi.',
    icon: Icons.request_quote_rounded,
    color: Color(0xFF1F6FB2),
    fields: [
      _IntegrationField('username', 'Username / Email'),
      _IntegrationField('password', 'Password', obscure: true),
      _IntegrationField(
        'companyCode',
        'Codice azienda',
        hint: 'Facoltativo: codice ditta fornito da Sistemi',
        optional: true,
      ),
    ],
    help:
        'Inserisci le credenziali del tuo account FattureWeb. L\'abilitazione '
        'all\'integrazione applicativa va richiesta al tuo commercialista o a '
        'Sistemi S.p.A.; se ti è stato fornito un codice azienda, indicalo.',
    helpUrl: 'https://fattureweb.sistemi.com',
  ),
  _IntegrationSpec(
    key: 'fattureincloud',
    name: 'Fatture in Cloud',
    category: 'Fatturazione',
    description:
        'Richiede un Access token generato dal portale developers (o app OAuth2).',
    icon: Icons.cloud_done_outlined,
    color: Color(0xFF0072BB),
    fields: [
      _IntegrationField(
        'accessToken',
        'Access token',
        hint: 'Devportal → tua app → Autenticazione manuale',
        obscure: true,
      ),
      _IntegrationField(
        'companyId',
        'Company ID',
        hint: 'Facoltativo: recuperabile con "List User Companies"',
        optional: true,
      ),
    ],
    help:
        'Crea una app su developers.fattureincloud.it e genera un token con '
        'l\'autenticazione manuale (consigliato per uso interno), oppure '
        'configura OAuth2 lato server. L\'API base è api-v2.fattureincloud.it.',
    helpUrl: 'https://developers.fattureincloud.it',
  ),
  _IntegrationSpec(
    key: 'zucchetti_dh',
    name: 'Zucchetti Digital Hub',
    category: 'Fatturazione',
    description:
        'Canale SDI Zucchetti: richiede credenziali OAuth2 rilasciate dal partner.',
    icon: Icons.hub_outlined,
    color: Color(0xFF6B5B95),
    fields: [
      _IntegrationField('clientId', 'Client ID'),
      _IntegrationField('clientSecret', 'Client secret', obscure: true),
      _IntegrationField(
        'environment',
        'Ambiente',
        options: ['Produzione', 'Test'],
      ),
    ],
    help:
        'Le credenziali OAuth2 per Digital Hub vengono rilasciate da Zucchetti '
        'o dal partner/commercialista che gestisce il canale SDI.',
    helpUrl: 'https://www.zucchetti.it',
  ),
  _IntegrationSpec(
    key: 'openapi_sdi',
    name: 'Openapi — Fatturazione SDI',
    category: 'Fatturazione',
    description:
        'Canale SDI a consumo: richiede email account e API key Openapi.',
    icon: Icons.swap_horiz_rounded,
    color: Color(0xFF2E7D4F),
    fields: [
      _IntegrationField('email', 'Email account Openapi'),
      _IntegrationField(
        'apiKey',
        'API key',
        hint: 'Dalla console: si usa per generare i token con scope SDI',
        obscure: true,
      ),
    ],
    help:
        'Registrati su openapi.com e recupera la API key dalla console. '
        'I token si generano con email + API key indicando lo scope del '
        'servizio SDI (TTL predefinito 1 anno).',
    helpUrl: 'https://console.openapi.com',
  ),

  // ── Anagrafica e dati aziendali ───────────────────────────────────────
  _IntegrationSpec(
    key: 'openapi_visure',
    name: 'Openapi — Visure e anagrafiche',
    category: 'Anagrafica e dati aziendali',
    description:
        'Compila i dati azienda da P.IVA (ATECO, sede, dipendenti): email e API key.',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFF3F6B5E),
    fields: [
      _IntegrationField('email', 'Email account Openapi'),
      _IntegrationField('apiKey', 'API key', obscure: true),
    ],
    help:
        'Stesso account Openapi della fatturazione: i token vanno generati '
        'con gli scope dei servizi Imprese/Visure. Permette di precompilare '
        'le schede società da partita IVA e qualificare i requisiti bandi.',
    helpUrl: 'https://console.openapi.com',
  ),
  _IntegrationSpec(
    key: 'cerved',
    name: 'Cerved API',
    category: 'Anagrafica e dati aziendali',
    description:
        'Dati ufficiali e score aziendali: richiede la API key del gateway Cerved.',
    icon: Icons.assessment_outlined,
    color: Color(0xFF8B1A1A),
    fields: [
      _IntegrationField(
        'apiKey',
        'API key',
        hint: 'Rilasciata da Cerved su api.cerved.com',
        obscure: true,
      ),
    ],
    help:
        'La API key viene rilasciata da Cerved con il contratto sul gateway '
        'api.cerved.com (anagrafiche, bilanci, score). Contatta il tuo '
        'referente commerciale Cerved per l\'attivazione.',
    helpUrl: 'https://api.cerved.com',
  ),

  // ── Firma elettronica ─────────────────────────────────────────────────
  _IntegrationSpec(
    key: 'yousign',
    name: 'Yousign',
    category: 'Firma elettronica',
    description:
        'Firma elettronica europea: richiede una API key (sandbox o produzione).',
    icon: Icons.draw_outlined,
    color: Color(0xFF946B2D),
    fields: [
      _IntegrationField(
        'apiKey',
        'API key',
        hint: 'Da yousign.app → Integrazioni → API',
        obscure: true,
      ),
      _IntegrationField(
        'environment',
        'Ambiente',
        options: ['Produzione', 'Sandbox'],
      ),
    ],
    help:
        'Genera la API key dall\'area Integrazioni della tua organizzazione '
        'Yousign. L\'ambiente Sandbox è gratuito per i test.',
    helpUrl: 'https://developers.yousign.com',
  ),
  _IntegrationSpec(
    key: 'docusign',
    name: 'DocuSign',
    category: 'Firma elettronica',
    description:
        'Richiede Integration Key, Secret e Account ID dalla console developer.',
    icon: Icons.gesture_rounded,
    color: Color(0xFF4A6B8A),
    fields: [
      _IntegrationField('integrationKey', 'Integration Key (Client ID)'),
      _IntegrationField('secretKey', 'Secret key', obscure: true),
      _IntegrationField('accountId', 'Account ID (API)'),
      _IntegrationField(
        'environment',
        'Ambiente',
        options: ['Produzione', 'Demo'],
      ),
    ],
    help:
        'Crea una app su developers.docusign.com (Apps & Keys): ottieni '
        'Integration Key e Secret, e copia l\'API Account ID del tuo account.',
    helpUrl: 'https://developers.docusign.com',
  ),

  // ── Comunicazione ─────────────────────────────────────────────────────
  _IntegrationSpec(
    key: 'pec',
    name: 'PEC (Aruba / Legalmail)',
    category: 'Comunicazione',
    description:
        'Porta la casella PEC dentro Threads via IMAP: indirizzo, password e host.',
    icon: Icons.mark_email_read_outlined,
    color: Color(0xFF7E3B4F),
    fields: [
      _IntegrationField('email', 'Indirizzo PEC'),
      _IntegrationField('password', 'Password', obscure: true),
      _IntegrationField(
        'imapHost',
        'Host IMAP',
        hint: 'imaps.pec.aruba.it oppure mbox.cert.legalmail.it',
      ),
    ],
    help:
        'L\'integrazione legge la casella via IMAP (porta 993, SSL). '
        'Host tipici: imaps.pec.aruba.it per Aruba PEC, '
        'mbox.cert.legalmail.it per Legalmail (InfoCert).',
    helpUrl: 'https://guide.pec.it',
  ),
  _IntegrationSpec(
    key: 'microsoft365',
    name: 'Microsoft 365 — Posta e Calendario',
    category: 'Comunicazione',
    description:
        'Outlook e calendario via Microsoft Graph: app Entra con Tenant, Client ID e secret.',
    icon: Icons.calendar_month_outlined,
    color: Color(0xFF0F6CBD),
    fields: [
      _IntegrationField('tenantId', 'Tenant ID (Directory ID)'),
      _IntegrationField('clientId', 'Application (Client) ID'),
      _IntegrationField('clientSecret', 'Client secret', obscure: true),
    ],
    help:
        'Registra una app su Microsoft Entra ID con permessi Graph Mail.Read '
        'e Calendars.ReadWrite. Puoi riusare la stessa app di OneDrive '
        'aggiungendo i permessi.',
    helpUrl: 'https://portal.azure.com',
  ),
  _IntegrationSpec(
    key: 'slack',
    name: 'Slack',
    category: 'Comunicazione',
    description:
        'Notifiche su deal, scadenze e ticket in un canale: basta un Incoming Webhook.',
    icon: Icons.tag_rounded,
    color: Color(0xFF611F69),
    fields: [
      _IntegrationField(
        'webhookUrl',
        'Webhook URL',
        hint: 'https://hooks.slack.com/services/…',
      ),
    ],
    help:
        'Crea una app Slack → attiva "Incoming Webhooks" → aggiungi un webhook '
        'al canale desiderato e incolla qui l\'URL.',
    helpUrl: 'https://api.slack.com/messaging/webhooks',
  ),
  _IntegrationSpec(
    key: 'teams',
    name: 'Microsoft Teams',
    category: 'Comunicazione',
    description: 'Notifiche nel canale Teams tramite webhook (Workflows).',
    icon: Icons.groups_2_outlined,
    color: Color(0xFF4B53BC),
    fields: [
      _IntegrationField(
        'webhookUrl',
        'Webhook URL',
        hint: 'Da Teams: canale → Workflow → "Post to a channel when a webhook request is received"',
      ),
    ],
    help:
        'In Teams apri il canale → ⋯ → Workflow e crea il flusso "Post to a '
        'channel when a webhook request is received": ottieni un URL da '
        'incollare qui.',
    helpUrl:
        'https://support.microsoft.com/office/creating-a-workflow-from-a-channel-in-teams',
  ),
  _IntegrationSpec(
    key: 'whatsapp',
    name: 'WhatsApp Business (Meta)',
    category: 'Comunicazione',
    description:
        'Messaggi ai clienti via Cloud API: token permanente e Phone Number ID.',
    icon: Icons.chat_outlined,
    color: Color(0xFF1FA855),
    fields: [
      _IntegrationField(
        'accessToken',
        'Access token permanente',
        hint: 'Da Meta Business → System user token',
        obscure: true,
      ),
      _IntegrationField('phoneNumberId', 'Phone Number ID'),
      _IntegrationField(
        'wabaId',
        'WhatsApp Business Account ID',
        optional: true,
      ),
    ],
    help:
        'Configura la WhatsApp Cloud API da developers.facebook.com: crea una '
        'app Business, collega il numero e genera un token permanente tramite '
        'un system user di Meta Business Suite.',
    helpUrl: 'https://developers.facebook.com/docs/whatsapp/cloud-api',
  ),

  // ── Banca e pagamenti ─────────────────────────────────────────────────
  _IntegrationSpec(
    key: 'stripe',
    name: 'Stripe',
    category: 'Banca e pagamenti',
    description:
        'Link di pagamento su preventivi e fatture: richiede la Secret key.',
    icon: Icons.credit_card_rounded,
    color: Color(0xFF635BFF),
    fields: [
      _IntegrationField(
        'secretKey',
        'Secret key',
        hint: 'Incolla qui la secret key Stripe',
        obscure: true,
      ),
    ],
    help:
        'Dalla dashboard Stripe: Developers → API keys → Secret key. '
        'Usa una chiave di test per provare senza movimenti reali.',
    helpUrl: 'https://dashboard.stripe.com/apikeys',
  ),
  _IntegrationSpec(
    key: 'gocardless',
    name: 'GoCardless (SDD ricorrenti)',
    category: 'Banca e pagamenti',
    description:
        'Addebiti diretti SEPA per canoni ricorrenti: richiede un Access token.',
    icon: Icons.autorenew_rounded,
    color: Color(0xFF2C2D84),
    fields: [
      _IntegrationField(
        'accessToken',
        'Access token',
        hint: 'manage.gocardless.com → Developers → Create access token',
        obscure: true,
      ),
      _IntegrationField(
        'environment',
        'Ambiente',
        options: ['Live', 'Sandbox'],
      ),
    ],
    help:
        'Crea un access token da manage.gocardless.com (Developers → API). '
        'Per i test usa l\'ambiente Sandbox con il relativo token.',
    helpUrl: 'https://manage.gocardless.com',
  ),
  _IntegrationSpec(
    key: 'fabrick',
    name: 'Fabrick (PSD2 / conti)',
    category: 'Banca e pagamenti',
    description:
        'Riconciliazione bancaria: saldo e movimenti dei conti via API key Fabrick.',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF0A4D68),
    fields: [
      _IntegrationField('apiKey', 'API key', obscure: true),
      _IntegrationField(
        'authSchema',
        'Auth schema',
        hint: 'Tipicamente "S2S"',
        optional: true,
      ),
    ],
    help:
        'Le credenziali della Fabrick Platform vengono rilasciate in fase di '
        'onboarding (fabrick.com → Developers). Permettono di leggere saldi e '
        'movimenti per la riconciliazione nel modulo Finanze.',
    helpUrl: 'https://www.fabrick.com/developers',
  ),
];

class _IntegrationsTabState extends State<_IntegrationsTab> {
  ArchiveIntegrationsState _archiveState = archiveIntegrationsController.state;
  Map<String, Map<String, dynamic>> _stored = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    archiveIntegrationsController.addListener(_handleArchiveState);
    archiveIntegrationsController.load();
    _loadStored();
  }

  @override
  void dispose() {
    archiveIntegrationsController.removeListener(_handleArchiveState);
    super.dispose();
  }

  void _handleArchiveState(ArchiveIntegrationsState state) {
    if (!mounted) return;
    setState(() => _archiveState = state);
  }

  Future<void> _loadStored() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final raw = doc.data()?['integrations'];
      if (!mounted) return;
      setState(() {
        _stored = raw is Map
            ? raw.map(
                (k, v) => MapEntry(
                  k.toString(),
                  v is Map
                      ? Map<String, dynamic>.from(v)
                      : <String, dynamic>{},
                ),
              )
            : {};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveStored(String key, Map<String, String> values) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).set(
      {
        'integrations': {
          key: {...values, 'updatedAt': FieldValue.serverTimestamp()},
        },
      },
      SetOptions(merge: true),
    );
    if (!mounted) return;
    setState(() => _stored[key] = Map<String, dynamic>.from(values));
  }

  Future<void> _removeStored(String key) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).set(
      {
        'integrations': {key: FieldValue.delete()},
      },
      SetOptions(merge: true),
    );
    if (!mounted) return;
    setState(() => _stored.remove(key));
  }

  bool _isConfigured(_IntegrationSpec spec) {
    final data = _stored[spec.key];
    if (data == null) return false;
    return spec.fields
        .where((f) => !f.optional && f.options == null)
        .every((f) => (data[f.key] as String? ?? '').trim().isNotEmpty);
  }

  Map<String, String> _initialFor(String key) {
    final data = _stored[key] ?? const {};
    return {
      for (final entry in data.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  Future<void> _configure(_IntegrationSpec spec) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _IntegrationConfigDialog(
        title: 'Collega ${spec.name}',
        icon: spec.icon,
        color: spec.color,
        fields: spec.fields,
        help: spec.help,
        helpUrl: spec.helpUrl,
        initial: _initialFor(spec.key),
      ),
    );
    if (values == null) return;
    await _saveStored(spec.key, values);
    if (spec.key == 'dropbox') {
      await archiveIntegrationsController.setConnected(
        ArchiveIntegrationProvider.dropbox,
        true,
      );
    }
  }

  Future<void> _disconnect(_IntegrationSpec spec) async {
    await _removeStored(spec.key);
    if (spec.key == 'dropbox') {
      await archiveIntegrationsController.setConnected(
        ArchiveIntegrationProvider.dropbox,
        false,
      );
    }
  }

  // ── Provider speciali ──────────────────────────────────────────────────

  Future<void> _connectGoogleDrive() async {
    final url = Uri.base.resolve(
      '/archivio/api/integrations/oauth_start.php?provider=google_drive',
    );
    await launchUrl(url, webOnlyWindowName: '_blank');
    await archiveIntegrationsController.setConnected(
      ArchiveIntegrationProvider.googleDrive,
      true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Completa l\'autorizzazione Google nella scheda aperta. Drive comparirà nell\'Archivio.',
        ),
      ),
    );
  }

  static const _youdoxFields = [
    _IntegrationField('username', 'Username'),
    _IntegrationField('password', 'Password', obscure: true),
    _IntegrationField(
      'clientId',
      'Client ID',
      hint: 'Identificativo API fornito da YouDOX',
    ),
  ];

  Future<void> _configureYoudox() async {
    final config = widget.youdoxConfig;
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _IntegrationConfigDialog(
        title: 'Collega YouDOX',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF946B2D),
        fields: _youdoxFields,
        help:
            'Inserisci le credenziali API fornite da YouDOX: vengono usate per '
            'creare le bozze delle fatture elettroniche direttamente dal CRM.',
        helpUrl: null,
        initial: {
          'username': config.username,
          'password': config.password,
          'clientId': config.clientId,
        },
      ),
    );
    if (values == null) return;
    await widget.onUpdateYoudoxConfig(
      config.copyWith(
        username: values['username'] ?? '',
        password: values['password'] ?? '',
        clientId: values['clientId'] ?? '',
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _disconnectYoudox() async {
    await widget.onUpdateYoudoxConfig(
      widget.youdoxConfig.copyWith(username: '', password: '', clientId: ''),
    );
    if (!mounted) return;
    setState(() {});
  }

  bool get _youdoxConnected =>
      widget.youdoxConfig.username.trim().isNotEmpty &&
      widget.youdoxConfig.clientId.trim().isNotEmpty;

  // ── Build ──────────────────────────────────────────────────────────────

  List<Widget> _cardsForCategory(String category) {
    final cards = <Widget>[];

    // Card speciali in testa alla loro categoria.
    if (category == 'Archiviazione') {
      cards.add(
        _IntegrationCard(
          name: 'Google Drive',
          description: _archiveState.googleDriveConnected
              ? 'Drive è visibile nella sidebar dell\'Archivio.'
              : 'Autorizza con il tuo account Google (OAuth): nessuna chiave '
                    'da inserire, i token restano cifrati sul server.',
          icon: Icons.add_to_drive_outlined,
          color: const Color(0xFF34A853),
          connected: _archiveState.googleDriveConnected,
          connectLabel: 'Collega con Google',
          onConnect: _connectGoogleDrive,
          onDisconnect: () => archiveIntegrationsController.setConnected(
            ArchiveIntegrationProvider.googleDrive,
            false,
          ),
        ),
      );
    }
    if (category == 'Fatturazione') {
      cards.add(
        _IntegrationCard(
          name: 'YouDOX',
          description: _youdoxConnected
              ? 'Le bozze delle fatture elettroniche vengono inviate a YouDOX.'
              : 'Richiede username, password e Client ID forniti da YouDOX.',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF946B2D),
          connected: _youdoxConnected,
          onConnect: _configureYoudox,
          onEdit: _configureYoudox,
          onDisconnect: _disconnectYoudox,
        ),
      );
    }

    for (final spec in _integrationSpecs.where(
      (s) => s.category == category,
    )) {
      final configured = spec.key == 'dropbox'
          ? (_archiveState.dropboxConnected && _isConfigured(spec))
          : _isConfigured(spec);
      cards.add(
        _IntegrationCard(
          name: spec.name,
          description: configured
              ? (spec.connectedDescription ??
                    'Configurata: credenziali salvate per il tuo account.')
              : spec.description,
          icon: spec.icon,
          color: spec.color,
          connected: configured,
          onConnect: () => _configure(spec),
          onEdit: () => _configure(spec),
          onDisconnect: () => _disconnect(spec),
        ),
      );
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SettingsSectionTitle(
          title: 'Integrazioni',
          subtitle:
              'Collega i servizi esterni che usi in studio, divisi per categoria. '
              'Le credenziali restano associate al tuo account.',
        ),
        const SizedBox(height: 18),
        for (final (label, icon) in _integrationCategories) ...[
          _IntegrationCategoryLabel(label: label, icon: icon),
          const SizedBox(height: 10),
          ..._cardsForCategory(
            label,
          ).expand((card) => [card, const SizedBox(height: 10)]),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _IntegrationCategoryLabel extends StatelessWidget {
  const _IntegrationCategoryLabel({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: GussoniBrand.textMuted),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: GussoniBrand.textMuted,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Divider(height: 1, color: GussoniBrand.borderSubtle),
        ),
      ],
    );
  }
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
    this.onEdit,
    this.connectLabel = 'Collega',
  });

  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final bool connected;
  final String connectLabel;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: GussoniBrand.glassPanel(radius: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: .10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: connected
                            ? GussoniBrand.successBg
                            : GussoniBrand.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        connected ? 'Collegato' : 'Non collegato',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: connected
                              ? GussoniBrand.success
                              : GussoniBrand.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: GussoniBrand.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (connected) ...[
            if (onEdit != null)
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: const Text('Modifica'),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Scollega',
              onPressed: onDisconnect,
              icon: const Icon(
                Icons.link_off_rounded,
                size: 18,
                color: GussoniBrand.textMuted,
              ),
            ),
          ] else
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link_rounded, size: 16),
              label: Text(connectLabel),
            ),
        ],
      ),
    );
  }
}

/// Dialog generico di configurazione credenziali per un'integrazione.
class _IntegrationConfigDialog extends StatefulWidget {
  const _IntegrationConfigDialog({
    required this.title,
    required this.icon,
    required this.color,
    required this.fields,
    required this.help,
    required this.initial,
    this.helpUrl,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_IntegrationField> fields;
  final String help;
  final String? helpUrl;
  final Map<String, String> initial;

  @override
  State<_IntegrationConfigDialog> createState() =>
      _IntegrationConfigDialogState();
}

class _IntegrationConfigDialogState extends State<_IntegrationConfigDialog> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _choices;
  final Set<String> _revealed = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fields)
        if (field.options == null)
          field.key: TextEditingController(
            text: widget.initial[field.key] ?? '',
          ),
    };
    _choices = {
      for (final field in widget.fields)
        if (field.options != null)
          field.key: widget.initial[field.key] ?? field.options!.first,
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    for (final field in widget.fields) {
      if (field.optional || field.options != null) continue;
      if (_controllers[field.key]!.text.trim().isEmpty) {
        setState(() => _error = 'Compila il campo "${field.label}".');
        return;
      }
    }
    Navigator.of(context).pop(<String, String>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
      ..._choices,
    });
  }

  @override
  Widget build(BuildContext context) {
    return NexoraDialog(
      title: widget.title,
      icon: widget.icon,
      accent: widget.color,
      width: 480,
      // ignore: sort_child_properties_last
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.help,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: GussoniBrand.textSecondary,
                  ),
                ),
                if (widget.helpUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(widget.helpUrl!),
                        webOnlyWindowName: '_blank',
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 13,
                            color: GussoniBrand.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              widget.helpUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: GussoniBrand.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final field in widget.fields) ...[
            if (field.options != null)
              DropdownButtonFormField<String>(
                initialValue: _choices[field.key],
                decoration: NexoraDialog.fieldDecoration(field.label),
                items: [
                  for (final option in field.options!)
                    DropdownMenuItem(value: option, child: Text(option)),
                ],
                onChanged: (value) => setState(
                  () => _choices[field.key] = value ?? field.options!.first,
                ),
              )
            else
              TextField(
                controller: _controllers[field.key],
                obscureText: field.obscure && !_revealed.contains(field.key),
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    NexoraDialog.fieldDecoration(
                      field.optional
                          ? '${field.label} (facoltativo)'
                          : field.label,
                      hint: field.hint,
                    ).copyWith(
                      suffixIcon: field.obscure
                          ? IconButton(
                              icon: Icon(
                                _revealed.contains(field.key)
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 17,
                                color: GussoniBrand.textMuted,
                              ),
                              onPressed: () => setState(() {
                                if (!_revealed.add(field.key)) {
                                  _revealed.remove(field.key);
                                }
                              }),
                            )
                          : null,
                    ),
              ),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: GussoniBrand.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: NexoraDialog.cancelButtonStyle(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _submit,
          style: NexoraDialog.primaryButtonStyle(),
          child: const Text('Salva e collega'),
        ),
      ],
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: GussoniBrand.textPrimary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: GussoniBrand.textMuted,
        ),
      ),
    ],
  );
}

// ─── iOS Settings widgets ─────────────────────────────────────────────────────

class _IosSettingsGroup extends StatelessWidget {
  const _IosSettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .70)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 56, color: GussoniBrand.borderSubtle),
          ],
        ],
      ),
    );
  }
}

class _IosSettingsRow extends StatelessWidget {
  const _IosSettingsRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(16))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Icon container (iOS style)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            // Label + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Trailing
            if (trailing != null)
              trailing!
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: GussoniBrand.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSidebarItem extends StatelessWidget {
  const _SettingsSidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: .78),
                      GussoniBrand.primary.withValues(alpha: .12),
                    ],
                  )
                : null,
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: .76)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: selected
                      ? GussoniBrand.primary.withValues(alpha: .18)
                      : Colors.white.withValues(alpha: .38),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? GussoniBrand.primaryDark
                      : GussoniBrand.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected
                        ? GussoniBrand.textPrimary
                        : GussoniBrand.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: GussoniBrand.glassPanel(radius: 22, opacity: .88),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textSecondary.withValues(
                              alpha: .92,
                            ),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AppearanceTab extends StatefulWidget {
  const _AppearanceTab({required this.userId, required this.userEmail});

  final String userId;
  final String userEmail;

  @override
  State<_AppearanceTab> createState() => _AppearanceTabState();
}

class _AppearanceTabState extends State<_AppearanceTab> {
  bool _loaded = false;
  bool _notificationsEnabled = true;
  bool _savingNotifications = false;
  bool _uploadingWallpaper = false;
  String? _wallpaperUrl;
  Color _accentColor = GussoniBrand.defaultPrimary;

  static const List<Color> _accentPresets = [
    GussoniBrand.defaultPrimary, // Bordeaux Gussoni
    Color(0xFF8B1A1A), // Rosso mattone
    Color(0xFFB05A3C), // Terracotta
    Color(0xFF946B2D), // Bronzo dorato
    Color(0xFFB08948), // Oro
    Color(0xFF5F7045), // Oliva
    Color(0xFF3F6B5E), // Verde bosco
    Color(0xFF486B6B), // Petrolio
    Color(0xFF4A6B8A), // Blu ardesia
    Color(0xFF6B5B95), // Viola spento
    Color(0xFF7E3B4F), // Vinaccia
    Color(0xFF1C1D1F), // Antracite
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _notificationsEnabled =
            data['desktopNotificationsEnabled'] as bool? ?? true;
        _accentColor =
            hexToColor(data['accentColorHex'] as String?) ??
            GussoniBrand.defaultPrimary;
        _wallpaperUrl = (data['desktopWallpaperUrl'] as String?)?.trim();
        if (_wallpaperUrl != null && _wallpaperUrl!.isEmpty) {
          _wallpaperUrl = null;
        }
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _savePreference(Map<String, dynamic> data) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set(data, SetOptions(merge: true));
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _notificationsEnabled = value;
      _savingNotifications = true;
    });
    try {
      await _savePreference({'desktopNotificationsEnabled': value});
    } finally {
      if (mounted) setState(() => _savingNotifications = false);
    }
  }

  Future<void> _uploadWallpaper() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() => _uploadingWallpaper = true);
    try {
      final headers = await ApiClient.instance.authorizedHeaders(
        includeJsonContentType: false,
      );
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/desktop/upload_wallpaper.php'),
      );
      request.headers.addAll(headers);
      request.fields['userId'] = widget.userId;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'desktop-wallpaper.jpg',
        ),
      );
      final response = await request.send();
      final body = await response.stream.bytesToString();
      final payload = body.isEmpty
          ? const <String, dynamic>{}
          : (jsonDecode(body) as Map<String, dynamic>);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          payload['error'] ??
              'Upload wallpaper fallito (${response.statusCode}).',
        );
      }
      final url = (payload['url'] as String? ?? '').trim();
      if (url.isEmpty) {
        throw Exception('Il backend non ha restituito l’URL del wallpaper.');
      }
      await _savePreference({'desktopWallpaperUrl': url});
      if (!mounted) return;
      setState(() => _wallpaperUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sfondo desktop aggiornato.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore upload wallpaper: $error')),
      );
    } finally {
      if (mounted) setState(() => _uploadingWallpaper = false);
    }
  }

  Future<void> _removeWallpaper() async {
    await _savePreference({'desktopWallpaperUrl': FieldValue.delete()});
    if (!mounted) return;
    setState(() => _wallpaperUrl = null);
  }

  Future<void> _setAccentColor(Color color) async {
    setState(() => _accentColor = color);
    GussoniBrand.applyAccent(color);
    if (color == GussoniBrand.defaultPrimary) {
      await _savePreference({'accentColorHex': FieldValue.delete()});
    } else {
      await _savePreference({'accentColorHex': colorToHex(color)});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          title: 'Colore principale',
          subtitle:
              'Scegli il colore con cui personalizzare pulsanti, menu e accenti dell’interfaccia.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in _accentPresets)
                Tooltip(
                  message: colorToHex(color),
                  child: InkWell(
                    onTap: () => _setAccentColor(color),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _accentColor == color
                              ? GussoniBrand.textPrimary
                              : Colors.white,
                          width: _accentColor == color ? 2.5 : 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: _accentColor == color
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _SectionCard(
          title: 'Notifiche',
          subtitle:
              'Attiva o disattiva le notifiche desktop per questa postazione di lavoro.',
          child: SwitchListTile(
            value: _notificationsEnabled,
            onChanged: _savingNotifications ? null : _toggleNotifications,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Notifiche desktop',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _notificationsEnabled
                  ? 'Ricevi avvisi e prompt operativi quando il sistema ne invia.'
                  : 'Le notifiche vengono disattivate su questo account finché non riattivi il toggle.',
            ),
          ),
        ),
        _SectionCard(
          title: 'Sfondo desktop',
          subtitle:
              'Carica un wallpaper personale per il desktop. Il file viene salvato sul tuo hosting PHP, non su Firebase Storage.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: GussoniBrand.border),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF8F3EC),
                      Color(0xFFF0E9E1),
                      Color(0xFFE6DCD0),
                    ],
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _wallpaperUrl == null
                    ? const Center(
                        child: Text(
                          'Nessun wallpaper personalizzato',
                          style: TextStyle(
                            color: GussoniBrand.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Image.network(
                        _wallpaperUrl!,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text(
                            'Impossibile caricare l’anteprima',
                            style: TextStyle(
                              color: GussoniBrand.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _uploadingWallpaper ? null : _uploadWallpaper,
                    icon: _uploadingWallpaper
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.wallpaper_rounded, size: 16),
                    label: Text(
                      _uploadingWallpaper ? 'Caricamento...' : 'Carica sfondo',
                    ),
                  ),
                  if (_wallpaperUrl != null)
                    OutlinedButton.icon(
                      onPressed: _removeWallpaper,
                      icon: const Icon(Icons.hide_image_outlined, size: 16),
                      label: const Text('Rimuovi sfondo'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Formato consigliato: JPG o PNG orizzontale, almeno 1920px di larghezza.',
                style: TextStyle(
                  fontSize: 11,
                  color: GussoniBrand.textSecondary.withValues(alpha: .92),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── TAB: Profilo ─────────────────────────────────────────────────────────────

class _ProfiloTab extends StatefulWidget {
  const _ProfiloTab({
    required this.userId,
    required this.userEmail,
    this.teamInfo,
  });
  final String userId;
  final String userEmail;
  final TeamInfo? teamInfo;

  @override
  State<_ProfiloTab> createState() => _ProfiloTabState();
}

class _ProfiloTabState extends State<_ProfiloTab> {
  String? _avatarUrl;
  String _displayName = '';
  String _role = '';
  bool _loadingAvatar = false;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        setState(() {
          _avatarUrl = data['avatarUrl'] as String?;
          _displayName = data['displayName'] as String? ?? '';
          _role = data['role'] as String? ?? '';
          _loaded = true;
        });
      } else {
        setState(() => _loaded = true);
      }
    } catch (_) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    setState(() => _loadingAvatar = true);
    try {
      final url = await uploadAssetImage(
        bytes: bytes,
        filename: 'avatar.jpg',
        folder: 'avatar',
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({'avatarUrl': url}, SetOptions(merge: true));
      if (mounted) setState(() => _avatarUrl = url);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore caricamento avatar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAvatar = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
            'displayName': _displayName.trim(),
            if (_role.trim().isNotEmpty) 'role': _role.trim(),
          }, SetOptions(merge: true));
      // Aggiorna anche nel team member se esiste
      final teamInfo = widget.teamInfo;
      if (teamInfo != null) {
        await FirebaseFirestore.instance
            .collection('teams')
            .doc(teamInfo.id)
            .collection('members')
            .doc(widget.userId)
            .set({
              'displayName': _displayName.trim(),
              'role': _role.trim(),
            }, SetOptions(merge: true));
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profilo salvato.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    final initials = _displayName.trim().isNotEmpty
        ? _displayName
              .trim()
              .split(' ')
              .map((p) => p.isNotEmpty ? p[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : (widget.userEmail.isNotEmpty
              ? widget.userEmail[0].toUpperCase()
              : '?');

    final teamMember = widget.teamInfo?.memberById(widget.userId);
    final teamRole = teamMember?.role ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          title: 'Foto profilo',
          subtitle: 'Visibile ovunque al posto delle iniziali.',
          child: Row(
            children: [
              // Avatar
              GestureDetector(
                onTap: _loadingAvatar ? null : _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFF3B82F6),
                      child: _avatarUrl != null
                          ? ClipOval(
                              child: Image.network(
                                _avatarUrl!,
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Text(
                                  initials,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: GussoniBrand.borderSubtle,
                            width: 1.5,
                          ),
                          boxShadow: [
                            const BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: _loadingAvatar
                            ? const Padding(
                                padding: EdgeInsets.all(6),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_outlined,
                                size: 14,
                                color: GussoniBrand.textSecondary,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadingAvatar ? null : _pickAvatar,
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: const Text('Carica foto'),
                  ),
                  if (_avatarUrl != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.userId)
                            .update({'avatarUrl': FieldValue.delete()});
                        setState(() => _avatarUrl = null);
                      },
                      child: const Text(
                        'Rimuovi foto',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    widget.userEmail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _SectionCard(
          title: 'Dati personali',
          child: Column(
            children: [
              TextFormField(
                initialValue: _displayName,
                onChanged: (v) => _displayName = v,
                decoration: const InputDecoration(
                  labelText: 'Nome visualizzato',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value:
                    GussoniRoles.all.contains(
                      _role.isNotEmpty ? _role : teamRole,
                    )
                    ? (_role.isNotEmpty ? _role : teamRole)
                    : null,
                hint: const Text('Seleziona ruolo'),
                decoration: const InputDecoration(
                  labelText: 'Ruolo',
                  border: OutlineInputBorder(),
                ),
                items: GussoniRoles.all
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => _role = v ?? ''),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: Text(_saving ? 'Salvataggio...' : 'Salva profilo'),
                ),
              ),
            ],
          ),
        ),
        if (widget.teamInfo != null)
          _SectionCard(
            title: 'Team',
            subtitle: 'Membri del team ${widget.teamInfo!.name}.',
            child: Column(
              children: widget.teamInfo!.activeMembers.map((m) {
                final isMe = m.userId == widget.userId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isMe
                        ? const Color(0xFF3B82F6)
                        : GussoniBrand.textMuted,
                    child: Text(
                      m.initials,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  title: Text(
                    m.displayName.isNotEmpty ? m.displayName : m.email,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    m.role.isNotEmpty ? m.role : m.email,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: isMe
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Text(
                            'Tu',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1D4ED8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : null,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ─── TAB: Fatturazione ────────────────────────────────────────────────────────

// ─── TAB: Disponibilità ──────────────────────────────────────────────────────

class _DisponibilitaTab extends StatelessWidget {
  const _DisponibilitaTab({
    required this.workspace,
    required this.onToggleAvailability,
    required this.onCreateVacation,
    required this.onDeleteVacation,
  });

  final WorkspaceSnapshot workspace;
  final Future<void> Function(UserAvailability, bool) onToggleAvailability;
  final Future<void> Function(VacationPeriod) onCreateVacation;
  final Future<void> Function(VacationPeriod) onDeleteVacation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 900;
        final availability = AvailabilityCard(
          availability: workspace.availability,
          onToggleOff: onToggleAvailability,
        );
        final vacations = VacationSettingsCard(
          vacations: workspace.vacations,
          onCreateVacation: onCreateVacation,
          onDeleteVacation: onDeleteVacation,
        );
        if (stacked) {
          return Column(
            children: [availability, const SizedBox(height: 16), vacations],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: availability),
              const SizedBox(width: 16),
              Expanded(child: vacations),
            ],
          ),
        );
      },
    );
  }
}

// ─── TAB: Template ────────────────────────────────────────────────────────────

class _TemplateTab extends StatefulWidget {
  const _TemplateTab({
    required this.userId,
    required this.templateRepo,
    required this.youdoxConfig,
    required this.onUpdateYoudoxConfig,
  });
  final String userId;
  final TemplateRepository templateRepo;
  final YouDoxConfig youdoxConfig;
  final Future<void> Function(YouDoxConfig) onUpdateYoudoxConfig;

  @override
  State<_TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends State<_TemplateTab> {
  String _category = kPreventivo;

  List<ProjectTemplate> get _projectTemplates {
    final templates = widget.youdoxConfig.projectTemplates
        .where((template) => template.id != kStandardProjectTemplate.id)
        .toList();
    return [kStandardProjectTemplate, ...templates];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProjectTemplatesSection(context),
        const SizedBox(height: 28),
        Row(
          children: [
            // Selector categoria
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: GussoniBrand.surfaceSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [kPreventivo, kFattura].map((cat) {
                  final sel = _category == cat;
                  final label = cat == kPreventivo ? 'Preventivi' : 'Fatture';
                  return GestureDetector(
                    onTap: () => setState(() => _category = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFFF0EDE8)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: sel
                            ? [
                                const BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel
                              ? const Color(0xFF1C1D1F)
                              : GussoniBrand.textMuted,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _openBuilder(context, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuovo template'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<DocumentTemplate>>(
          stream: widget.templateRepo.watchTemplates(widget.userId),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                'Errore: ${snap.error}',
                style: const TextStyle(color: Color(0xFFEF4444)),
              );
            }
            if (!snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final templates = snap.data!
                .where((t) => t.category == _category)
                .toList();
            if (templates.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GussoniBrand.borderSubtle),
                ),
                child: Column(
                  children: [
                    Icon(
                      _category == kPreventivo
                          ? Icons.request_quote_outlined
                          : Icons.receipt_long_outlined,
                      size: 40,
                      color: GussoniBrand.borderSubtle,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nessun template ${_category == kPreventivo ? "preventivo" : "fattura"}.',
                      style: const TextStyle(color: GussoniBrand.textMuted),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => _openBuilder(context, null),
                      child: const Text('Crea il primo template'),
                    ),
                  ],
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                childAspectRatio: 1.4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: templates.length,
              itemBuilder: (_, i) => _TemplateCard(
                template: templates[i],
                onEdit: () => _openBuilder(context, templates[i]),
                onDelete: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Elimina template'),
                      content: Text(
                        'Eliminare "${templates[i].name}"? L\'operazione è irreversibile.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Annulla'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Elimina'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await widget.templateRepo.delete(
                      widget.userId,
                      templates[i].id,
                    );
                  }
                },
              ),
            );
          },
        ),
        _buildEmailSection(context),
      ],
    );
  }

  Widget _buildProjectTemplatesSection(BuildContext context) {
    return _SectionCard(
      title: 'Template progetto',
      subtitle:
          'Definisci fasi e task riutilizzabili quando crei un nuovo progetto.',
      action: FilledButton.icon(
        onPressed: () => _openProjectTemplateEditor(context),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Nuovo template progetto'),
      ),
      child: Column(
        children: _projectTemplates.map((template) {
          final taskCount = template.phases.fold<int>(
            0,
            (sum, phase) => sum + phase.tasks.length,
          );
          final isStandard = template.id == kStandardProjectTemplate.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GussoniBrand.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isStandard
                        ? GussoniBrand.primaryBg
                        : const Color(0xFFF0EDE8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isStandard
                        ? Icons.star_outline_rounded
                        : Icons.account_tree_outlined,
                    color: const Color(0xFF5B1205),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              template.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1D1F),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: GussoniBrand.borderSubtle,
                              ),
                            ),
                            child: Text(
                              isStandard ? 'Standard' : 'Custom',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: GussoniBrand.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${template.phases.length} fasi · $taskCount task',
                        style: const TextStyle(
                          fontSize: 12,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: template.phases
                            .take(4)
                            .map(
                              (phase) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: GussoniBrand.borderSubtle,
                                  ),
                                ),
                                child: Text(
                                  phase.name,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B5A4E),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isStandard)
                  OutlinedButton.icon(
                    onPressed: () => _openProjectTemplateEditor(
                      context,
                      seed: template.copyWith(
                        id: '',
                        name: '${template.name} copia',
                        isDefault: false,
                      ),
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Duplica'),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Modifica template',
                        onPressed: () => _openProjectTemplateEditor(
                          context,
                          template: template,
                        ),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Elimina template',
                        onPressed: () =>
                            _deleteProjectTemplate(context, template),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Color(0xFFC1B8AB),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmailSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          children: [
            const Text(
              'Template email',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1D1F),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _openEmailEditor(context, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuovo template email'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Template usati al momento dell\'invio email del ${_category == kPreventivo ? "preventivo" : "fattura"}.',
          style: const TextStyle(fontSize: 12, color: GussoniBrand.textMuted),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<EmailTemplate>>(
          stream: widget.templateRepo.watchEmailTemplates(widget.userId),
          builder: (context, snap) {
            if (!snap.hasData)
              return const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator()),
              );
            final emails = snap.data!
                .where((t) => t.category == _category)
                .toList();
            if (emails.isEmpty) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: GussoniBrand.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GussoniBrand.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      color: GussoniBrand.borderSubtle,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Nessun template email. Creane uno per usarlo nell\'invio automatico.',
                        style: TextStyle(
                          fontSize: 13,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openEmailEditor(context, null),
                      child: const Text('Crea'),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: emails
                  .map(
                    (t) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: GussoniBrand.borderSubtle),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.email_outlined,
                            size: 20,
                            color: Color(0xFF0EA5E9),
                          ),
                        ),
                        title: Text(
                          t.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Oggetto: ${t.subject.length > 60 ? "${t.subject.substring(0, 60)}…" : t.subject}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: GussoniBrand.textMuted,
                              ),
                              onPressed: () => _openEmailEditor(context, t),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Color(0xFFC1B8AB),
                              ),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Elimina template email'),
                                    content: Text('Eliminare "${t.name}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Annulla'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFEF4444,
                                          ),
                                        ),
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text('Elimina'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true)
                                  widget.templateRepo.deleteEmailTemplate(
                                    widget.userId,
                                    t.id,
                                  );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  void _openEmailEditor(BuildContext context, EmailTemplate? existing) {
    showDialog<void>(
      context: context,
      builder: (ctx) => EmailTemplateEditorDialog(
        template: existing,
        category: _category,
        onSave: (t) => widget.templateRepo.saveEmailTemplate(widget.userId, t),
      ),
    );
  }

  void _openBuilder(BuildContext context, DocumentTemplate? existing) {
    final template =
        existing ??
        DocumentTemplate(
          id: 'tpl_${DateTime.now().microsecondsSinceEpoch}',
          name: _category == kPreventivo ? 'Nuovo preventivo' : 'Nuova fattura',
          category: _category,
          elements: [],
          customFields: [],
        );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplateBuilderPage(
          template: template,
          userId: widget.userId,
          onSave: (t) => widget.templateRepo.save(widget.userId, t),
        ),
      ),
    );
  }

  Future<void> _saveProjectTemplate(ProjectTemplate template) async {
    final templates =
        widget.youdoxConfig.projectTemplates
            .where((item) => item.id != template.id)
            .toList()
          ..add(template);
    await widget.onUpdateYoudoxConfig(
      widget.youdoxConfig.copyWith(projectTemplates: templates),
    );
  }

  Future<void> _deleteProjectTemplate(
    BuildContext context,
    ProjectTemplate template,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina template progetto'),
        content: Text('Eliminare "${template.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final templates = widget.youdoxConfig.projectTemplates
        .where((item) => item.id != template.id)
        .toList();
    await widget.onUpdateYoudoxConfig(
      widget.youdoxConfig.copyWith(projectTemplates: templates),
    );
  }

  void _openProjectTemplateEditor(
    BuildContext context, {
    ProjectTemplate? template,
    ProjectTemplate? seed,
  }) {
    final initial =
        template ??
        seed ??
        ProjectTemplate(
          id: '',
          name: 'Nuovo template progetto',
          phases: const [],
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProjectTemplateEditorDialog(
        template: initial,
        onSave: _saveProjectTemplate,
      ),
    );
  }
}

class _ProjectTemplateEditorDialog extends StatefulWidget {
  const _ProjectTemplateEditorDialog({
    required this.template,
    required this.onSave,
  });

  final ProjectTemplate template;
  final Future<void> Function(ProjectTemplate template) onSave;

  @override
  State<_ProjectTemplateEditorDialog> createState() =>
      _ProjectTemplateEditorDialogState();
}

class _ProjectTemplateEditorDialogState
    extends State<_ProjectTemplateEditorDialog> {
  late final TextEditingController _name;
  late List<_EditableTemplatePhase> _phases;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template.name);
    _phases = widget.template.phases
        .map((phase) => _EditableTemplatePhase.fromTemplate(phase))
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final phase in _phases) {
      phase.dispose();
    }
    super.dispose();
  }

  void _addPhase() {
    setState(() {
      _phases.add(
        _EditableTemplatePhase(
          name: TextEditingController(text: ''),
          tasks: [TextEditingController(text: '')],
        ),
      );
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome del template.')),
      );
      return;
    }
    final phases = <ProjectTemplatePhase>[];
    for (final phase in _phases) {
      final phaseName = phase.name.text.trim();
      final tasks = phase.tasks
          .map((ctrl) => ctrl.text.trim())
          .where((task) => task.isNotEmpty)
          .toList();
      if (phaseName.isEmpty) continue;
      phases.add(ProjectTemplatePhase(name: phaseName, tasks: tasks));
    }
    if (phases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aggiungi almeno una fase al template.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        widget.template.copyWith(
          id: widget.template.id.isEmpty
              ? 'ptpl_${DateTime.now().microsecondsSinceEpoch}'
              : widget.template.id,
          name: name,
          phases: phases,
          isDefault: false,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 14, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Template progetto',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1D1F),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nome template',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Fasi e task',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1D1F),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _addPhase,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Aggiungi fase'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_phases.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: GussoniBrand.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: GussoniBrand.borderSubtle),
                        ),
                        child: const Text(
                          'Nessuna fase ancora presente. Aggiungi la prima fase del template.',
                          style: TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                      ),
                    ..._phases.asMap().entries.map((entry) {
                      final index = entry.key;
                      final phase = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: GussoniBrand.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: GussoniBrand.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: phase.name,
                                    decoration: InputDecoration(
                                      labelText: 'Nome fase ${index + 1}',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  tooltip: 'Elimina fase',
                                  onPressed: () {
                                    setState(() {
                                      final removed = _phases.removeAt(index);
                                      removed.dispose();
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...phase.tasks.asMap().entries.map((taskEntry) {
                              final taskIndex = taskEntry.key;
                              final controller = taskEntry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        decoration: InputDecoration(
                                          labelText: 'Task ${taskIndex + 1}',
                                          border: const OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Elimina task',
                                      onPressed: phase.tasks.length == 1
                                          ? null
                                          : () {
                                              setState(() {
                                                final removedTask = phase.tasks
                                                    .removeAt(taskIndex);
                                                removedTask.dispose();
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  phase.tasks.add(
                                    TextEditingController(text: ''),
                                  );
                                });
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Aggiungi task'),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Salva template'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableTemplatePhase {
  _EditableTemplatePhase({required this.name, required this.tasks});

  final TextEditingController name;
  final List<TextEditingController> tasks;

  factory _EditableTemplatePhase.fromTemplate(ProjectTemplatePhase phase) =>
      _EditableTemplatePhase(
        name: TextEditingController(text: phase.name),
        tasks: phase.tasks.isEmpty
            ? [TextEditingController(text: '')]
            : phase.tasks
                  .map((task) => TextEditingController(text: task))
                  .toList(),
      );

  void dispose() {
    name.dispose();
    for (final task in tasks) {
      task.dispose();
    }
  }
}

// ─── TAB: Branding (solo Team Owner) ─────────────────────────────────────────

class _BrandingTab extends StatefulWidget {
  const _BrandingTab({required this.userId, required this.teamInfo});
  final String userId;
  final TeamInfo teamInfo;

  @override
  State<_BrandingTab> createState() => _BrandingTabState();
}

class _BrandingTabState extends State<_BrandingTab> {
  bool _uploadingLogo = false;
  bool _savingColor = false;

  // Colori preset
  static const _presets = [
    Color(0xFF5B1205),
    Color(0xFF10B981),
    Color(0xFF3B82F6),
    Color(0xFF7C3AED),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFF64748B),
    Color(0xFF1C1D1F),
  ];

  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: colorToHex(GussoniBrand.primary));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final url = await uploadAssetImage(
        bytes: bytes,
        filename: result.files.first.name,
        folder: 'brand',
      );
      await _saveToFirestore(logoUrl: url);
      GussoniBrand.primary;
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Logo aggiornato.')));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    await _saveToFirestore(removeLogo: true);
    GussoniBrand.primary;
  }

  Future<void> _applyColor(Color color) async {
    setState(() => _savingColor = true);
    try {
      final hex = colorToHex(color);
      _hexCtrl.text = hex;
      await _saveToFirestore(brandColor: hex);
      GussoniBrand.primary;
    } finally {
      if (mounted) setState(() => _savingColor = false);
    }
  }

  Future<void> _saveToFirestore({
    String? logoUrl,
    String? brandColor,
    bool removeLogo = false,
  }) async {
    final Map<String, dynamic> data = {};
    if (removeLogo) data['brandLogoUrl'] = FieldValue.delete();
    if (logoUrl != null) data['brandLogoUrl'] = logoUrl;
    if (brandColor != null) data['brandColor'] = brandColor;
    if (data.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('teams')
        .doc(widget.teamInfo.id)
        .set(data, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final currentLogo = null;
    final currentColor = GussoniBrand.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Logo aziendale ──
        _SectionCard(
          title: 'Logo aziendale',
          subtitle:
              'Verrà mostrato in alto nella sidebar al posto del logo Nexora. Formato consigliato: PNG o SVG, sfondo trasparente.',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview
              Container(
                width: 180,
                height: 64,
                decoration: BoxDecoration(
                  color: GussoniBrand.sidebarBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GussoniBrand.borderSubtle),
                ),
                alignment: Alignment.center,
                child: currentLogo != null
                    ? Image.network(
                        currentLogo,
                        fit: BoxFit.contain,
                        height: 48,
                        errorBuilder: (_, __, ___) => _nexoraLogoPreview(),
                      )
                    : _nexoraLogoPreview(),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: _uploadingLogo ? null : _uploadLogo,
                    icon: _uploadingLogo
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload_outlined, size: 16),
                    label: Text(
                      _uploadingLogo ? 'Caricamento...' : 'Carica logo',
                    ),
                  ),
                  if (currentLogo != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _removeLogo,
                      child: const Text(
                        'Rimuovi logo',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'PNG, JPG, SVG · Max 5MB\nSfondo trasparente consigliato',
                    style: TextStyle(fontSize: 11, color: Color(0xFFC1B8AB)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Colore brand ──
        _SectionCard(
          title: 'Colore brand',
          subtitle:
              'Personalizza il colore principale della tua piattaforma: sidebar, pulsanti e accenti.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview live
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: currentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Anteprima colore · ${colorToHex(currentColor)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Preset colors
              const Text(
                'Colori preset',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets.map((color) {
                  final isSelected =
                      colorToHex(color) == colorToHex(currentColor);
                  return GestureDetector(
                    onTap: () => _applyColor(color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withOpacity(.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // HEX input
              const Text(
                'Colore personalizzato (HEX)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      controller: _hexCtrl,
                      decoration: const InputDecoration(
                        hintText: '#034F3B',
                        border: OutlineInputBorder(),
                        prefixText: '',
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                      onChanged: (v) {
                        final color = hexToColor(
                          v.trim().startsWith('#') ? v.trim() : '#${v.trim()}',
                        );
                        if (color != null) {
                          GussoniBrand.primary;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _savingColor
                        ? null
                        : () {
                            final hex = _hexCtrl.text.trim();
                            final color = hexToColor(
                              hex.startsWith('#') ? hex : '#$hex',
                            );
                            if (color != null) _applyColor(color);
                          },
                    child: Text(_savingColor ? 'Salvataggio...' : 'Applica'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _applyColor(GussoniBrand.primary),
                    child: const Text('Ripristina default'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nexoraLogoPreview() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(GussoniBrand.logoWhitePath, height: 28),
      const SizedBox(width: 6),
      const Text(
        'Gussoni CRM',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

// ─── TAB: Gestione Team ──────────────────────────────────────────────────────

class _PianoTeamTab extends StatefulWidget {
  const _PianoTeamTab({
    required this.userId,
    required this.teamInfo,
    required this.adminRepo,
    this.onRemoveTeamMember,
  });

  final String userId;
  final TeamInfo teamInfo;
  final AdminRepository adminRepo;
  final Future<void> Function(String memberId)? onRemoveTeamMember;

  @override
  State<_PianoTeamTab> createState() => _PianoTeamTabState();
}

class _PianoTeamTabState extends State<_PianoTeamTab> {
  @override
  Widget build(BuildContext context) {
    final members = widget.teamInfo.activeMembers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          title: 'Membri del team',
          subtitle: '${members.length} membro/i',
          action: FilledButton.icon(
            onPressed: () => _showAddMemberDialog(context),
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: const Text('Aggiungi membro'),
            style: FilledButton.styleFrom(
              backgroundColor: GussoniBrand.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          child: Column(
            children: members.map((m) {
              final isMe = m.userId == widget.userId;
              final isOwner = m.userId == widget.teamInfo.ownerId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: isOwner
                      ? GussoniBrand.primary
                      : GussoniBrand.textMuted,
                  child: Text(
                    m.initials,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                title: Text(
                  m.displayName.isNotEmpty ? m.displayName : m.email,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${m.email}${m.role.isNotEmpty ? " · ${m.role}" : ""}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: GussoniBrand.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: GussoniBrand.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Owner',
                          style: TextStyle(
                            fontSize: 11,
                            color: GussoniBrand.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (isMe && !isOwner)
                      const Text(
                        'Tu',
                        style: TextStyle(
                          fontSize: 12,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    if (!isOwner && !isMe && widget.onRemoveTeamMember != null)
                      IconButton(
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          size: 18,
                          color: Color(0xFFEF4444),
                        ),
                        tooltip: 'Rimuovi dal team',
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Rimuovi membro'),
                              content: Text(
                                'Rimuovere ${m.displayName.isNotEmpty ? m.displayName : m.email} dal team?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Annulla'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Rimuovi'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true)
                            await widget.onRemoveTeamMember!(m.userId);
                        },
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _AddMemberDialog(teamId: widget.teamInfo.id, repo: widget.adminRepo),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.teamId, required this.repo});
  final String teamId;
  final AdminRepository repo;
  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String? _selectedRole;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Email e password sono obbligatori.');
      return;
    }
    if (_selectedRole == null) {
      setState(() => _error = 'Seleziona un ruolo.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.addMemberToTeam(
        teamId: widget.teamId,
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        role: _selectedRole!,
        password: _passCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aggiungi membro al team'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email *'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: 'Password *'),
                    obscureText: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    hint: const Text('Ruolo *'),
                    decoration: const InputDecoration(labelText: 'Ruolo *'),
                    items: GussoniRoles.all
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedRole = v),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Aggiungi'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
  });
  final DocumentTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isPreventivo = template.category == kPreventivo;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GussoniBrand.borderSubtle),
        boxShadow: [
          const BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPreventivo
                          ? const Color(0xFFEFF6FF)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPreventivo
                          ? Icons.request_quote_outlined
                          : Icons.receipt_long_outlined,
                      size: 20,
                      color: isPreventivo
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF22C55E),
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('Modifica'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Elimina',
                              style: TextStyle(color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    icon: const Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Color(0xFFC1B8AB),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                template.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1D1F),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${template.elements.length} elementi · ${template.customFields.length} campi custom',
                style: const TextStyle(
                  fontSize: 11,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
