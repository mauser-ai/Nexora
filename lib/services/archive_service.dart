import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'archive_integrations.dart';

class ArchiveEntry {
  const ArchiveEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  factory ArchiveEntry.fromMap(Map<String, dynamic> map) {
    return ArchiveEntry(
      name: (map['name'] ?? '') as String,
      path: (map['path'] ?? '') as String,
      isDirectory: (map['isDirectory'] ?? false) as bool,
      sizeBytes: map['sizeBytes'] as int?,
      modifiedAt: map['modifiedAt'] == null
          ? null
          : DateTime.tryParse(map['modifiedAt'] as String),
    );
  }
}

class ArchiveListResponse {
  const ArchiveListResponse({
    required this.currentPath,
    required this.folders,
    required this.files,
  });

  final String currentPath;
  final List<ArchiveEntry> folders;
  final List<ArchiveEntry> files;

  factory ArchiveListResponse.fromMap(Map<String, dynamic> map) {
    final foldersRaw = (map['folders'] as List<dynamic>? ?? const []);
    final filesRaw = (map['files'] as List<dynamic>? ?? const []);
    return ArchiveListResponse(
      currentPath: (map['currentPath'] ?? '') as String,
      folders: foldersRaw
          .map((item) => ArchiveEntry.fromMap(item as Map<String, dynamic>))
          .toList(),
      files: filesRaw
          .map((item) => ArchiveEntry.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ArchiveSharedFile {
  const ArchiveSharedFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  final String name;
  final String path;
  final int sizeBytes;

  factory ArchiveSharedFile.fromMap(Map<String, dynamic> map) {
    return ArchiveSharedFile(
      name: (map['name'] ?? '') as String,
      path: (map['path'] ?? '') as String,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class ArchiveShareSession {
  const ArchiveShareSession({
    required this.token,
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.files,
  });

  final String token;
  final String path;
  final String name;
  final bool isDirectory;
  final List<ArchiveSharedFile> files;

  factory ArchiveShareSession.fromMap(Map<String, dynamic> map) {
    final filesRaw = (map['files'] as List<dynamic>? ?? const []);
    return ArchiveShareSession(
      token: (map['token'] ?? '') as String,
      path: (map['path'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      isDirectory: (map['isDirectory'] ?? false) as bool,
      files: filesRaw
          .map(
            (item) => ArchiveSharedFile.fromMap(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ArchiveService {
  ArchiveService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _requestTimeout = Duration(seconds: 14);
  static const String _basePath = String.fromEnvironment(
    'ARCHIVE_API_BASE',
    defaultValue: '/archivio/api',
  );
  static const String _apiOrigin = String.fromEnvironment(
    'ARCHIVE_API_ORIGIN',
    defaultValue: 'https://nexora.sviluppo.host',
  );

  Uri _uri(String script, [Map<String, String>? query]) {
    final normalizedBase = _normalizeBasePath(_basePath);
    final target = '$normalizedBase/$script';
    if (_isAbsoluteUrl(normalizedBase) || kIsWeb) {
      return Uri.parse(target).replace(queryParameters: query);
    }
    final origin = _normalizeOrigin(_apiOrigin);
    return Uri.parse('$origin$target').replace(queryParameters: query);
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

  Future<ArchiveListResponse> list(String path) async {
    final response = await _getWithRetry(_uri('list.php', {'path': path}));
    final payload = _decodeResponse(response);
    return ArchiveListResponse.fromMap(payload);
  }

  Future<ArchiveListResponse> listIntegration({
    required ArchiveIntegrationProvider provider,
    required String path,
  }) async {
    final response = await _getWithRetry(
      _uri('integrations/list.php', {'provider': provider.key, 'path': path}),
    );
    final payload = _decodeResponse(response);
    return ArchiveListResponse.fromMap(payload);
  }

  Future<void> createFolder({
    required String path,
    required String name,
  }) async {
    await _postJson('create_folder.php', {'path': path, 'name': name});
  }

  Future<void> createIntegrationFolder({
    required ArchiveIntegrationProvider provider,
    required String path,
    required String name,
  }) async {
    await _postJson('integrations/create_folder.php', {
      'provider': provider.key,
      'path': path,
      'name': name,
    });
  }

  Future<void> ensureCompanyFolders(List<String> companyNames) async {
    await _postJson('ensure_companies.php', {'companies': companyNames});
  }

  Future<void> createCompanyStructure(String companyName) async {
    await _postJson('create_company_structure.php', {'company': companyName});
  }

  Future<void> createProjectStructure({
    required String companyName,
    required String projectName,
    List<String> phaseNames = const [],
  }) async {
    await _postJson('create_project_structure.php', {
      'company': companyName,
      'project': projectName,
      'phases': phaseNames,
    });
  }

  Future<void> deleteEntry({
    required String path,
    required bool isDirectory,
  }) async {
    await _postJson('delete.php', {'path': path, 'isDirectory': isDirectory});
  }

  Future<void> deleteIntegrationEntry({
    required ArchiveIntegrationProvider provider,
    required String path,
    required bool isDirectory,
  }) async {
    await _postJson('integrations/delete.php', {
      'provider': provider.key,
      'path': path,
      'isDirectory': isDirectory,
    });
  }

  Future<void> renameEntry({
    required String path,
    required String newName,
  }) async {
    await _postJson('rename.php', {'path': path, 'newName': newName});
  }

  Future<void> renameIntegrationEntry({
    required ArchiveIntegrationProvider provider,
    required String path,
    required String newName,
  }) async {
    await _postJson('integrations/rename.php', {
      'provider': provider.key,
      'path': path,
      'newName': newName,
    });
  }

  Future<void> moveEntry({
    required String sourcePath,
    required String destinationPath,
  }) async {
    await _postJson('move.php', {
      'sourcePath': sourcePath,
      'destinationPath': destinationPath,
    });
  }

  Future<void> moveIntegrationEntry({
    required ArchiveIntegrationProvider provider,
    required String sourcePath,
    required String destinationPath,
  }) async {
    await _postJson('integrations/move.php', {
      'provider': provider.key,
      'sourcePath': sourcePath,
      'destinationPath': destinationPath,
    });
  }

  Future<List<String>> listFolders() async {
    final response = await _getWithRetry(_uri('list_folders.php'));
    final payload = _decodeResponse(response);
    final folders = (payload['folders'] as List<dynamic>? ?? const [])
        .map((item) => (item as String?) ?? '')
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return folders;
  }

  Future<List<String>> listIntegrationFolders(
    ArchiveIntegrationProvider provider,
  ) async {
    final response = await _getWithRetry(
      _uri('integrations/list_folders.php', {'provider': provider.key}),
    );
    final payload = _decodeResponse(response);
    final folders = (payload['folders'] as List<dynamic>? ?? const [])
        .map((item) => (item as String?) ?? '')
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return folders;
  }

  Future<String> createShareLink({
    required String path,
    required bool isDirectory,
  }) async {
    final payload = await _postJson('share_create.php', {
      'path': path,
      'isDirectory': isDirectory,
    });
    return (payload['url'] ?? '') as String;
  }

  Future<ArchiveShareSession> createShareSession({
    required String path,
    required bool isDirectory,
  }) async {
    final payload = await _postJson('share_create.php', {
      'path': path,
      'isDirectory': isDirectory,
    });
    final token = (payload['token'] ?? '') as String;
    if (token.trim().isEmpty) {
      throw StateError('Token condivisione non disponibile.');
    }
    final metaResponse = await _getWithRetry(
      _uri('share_meta.php', {'token': token}),
    );
    final metaPayload = _decodeResponse(metaResponse);
    return ArchiveShareSession.fromMap(metaPayload);
  }

  String buildDownloadUrl({required String token, required String filePath}) {
    return _uri('download.php', {'token': token, 'file': filePath}).toString();
  }

  String buildIntegrationDownloadUrl({
    required ArchiveIntegrationProvider provider,
    required String path,
  }) {
    return _uri('integrations/download.php', {
      'provider': provider.key,
      'path': path,
    }).toString();
  }

  Future<void> uploadFile({
    required String path,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final request = http.MultipartRequest('POST', _uri('upload.php'));
      request.fields['path'] = path;
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      _decodeResponse(response);
      return;
    } catch (_) {
      try {
        // Fallback 1: alcuni hosting/proxy bloccano multipart.
        await _postJson('upload.php', {
          'path': path,
          'fileName': fileName,
          'contentBase64': base64Encode(bytes),
        });
        return;
      } catch (_) {
        // Fallback 2: raw body binario.
        final response = await _client.post(
          _uri('upload.php', {'path': path, 'fileName': fileName}),
          headers: {'Content-Type': 'application/octet-stream'},
          body: bytes,
        );
        _decodeResponse(response);
      }
    }
  }

  Future<void> uploadIntegrationFile({
    required ArchiveIntegrationProvider provider,
    required String path,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri('integrations/upload.php'),
      );
      request.fields['provider'] = provider.key;
      request.fields['path'] = path;
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      _decodeResponse(response);
      return;
    } catch (_) {
      await _postJson('integrations/upload.php', {
        'provider': provider.key,
        'path': path,
        'fileName': fileName,
        'contentBase64': base64Encode(bytes),
      });
    }
  }

  Future<http.Response> _getWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(_requestTimeout);
        if (response.statusCode >= 500 && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return response;
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
      }
    }
    throw StateError('Archivio temporaneamente non raggiungibile: $lastError');
  }

  Future<Map<String, dynamic>> _postJson(
    String script,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          _uri(script),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final body = response.body.isEmpty ? '{}' : response.body;
    Map<String, dynamic> map;
    try {
      map = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      final preview = body.length > 180 ? '${body.substring(0, 180)}...' : body;
      throw StateError(
        'Risposta non JSON (${response.statusCode}) da $_basePath. Anteprima: $preview',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return map;
    }
    final message = (map['error'] ?? 'Errore archivio') as String;
    throw StateError(message);
  }
}
