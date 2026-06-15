import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget archiveIframePreview(String url) => _StubPreview(url: url);

class _StubPreview extends StatelessWidget {
  const _StubPreview({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.open_in_new_rounded, size: 48, color: Colors.black38),
        const SizedBox(height: 16),
        const Text('Anteprima disponibile solo su web.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Apri'),
        ),
      ],
    ),
  );
}
