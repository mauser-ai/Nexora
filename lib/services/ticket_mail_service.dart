import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class InboundTicketEmail {
  const InboundTicketEmail({
    required this.from,
    required this.fromName,
    required this.subject,
    required this.body,
    required this.receivedAt,
    required this.attachments,
  });

  final String from;
  final String fromName;
  final String subject;
  final String body;
  final DateTime receivedAt;
  final List<InboundTicketAttachment> attachments;

  factory InboundTicketEmail.fromMap(Map<String, dynamic> map) {
    final rawDate = map['receivedAt'] as String? ?? '';
    final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    return InboundTicketEmail(
      from: (map['from'] as String? ?? '').trim(),
      fromName: (map['fromName'] as String? ?? '').trim(),
      subject: (map['subject'] as String? ?? '').trim(),
      body: (map['body'] as String? ?? '').trim(),
      receivedAt: parsedDate,
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => InboundTicketAttachment.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.fileName.isNotEmpty && item.base64.isNotEmpty)
          .toList(),
    );
  }
}

class InboundTicketAttachment {
  const InboundTicketAttachment({
    required this.fileName,
    required this.mimeType,
    required this.base64,
    required this.contentId,
  });

  final String fileName;
  final String mimeType;
  final String base64;
  final String contentId;

  factory InboundTicketAttachment.fromMap(Map<String, dynamic> map) {
    return InboundTicketAttachment(
      fileName: (map['fileName'] as String? ?? '').trim(),
      mimeType: (map['mimeType'] as String? ?? '').trim(),
      base64: (map['base64'] as String? ?? '').trim(),
      contentId: (map['contentId'] as String? ?? '').trim(),
    );
  }
}

class TicketMailService {
  TicketMailService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _basePath = String.fromEnvironment(
    'ARCHIVE_API_BASE',
    defaultValue: '/archivio/api',
  );
  static const String _apiOrigin = String.fromEnvironment(
    'ARCHIVE_API_ORIGIN',
    defaultValue: 'https://nexora.sviluppo.host',
  );
  static const String _hookKey = String.fromEnvironment(
    'TICKET_HOOK_KEY',
    defaultValue: '',
  );

  Uri _uri(String script) {
    final normalizedBase = _normalizeBasePath(_basePath);
    final target = '$normalizedBase/$script';
    if (_isAbsoluteUrl(normalizedBase) || kIsWeb) {
      return Uri.parse(target);
    }
    final origin = _normalizeOrigin(_apiOrigin);
    return Uri.parse('$origin$target');
  }

  bool _isAbsoluteUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  String _normalizeBasePath(String value) {
    var base = value.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (_isAbsoluteUrl(base)) {
      return base;
    }
    if (!base.startsWith('/')) {
      base = '/$base';
    }
    return base;
  }

  String _normalizeOrigin(String value) {
    var origin = value.trim();
    if (origin.endsWith('/')) {
      origin = origin.substring(0, origin.length - 1);
    }
    return origin;
  }

  Future<void> sendTicketEmail({
    required String toEmail,
    required String subject,
    required String body,
    required List<String> attachmentPaths,
    String signatureHtml = '',
    List<Map<String, String>> attachmentsBase64 = const [],
    String? fromEmail,
    String? fromName,
  }) async {
    final response = await _client.post(
      _uri('send_ticket.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'to': toEmail,
        'subject': subject,
        'body': body,
        'attachments': attachmentPaths,
        'attachmentsBase64': attachmentsBase64,
        'signatureHtml': signatureHtml,
        if (fromEmail != null && fromEmail.isNotEmpty) 'fromEmail': fromEmail,
        if (fromName != null && fromName.isNotEmpty) 'fromName': fromName,
      }),
    );
    final raw = response.body.isEmpty ? '{}' : response.body;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Risposta non valida dal backend email.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError((payload['error'] ?? 'Invio email fallito.') as String);
    }
  }

  Future<List<InboundTicketEmail>> pullInboundEmails() async {
    final uri = _uri(
      _hookKey.isEmpty
          ? 'ticket_inbound_drain.php'
          : 'ticket_inbound_drain.php?key=${Uri.encodeQueryComponent(_hookKey)}',
    );
    final response = await _client.get(uri);
    final raw = response.body.isEmpty ? '{}' : response.body;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Risposta non valida dal backend inbound.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        (payload['error'] ?? 'Lettura inbound fallita.') as String,
      );
    }
    final items = payload['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => InboundTicketEmail.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}
