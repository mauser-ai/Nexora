/// Ruoli predefiniti della piattaforma Gussoni CRM.
/// Il primo utente di ogni team è sempre Owner (nessun ruolo selezionabile).
/// I permessi per ciascun ruolo verranno definiti in seguito.
abstract class GussoniRoles {
  static const String commerciale             = 'Commerciale';
  static const String amministrazione         = 'Amministrazione';
  static const String responsabileAmm         = 'Responsabile Amministrazione';
  static const String operatore               = 'Operatore';
  static const String responsabileRendiconti  = 'Responsabile Rendiconti';
  static const String cliente                 = 'Cliente';

  /// Tutti i ruoli selezionabili al momento dell'aggiunta di un membro.
  static const List<String> all = [
    commerciale,
    amministrazione,
    responsabileAmm,
    operatore,
    responsabileRendiconti,
    cliente,
  ];
}
