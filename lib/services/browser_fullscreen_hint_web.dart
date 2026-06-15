// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

bool shouldSuggestBrowserFullscreen({
  required double viewportWidth,
  required double viewportHeight,
}) {
  final screen = html.window.screen;
  final screenWidth = screen?.width?.toDouble();
  final screenHeight = screen?.height?.toDouble();
  if (screenWidth == null || screenHeight == null) {
    return false;
  }
  final widthGap = screenWidth - viewportWidth;
  final heightGap = screenHeight - viewportHeight;
  return widthGap > 100 || heightGap > 120;
}

Future<void> requestBrowserFullscreen() async {
  final element = html.document.documentElement;
  if (element == null) return;
  try {
    await element.requestFullscreen();
  } catch (_) {}
}
