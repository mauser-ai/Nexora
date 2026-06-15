// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String? aiLocalStorageGet(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void aiLocalStorageSet(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {}
}

void aiDownloadCsv(String content, String filename) {
  try {
    final bytes = html.Blob([content], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(bytes);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}
