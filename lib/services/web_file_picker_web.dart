import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;

typedef PickedUploadFile = ({String name, Uint8List bytes});

Future<List<PickedUploadFile>> pickFilesForWeb() async {
  final completer = Completer<List<PickedUploadFile>>();
  final input = html.FileUploadInputElement()..multiple = true;
  input.style.display = 'none';
  html.document.body?.append(input);

  void finish(List<PickedUploadFile> files) {
    input.remove();
    if (!completer.isCompleted) {
      completer.complete(files);
    }
  }

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      finish(const []);
      return;
    }
    final result = <PickedUploadFile>[];
    var pending = files.length;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) {
        try {
          final data = reader.result;
          if (data is ByteBuffer) {
            result.add((name: file.name, bytes: data.asUint8List()));
          } else if (data is Uint8List) {
            result.add((name: file.name, bytes: data));
          }
        } catch (_) {
          // Ignora singolo file non leggibile.
        } finally {
          pending -= 1;
          if (pending <= 0) {
            finish(result);
          }
        }
      });
      reader.onError.listen((_) {
        pending -= 1;
        if (pending <= 0) {
          finish(result);
        }
      });
      reader.readAsArrayBuffer(file);
    }
  });
  input.click();

  return completer.future.timeout(
    const Duration(seconds: 60),
    onTimeout: () {
      input.remove();
      return const [];
    },
  );
}
