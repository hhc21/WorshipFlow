import 'package:cloud_firestore/cloud_firestore.dart';

int compareProjectDocs(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  final aData = a.data();
  final bData = b.data();
  final aDate = (aData['date']?.toString() ?? a.id).trim();
  final bDate = (bData['date']?.toString() ?? b.id).trim();
  final byDate = bDate.compareTo(aDate);
  if (byDate != 0) return byDate;

  final aCreatedAt = (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch;
  final bCreatedAt = (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch;
  if (aCreatedAt != null && bCreatedAt != null && aCreatedAt != bCreatedAt) {
    return bCreatedAt.compareTo(aCreatedAt);
  }
  return b.id.compareTo(a.id);
}

bool isRetriableCleanupErrorCode(String code) {
  return code == 'aborted' ||
      code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'resource-exhausted';
}

bool isSkippableCleanupErrorCode(String code) {
  return code == 'permission-denied' ||
      code == 'failed-precondition' ||
      code == 'unavailable';
}

String cleanupLabelPreview(
  List<String> skippedCleanupSteps,
  List<String> failedCleanupSteps, {
  int maxItems = 3,
}) {
  final merged = <String>[...skippedCleanupSteps, ...failedCleanupSteps];
  if (merged.isEmpty) return '';
  if (merged.length <= maxItems) return merged.join(', ');
  final preview = merged.take(maxItems).join(', ');
  return '$preview 외 ${merged.length - maxItems}건';
}
