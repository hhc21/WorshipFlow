import 'dart:typed_data';

class BrowserFileSelection {
  final String name;
  final Uint8List bytes;
  final String? contentType;
  final int sizeBytes;

  const BrowserFileSelection({
    required this.name,
    required this.bytes,
    required this.contentType,
    required this.sizeBytes,
  });
}

abstract class BrowserPopupHandle {
  void navigate(String url);

  void close();
}
