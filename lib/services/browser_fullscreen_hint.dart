import 'browser_fullscreen_hint_stub.dart'
    if (dart.library.html) 'browser_fullscreen_hint_web.dart' as impl;

bool shouldSuggestBrowserFullscreen({
  required double viewportWidth,
  required double viewportHeight,
}) => impl.shouldSuggestBrowserFullscreen(
  viewportWidth: viewportWidth,
  viewportHeight: viewportHeight,
);

Future<void> requestBrowserFullscreen() => impl.requestBrowserFullscreen();
