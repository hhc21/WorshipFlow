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

class SongResolutionCandidate {
  final String id;
  final String title;
  final String source;

  const SongResolutionCandidate({
    required this.id,
    required this.title,
    required this.source,
  });

  SongCandidate toSongCandidate() => SongCandidate(id: id, title: title);
}

class SongResolutionResult {
  final List<SongResolutionCandidate> candidates;

  const SongResolutionResult(this.candidates);

  SongResolutionCandidate? get primary =>
      candidates.isEmpty ? null : candidates.first;

  bool get isResolved => candidates.isNotEmpty;

  List<String> get songIds =>
      candidates.map((candidate) => candidate.id).toList();

  List<SongCandidate> toSongCandidates() =>
      candidates.map((candidate) => candidate.toSongCandidate()).toList();
}

SongCandidate? preferResolvedSongCandidate(
  Iterable<SongCandidate> candidates,
  String queryText,
) {
  final normalizedQuery = normalizeQuery(queryText);
  if (normalizedQuery.isEmpty) {
    for (final candidate in candidates) {
      return candidate;
    }
    return null;
  }

  for (final candidate in candidates) {
    if (normalizeQuery(candidate.title) == normalizedQuery) {
      return candidate;
    }
  }

  for (final candidate in candidates) {
    return candidate;
  }
  return null;
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

@visibleForTesting
void resetSongSearchCaches() {
  _songCandidateCache.clear();
  _songCandidateCacheOrder.clear();
  _teamSongRefCache.clear();
  _teamSongRefCacheOrder.clear();
}

String sanitizeSongLookupTitle(String rawTitle, {String? keyText}) {
  final title = rawTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (title.isEmpty) return '';

  final normalizedKey = keyText?.trim().isEmpty ?? true
      ? ''
      : normalizeKeyText(keyText!.trim());
  if (normalizedKey.isEmpty) return title;

  final withKeyPattern = RegExp(
    r'^(?<label>\d+(?:-\d+)?)(?:[.)])?\s+(?<key>[A-G](?:#|b)?(?:\s*(?:-|/|→)\s*[A-G](?:#|b)?)*)\s+(?<title>.+)$',
    caseSensitive: false,
  );
  final withKeyMatch = withKeyPattern.firstMatch(title);
  if (withKeyMatch != null) {
    final prefixedKey = withKeyMatch.namedGroup('key')?.trim() ?? '';
    if (prefixedKey.isNotEmpty &&
        normalizeKeyText(prefixedKey) == normalizedKey) {
      final sanitized = withKeyMatch.namedGroup('title')?.trim() ?? '';
      if (sanitized.isNotEmpty) {
        return sanitized;
      }
    }
  }

  return title;
}

List<String> buildSongLookupTitleCandidates(
  String rawTitle, {
  String? keyText,
}) {
  final seed = rawTitle.trim();
  if (seed.isEmpty) return const <String>[];

  final candidates = <String>{};

  void addTitle(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isNotEmpty) {
      candidates.add(trimmed);
    }
  }

  addTitle(seed);
  addTitle(sanitizeSongLookupTitle(seed, keyText: keyText));

  final withoutCueLabel = seed
      .replaceFirst(RegExp(r'^\s*\d+(?:-\d+)?(?:[.)])?\s+'), '')
      .trim();
  addTitle(withoutCueLabel);
  addTitle(sanitizeSongLookupTitle(withoutCueLabel, keyText: keyText));

  for (final candidate in candidates.toList()) {
    final parsed = parseSongInput(candidate).title.trim();
    addTitle(parsed);
    addTitle(sanitizeSongLookupTitle(parsed, keyText: keyText));
  }

  return candidates.toList();
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

List<SongResolutionCandidate> _preferKeyMatches(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String? normalizedKey,
  String source,
) {
  final all = docs
      .map(
        (doc) => SongResolutionCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
          source: source,
        ),
      )
      .toList();
  if (normalizedKey == null || normalizedKey.isEmpty) {
    return all;
  }

  final withKey = docs
      .where((doc) {
        final rawDefaultKey = doc.data()['defaultKey']?.toString().trim();
        if (rawDefaultKey == null || rawDefaultKey.isEmpty) {
          return false;
        }
        return normalizeKeyText(rawDefaultKey) == normalizedKey;
      })
      .map(
        (doc) => SongResolutionCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
          source: source,
        ),
      )
      .toList();

  return withKey.isNotEmpty ? withKey : all;
}

Future<List<SongResolutionCandidate>> _querySongsByExactTitle(
  FirebaseFirestore firestore,
  String title, {
  String? normalizedKey,
}) async {
  final query = await firestore
      .collection('songs')
      .where('title', isEqualTo: title)
      .limit(10)
      .get();
  return _preferKeyMatches(query.docs, normalizedKey, 'canonical_title_key');
}

Future<List<SongResolutionCandidate>> _querySongsByAlias(
  FirebaseFirestore firestore,
  String title, {
  String? normalizedKey,
}) async {
  final query = await firestore
      .collection('songs')
      .where('aliases', arrayContains: title)
      .limit(10)
      .get();
  return _preferKeyMatches(query.docs, normalizedKey, 'alias');
}

Future<List<SongResolutionCandidate>> _querySongsByNormalizedToken(
  FirebaseFirestore firestore,
  String normalizedTitle, {
  String? normalizedKey,
}) async {
  final tokenQuery = await firestore
      .collection('songs')
      .where('searchTokens', arrayContains: normalizedTitle)
      .limit(10)
      .get();
  final tokenMatches = _preferKeyMatches(
    tokenQuery.docs,
    normalizedKey,
    'normalized_token',
  );
  if (tokenMatches.isNotEmpty) {
    return tokenMatches;
  }

  final matches = <SongResolutionCandidate>[];
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
    final pageMatches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in page.docs) {
      final title = (doc.data()['title'] ?? '').toString();
      if (normalizeQuery(title) == normalizedTitle) {
        pageMatches.add(doc);
        continue;
      }
      final aliases = (doc.data()['aliases'] as List?) ?? const [];
      for (final alias in aliases) {
        if (normalizeQuery(alias.toString()) == normalizedTitle) {
          pageMatches.add(doc);
          break;
        }
      }
    }
    if (pageMatches.isNotEmpty) {
      matches.addAll(
        _preferKeyMatches(pageMatches, normalizedKey, 'normalized_token'),
      );
      break;
    }
  }

  if (scanned > 0) {
    OpsMetrics.emit(
      'song_search_broad_scan',
      fields: <String, Object?>{
        'query': normalizedTitle,
        'scanned': scanned,
        'matchCount': matches.length,
      },
    );
  }
  return matches;
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

Future<SongResolutionResult> resolveSongLookup(
  FirebaseFirestore firestore, {
  required String? songId,
  required String? rawTitle,
  required String? keyText,
  String? teamId,
}) async {
  final candidates = <SongResolutionCandidate>[];
  final byId = <String, SongResolutionCandidate>{};

  void addCandidate(SongResolutionCandidate candidate) {
    final existing = byId[candidate.id];
    if (existing == null) {
      byId[candidate.id] = candidate;
      candidates.add(candidate);
      return;
    }
    if (existing.title.isEmpty && candidate.title.isNotEmpty) {
      final updated = SongResolutionCandidate(
        id: existing.id,
        title: candidate.title,
        source: existing.source,
      );
      byId[candidate.id] = updated;
      final index = candidates.indexWhere((item) => item.id == candidate.id);
      if (index >= 0) {
        candidates[index] = updated;
      }
    }
  }

  final safeSongId = songId?.trim() ?? '';
  final normalizedKey = keyText?.trim().isEmpty ?? true
      ? null
      : normalizeKeyText(keyText!.trim());
  final titleCandidates = buildSongLookupTitleCandidates(
    rawTitle?.trim() ?? '',
    keyText: normalizedKey,
  );

  if (safeSongId.isNotEmpty) {
    addCandidate(
      SongResolutionCandidate(
        id: safeSongId,
        title: titleCandidates.isEmpty ? '' : titleCandidates.first,
        source: 'song_id',
      ),
    );
  }

  final safeTeamId = teamId?.trim() ?? '';
  if (safeTeamId.isNotEmpty) {
    for (final title in titleCandidates) {
      final teamMatches = await findTeamSongRefCandidates(
        firestore,
        teamId: safeTeamId,
        title: title,
      );
      for (final id in teamMatches) {
        addCandidate(
          SongResolutionCandidate(
            id: id,
            title: title,
            source: 'team_song_ref',
          ),
        );
      }
      if (candidates.isNotEmpty && safeSongId.isEmpty) {
        break;
      }
    }
  }

  for (final title in titleCandidates) {
    final exactMatches = await _querySongsByExactTitle(
      firestore,
      title,
      normalizedKey: normalizedKey,
    );
    for (final candidate in exactMatches) {
      addCandidate(candidate);
    }
    if (exactMatches.isNotEmpty) {
      break;
    }
  }

  for (final title in titleCandidates) {
    final aliasMatches = await _querySongsByAlias(
      firestore,
      title,
      normalizedKey: normalizedKey,
    );
    for (final candidate in aliasMatches) {
      addCandidate(candidate);
    }
    if (aliasMatches.isNotEmpty) {
      break;
    }
  }

  for (final title in titleCandidates) {
    final normalizedTitle = normalizeQuery(title);
    if (normalizedTitle.isEmpty) continue;
    final tokenMatches = await _querySongsByNormalizedToken(
      firestore,
      normalizedTitle,
      normalizedKey: normalizedKey,
    );
    for (final candidate in tokenMatches) {
      addCandidate(candidate);
    }
    if (tokenMatches.isNotEmpty) {
      break;
    }
  }

  return SongResolutionResult(candidates);
}

Future<List<SongCandidate>> resolveSongCandidates(
  FirebaseFirestore firestore, {
  required String? songId,
  required String? rawTitle,
  required String? keyText,
  String? teamId,
}) async {
  final result = await resolveSongLookup(
    firestore,
    songId: songId,
    rawTitle: rawTitle,
    keyText: keyText,
    teamId: teamId,
  );
  return result.toSongCandidates();
}

Future<SongCandidate?> resolvePrimarySongCandidate(
  FirebaseFirestore firestore, {
  required String? songId,
  required String? rawTitle,
  required String? keyText,
  String? teamId,
}) async {
  final candidates = await resolveSongCandidates(
    firestore,
    songId: songId,
    rawTitle: rawTitle,
    keyText: keyText,
    teamId: teamId,
  );
  return preferResolvedSongCandidate(candidates, rawTitle ?? '');
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
