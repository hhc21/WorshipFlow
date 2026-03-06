import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/teams/team_home_logic.dart';

void main() {
  test('compareProjectDocs sorts by date desc and createdAt desc', () async {
    final firestore = FakeFirebaseFirestore();
    final projects = firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects');

    await projects.doc('older').set({
      'date': '2026.03.01',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(10),
    });
    await projects.doc('newer').set({
      'date': '2026.03.04',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(20),
    });
    await projects.doc('same-date-late').set({
      'date': '2026.03.04',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(30),
    });

    final snapshot = await projects.get();
    final docs = [...snapshot.docs]..sort(compareProjectDocs);

    expect(docs.map((doc) => doc.id).toList(), [
      'same-date-late',
      'newer',
      'older',
    ]);
  });

  test('cleanup error code predicates classify retry/skippable codes', () {
    expect(isRetriableCleanupErrorCode('aborted'), isTrue);
    expect(isRetriableCleanupErrorCode('resource-exhausted'), isTrue);
    expect(isRetriableCleanupErrorCode('permission-denied'), isFalse);

    expect(isSkippableCleanupErrorCode('permission-denied'), isTrue);
    expect(isSkippableCleanupErrorCode('failed-precondition'), isTrue);
    expect(isSkippableCleanupErrorCode('aborted'), isFalse);
  });

  test('cleanupLabelPreview truncates long lists', () {
    final preview = cleanupLabelPreview(
      ['a(1)', 'b(2)'],
      ['c(3)', 'd(4)'],
      maxItems: 3,
    );
    expect(preview, 'a(1), b(2), c(3) 외 1건');
  });
}
