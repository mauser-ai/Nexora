import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/api_client.dart';

/// Carica un'immagine sull'hosting PHP (stesso flusso del wallpaper desktop:
/// il progetto non usa Firebase Storage). Ritorna l'URL pubblico.
///
/// [folder] ∈ 'template' | 'brand' | 'avatar' (whitelist lato server).
Future<String> uploadAssetImage({
  required Uint8List bytes,
  required String filename,
  required String folder,
}) async {
  final headers = await ApiClient.instance.authorizedHeaders(
    includeJsonContentType: false,
  );
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('${ApiClient.baseUrl}/desktop/upload_asset.php'),
  );
  request.headers.addAll(headers);
  request.fields['folder'] = folder;
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename.isNotEmpty ? filename : 'asset.png',
    ),
  );
  final response = await request.send();
  final body = await response.stream.bytesToString();
  final payload = body.isEmpty
      ? const <String, dynamic>{}
      : (jsonDecode(body) as Map<String, dynamic>);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      payload['error'] ?? 'Upload fallito (${response.statusCode}).',
    );
  }
  final url = (payload['url'] as String? ?? '').trim();
  if (url.isEmpty) {
    throw Exception('Il server non ha restituito l\'URL dell\'immagine.');
  }
  return url;
}
