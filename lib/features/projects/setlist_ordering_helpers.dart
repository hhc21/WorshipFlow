import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/project_setlist_section_type.dart';

class CanonicalSetlistPendingInsert {
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> data;

  const CanonicalSetlistPendingInsert({
    required this.reference,
    required this.data,
  });
}

Map<String, dynamic> buildCanonicalSetlistOrderUpdate(
  Map<String, dynamic> data,
  int nextOrder,
) {
  return <String, dynamic>{'order': nextOrder};
}

int canonicalInsertIndexForSection(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ProjectSetlistSectionType sectionType,
) {
  final targetSections = switch (sectionType) {
    ProjectSetlistSectionType.worship => {ProjectSetlistSectionType.worship},
    ProjectSetlistSectionType.sermonResponse ||
    ProjectSetlistSectionType.prayer => {
      ProjectSetlistSectionType.sermonResponse,
      ProjectSetlistSectionType.prayer,
    },
  };

  var lastMatchingIndex = -1;
  for (var i = 0; i < items.length; i++) {
    final itemSectionType = ProjectSetlistSectionType.fromUnknown(
      items[i].data()['sectionType']?.toString(),
    );
    if (targetSections.contains(itemSectionType)) {
      lastMatchingIndex = i;
    }
  }

  if (lastMatchingIndex >= 0) {
    return lastMatchingIndex + 1;
  }

  return switch (sectionType) {
    ProjectSetlistSectionType.worship => 0,
    ProjectSetlistSectionType.sermonResponse ||
    ProjectSetlistSectionType.prayer => items.length,
  };
}

Future<void> insertCanonicalSetlistItems(
  FirebaseFirestore firestore, {
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  required int insertIndex,
  required List<CanonicalSetlistPendingInsert> inserts,
}) async {
  if (inserts.isEmpty) return;

  final batch = firestore.batch();
  var hasChanges = false;
  var existingIndex = 0;
  final boundedInsertIndex = insertIndex.clamp(0, items.length);
  final totalLength = items.length + inserts.length;

  for (var i = 0; i < totalLength; i++) {
    final nextOrder = i + 1;
    final isInsertSlot =
        i >= boundedInsertIndex && i < boundedInsertIndex + inserts.length;
    if (isInsertSlot) {
      final insert = inserts[i - boundedInsertIndex];
      batch.set(insert.reference, <String, dynamic>{
        ...insert.data,
        'order': nextOrder,
      });
      hasChanges = true;
      continue;
    }

    final item = items[existingIndex++];
    final data = item.data();
    final updates = buildCanonicalSetlistOrderUpdate(data, nextOrder);
    final rawOrder = data['order'];
    final currentOrder = rawOrder is num
        ? rawOrder.toInt()
        : int.tryParse(rawOrder?.toString() ?? '');
    if (updates.length == 1 && updates['order'] == currentOrder) {
      continue;
    }
    batch.update(item.reference, updates);
    hasChanges = true;
  }

  if (!hasChanges) return;
  await batch.commit();
}

Future<void> reindexCanonicalSetlistOrder(
  FirebaseFirestore firestore,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
) async {
  await commitCanonicalSetlistOrder(firestore, items: items);
}

Future<void> commitCanonicalSetlistOrder(
  FirebaseFirestore firestore, {
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  DocumentReference<Map<String, dynamic>>? deleteRef,
}) async {
  final batch = firestore.batch();
  var hasChanges = deleteRef != null;
  if (deleteRef != null) {
    batch.delete(deleteRef);
  }

  if (items.isEmpty) {
    if (hasChanges) {
      await batch.commit();
    }
    return;
  }
  for (var i = 0; i < items.length; i++) {
    final nextOrder = i + 1;
    final data = items[i].data();
    final updates = buildCanonicalSetlistOrderUpdate(data, nextOrder);
    final rawOrder = data['order'];
    final currentOrder = rawOrder is num
        ? rawOrder.toInt()
        : int.tryParse(rawOrder?.toString() ?? '');
    if (updates.length == 1 && updates['order'] == currentOrder) {
      continue;
    }
    batch.update(items[i].reference, updates);
    hasChanges = true;
  }

  if (!hasChanges) return;
  await batch.commit();
}
