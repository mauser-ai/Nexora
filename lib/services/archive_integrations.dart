import 'archive_integrations_stub.dart'
    if (dart.library.html) 'archive_integrations_web.dart'
    as impl;
import 'archive_integrations_models.dart';
export 'archive_integrations_models.dart';

final archiveIntegrationsController = ArchiveIntegrationsController();

class ArchiveIntegrationsController {
  final impl.ArchiveIntegrationsStore _store = impl.ArchiveIntegrationsStore();
  final listeners = <void Function(ArchiveIntegrationsState)>[];
  ArchiveIntegrationsState _state = const ArchiveIntegrationsState();
  bool _loaded = false;

  ArchiveIntegrationsState get state => _state;

  void addListener(void Function(ArchiveIntegrationsState) listener) {
    listeners.add(listener);
  }

  void removeListener(void Function(ArchiveIntegrationsState) listener) {
    listeners.remove(listener);
  }

  Future<ArchiveIntegrationsState> load() async {
    if (_loaded) return _state;
    _state = await _store.load();
    _loaded = true;
    _notify();
    return _state;
  }

  Future<void> setConnected(
    ArchiveIntegrationProvider provider,
    bool connected,
  ) async {
    await load();
    _state = switch (provider) {
      ArchiveIntegrationProvider.googleDrive => _state.copyWith(
        googleDriveConnected: connected,
      ),
      ArchiveIntegrationProvider.dropbox => _state.copyWith(
        dropboxConnected: connected,
      ),
    };
    await _store.save(_state);
    _notify();
  }

  void _notify() {
    for (final listener in List.of(listeners)) {
      listener(_state);
    }
  }
}
