import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/ops/ops_metrics.dart';
import '../utils/song_parser.dart';

class SongCandidate {
  final String id;
  final String title;

  const SongCandidate({required this.id, required this.title});
}

const int _maxSongSearchCacheEntries = 256;
const int _maxTeamSongRefCacheEntries = 256;

final Map<String, List<SongCandidate>> _songCandidateCache =
    <String, List<SongCandidate>>{};
final ListQueue<String> _songCandidateCacheOrder = ListQueue<String>();

final Map<String, List<String>> _teamSongRefCache = <String, List<String>>{};
final ListQueue<String> _teamSongRefCacheOrder = ListQueue<String>();

void _rememberSongCandidateCache(String cacheKey, List<SongCandidate> value) {
  _songCandidateCache[cacheKey] = List<SongCandidate>.unmodifiable(value);
  _songCandidateCacheOrder.remove(cacheKey);
  _songCandidateCacheOrder.addLast(cacheKey);
  while (_songCandidateCacheOrder.length > _maxSongSearchCacheEntries) {
    final oldest = _songCandidateCacheOrder.removeFirst();
    _songCandidateCache.remove(oldest);
  }
}

void _rememberTeamSongRefCache(String cacheKey, List<String> value) {
  _teamSongRefCache[cacheKey] = List<String>.unmodifiable(value);
  _teamSongRefCacheOrder.remove(cacheKey);
  _teamSongRefCacheOrder.addLast(cacheKey);
  while (_teamSongRefCacheOrder.length > _maxTeamSongRefCacheEntries) {
    final oldest = _teamSongRefCacheOrder.removeFirst();
    _teamSongRefCache.remove(oldest);
  }
}

List<SongCandidate> _toSongCandidates(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs
      .map(
        (doc) => SongCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
        ),
      )
      .toList();
}

Future<List<SongCandidate>> findSongCandidates(
  FirebaseFirestore firestore,
  String queryText,
) async {
  final rawQuery = queryText.trim();
  if (rawQuery.isEmpty) return [];
  final normalized = normalizeQuery(rawQuery);
  if (normalized.isEmpty) return [];

  final cached = _songCandidateCache[normalized];
  if (cached != null) {
    return cached;
  }

  final tokenQuery = await firestore
      .collection('songs')
      .where('searchTokens', arrayContains: normalized)
      .limit(10)
      .get();

  final fromToken = _toSongCandidates(tokenQuery.docs);
  if (fromToken.isNotEmpty) {
    _rememberSongCandidateCache(normalized, fromToken);
    return fromToken;
  }

  if (rawQuery != normalized) {
    final exactTitleQuery = await firestore
        .collection('songs')
        .where('title', isEqualTo: rawQuery)
        .limit(10)
        .get();
    final fromExactTitle = _toSongCandidates(exactTitleQuery.docs);
    if (fromExactTitle.isNotEmpty) {
      _rememberSongCandidateCache(normalized, fromExactTitle);
      return fromExactTitle;
    }
  }

  final aliasQuery = await firestore
      .collection('songs')
      .where('aliases', arrayContains: rawQuery)
      .limit(10)
      .get();
  final fromAlias = _toSongCandidates(aliasQuery.docs);
  if (fromAlias.isNotEmpty) {
    _rememberSongCandidateCache(normalized, fromAlias);
    return fromAlias;
  }

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
  if (scanned > 0) {
    OpsMetrics.emit(
      'song_search_broad_scan',
      fields: <String, Object?>{
        'query': normalized,
        'scanned': scanned,
        'matchCount': matches.length,
      },
    );
  }
  _rememberSongCandidateCache(normalized, matches);
  return matches;
}

Future<List<String>> findTeamSongRefCandidates(
  FirebaseFirestore firestore, {
  required String teamId,
  required String title,
}) async {
  final safeTeamId = teamId.trim();
  final rawTitle = title.trim();
  if (safeTeamId.isEmpty || rawTitle.isEmpty) return const <String>[];
  final normalizedTitle = normalizeQuery(rawTitle);
  if (normalizedTitle.isEmpty) return const <String>[];

  final cacheKey = '$safeTeamId::$normalizedTitle';
  final cached = _teamSongRefCache[cacheKey];
  if (cached != null) {
    return cached;
  }

  final ids = <String>[];
  final seen = <String>{};
  void addId(String? rawId) {
    final id = rawId?.trim() ?? '';
    if (id.isEmpty) return;
    if (seen.add(id)) {
      ids.add(id);
    }
  }

  try {
    final byTitle = await firestore
        .collection('teams')
        .doc(safeTeamId)
        .collection('songRefs')
        .where('title', isEqualTo: rawTitle)
        .limit(10)
        .get();
    for (final doc in byTitle.docs) {
      addId(doc.data()['songId']?.toString());
      addId(doc.id);
    }
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[song_search] team songRefs byTitle failed: $error');
    }
  }

  try {
    final byToken = await firestore
        .collection('teams')
        .doc(safeTeamId)
        .collection('songRefs')
        .where('searchTokens', arrayContains: normalizedTitle)
        .limit(10)
        .get();
    for (final doc in byToken.docs) {
      addId(doc.data()['songId']?.toString());
      addId(doc.id);
    }
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[song_search] team songRefs byToken failed: $error');
    }
  }

  _rememberTeamSongRefCache(cacheKey, ids);
  return ids;
}
