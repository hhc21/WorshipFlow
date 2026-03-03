import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/song_parser.dart';

void main() {
  group('parseSongInput', () {
    test('parses leading key format', () {
      final parsed = parseSongInput('D 주의 집에 거하는 자');
      expect(parsed.title, '주의 집에 거하는 자');
      expect(parsed.keyText, 'D');
    });

    test('parses trailing key format', () {
      final parsed = parseSongInput('주의 집에 거하는 자 D');
      expect(parsed.title, '주의 집에 거하는 자');
      expect(parsed.keyText, 'D');
    });

    test('normalizes compound key', () {
      final parsed = parseSongInput('g - a 예수는 나의 힘이요');
      expect(parsed.title, '예수는 나의 힘이요');
      expect(parsed.keyText, 'G-A');
    });
  });

  group('filename key extraction', () {
    test('extracts leading key from filename', () {
      expect(extractKeyFromFilename('[Db 당신의 날에].pdf'), 'Db');
    });

    test('extracts trailing key from filename', () {
      expect(extractKeyFromFilename('당신의 날에 C#.jpg'), 'C#');
    });

    test('returns null when key missing', () {
      expect(extractKeyFromFilename('당신의 날에 악보.pdf'), isNull);
    });
  });

  group('asset key matching', () {
    test('matches canonical equivalent keys', () {
      final asset = <String, dynamic>{'fileName': 'Db 당신의 날에.pdf'};
      expect(isAssetKeyMatch(asset, 'C#'), isTrue);
    });

    test('returns false when key differs', () {
      final asset = <String, dynamic>{'fileName': 'D 당신의 날에.pdf'};
      expect(isAssetKeyMatch(asset, 'A'), isFalse);
    });
  });
}
