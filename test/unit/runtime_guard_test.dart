import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/core/runtime/runtime_guard.dart';

void main() {
  test('guardFirestoreId rejects invalid id', () {
    final value = RuntimeGuard.guardFirestoreId(
      'a/b',
      field: 'teamId',
      route: '/teams/:teamId',
    );
    expect(value, isNull);
  });

  test('validateSetlistOrder accepts sequential order', () {
    final result = RuntimeGuard.validateSetlistOrder(<Map<String, dynamic>>[
      <String, dynamic>{'order': 1},
      <String, dynamic>{'order': 2},
      <String, dynamic>{'order': 3},
    ]);
    expect(result.isValid, isTrue);
    expect(result.missingOrders, isEmpty);
    expect(result.duplicateOrders, isEmpty);
    expect(result.invalidOrderCount, 0);
  });

  test('validateSetlistOrder detects missing/duplicate order', () {
    final result = RuntimeGuard.validateSetlistOrder(<Map<String, dynamic>>[
      <String, dynamic>{'order': 1},
      <String, dynamic>{'order': 1},
      <String, dynamic>{'order': 4},
    ]);
    expect(result.isValid, isFalse);
    expect(result.missingOrders, containsAll(<int>[2, 3]));
    expect(result.duplicateOrders, contains(1));
  });

  test('validateLiveCueState returns clear when setlist empty', () {
    final result = RuntimeGuard.validateLiveCueState(
      cueData: <String, dynamic>{'currentSongId': 'song-1'},
      setlistLength: 0,
      resolvedCurrentIndex: -1,
    );
    expect(result.shouldClearState, isTrue);
    expect(result.requiresFallback, isTrue);
  });

  test(
    'validateLiveCueState falls back to first item for invalid current index',
    () {
      final result = RuntimeGuard.validateLiveCueState(
        cueData: <String, dynamic>{
          'currentSongId': 'song-1',
          'nextSongId': 'song-2',
        },
        setlistLength: 3,
        resolvedCurrentIndex: 99,
      );
      expect(result.currentIndexInRange, isFalse);
      expect(result.fallbackCurrentIndex, 0);
      expect(result.fallbackNextIndex, 1);
    },
  );

  test('guardHostViewerInitPayload rejects missing required fields', () {
    final valid = RuntimeGuard.guardHostViewerInitPayload(<String, Object?>{
      'teamId': 'team-1',
      'projectId': '',
      'scoreImageUrl': 'https://example.com/score.png',
      'idToken': '',
    });
    expect(valid, isFalse);
  });
}
