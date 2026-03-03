import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/browser_types.dart';
import 'package:worshipflow/utils/storage_helpers.dart';

void main() {
  group('resolveSongAssetContentType', () {
    test('accepts explicit supported content type', () {
      final resolved = resolveSongAssetContentType(
        fileName: 'score.pdf',
        rawContentType: 'application/pdf',
      );
      expect(resolved, 'application/pdf');
    });

    test('infers jpeg from extension', () {
      final resolved = resolveSongAssetContentType(
        fileName: 'score.JPG',
        rawContentType: null,
      );
      expect(resolved, 'image/jpeg');
    });

    test('rejects unsupported type', () {
      final resolved = resolveSongAssetContentType(
        fileName: 'score.txt',
        rawContentType: null,
      );
      expect(resolved, isNull);
    });
  });

  group('validateSongAssetSelection', () {
    const validType = 'image/png';
    final goodSelection = BrowserFileSelection(
      name: 'test.png',
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: validType,
      sizeBytes: 3,
    );

    test('returns null for valid selection', () {
      final error = validateSongAssetSelection(
        picked: goodSelection,
        resolvedContentType: validType,
      );
      expect(error, isNull);
    });

    test('rejects oversize file', () {
      final largeSelection = BrowserFileSelection(
        name: 'large.png',
        bytes: Uint8List.fromList([1]),
        contentType: validType,
        sizeBytes: kMaxSongAssetBytes + 1,
      );
      final error = validateSongAssetSelection(
        picked: largeSelection,
        resolvedContentType: validType,
      );
      expect(error, contains('25MB'));
    });

    test('rejects unsupported content type', () {
      final error = validateSongAssetSelection(
        picked: goodSelection,
        resolvedContentType: null,
      );
      expect(error, contains('지원되지 않는 파일 형식'));
    });
  });
}
