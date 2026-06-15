// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget archiveIframePreview(String url) => _IframePreview(url: url);

class _IframePreview extends StatefulWidget {
  const _IframePreview({required this.url});
  final String url;

  @override
  State<_IframePreview> createState() => _IframePreviewState();
}

class _IframePreviewState extends State<_IframePreview> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'archive-iframe-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      return html.IFrameElement()
        ..src = widget.url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..allow = 'fullscreen';
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewId);
}
