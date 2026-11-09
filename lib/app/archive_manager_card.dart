import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand_config.dart';
import '../data/firestore_workspace_repository.dart';
import 'archive_file_preview.dart';
import 'nexora_dialog.dart';
import '../services/archive_integrations.dart';
import '../services/archive_service.dart';
import '../services/web_file_picker.dart';

enum _ArchiveViewMode { icons, list, columns }

enum _ArchiveSource { local, googleDrive, dropbox }

class ArchiveManagerCard extends StatefulWidget {
  const ArchiveManagerCard({super.key, required this.workspace});

  final WorkspaceSnapshot workspace;

  @override
  State<ArchiveManagerCard> createState() => _ArchiveManagerCardState();
}

class _ArchiveManagerCardState extends State<ArchiveManagerCard> {
  final ArchiveService _service = ArchiveService();
  bool _loading = false;
  bool _dragging = false;
  String? _loadError;
  String _currentPath = '';
  String _query = '';
  _ArchiveViewMode _viewMode = _ArchiveViewMode.list;
  _ArchiveSource _source = _ArchiveSource.local;
  ArchiveIntegrationsState _integrations = archiveIntegrationsController.state;
  List<ArchiveEntry> _folders = const [];
  List<ArchiveEntry> _files = const [];

  @override
  void initState() {
    super.initState();
    archiveIntegrationsController.addListener(_handleIntegrationsChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _integrations = await archiveIntegrationsController.load();
    await _load();
  }

  @override
  void dispose() {
    archiveIntegrationsController.removeListener(_handleIntegrationsChanged);
    super.dispose();
  }

  void _handleIntegrationsChanged(ArchiveIntegrationsState state) {
    if (!mounted) return;
    setState(() => _integrations = state);
    if (!_sourceAvailable(_source)) {
      setState(() {
        _source = _ArchiveSource.local;
        _currentPath = '';
      });
      _load();
    }
  }

  ArchiveIntegrationProvider? get _activeProvider => switch (_source) {
    _ArchiveSource.googleDrive => ArchiveIntegrationProvider.googleDrive,
    _ArchiveSource.dropbox => ArchiveIntegrationProvider.dropbox,
    _ArchiveSource.local => null,
  };

  bool _sourceAvailable(_ArchiveSource source) => switch (source) {
    _ArchiveSource.local => true,
    _ArchiveSource.googleDrive => _integrations.googleDriveConnected,
    _ArchiveSource.dropbox => _integrations.dropboxConnected,
  };

  void _selectSource(_ArchiveSource source) {
    if (!_sourceAvailable(source)) return;
    setState(() {
      _source = source;
      _currentPath = '';
      _query = '';
      _folders = const [];
      _files = const [];
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final provider = _activeProvider;
      final response = provider == null
          ? await _service.list(_currentPath)
          : await _service.listIntegration(
              provider: provider,
              path: _currentPath,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _folders = response.folders;
        _files = response.files;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadError = _friendlyArchiveError(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_loadError ?? 'Archivio non disponibile.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _friendlyArchiveError(Object error) {
    final raw = error.toString();
    if (raw.contains('temporaneamente non raggiungibile') ||
        raw.contains('TimeoutException')) {
      return 'Archivio lento o non raggiungibile. Riprova tra qualche secondo.';
    }
    if (raw.contains('Risposta non JSON')) {
      return 'Archivio: risposta server non valida. Riprova o controlla il PHP.';
    }
    return raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Exception: ', '');
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const NexoraInputDialog(
        title: 'Nuova cartella',
        label: 'Nome cartella',
        icon: Icons.create_new_folder_outlined,
        confirmLabel: 'Crea',
      ),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    try {
      final provider = _activeProvider;
      if (provider == null) {
        await _service.createFolder(path: _currentPath, name: name.trim());
      } else {
        await _service.createIntegrationFolder(
          provider: provider,
          path: _currentPath,
          name: name.trim(),
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore creazione cartella: $error')),
      );
    }
  }

  Future<void> _pickAndUploadFiles() async {
    try {
      final payload = <({String name, Uint8List bytes})>[];
      if (kIsWeb) {
        final webFiles = await pickFilesForWeb();
        payload.addAll(webFiles);
      } else {
        final picked = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: false,
        );
        if (picked == null) {
          return;
        }
        final pickedFiles = picked.xFiles;
        for (final file in pickedFiles) {
          try {
            final name = file.name.trim();
            if (name.isEmpty) {
              continue;
            }
            final bytes = await file.readAsBytes();
            if (bytes.isEmpty) {
              continue;
            }
            payload.add((name: name, bytes: bytes));
          } catch (_) {
            continue;
          }
        }
      }
      if (payload.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nessun file selezionato.')),
          );
        }
        return;
      }
      await _uploadMany(payload);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore selezione file: $error')));
    }
  }

  Future<void> _uploadMany(List<({String name, Uint8List bytes})> files) async {
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drop senza file rilevati.')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final provider = _activeProvider;
      for (final file in files) {
        if (provider == null) {
          await _service.uploadFile(
            path: _currentPath,
            fileName: file.name,
            bytes: file.bytes,
          );
        } else {
          await _service.uploadIntegrationFile(
            provider: provider,
            path: _currentPath,
            fileName: file.name,
            bytes: file.bytes,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Caricati ${files.length} file.')),
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore upload: $error')));
      setState(() => _loading = false);
    }
  }

  Future<void> _handleDrop(List<dynamic> files) async {
    try {
      final payload = <({String name, Uint8List bytes})>[];
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          String name = '';
          try {
            name = file.name.trim();
          } catch (_) {
            name = '';
          }
          if (name.isEmpty) {
            final rawPath = file.path;
            if (rawPath.isNotEmpty) {
              name = rawPath.split('/').last;
            }
          }
          if (name.isNotEmpty && bytes.isNotEmpty) {
            payload.add((name: name, bytes: bytes));
          }
        } catch (_) {
          continue;
        }
      }
      await _uploadMany(payload);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore drag and drop: $error')));
    }
  }

  Future<void> _deleteEntry(ArchiveEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina elemento?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare "${entry.name}"?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final provider = _activeProvider;
      if (provider == null) {
        await _service.deleteEntry(
          path: entry.path,
          isDirectory: entry.isDirectory,
        );
      } else {
        await _service.deleteIntegrationEntry(
          provider: provider,
          path: entry.path,
          isDirectory: entry.isDirectory,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore eliminazione: $error')));
    }
  }

  Future<void> _renameEntry(ArchiveEntry entry) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => NexoraInputDialog(
        title: 'Rinomina',
        label: 'Nuovo nome',
        initialValue: entry.name,
        icon: Icons.drive_file_rename_outline_rounded,
        confirmLabel: 'Salva',
      ),
    );
    if (newName == null || newName.isEmpty || newName == entry.name) {
      return;
    }
    try {
      final provider = _activeProvider;
      if (provider == null) {
        await _service.renameEntry(path: entry.path, newName: newName);
      } else {
        await _service.renameIntegrationEntry(
          provider: provider,
          path: entry.path,
          newName: newName,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore rinomina: $error')));
    }
  }

  Future<void> _moveEntry(ArchiveEntry entry) async {
    try {
      final provider = _activeProvider;
      final folders = provider == null
          ? await _service.listFolders()
          : await _service.listIntegrationFolders(provider);
      if (!mounted) {
        return;
      }
      String destination = _currentPath;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => NexoraDialog(
            title: 'Sposta',
            icon: Icons.drive_file_move_outline,
            width: 460,
            actions: [
              TextButton(
                style: NexoraDialog.cancelButtonStyle(),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annulla'),
              ),
              FilledButton(
                style: NexoraDialog.primaryButtonStyle(),
                onPressed: () => Navigator.of(context).pop(destination),
                child: const Text('Sposta'),
              ),
            ],
            child: DropdownButtonFormField<String>(
              initialValue: destination,
              decoration: NexoraDialog.fieldDecoration('Cartella destinazione'),
              items: folders
                  .map(
                    (folder) => DropdownMenuItem<String>(
                      value: folder,
                      child: Text(folder.isEmpty ? 'Clienti (root)' : folder),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setModalState(() => destination = value);
              },
            ),
          ),
        ),
      );
      if (selected == null) {
        return;
      }
      if (provider == null) {
        await _service.moveEntry(
          sourcePath: entry.path,
          destinationPath: selected,
        );
      } else {
        await _service.moveIntegrationEntry(
          provider: provider,
          sourcePath: entry.path,
          destinationPath: selected,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore spostamento: $error')));
    }
  }

  Future<void> _downloadEntry(ArchiveEntry entry) async {
    if (entry.isDirectory) {
      return;
    }
    if (_activeProvider != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Download diretto ${_activeProvider!.label}: endpoint cloud da collegare lato hosting.',
          ),
        ),
      );
      return;
    }
    try {
      final session = await _service.createShareSession(
        path: _currentPath,
        isDirectory: true,
      );
      final url = _service.buildDownloadUrl(
        token: session.token,
        filePath: entry.path,
      );
      final opened = await launchUrl(
        Uri.parse(url),
        webOnlyWindowName: '_blank',
      );
      if (opened || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il download.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore download: $error')));
    }
  }

  Future<void> _shareEntry(ArchiveEntry entry) async {
    if (_activeProvider != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Condivisione ${_activeProvider!.label}: endpoint cloud da collegare lato hosting.',
          ),
        ),
      );
      return;
    }
    try {
      final link = await _service.createShareLink(
        path: entry.path,
        isDirectory: entry.isDirectory,
      );
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link condiviso copiato negli appunti.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore condivisione: $error')));
    }
  }

  List<String> get _segments => _currentPath
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();

  String _pathUntil(int indexInclusive) {
    if (indexInclusive < 0) {
      return '';
    }
    return _segments.take(indexInclusive + 1).join('/');
  }

  List<ArchiveEntry> _visibleEntries() {
    final query = _query.trim().toLowerCase();
    final entries = [..._folders, ..._files];
    if (query.isEmpty) {
      return entries;
    }
    return entries
        .where((entry) => entry.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries();
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 760;
        return mobile
            ? _buildMobileFiles(entries)
            : _buildDesktopFinder(entries);
      },
    );
  }

  Widget _buildDesktopFinder(List<ArchiveEntry> entries) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .82),
            GussoniBrand.surfaceSubtle.withValues(alpha: .68),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: GussoniBrand.border.withValues(alpha: .88)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _ArchiveSidebar(
            segments: _segments,
            currentPath: _currentPath,
            source: _source,
            integrations: _integrations,
            onSource: _selectSource,
            onRoot: () {
              setState(() => _currentPath = '');
              _load();
            },
            onSegment: (index) {
              setState(() => _currentPath = _pathUntil(index));
              _load();
            },
          ),
          Expanded(
            child: Column(
              children: [
                _buildFinderToolbar(mobile: false),
                Expanded(child: _buildDropArea(entries)),
                _ArchiveStatusBar(
                  count: entries.length,
                  folders: _folders.length,
                  files: _files.length,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFiles(List<ArchiveEntry> entries) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .96),
            GussoniBrand.surfaceSubtle.withValues(alpha: .92),
            GussoniBrand.primaryBg.withValues(alpha: .54),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildFinderToolbar(mobile: true),
          Expanded(child: _buildDropArea(entries, mobile: true)),
        ],
      ),
    );
  }

  Widget _buildFinderToolbar({required bool mobile}) {
    final rootTitle = switch (_source) {
      _ArchiveSource.local => 'Archivio',
      _ArchiveSource.googleDrive => 'Drive',
      _ArchiveSource.dropbox => 'Dropbox',
    };
    final title = _segments.isEmpty ? rootTitle : _segments.last;
    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 18, 12, mobile ? 16 : 18, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: mobile ? .58 : .64),
        border: Border(
          bottom: BorderSide(color: GussoniBrand.border.withValues(alpha: .92)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _segments.isEmpty || _loading
                    ? null
                    : () {
                        setState(() {
                          _currentPath = _segments.length == 1
                              ? ''
                              : _pathUntil(_segments.length - 2);
                        });
                        _load();
                      },
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Indietro',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: mobile ? 24 : 22,
                    fontWeight: FontWeight.w900,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
              if (!mobile) ...[
                _ArchiveViewSwitcher(
                  value: _viewMode,
                  onChanged: (mode) => setState(() => _viewMode = mode),
                ),
                const SizedBox(width: 10),
              ],
              IconButton(
                onPressed: _loading ? null : _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: 'Nuova cartella',
              ),
              IconButton.filledTonal(
                onPressed: _loading ? null : _pickAndUploadFiles,
                icon: const Icon(Icons.upload_file_outlined),
                tooltip: 'Carica file',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: mobile ? 'Cerca' : 'Cerca in Archivio',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: GussoniBrand.glassSurface.withValues(alpha: .90),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: GussoniBrand.border.withValues(alpha: .92),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: GussoniBrand.border.withValues(alpha: .92),
                      ),
                    ),
                  ),
                ),
              ),
              if (mobile) ...[
                const SizedBox(width: 8),
                _ArchiveViewSwitcher(
                  value: _viewMode == _ArchiveViewMode.columns
                      ? _ArchiveViewMode.list
                      : _viewMode,
                  compact: true,
                  onChanged: (mode) => setState(() => _viewMode = mode),
                ),
              ],
            ],
          ),
          if (_segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ArchiveBreadcrumbs(
              segments: _segments,
              rootLabel: rootTitle,
              onRoot: () {
                setState(() => _currentPath = '');
                _load();
              },
              onSegment: (index) {
                setState(() => _currentPath = _pathUntil(index));
                _load();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropArea(List<ArchiveEntry> entries, {bool mobile = false}) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(mobile ? 0 : 20),
        border: Border.all(
          color: _dragging
              ? GussoniBrand.primary
              : GussoniBrand.border.withValues(alpha: mobile ? 0 : .84),
          width: _dragging ? 2 : 1,
        ),
        color: _dragging
            ? GussoniBrand.primaryBg
            : GussoniBrand.glassSurface.withValues(alpha: mobile ? .24 : .54),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_loadError != null)
                  _ArchiveLoadErrorBanner(message: _loadError!, onRetry: _load),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            _loadError == null
                                ? 'Cartella vuota. Trascina qui i file o usa "Carica file".'
                                : 'Dati non disponibili al momento.',
                          ),
                        )
                      : _buildEntries(entries, mobile: mobile),
                ),
              ],
            ),
    );

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        await _handleDrop(detail.files);
      },
      child: content,
    );
  }

  Widget _buildEntries(List<ArchiveEntry> entries, {required bool mobile}) {
    if (_viewMode == _ArchiveViewMode.icons) {
      return GridView.builder(
        padding: EdgeInsets.all(mobile ? 16 : 14),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: mobile ? 132 : 170,
          crossAxisSpacing: mobile ? 14 : 12,
          mainAxisSpacing: mobile ? 14 : 12,
          mainAxisExtent: mobile ? 128 : 136,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => _buildTile(entries[index]),
      );
    }
    if (_viewMode == _ArchiveViewMode.columns && !mobile) {
      return _ArchiveColumnsView(
        segments: _segments,
        entries: entries,
        entryIcon: _entryIcon,
        entryAccent: _entryAccent,
        meta: _formatFileMeta,
        onRoot: () {
          setState(() => _currentPath = '');
          _load();
        },
        onSegment: (index) {
          setState(() => _currentPath = _pathUntil(index));
          _load();
        },
        onOpen: _openEntry,
        onRename: _renameEntry,
        onMove: _moveEntry,
        onShare: _shareEntry,
        onDelete: _deleteEntry,
      );
    }
    return Column(
      children: [
        if (!mobile) const _ArchiveListHeader(),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              mobile ? 12 : 10,
              8,
              mobile ? 12 : 10,
              16,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _ArchiveListRow(
                entry: entry,
                icon: _entryIcon(entry),
                accentColor: _entryAccent(entry),
                meta: entry.isDirectory ? 'Cartella' : _formatFileMeta(entry),
                type: entry.isDirectory ? 'Cartella' : _fileTypeLabel(entry),
                modified: _formatDate(entry.modifiedAt),
                onOpen: () => _openEntry(entry),
                onRename: () => _renameEntry(entry),
                onMove: () => _moveEntry(entry),
                onShare: () => _shareEntry(entry),
                onDelete: () => _deleteEntry(entry),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTile(ArchiveEntry entry) => _ArchiveTile(
    entry: entry,
    subtitle: entry.isDirectory ? 'Cartella' : _formatFileMeta(entry),
    extensionBadge: _fileExtension(entry.name),
    icon: _entryIcon(entry),
    accentColor: _entryAccent(entry),
    onOpen: () => _openEntry(entry),
    onRename: () => _renameEntry(entry),
    onMove: () => _moveEntry(entry),
    onShare: () => _shareEntry(entry),
    onDelete: () => _deleteEntry(entry),
  );

  void _openEntry(ArchiveEntry entry) {
    if (entry.isDirectory) {
      setState(() => _currentPath = entry.path);
      _load();
      return;
    }
    _previewEntry(entry);
  }

  Future<void> _previewEntry(ArchiveEntry entry) async {
    final provider = _activeProvider;
    final Future<String> urlFuture;

    if (provider == null) {
      urlFuture = _service
          .createShareSession(path: _currentPath, isDirectory: true)
          .then(
            (session) => _service.buildDownloadUrl(
              token: session.token,
              filePath: entry.path,
            ),
          );
    } else {
      urlFuture = Future.value(
        _service.buildIntegrationDownloadUrl(
          provider: provider,
          path: entry.path,
        ),
      );
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: GussoniBrand.glassDark.withValues(alpha: .42),
      builder: (ctx) =>
          ArchiveFilePreviewDialog(entry: entry, urlFuture: urlFuture),
    );
  }

  String _formatFileMeta(ArchiveEntry entry) {
    final size = entry.sizeBytes;
    final modified = entry.modifiedAt;
    final sizeLabel = size == null ? '-' : _formatSize(size);
    final modifiedLabel = modified == null
        ? '-'
        : '${modified.day.toString().padLeft(2, '0')}/${modified.month.toString().padLeft(2, '0')}/${modified.year}';
    return '$sizeLabel • $modifiedLabel';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _fileTypeLabel(ArchiveEntry entry) {
    if (entry.isDirectory) {
      return 'Cartella';
    }
    final ext = _fileExtension(entry.name);
    if (ext.isEmpty) {
      return 'File';
    }
    return '$ext file';
  }

  IconData _entryIcon(ArchiveEntry entry) {
    if (entry.isDirectory) {
      return Icons.folder_rounded;
    }
    final ext = _fileExtension(entry.name).toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'svg':
        return Icons.image_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _entryAccent(ArchiveEntry entry) {
    if (entry.isDirectory) {
      return GussoniBrand.gold;
    }
    final ext = _fileExtension(entry.name).toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Color(0xFFC0392B);
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return GussoniBrand.info;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return GussoniBrand.success;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'svg':
        return const Color(0xFF7C3AED);
      case 'zip':
      case 'rar':
      case '7z':
        return GussoniBrand.warning;
      default:
        return GussoniBrand.textMuted;
    }
  }

  String _fileExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toUpperCase();
  }
}

class _ArchiveSidebar extends StatelessWidget {
  const _ArchiveSidebar({
    required this.segments,
    required this.currentPath,
    required this.source,
    required this.integrations,
    required this.onSource,
    required this.onRoot,
    required this.onSegment,
  });

  final List<String> segments;
  final String currentPath;
  final _ArchiveSource source;
  final ArchiveIntegrationsState integrations;
  final ValueChanged<_ArchiveSource> onSource;
  final VoidCallback onRoot;
  final void Function(int index) onSegment;

  @override
  Widget build(BuildContext context) {
    final items = <_ArchiveSideItem>[
      _ArchiveSideItem(
        'Archivio',
        Icons.folder_special_outlined,
        () => onSource(_ArchiveSource.local),
        source == _ArchiveSource.local && currentPath.isEmpty,
      ),
      ...List.generate(
        segments.length,
        (index) => _ArchiveSideItem(
          segments[index],
          Icons.folder_outlined,
          () => onSegment(index),
          index == segments.length - 1,
        ),
      ),
    ];
    final cloudItems = <_ArchiveSideItem>[
      if (integrations.googleDriveConnected)
        _ArchiveSideItem(
          'Drive',
          Icons.add_to_drive_outlined,
          () => onSource(_ArchiveSource.googleDrive),
          source == _ArchiveSource.googleDrive && currentPath.isEmpty,
        ),
      if (integrations.dropboxConnected)
        _ArchiveSideItem(
          'Dropbox',
          Icons.cloud_queue_rounded,
          () => onSource(_ArchiveSource.dropbox),
          source == _ArchiveSource.dropbox && currentPath.isEmpty,
        ),
    ];
    return Container(
      width: 230,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF4).withValues(alpha: .72),
        border: Border(
          right: BorderSide(color: Colors.black.withValues(alpha: .08)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferiti',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: GussoniBrand.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in items) _ArchiveSidebarRow(item: item),
          if (cloudItems.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Cloud',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: GussoniBrand.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final item in cloudItems) _ArchiveSidebarRow(item: item),
          ],
          const Spacer(),
          const Text(
            'Archivio Nexora',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveSideItem {
  const _ArchiveSideItem(this.label, this.icon, this.onTap, this.selected);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
}

class _ArchiveSidebarRow extends StatelessWidget {
  const _ArchiveSidebarRow({required this.item});

  final _ArchiveSideItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: item.selected
          ? Colors.white.withValues(alpha: .72)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 18,
                color: item.selected
                    ? GussoniBrand.primary
                    : GussoniBrand.textSecondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: item.selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: item.selected
                        ? GussoniBrand.textPrimary
                        : GussoniBrand.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ArchiveViewSwitcher extends StatelessWidget {
  const _ArchiveViewSwitcher({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final _ArchiveViewMode value;
  final ValueChanged<_ArchiveViewMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final modes = compact
        ? const [_ArchiveViewMode.icons, _ArchiveViewMode.list]
        : _ArchiveViewMode.values;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in modes)
            Tooltip(
              message: switch (mode) {
                _ArchiveViewMode.icons => 'Icone',
                _ArchiveViewMode.list => 'Elenco',
                _ArchiveViewMode.columns => 'Colonne',
              },
              child: InkWell(
                onTap: () => onChanged(mode),
                borderRadius: BorderRadius.circular(11),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 34,
                  height: 32,
                  decoration: BoxDecoration(
                    color: value == mode
                        ? Colors.white.withValues(alpha: .90)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: value == mode
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    switch (mode) {
                      _ArchiveViewMode.icons => Icons.grid_view_rounded,
                      _ArchiveViewMode.list => Icons.view_list_rounded,
                      _ArchiveViewMode.columns => Icons.view_column_rounded,
                    },
                    size: 18,
                    color: value == mode
                        ? GussoniBrand.textPrimary
                        : GussoniBrand.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchiveBreadcrumbs extends StatelessWidget {
  const _ArchiveBreadcrumbs({
    required this.segments,
    required this.rootLabel,
    required this.onRoot,
    required this.onSegment,
  });

  final List<String> segments;
  final String rootLabel;
  final VoidCallback onRoot;
  final void Function(int index) onSegment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ActionChip(
            label: Text(rootLabel),
            avatar: const Icon(Icons.home_rounded, size: 15),
            onPressed: onRoot,
          ),
          for (var i = 0; i < segments.length; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: GussoniBrand.textMuted,
              ),
            ),
            ActionChip(label: Text(segments[i]), onPressed: () => onSegment(i)),
          ],
        ],
      ),
    );
  }
}

class _ArchiveStatusBar extends StatelessWidget {
  const _ArchiveStatusBar({
    required this.count,
    required this.folders,
    required this.files,
  });

  final int count;
  final int folders;
  final int files;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: GussoniBrand.glassSurfaceStrong.withValues(alpha: .72),
      border: Border(
        top: BorderSide(color: GussoniBrand.border.withValues(alpha: .92)),
      ),
    ),
    child: Text(
      '$count elementi, $folders cartelle, $files file',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: GussoniBrand.textMuted,
      ),
    ),
  );
}

class _ArchiveListHeader extends StatelessWidget {
  const _ArchiveListHeader();

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.fromLTRB(24, 0, 56, 0),
    decoration: BoxDecoration(
      color: GussoniBrand.glassSurface.withValues(alpha: .52),
      border: Border(
        bottom: BorderSide(color: GussoniBrand.border.withValues(alpha: .92)),
      ),
    ),
    child: const Row(
      children: [
        Expanded(flex: 7, child: _ArchiveHeaderText('Nome')),
        Expanded(flex: 2, child: _ArchiveHeaderText('Dimensioni')),
        Expanded(flex: 2, child: _ArchiveHeaderText('Tipo')),
        Expanded(flex: 2, child: _ArchiveHeaderText('Data')),
      ],
    ),
  );
}

class _ArchiveHeaderText extends StatelessWidget {
  const _ArchiveHeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w900,
      color: GussoniBrand.textMuted,
    ),
  );
}

class _ArchiveListRow extends StatelessWidget {
  const _ArchiveListRow({
    required this.entry,
    required this.icon,
    required this.accentColor,
    required this.meta,
    required this.type,
    required this.modified,
    required this.onOpen,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final ArchiveEntry entry;
  final IconData icon;
  final Color accentColor;
  final String meta;
  final String type;
  final String modified;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(compact ? 18 : 10),
              child: Ink(
                height: compact ? null : 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 18 : 10),
                  color: Colors.white.withValues(alpha: compact ? .58 : .42),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: compact ? .72 : .20),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 10,
                    compact ? 11 : 0,
                    compact ? 6 : 4,
                    compact ? 11 : 0,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: compact ? 40 : 26,
                        height: compact ? 40 : 26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(compact ? 13 : 8),
                          color: accentColor.withValues(alpha: .13),
                        ),
                        child: Icon(
                          icon,
                          size: compact ? 22 : 16,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: compact ? 1 : 7,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.name,
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 14 : 13,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: GussoniBrand.textPrimary,
                              ),
                            ),
                            if (compact) ...[
                              const SizedBox(height: 4),
                              Text(
                                '$type • $meta',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: GussoniBrand.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!compact) ...[
                        Expanded(flex: 2, child: _ArchiveCellText(meta)),
                        Expanded(flex: 2, child: _ArchiveCellText(type)),
                        Expanded(flex: 2, child: _ArchiveCellText(modified)),
                      ],
                      PopupMenuButton<_ArchiveAction>(
                        tooltip: 'Azioni',
                        icon: const Icon(Icons.more_horiz_rounded, size: 18),
                        onSelected: (action) => _selectAction(action),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _ArchiveAction.rename,
                            child: Text('Rinomina'),
                          ),
                          PopupMenuItem(
                            value: _ArchiveAction.move,
                            child: Text('Sposta'),
                          ),
                          PopupMenuItem(
                            value: _ArchiveAction.share,
                            child: Text('Condividi link'),
                          ),
                          PopupMenuItem(
                            value: _ArchiveAction.delete,
                            child: Text('Elimina'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectAction(_ArchiveAction action) {
    switch (action) {
      case _ArchiveAction.rename:
        onRename();
        break;
      case _ArchiveAction.move:
        onMove();
        break;
      case _ArchiveAction.share:
        onShare();
        break;
      case _ArchiveAction.delete:
        onDelete();
        break;
    }
  }
}

class _ArchiveCellText extends StatelessWidget {
  const _ArchiveCellText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: GussoniBrand.textMuted,
    ),
  );
}

class _ArchiveColumnsView extends StatelessWidget {
  const _ArchiveColumnsView({
    required this.segments,
    required this.entries,
    required this.entryIcon,
    required this.entryAccent,
    required this.meta,
    required this.onRoot,
    required this.onSegment,
    required this.onOpen,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final List<String> segments;
  final List<ArchiveEntry> entries;
  final IconData Function(ArchiveEntry entry) entryIcon;
  final Color Function(ArchiveEntry entry) entryAccent;
  final String Function(ArchiveEntry entry) meta;
  final VoidCallback onRoot;
  final ValueChanged<int> onSegment;
  final ValueChanged<ArchiveEntry> onOpen;
  final ValueChanged<ArchiveEntry> onRename;
  final ValueChanged<ArchiveEntry> onMove;
  final ValueChanged<ArchiveEntry> onShare;
  final ValueChanged<ArchiveEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final folders = entries.where((entry) => entry.isDirectory).length;
    final files = entries.length - folders;
    return Row(
      children: [
        SizedBox(
          width: 230,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _ArchiveColumnPathItem(
                label: 'Clienti',
                icon: Icons.home_rounded,
                selected: segments.isEmpty,
                onTap: onRoot,
              ),
              for (var i = 0; i < segments.length; i++)
                _ArchiveColumnPathItem(
                  label: segments[i],
                  icon: Icons.folder_rounded,
                  selected: i == segments.length - 1,
                  onTap: i == segments.length - 1 ? null : () => onSegment(i),
                ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: Colors.black.withValues(alpha: .07)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _ArchiveColumnEntry(
                entry: entry,
                icon: entryIcon(entry),
                accentColor: entryAccent(entry),
                meta: entry.isDirectory ? 'Cartella' : meta(entry),
                onOpen: () => onOpen(entry),
                onRename: () => onRename(entry),
                onMove: () => onMove(entry),
                onShare: () => onShare(entry),
                onDelete: () => onDelete(entry),
              );
            },
          ),
        ),
        VerticalDivider(width: 1, color: Colors.black.withValues(alpha: .07)),
        Container(
          width: 260,
          padding: const EdgeInsets.all(18),
          color: Colors.white.withValues(alpha: .28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      GussoniBrand.primary.withValues(alpha: .18),
                      Colors.white.withValues(alpha: .62),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .72),
                  ),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: GussoniBrand.primary,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                segments.isEmpty ? 'Archivio clienti' : segments.last,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$folders cartelle, $files file',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Vista a colonne per navigare velocemente tra cartelle e documenti, mantenendo sempre il contesto della posizione corrente.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: GussoniBrand.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArchiveColumnPathItem extends StatelessWidget {
  const _ArchiveColumnPathItem({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: selected
          ? GussoniBrand.glassSurfaceStrong.withValues(alpha: .82)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? GussoniBrand.primary : GussoniBrand.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected
                        ? GussoniBrand.textPrimary
                        : GussoniBrand.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ArchiveColumnEntry extends StatelessWidget {
  const _ArchiveColumnEntry({
    required this.entry,
    required this.icon,
    required this.accentColor,
    required this.meta,
    required this.onOpen,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final ArchiveEntry entry;
  final IconData icon;
  final Color accentColor;
  final String meta;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Material(
      color: Colors.white.withValues(alpha: .44),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
          child: Row(
            children: [
              Icon(icon, size: 19, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _ArchiveActionsButton(
                onRename: onRename,
                onMove: onMove,
                onShare: onShare,
                onDelete: onDelete,
              ),
              if (entry.isDirectory)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: GussoniBrand.textMuted,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ArchiveActionsButton extends StatelessWidget {
  const _ArchiveActionsButton({
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_ArchiveAction>(
    tooltip: 'Azioni',
    icon: const Icon(Icons.more_horiz_rounded, size: 18),
    onSelected: (action) {
      switch (action) {
        case _ArchiveAction.rename:
          onRename();
          break;
        case _ArchiveAction.move:
          onMove();
          break;
        case _ArchiveAction.share:
          onShare();
          break;
        case _ArchiveAction.delete:
          onDelete();
          break;
      }
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: _ArchiveAction.rename, child: Text('Rinomina')),
      PopupMenuItem(value: _ArchiveAction.move, child: Text('Sposta')),
      PopupMenuItem(value: _ArchiveAction.share, child: Text('Condividi link')),
      PopupMenuItem(value: _ArchiveAction.delete, child: Text('Elimina')),
    ],
  );
}

enum _ArchiveAction { rename, move, share, delete }

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.entry,
    required this.subtitle,
    required this.extensionBadge,
    required this.icon,
    required this.accentColor,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
    this.onOpen,
  });

  final ArchiveEntry entry;
  final String subtitle;
  final String extensionBadge;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final canOpen = onOpen != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GussoniBrand.border),
            color: Colors.white,
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ArchiveVisual(
                        icon: icon,
                        accentColor: accentColor,
                        extensionBadge: extensionBadge,
                        isDirectory: entry.isDirectory,
                      ),
                    ),
                    PopupMenuButton<_ArchiveAction>(
                      tooltip: 'Azioni',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      onSelected: (action) {
                        switch (action) {
                          case _ArchiveAction.rename:
                            onRename();
                            break;
                          case _ArchiveAction.move:
                            onMove();
                            break;
                          case _ArchiveAction.share:
                            onShare();
                            break;
                          case _ArchiveAction.delete:
                            onDelete();
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _ArchiveAction.rename,
                          child: Text('Rinomina'),
                        ),
                        PopupMenuItem(
                          value: _ArchiveAction.move,
                          child: Text('Sposta'),
                        ),
                        PopupMenuItem(
                          value: _ArchiveAction.share,
                          child: Text('Condividi link'),
                        ),
                        PopupMenuItem(
                          value: _ArchiveAction.delete,
                          child: Text('Elimina'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.isEmpty ? (canOpen ? 'Cartella' : 'File') : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: GussoniBrand.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveVisual extends StatelessWidget {
  const _ArchiveVisual({
    required this.icon,
    required this.accentColor,
    required this.extensionBadge,
    required this.isDirectory,
  });

  final IconData icon;
  final Color accentColor;
  final String extensionBadge;
  final bool isDirectory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Stack(
        children: [
          Positioned(
            left: 2,
            top: 4,
            child: Container(
              width: 54,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentColor.withValues(alpha: isDirectory ? 0.22 : 0.16),
                    GussoniBrand.surfaceSubtle,
                  ],
                ),
                border: Border.all(color: accentColor.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, size: 26, color: accentColor),
            ),
          ),
          if (extensionBadge.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: GussoniBrand.primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: GussoniBrand.primaryBorder),
                ),
                child: Text(
                  extensionBadge,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchiveLoadErrorBanner extends StatelessWidget {
  const _ArchiveLoadErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GussoniBrand.warningBg.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GussoniBrand.warningBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: GussoniBrand.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Riprova'),
          ),
        ],
      ),
    );
  }
}
