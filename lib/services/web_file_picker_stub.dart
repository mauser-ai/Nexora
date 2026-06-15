import 'dart:typed_data';

typedef PickedUploadFile = ({String name, Uint8List bytes});

Future<List<PickedUploadFile>> pickFilesForWeb() async {
  return const [];
}

