// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'archive_integrations_models.dart';

const _key = 'nexora_archive_integrations_v1';

class ArchiveIntegrationsStore {
  Future<ArchiveIntegrationsState> load() async {
    try {
      final raw = html.window.localStorage[_key];
      if (raw == null || raw.isEmpty) {
        return const ArchiveIntegrationsState();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ArchiveIntegrationsState.fromJson(decoded);
      }
      if (decoded is Map) {
        return ArchiveIntegrationsState.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      // Cache locale non disponibile o corrotta: le integrazioni tornano off.
    }
    return const ArchiveIntegrationsState();
  }

  Future<void> save(ArchiveIntegrationsState state) async {
    try {
      html.window.localStorage[_key] = jsonEncode(state.toJson());
    } catch (_) {
      // no-op
    }
  }
}
