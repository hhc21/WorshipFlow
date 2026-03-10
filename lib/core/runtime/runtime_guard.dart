import 'package:cloud_firestore/cloud_firestore.dart';

import '../ops/ops_metrics.dart';
import '../firestore_id.dart';

class SetlistOrderValidation {
  final bool isValid;
  final List<int> missingOrders;
  final List<int> duplicateOrders;
  final int invalidOrderCount;

  const SetlistOrderValidation({
    required this.isValid,
    required this.missingOrders,
    required this.duplicateOrders,
    required this.invalidOrderCount,
  });
}

class LiveCueStateValidation {
  final bool shouldClearState;
  final bool hasCurrent;
  final bool hasNext;
  final bool currentIndexInRange;
  final bool nextIndexInRange;
  final int fallbackCurrentIndex;
  final int fallbackNextIndex;

  const LiveCueStateValidation({
    required this.shouldClearState,
    required this.hasCurrent,
    required this.hasNext,
    required this.currentIndexInRange,
    required this.nextIndexInRange,
    required this.fallbackCurrentIndex,
    required this.fallbackNextIndex,
  });

  bool get requiresFallback =>
      shouldClearState || !currentIndexInRange || !hasCurrent;
}

class RuntimeGuard {
  static String? guardFirestoreId(
    String? rawValue, {
    required String field,
    required String route,
    Map<String, Object?> fields = const {},
  }) {
    final value = (rawValue ?? '').trim();
    if (!isValidFirestoreDocId(value)) {
      OpsMetrics.routerInvalidId(
        fields: <String, Object?>{
          'field': field,
          'route': route,
          'raw': rawValue,
          ...fields,
        },
      );
      OpsMetrics.runtimeGuardTriggered(
        guard: 'invalid_firestore_id',
        fields: <String, Object?>{'field': field, 'route': route, ...fields},
      );
      return null;
    }
    return value;
  }

  static SetlistOrderValidation validateSetlistOrder(
    Iterable<Map<String, dynamic>> items,
  ) {
    final list = items.toList(growable: false);
    final expectedMax = list.length;
    final counts = <int, int>{};
    var invalidCount = 0;

    for (final item in list) {
      final rawOrder = item['order'];
      int? parsed;
      if (rawOrder is num) {
        parsed = rawOrder.toInt();
      } else {
        parsed = int.tryParse(rawOrder?.toString() ?? '');
      }
      if (parsed == null || parsed <= 0) {
        invalidCount += 1;
        continue;
      }
      counts[parsed] = (counts[parsed] ?? 0) + 1;
    }

    final missing = <int>[];
    final duplicates = <int>[];
    for (var i = 1; i <= expectedMax; i++) {
      final count = counts[i] ?? 0;
      if (count == 0) {
        missing.add(i);
      } else if (count > 1) {
        duplicates.add(i);
      }
    }

    final outOfRange = counts.keys.any((order) => order > expectedMax);
    final isValid =
        invalidCount == 0 &&
        missing.isEmpty &&
        duplicates.isEmpty &&
        !outOfRange;

    return SetlistOrderValidation(
      isValid: isValid,
      missingOrders: missing,
      duplicateOrders: duplicates,
      invalidOrderCount: invalidCount,
    );
  }

  static LiveCueStateValidation validateLiveCueState({
    required Map<String, dynamic>? cueData,
    required int setlistLength,
    required int resolvedCurrentIndex,
  }) {
    final data = cueData ?? const <String, dynamic>{};
    final hasCurrent = _hasCueValue(data, 'current');
    final hasNext = _hasCueValue(data, 'next');
    final shouldClearState = setlistLength == 0;

    final currentIndexInRange =
        setlistLength > 0 &&
        resolvedCurrentIndex >= 0 &&
        resolvedCurrentIndex < setlistLength;

    final safeCurrentIndex = currentIndexInRange
        ? resolvedCurrentIndex
        : (setlistLength > 0 ? 0 : -1);
    final tentativeNextIndex = safeCurrentIndex + 1;
    final nextIndexInRange =
        tentativeNextIndex >= 0 && tentativeNextIndex < setlistLength;

    return LiveCueStateValidation(
      shouldClearState: shouldClearState,
      hasCurrent: hasCurrent,
      hasNext: hasNext,
      currentIndexInRange: currentIndexInRange,
      nextIndexInRange: nextIndexInRange,
      fallbackCurrentIndex: safeCurrentIndex,
      fallbackNextIndex: nextIndexInRange ? tentativeNextIndex : -1,
    );
  }

  static bool guardHostViewerInitPayload(
    Map<String, Object?> payload, {
    Map<String, Object?> fields = const {},
  }) {
    bool nonEmptyString(String key) {
      final value = payload[key]?.toString().trim() ?? '';
      return value.isNotEmpty;
    }

    final invalidFields = <String>[];
    const required = <String>[
      'teamId',
      'projectId',
      'scoreImageUrl',
      'idToken',
    ];
    for (final key in required) {
      if (!nonEmptyString(key)) invalidFields.add(key);
    }

    if (invalidFields.isEmpty) return true;

    OpsMetrics.runtimeGuardTriggered(
      guard: 'host_viewer_contract_invalid',
      fields: <String, Object?>{
        'invalidFields': invalidFields.join(','),
        ...fields,
      },
    );
    return false;
  }

  static Map<String, dynamic> snapshotDataOrEmpty(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String path,
    Map<String, Object?> fields = const {},
  }) {
    if (!snapshot.exists) {
      OpsMetrics.firestoreSnapshotError(
        fields: <String, Object?>{
          'path': path,
          'reason': 'not-found',
          ...fields,
        },
      );
      return const <String, dynamic>{};
    }
    final data = snapshot.data();
    if (data == null) {
      OpsMetrics.firestoreSnapshotError(
        fields: <String, Object?>{
          'path': path,
          'reason': 'null-data',
          ...fields,
        },
      );
      return const <String, dynamic>{};
    }
    return data;
  }

  static bool _hasCueValue(Map<String, dynamic> cueData, String prefix) {
    final songId = cueData['${prefix}SongId']?.toString().trim() ?? '';
    final displayTitle =
        cueData['${prefix}DisplayTitle']?.toString().trim() ?? '';
    final freeText = cueData['${prefix}FreeTextTitle']?.toString().trim() ?? '';
    return songId.isNotEmpty || displayTitle.isNotEmpty || freeText.isNotEmpty;
  }
}
