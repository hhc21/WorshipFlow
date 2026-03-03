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
}
