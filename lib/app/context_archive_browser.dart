import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand_config.dart';
import '../services/archive_service.dart';
import '../services/web_file_picker.dart';

enum ContextArchiveBrowserMode { grid, list }

class ContextArchiveBrowser extends StatefulWidget {
  const ContextArchiveBrowser({
    super.key,
    required this.rootPath,
    required this.rootLabel,
    required this.title,
    this.mode = ContextArchiveBrowserMode.grid,
    this.showHeader = true,
    this.emptyLabel,
  });

  final String rootPath;
  final String rootLabel;
  final String title;
  final ContextArchiveBrowserMode mode;
  final bool showHeader;
  final String? emptyLabel;

  @override
  State<ContextArchiveBrowser> createState() => _ContextArchiveBrowserState();
}

class _ContextArchiveBrowserState extends State<ContextArchiveBrowser> {
  final ArchiveService _service = ArchiveService();

  bool _loading = false;
  String? _error;
  late String _currentPath;
  List<ArchiveEntry> _folders = const [];
  List<ArchiveEntry> _files = const [];
  String? _downloadToken;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.rootPath;
    _load();
    _prepareDownloadToken();
  }

  Future<void> _prepareDownloadToken() async {
    try {
      final session = await _service.createShareSession(
        path: widget.rootPath,
        isDirectory: true,
      );
      if (!mounted) {
        return;
      }
      setState(() => _downloadToken = session.token);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _service.list(_currentPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _folders = response.folders;
        _files = response.files;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<String> get _relativeSegments {
    final current = _currentPath.trim();
    final root = widget.rootPath.trim();
    if (current == root || !current.startsWith(root)) {
      return const [];
    }
    final relative = current
        .substring(root.length)
        .replaceFirst(RegExp(r'^/'), '');
    if (relative.isEmpty) {
      return const [];
    }
    return relative
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
  }

  String _relativePathUntil(int indexInclusive) {
    if (indexInclusive < 0) {
      return widget.rootPath;
    }
    return '${widget.rootPath}/${_relativeSegments.take(indexInclusive + 1).join('/')}';
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuova cartella'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome cartella',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) {
      return;
    }
    try {
      await _service.createFolder(path: _currentPath, name: name);
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
        payload.addAll(await pickFilesForWeb());
      } else {
        final picked = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: false,
        );
        if (picked == null) {
          return;
        }
        for (final file in picked.xFiles) {
          final name = file.name.trim();
          if (name.isEmpty) {
            continue;
          }
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) {
            continue;
          }
          payload.add((name: name, bytes: bytes));
        }
      }
      if (payload.isEmpty) {
        return;
      }
      setState(() => _loading = true);
      for (final file in payload) {
        await _service.uploadFile(
          path: _currentPath,
          fileName: file.name,
          bytes: file.bytes,
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

  Future<void> _downloadFile(ArchiveEntry entry) async {
    try {
      final token = _downloadToken;
      if (token == null || token.isEmpty) {
        await _prepareDownloadToken();
      }
      final resolvedToken = _downloadToken;
      if (resolvedToken == null || resolvedToken.isEmpty) {
        throw StateError('Token download non disponibile.');
      }
      final url = _service.buildDownloadUrl(
        token: resolvedToken,
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
        const SnackBar(
          content: Text('Impossibile aprire il download del file.'),
        ),
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

  @override
  Widget build(BuildContext context) {
    final entries = [..._folders, ..._files];
    return Container(
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GussoniBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildError()
                : entries.isEmpty
                ? _buildEmpty()
                : widget.mode == ContextArchiveBrowserMode.grid
                ? _buildGrid(entries)
                : _buildList(entries),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('Nuova cartella'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading ? null : _pickAndUploadFiles,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Carica'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                label: Text(widget.rootLabel),
                onPressed: () {
                  setState(() => _currentPath = widget.rootPath);
                  _load();
                },
              ),
              ...List.generate(_relativeSegments.length, (index) {
                final label = _relativeSegments[index];
                return ActionChip(
                  label: Text(label),
                  onPressed: () {
                    setState(() => _currentPath = _relativePathUntil(index));
                    _load();
                  },
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_off_outlined,
              size: 28,
              color: GussoniBrand.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Errore archivio',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: GussoniBrand.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.emptyLabel ?? 'Nessun file o cartella presente.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
        ),
      ),
    );
  }

  Widget _buildGrid(List<ArchiveEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 144,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _ContextArchiveGridTile(
              entry: entry,
              icon: _entryIcon(entry),
              accentColor: _entryAccent(entry),
              extensionBadge: _fileExtension(entry.name),
              subtitle: entry.isDirectory ? 'Cartella' : _formatFileMeta(entry),
              onTap: () {
                if (entry.isDirectory) {
                  setState(() => _currentPath = entry.path);
                  _load();
                } else {
                  _downloadFile(entry);
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildList(List<ArchiveEntry> entries) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _entryAccent(entry).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _entryIcon(entry),
              color: _entryAccent(entry),
              size: 18,
            ),
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textPrimary,
            ),
          ),
          subtitle: Text(
            entry.isDirectory ? 'Cartella' : _formatFileMeta(entry),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: GussoniBrand.textMuted,
            ),
          ),
          trailing: entry.isDirectory
              ? const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: GussoniBrand.textMuted,
                )
              : (_fileExtension(entry.name).isEmpty
                    ? const Icon(
                        Icons.download_outlined,
                        size: 18,
                        color: GussoniBrand.textMuted,
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: GussoniBrand.primaryBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: GussoniBrand.primaryBorder),
                        ),
                        child: Text(
                          _fileExtension(entry.name),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: GussoniBrand.primary,
                          ),
                        ),
                      )),
          onTap: () {
            if (entry.isDirectory) {
              setState(() => _currentPath = entry.path);
              _load();
            } else {
              _downloadFile(entry);
            }
          },
        );
      },
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

class _ContextArchiveGridTile extends StatelessWidget {
  const _ContextArchiveGridTile({
    required this.entry,
    required this.icon,
    required this.accentColor,
    required this.extensionBadge,
    required this.subtitle,
    required this.onTap,
  });

  final ArchiveEntry entry;
  final IconData icon;
  final Color accentColor;
  final String extensionBadge;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GussoniBrand.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 56,
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
                                accentColor.withValues(
                                  alpha: entry.isDirectory ? 0.22 : 0.16,
                                ),
                                GussoniBrand.surfaceSubtle,
                              ],
                            ),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Icon(icon, size: 26, color: accentColor),
                        ),
                      ),
                      if (extensionBadge.isNotEmpty)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: GussoniBrand.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              extensionBadge,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
                  subtitle,
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
