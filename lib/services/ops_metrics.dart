import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> logTeamOpsMetric({
  required FirebaseFirestore firestore,
  required String teamId,
  required String category,
  required String action,
  required String status,
  String? code,
  int? retryCount,
  int? skippedCount,
  int? failedCount,
  Map<String, Object?> extra = const <String, Object?>{},
}) async {
  if (teamId.trim().isEmpty) return;
  try {
    await firestore
        .collection('teams')
        .doc(teamId)
        .collection('opsMetrics')
        .add({
          'category': category,
          'action': action,
          'status': status,
          if (code != null && code.isNotEmpty) 'code': code,
          if (retryCount != null) 'retryCount': retryCount,
          if (skippedCount != null) 'skippedCount': skippedCount,
          if (failedCount != null) 'failedCount': failedCount,
          if (extra.isNotEmpty) 'extra': extra,
          'createdAt': FieldValue.serverTimestamp(),
        });
  } on FirebaseException {
    // Metrics are best-effort and should never break user flows.
  }
}

Future<void> logLegacyFallbackUsage({
  required FirebaseFirestore firestore,
  required String teamId,
  required String path,
  String? detail,
}) {
  return logTeamOpsMetric(
    firestore: firestore,
    teamId: teamId,
    category: 'legacy_fallback',
    action: path,
    status: 'used',
    extra: <String, Object?>{
      if (detail != null && detail.isNotEmpty) 'detail': detail,
    },
  );
}
