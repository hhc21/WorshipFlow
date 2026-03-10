import 'dart:convert';

import 'package:flutter/foundation.dart';

class OpsMetrics {
  static void emit(String metric, {Map<String, Object?> fields = const {}}) {
    final payload = <String, Object?>{
      'metric': metric,
      'ts': DateTime.now().toUtc().toIso8601String(),
      if (fields.isNotEmpty) ...fields,
    };
    debugPrint('[ops] ${jsonEncode(payload)}');
  }

  static void runtimeGuardTriggered({
    required String guard,
    Map<String, Object?> fields = const {},
  }) {
    emit(
      'runtime_guard_triggered',
      fields: <String, Object?>{'guard': guard, ...fields},
    );
  }

  static void liveCueStateInvalid({Map<String, Object?> fields = const {}}) {
    emit('livecue_state_invalid', fields: fields);
  }

  static void setlistOrderInvalid({Map<String, Object?> fields = const {}}) {
    emit('setlist_order_invalid', fields: fields);
  }

  static void routerInvalidId({Map<String, Object?> fields = const {}}) {
    emit('router_invalid_id', fields: fields);
  }

  static void firestoreSnapshotError({Map<String, Object?> fields = const {}}) {
    emit('firestore_snapshot_error', fields: fields);
  }
}
