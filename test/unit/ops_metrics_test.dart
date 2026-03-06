import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/services/ops_metrics.dart';

void main() {
  group('ops metrics', () {
    test('skips write when team id is blank', () async {
      final firestore = FakeFirebaseFirestore();

      await logTeamOpsMetric(
        firestore: firestore,
        teamId: '   ',
        category: 'delete',
        action: 'team_delete',
        status: 'started',
      );

      final snapshot = await firestore
          .collection('teams')
          .doc('team-a')
          .collection('opsMetrics')
          .get();
      expect(snapshot.docs, isEmpty);
    });

    test('writes metric payload with optional fields', () async {
      final firestore = FakeFirebaseFirestore();

      await logTeamOpsMetric(
        firestore: firestore,
        teamId: 'team-a',
        category: 'delete',
        action: 'project_delete',
        status: 'failed',
        code: 'permission-denied',
        retryCount: 2,
        skippedCount: 1,
        failedCount: 3,
        extra: const {'projectId': 'p-1'},
      );

      final snapshot = await firestore
          .collection('teams')
          .doc('team-a')
          .collection('opsMetrics')
          .get();
      expect(snapshot.docs.length, 1);

      final data = snapshot.docs.first.data();
      expect(data['category'], 'delete');
      expect(data['action'], 'project_delete');
      expect(data['status'], 'failed');
      expect(data['code'], 'permission-denied');
      expect(data['retryCount'], 2);
      expect(data['skippedCount'], 1);
      expect(data['failedCount'], 3);
      expect(data['extra'], {'projectId': 'p-1'});
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('logs legacy fallback usage with detail', () async {
      final firestore = FakeFirebaseFirestore();

      await logLegacyFallbackUsage(
        firestore: firestore,
        teamId: 'team-z',
        path: 'live_cue.legacy_doc_id',
        detail: 'project-2026',
      );

      final snapshot = await firestore
          .collection('teams')
          .doc('team-z')
          .collection('opsMetrics')
          .get();
      expect(snapshot.docs.length, 1);
      final data = snapshot.docs.first.data();
      expect(data['category'], 'legacy_fallback');
      expect(data['action'], 'live_cue.legacy_doc_id');
      expect(data['status'], 'used');
      expect(data['extra'], {'detail': 'project-2026'});
    });
  });
}
