import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand_config.dart';
import '../services/archive_service.dart';
import 'archive_iframe_preview_stub.dart'
    if (dart.library.html) 'archive_iframe_preview_web.dart';

class ArchiveFilePreviewDialog extends StatefulWidget {
  const ArchiveFilePreviewDialog({
    super.key,
    required this.entry,
    required this.urlFuture,
  });

  final ArchiveEntry entry;
  final Future<String> urlFuture;

  @override
  State<ArchiveFilePreviewDialog> createState() =>
      _ArchiveFilePreviewDialogState();
}

class _ArchiveFilePreviewDialogState extends State<ArchiveFilePreviewDialog> {
  String? _url;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.urlFuture.then((url) {
      if (mounted) setState(() => _url = url);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  String get _ext {
    final name = widget.entry.name;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot >= name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get _isImage => const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg']
      .contains(_ext);
  bool get _isPdf => _ext == 'pdf';
  bool get _isOffice => const ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv']
      .contains(_ext);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF2F8FF).withValues(alpha: .97),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .72)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x28000000),
                blurRadius: 48,
                offset: Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildTitleBar(context),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: .07)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: GussoniBrand.primary.withValues(alpha: .10),
            ),
            child: Icon(
              Icons.visibility_outlined,
              size: 17,
              color: GussoniBrand.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GussoniBrand.textPrimary,
              ),
            ),
          ),
          if (_url != null) ...[
            Tooltip(
              message: 'Apri in nuova scheda',
              child: IconButton(
                onPressed: () => launchUrl(
                  Uri.parse(_url!),
                  webOnlyWindowName: '_blank',
                ),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: GussoniBrand.textSecondary,
                ),
              ),
            ),
          ],
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: GussoniBrand.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: GussoniBrand.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Impossibile caricare il file.',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_url == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isImage) {
      return _ImagePreview(url: _url!);
    }

    if (_isPdf) {
      return archiveIframePreview(_url!);
    }

    if (_isOffice) {
      final viewerUrl =
          'https://docs.google.com/viewer?url=${Uri.encodeComponent(_url!)}&embedded=true';
      return archiveIframePreview(viewerUrl);
    }

    return _UnsupportedPreview(url: _url!, ext: _ext.toUpperCase());
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    child: Center(
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, _) => const Center(
          child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.black26),
        ),
      ),
    ),
  );
}

class _UnsupportedPreview extends StatelessWidget {
  const _UnsupportedPreview({required this.url, required this.ext});
  final String url;
  final String ext;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: GussoniBrand.primary.withValues(alpha: .08),
            ),
            child: Icon(
              Icons.insert_drive_file_rounded,
              size: 40,
              color: GussoniBrand.primary,
            ),
          ),
          const SizedBox(height: 16),
          if (ext.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: GussoniBrand.primary,
              ),
              child: Text(
                ext,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          const Text(
            'Anteprima non disponibile per questo tipo di file.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(url),
              webOnlyWindowName: '_blank',
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Scarica file'),
          ),
        ],
      ),
    ),
  );
}
