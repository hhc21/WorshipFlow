import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/firestore_id.dart';

void main() {
  group('isValidFirestoreDocId', () {
    test('accepts normal ids', () {
      expect(isValidFirestoreDocId('abc123'), isTrue);
      expect(isValidFirestoreDocId('2026.02.20'), isTrue);
      expect(isValidFirestoreDocId('team_01'), isTrue);
    });

    test('rejects empty and dot ids', () {
      expect(isValidFirestoreDocId(''), isFalse);
      expect(isValidFirestoreDocId('   '), isFalse);
      expect(isValidFirestoreDocId('.'), isFalse);
      expect(isValidFirestoreDocId('..'), isFalse);
    });

    test('rejects slash-containing ids', () {
      expect(isValidFirestoreDocId('abc/123'), isFalse);
    });
  });

  group('private project note doc ids', () {
    test('builds deterministic v2 doc id', () {
      expect(
        privateProjectNoteDocIdV2('2026.03.01', 'user-1'),
        'v2__2026.03.01__user-1',
      );
    });

    test('builds deterministic legacy doc id', () {
      expect(
        privateProjectNoteDocIdLegacy('2026.03.01', 'user-1'),
        '2026.03.01__user-1',
      );
    });
  });
}
