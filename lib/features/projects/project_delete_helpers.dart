import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> deleteProjectDirectly({
  required FirebaseFirestore firestore,
  required String teamId,
  required String projectId,
}) async {
  final teamRef = firestore.collection('teams').doc(teamId);
  final projectRef = teamRef.collection('projects').doc(projectId);

  await _deleteCollectionDocs(projectRef.collection('segmentA_setlist'));
  await _deleteCollectionDocs(projectRef.collection('segmentB_application'));
  await _deleteCollectionDocs(projectRef.collection('liveCue'));
  await _deleteCollectionDocs(projectRef.collection('sharedNotes'));
  try {
    await _deleteQueryDocs(
      teamRef
          .collection('userProjectNotes')
          .where('projectId', isEqualTo: projectId),
    );
  } on FirebaseException catch (error) {
    if (error.code != 'permission-denied') rethrow;
  }

  await projectRef.delete();

  final remainingProjects = await teamRef
      .collection('projects')
      .orderBy('date', descending: true)
      .limit(1)
      .get();
  try {
    await teamRef.set({
      'lastProjectId': remainingProjects.docs.isEmpty
          ? FieldValue.delete()
          : remainingProjects.docs.first.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } on FirebaseException catch (error) {
    if (error.code != 'permission-denied') rethrow;
  }
}

Future<void> _deleteCollectionDocs(
  CollectionReference<Map<String, dynamic>> collectionRef, {
  int batchSize = 400,
}) async {
  while (true) {
    final snapshot = await collectionRef.limit(batchSize).get();
    if (snapshot.docs.isEmpty) return;

    final batch = collectionRef.firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    if (snapshot.docs.length < batchSize) return;
  }
}

Future<void> _deleteQueryDocs(
  Query<Map<String, dynamic>> query, {
  int batchSize = 400,
}) async {
  while (true) {
    final snapshot = await query.limit(batchSize).get();
    if (snapshot.docs.isEmpty) return;

    final batch = query.firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    if (snapshot.docs.length < batchSize) return;
  }
}
