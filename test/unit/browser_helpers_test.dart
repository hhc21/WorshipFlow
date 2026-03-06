import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/browser_helpers.dart';

void main() {
  test('stub helpers return safe defaults in non-web tests', () async {
    expect(await copyTextInBrowser('hello'), isFalse);
    expect(
      await shareTextLinkInBrowser(
        title: 't',
        text: 'x',
        url: 'https://example.com',
      ),
      isFalse,
    );
    expect(await pickFileForUpload(accept: 'image/*'), isNull);
    expect(openUrlInNewTab('https://example.com'), isFalse);
    expect(
      downloadUrlInBrowser('https://example.com/file.png', fileName: 'f.png'),
      isFalse,
    );
    expect(openBlankPopupWindow(), isNull);
  });
}
