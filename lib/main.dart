import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/mb_workflow_app.dart';
import 'firebase_options.dart';
import 'services/analytics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }
  final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      (firebaseOptions.appId.contains(':web:') ||
          (firebaseOptions.iosBundleId?.isEmpty ?? true))) {
    runApp(
      const FirebaseBootstrapErrorApp(
        message:
            'Configurazione Firebase iOS non valida: l\'app sta usando un appId web oppure manca iosBundleId.',
        stackTrace:
            'Aggiorna lib/firebase_options.dart con un FirebaseOptions iOS reale oppure aggiungi ios/Runner/GoogleService-Info.plist del progetto corretto.',
      ),
    );
    return;
  }
  try {
    await Firebase.initializeApp(options: firebaseOptions);

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    runApp(const MbWorkflowApp());
    AnalyticsService.instance.logAppOpened();
  } catch (error, stackTrace) {
    debugPrint('Bootstrap Firebase fallito: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(
      FirebaseBootstrapErrorApp(
        message: error.toString(),
        stackTrace: stackTrace.toString(),
      ),
    );
  }
}

class FirebaseBootstrapErrorApp extends StatelessWidget {
  const FirebaseBootstrapErrorApp({
    required this.message,
    required this.stackTrace,
    super.key,
  });

  final String message;
  final String stackTrace;

  @override
  Widget build(BuildContext context) {
    const panelColor = Colors.white;
    const accent = Color(0xFF00332A);
    const soft = Color(0xFFACCF78);
    const bg = Color(0xFFF7F7F7);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: bg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFD8E7E0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1400332A),
                    blurRadius: 36,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0x1100332A),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.developer_mode_rounded, color: accent),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Avvio iOS bloccato',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'L’app non sta più crashando nel vuoto: il bootstrap si ferma perché la configurazione Firebase iOS non è valida per questo bundle.',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.45,
                      color: Color(0xFF355A52),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7F5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD7E6DF)),
                    ),
                    child: SelectableText(
                      message,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _HintChip(
                        text: 'Serve un GoogleService-Info.plist iOS oppure un firebase_options.dart con appId iOS reale',
                      ),
                      _HintChip(
                        text: 'Il valore attuale usa un appId web, quindi Firebase iPhone abortisce l’avvio',
                      ),
                    ],
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 22),
                    const Text(
                      'Dettaglio tecnico',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 220),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E231E),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          stackTrace,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: soft,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1400332A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x2200332A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: Color(0xFF355A52),
        ),
      ),
    );
  }
}
