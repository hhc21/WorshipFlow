import 'package:cloud_firestore/cloud_firestore.dart';

class SongCandidate {
  final String id;
  final String title;

  const SongCandidate({required this.id, required this.title});
}

Future<List<SongCandidate>> findSongCandidates(
  FirebaseFirestore firestore,
  String normalizedTitle,
) async {
  if (normalizedTitle.isEmpty) return [];

  final normalized = normalizedTitle.trim().toLowerCase();
  if (normalized.isEmpty) return [];

  final tokenQuery = await firestore
      .collection('songs')
      .where('searchTokens', arrayContains: normalized)
      .limit(10)
      .get();

  final fromToken = tokenQuery.docs
      .map(
        (doc) => SongCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
        ),
      )
      .toList();
  if (fromToken.isNotEmpty) return fromToken;

  final exactTitleQuery = await firestore
      .collection('songs')
      .where('title', isEqualTo: normalizedTitle.trim())
      .limit(10)
      .get();
  final fromExactTitle = exactTitleQuery.docs
      .map(
        (doc) => SongCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
        ),
      )
      .toList();
  if (fromExactTitle.isNotEmpty) return fromExactTitle;

  final aliasQuery = await firestore
      .collection('songs')
      .where('aliases', arrayContains: normalizedTitle.trim())
      .limit(10)
      .get();
  final fromAlias = aliasQuery.docs
      .map(
        (doc) => SongCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
        ),
      )
      .toList();
  if (fromAlias.isNotEmpty) return fromAlias;

  final matches = <SongCandidate>[];
  QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  var scanned = 0;
  const pageSize = 200;
  const maxScan = 2000;

  while (scanned < maxScan) {
    var query = firestore
        .collection('songs')
        .orderBy(FieldPath.documentId)
        .limit(pageSize);
    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final page = await query.get();
    if (page.docs.isEmpty) break;

    scanned += page.docs.length;
    cursor = page.docs.last;
    for (final doc in page.docs) {
      final title = (doc.data()['title'] ?? '').toString();
      if (title.trim().toLowerCase() == normalized) {
        matches.add(SongCandidate(id: doc.id, title: title));
        continue;
      }
      final aliases = (doc.data()['aliases'] as List?) ?? const [];
      for (final alias in aliases) {
        if (alias.toString().trim().toLowerCase() == normalized) {
          matches.add(SongCandidate(id: doc.id, title: title));
          break;
        }
      }
    }
    if (matches.isNotEmpty) {
      break;
    }
  }
  return matches;
}
