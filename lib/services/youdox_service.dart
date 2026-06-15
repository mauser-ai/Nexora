import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/domain_models.dart';

class YoudoxDraftResult {
  const YoudoxDraftResult({required this.filename, required this.message});

  final String filename;
  final String message;
}

class YoudoxService {
  const YoudoxService();

  Future<YoudoxDraftResult> createDraftFromXml({
    required String xml,
    required String filename,
    required YouDoxConfig credentials,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Utente non autenticato.');
    }
    final idToken = await user.getIdToken();
    final uri = Uri.parse(
      'https://youdoxcreatedrafthttp-pqdcqemh4a-ew.a.run.app',
    );
    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(<String, dynamic>{
        'xml': xml,
        'filename': filename,
        'credentials': <String, String>{
          'username': credentials.username,
          'password': credentials.password,
          'clientId': credentials.clientId,
        },
      }),
    );
    final decoded = jsonDecode(response.body);
    final data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        (data['error'] as String? ?? 'Errore YouDOX (${response.statusCode}).')
            .trim(),
      );
    }
    if (data['ok'] != true) {
      throw Exception('YouDOX non ha confermato la creazione bozza.');
    }
    return YoudoxDraftResult(
      filename: (data['filename'] as String? ?? filename).trim(),
      message: (data['message'] as String? ?? '').trim(),
    );
  }
}
