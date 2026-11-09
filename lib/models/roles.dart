/// Ruoli predefiniti/fallback della piattaforma Nexora.
/// Il primo utente di ogni team è sempre Owner (nessun ruolo selezionabile).
abstract class GussoniRoles {
  static const String commerciale = 'Commerciale';
  static const String amministrazione = 'Amministrazione';
  static const String responsabileAmm = 'Responsabile Amministrazione';
  static const String operatore = 'Operatore';
  static const String responsabileRendiconti = 'Responsabile Rendiconti';
  static const String cliente = 'Cliente';

  /// Tutti i ruoli selezionabili al momento dell'aggiunta di un membro.
  static const List<String> all = [
    commerciale,
    amministrazione,
    responsabileAmm,
    operatore,
    responsabileRendiconti,
    cliente,
  ];

  static List<String> normalize(Iterable<String> roles) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final role in roles) {
      final value = role.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (key == 'owner') continue;
      if (seen.add(key)) {
        normalized.add(value);
      }
    }
    return normalized;
  }
}
