import 'package:flutter/material.dart';

class DesktopTrayItem {
  const DesktopTrayItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.iconKey,
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String iconKey;

  IconData get icon => _iconForKey(iconKey);

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'title': title,
    'subtitle': subtitle,
    'iconKey': iconKey,
  };

  factory DesktopTrayItem.fromMap(Map<String, dynamic> map) => DesktopTrayItem(
    id: (map['id'] as String?) ?? '',
    type: (map['type'] as String?) ?? 'Elemento',
    title: (map['title'] as String?) ?? 'Elemento',
    subtitle: (map['subtitle'] as String?) ?? '',
    iconKey:
        (map['iconKey'] as String?) ??
        _iconKeyForLegacyCodePoint((map['iconCodePoint'] as num?)?.toInt()),
  );
}

IconData _iconForKey(String key) {
  switch (key) {
    case 'quote':
      return Icons.request_quote_rounded;
    case 'company':
      return Icons.apartment_rounded;
    case 'contact':
      return Icons.person_rounded;
    case 'project':
      return Icons.folder_open_rounded;
    case 'opportunity':
      return Icons.trending_up_rounded;
    case 'task':
      return Icons.check_circle_rounded;
    case 'invoice':
      return Icons.receipt_long_rounded;
    default:
      return Icons.push_pin_rounded;
  }
}

String _iconKeyForLegacyCodePoint(int? codePoint) {
  if (codePoint == Icons.request_quote_rounded.codePoint) return 'quote';
  if (codePoint == Icons.apartment_rounded.codePoint) return 'company';
  if (codePoint == Icons.person_rounded.codePoint) return 'contact';
  if (codePoint == Icons.folder_open_rounded.codePoint) return 'project';
  if (codePoint == Icons.trending_up_rounded.codePoint) return 'opportunity';
  if (codePoint == Icons.check_circle_rounded.codePoint) return 'task';
  if (codePoint == Icons.receipt_long_rounded.codePoint) return 'invoice';
  return 'pin';
}
