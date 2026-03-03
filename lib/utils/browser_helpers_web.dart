// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'browser_types.dart';

class _WebPopupHandle implements BrowserPopupHandle {
  final html.WindowBase _window;

  const _WebPopupHandle(this._window);

  @override
  void navigate(String url) {
    _window.location.href = url;
  }

  @override
  void close() {
    _window.close();
  }
}

Future<bool> copyTextInBrowser(String text) async {
  try {
    final clipboard = html.window.navigator.clipboard;
    if (clipboard != null) {
      await clipboard.writeText(text);
      return true;
    }
  } catch (_) {}

  try {
    final textArea = html.TextAreaElement()
      ..value = text
      ..style.position = 'fixed'
      ..style.left = '-9999px'
      ..style.top = '-9999px'
      ..style.opacity = '0';
    html.document.body?.append(textArea);
    textArea.focus();
    textArea.select();
    final copied = html.document.execCommand('copy');
    textArea.remove();
    return copied;
  } catch (_) {
    return false;
  }
}

Future<bool> shareTextLinkInBrowser({
  required String title,
  required String text,
  required String url,
}) async {
  try {
    final navigator = html.window.navigator;
    final data = <String, String>{'title': title, 'text': text, 'url': url};
    // ignore: avoid_dynamic_calls
    await (navigator as dynamic).share(data);
    return true;
  } catch (_) {
    return false;
  }
}

Future<BrowserFileSelection?> pickFileForUpload({
  required String accept,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final input = html.FileUploadInputElement()..accept = accept;
  input.click();
  try {
    await input.onChange.first.timeout(timeout);
  } on TimeoutException {
    return null;
  }

  final file = input.files?.first;
  if (file == null) return null;

  final reader = html.FileReader();
  final completer = Completer<Uint8List>();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
      return;
    }
    if (result is Uint8List) {
      completer.complete(result);
      return;
    }
    completer.completeError(StateError('파일을 읽지 못했습니다.'));
  });
  reader.onError.listen((_) {
    completer.completeError(StateError('파일 읽기 오류가 발생했습니다.'));
  });
  reader.readAsArrayBuffer(file);

  final bytes = await completer.future;
  final contentType = file.type.trim().isEmpty ? null : file.type;
  return BrowserFileSelection(
    name: file.name,
    bytes: bytes,
    contentType: contentType,
    sizeBytes: file.size,
  );
}

bool openUrlInNewTab(String url) {
  try {
    html.window.open(url, '_blank');
    return true;
  } catch (_) {
    return false;
  }
}

bool downloadUrlInBrowser(String url, {String? fileName}) {
  try {
    final anchor = html.AnchorElement(href: url)
      ..style.display = 'none'
      ..rel = 'noopener';
    final normalizedFileName = fileName?.trim();
    if (normalizedFileName != null && normalizedFileName.isNotEmpty) {
      anchor.download = normalizedFileName;
    }
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}

BrowserPopupHandle? openBlankPopupWindow() {
  try {
    return _WebPopupHandle(html.window.open('', '_blank'));
  } catch (_) {
    return null;
  }
}
