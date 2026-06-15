import 'archive_integrations_models.dart';

class ArchiveIntegrationsStore {
  ArchiveIntegrationsState _state = const ArchiveIntegrationsState();

  Future<ArchiveIntegrationsState> load() async => _state;

  Future<void> save(ArchiveIntegrationsState state) async {
    _state = state;
  }
}
