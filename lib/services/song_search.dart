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

  final tokenQuery = await firestore
      .collection('songs')
      .where('searchTokens', arrayContains: normalizedTitle)
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

  final fallback = await firestore.collection('songs').limit(200).get();
  final normalized = normalizedTitle.trim().toLowerCase();
  final matches = <SongCandidate>[];
  for (final doc in fallback.docs) {
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
  return matches;
}
