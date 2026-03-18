part of 'live_cue_page.dart';

bool supportsLiveCueDrawingPointer(PointerDeviceKind kind) {
  return kind == PointerDeviceKind.mouse ||
      kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      kind == PointerDeviceKind.unknown;
}

DocumentReference<Map<String, dynamic>> _liveCueRefFor(
  FirebaseFirestore firestore,
  String teamId,
  String projectId,
) {
  return firestore
      .collection('teams')
      .doc(teamId)
      .collection('projects')
      .doc(projectId)
      .collection('liveCue')
      .doc('state');
}

CollectionReference<Map<String, dynamic>> _setlistRefFor(
  FirebaseFirestore firestore,
  String teamId,
  String projectId,
) {
  return firestore
      .collection('teams')
      .doc(teamId)
      .collection('projects')
      .doc(projectId)
      .collection('segmentA_setlist');
}

bool _hasCueValue(Map<String, dynamic> cueData, String prefix) {
  final songId = cueData['${prefix}SongId']?.toString().trim() ?? '';
  final displayTitle =
      cueData['${prefix}DisplayTitle']?.toString().trim() ?? '';
  final freeText = cueData['${prefix}FreeTextTitle']?.toString().trim() ?? '';
  return songId.isNotEmpty || displayTitle.isNotEmpty || freeText.isNotEmpty;
}

Map<String, dynamic> _clearCueFields({required String prefix}) {
  return {
    '${prefix}SongId': null,
    '${prefix}FreeTextTitle': null,
    '${prefix}DisplayTitle': null,
    '${prefix}KeyText': null,
    '${prefix}CueLabel': null,
  };
}

String _cueLabelFromItem(Map<String, dynamic> item, int fallbackOrder) {
  final raw = item['cueLabel']?.toString().trim();
  if (raw != null && raw.isNotEmpty) return raw;
  final order = item['order'];
  if (order is num) return order.toInt().toString();
  return fallbackOrder.toString();
}

String _displayOrderLabelFromItem(
  Map<String, dynamic> item,
  int fallbackOrder,
) {
  final order = item['order'];
  if (order is num) return order.toInt().toString();
  return fallbackOrder.toString();
}

String _titleFromItem(Map<String, dynamic> item) {
  return (item['displayTitle'] ?? item['freeTextTitle'] ?? '곡')
      .toString()
      .trim();
}

String _sanitizeLegacyDisplayTitle(
  String rawTitle, {
  String? normalizedKeyText,
}) {
  final title = rawTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (title.isEmpty) return '';
  final normalizedKey = normalizedKeyText?.trim() ?? '';
  if (normalizedKey.isEmpty) return title;

  final withKeyPattern = RegExp(
    r'^(?<label>\d+(?:-\d+)?)(?:[.)])?\s+(?<key>[A-G](?:#|b)?(?:\s*(?:-|/|→)\s*[A-G](?:#|b)?)*)\s+(?<title>.+)$',
    caseSensitive: false,
  );
  final withKeyMatch = withKeyPattern.firstMatch(title);
  if (withKeyMatch != null) {
    final prefixedKey = withKeyMatch.namedGroup('key')?.trim() ?? '';
    if (prefixedKey.isNotEmpty &&
        normalizeKeyText(prefixedKey) == normalizeKeyText(normalizedKey)) {
      final sanitized = withKeyMatch.namedGroup('title')?.trim() ?? '';
      if (sanitized.isNotEmpty) return sanitized;
    }
  }

  return title;
}

String _titleForDisplayFromItem(Map<String, dynamic> item) {
  final title = _titleFromItem(item);
  final key = _keyFromItem(item);
  final sanitized = _sanitizeLegacyDisplayTitle(title, normalizedKeyText: key);
  return sanitized.isEmpty ? '곡' : sanitized;
}

String? _keyFromItem(Map<String, dynamic> item) {
  final key = item['keyText']?.toString().trim();
  if (key == null || key.isEmpty) return null;
  return normalizeKeyText(key);
}

String _lineText({
  required String label,
  required String title,
  String? keyText,
}) {
  final parts = <String>[label, title];
  if (keyText != null && keyText.trim().isNotEmpty) {
    parts.add(normalizeKeyText(keyText));
  }
  return parts.join(' ');
}

const List<int> _liveCueDrawingPalette = <int>[
  0xFFD32F2F,
  0xFF1976D2,
  0xFF2E7D32,
  0xFFF9A825,
  0xFF000000,
  0xFFFFFFFF,
];

const String _nextViewerUrl = String.fromEnvironment(
  'WF_NEXT_VIEWER_URL',
  defaultValue: '',
);
const String _nextViewerReadbackMode = String.fromEnvironment(
  'WF_NEXT_WILL_READ_FREQUENTLY',
  defaultValue: 'enabled',
);
const int _liveCueImageCacheMaxEntries = 120;
const int _liveCueImageCacheMaxBytes = 80 * 1024 * 1024;

void _traceLiveCueSync(
  String scope,
  String event, {
  int? generation,
  int? sequence,
  String? detail,
}) {
  final buffer = StringBuffer('[LiveCueSync][$scope] $event');
  if (generation != null) {
    buffer.write(' generation=$generation');
  }
  if (sequence != null) {
    buffer.write(' seq=$sequence');
  }
  if (detail != null && detail.isNotEmpty) {
    buffer.write(' detail=$detail');
  }
  debugPrint(buffer.toString());
}

Future<SongCandidate?> _matchSongAutomatically(
  FirebaseFirestore firestore,
  String title, {
  String? keyText,
  String? teamId,
}) async {
  return resolvePrimarySongCandidate(
    firestore,
    songId: null,
    rawTitle: title,
    keyText: keyText,
    teamId: teamId,
  );
}

Future<List<String>> _songIdCandidatesForPreview(
  FirebaseFirestore firestore,
  String? teamId,
  String? preferredSongId,
  String? keyText,
  String? fallbackTitle,
) async {
  final result = await resolveSongLookup(
    firestore,
    songId: preferredSongId,
    rawTitle: fallbackTitle,
    keyText: keyText,
    teamId: teamId,
  );
  return result.songIds;
}

Future<Map<String, dynamic>> _cueFieldsFromSetlist(
  FirebaseFirestore firestore,
  Map<String, dynamic> setlistItem, {
  required String prefix,
  String? teamId,
}) async {
  String? songId = setlistItem['songId']?.toString().trim();
  String displayTitle =
      (setlistItem['displayTitle'] ?? setlistItem['freeTextTitle'] ?? '곡')
          .toString()
          .trim();
  String? freeTextTitle = setlistItem['freeTextTitle']?.toString().trim();

  final rawKey = setlistItem['keyText']?.toString().trim();
  final keyText = (rawKey == null || rawKey.isEmpty)
      ? null
      : normalizeKeyText(rawKey);

  final cueLabel = setlistItem['cueLabel']?.toString().trim();
  final orderValue = setlistItem['order'];
  final normalizedLabel = (cueLabel == null || cueLabel.isEmpty)
      ? orderValue?.toString()
      : cueLabel;

  if ((songId == null || songId.isEmpty) && displayTitle.isNotEmpty) {
    final matched = await _matchSongAutomatically(
      firestore,
      displayTitle,
      keyText: keyText,
      teamId: teamId,
    );
    if (matched != null) {
      songId = matched.id;
      displayTitle = matched.title;
      freeTextTitle = null;
    }
  }

  final hasSongId = songId != null && songId.isNotEmpty;
  return {
    '${prefix}SongId': hasSongId ? songId : null,
    '${prefix}FreeTextTitle': hasSongId ? null : freeTextTitle,
    '${prefix}DisplayTitle': displayTitle,
    '${prefix}KeyText': keyText,
    '${prefix}CueLabel': normalizedLabel,
  };
}

int _keySortWeight(String keyText) {
  final normalized = canonicalKeyText(keyText);
  const canonicalOrder = [
    'C',
    'C#',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];
  final idx = canonicalOrder.indexOf(normalized);
  return idx < 0 ? 999 : idx;
}

Future<List<String>> _loadAvailableKeysForSong(
  FirebaseFirestore firestore,
  String songId,
) async {
  final assets = await firestore
      .collection('songs')
      .doc(songId)
      .collection('assets')
      .orderBy('createdAt', descending: true)
      .get();

  final keys = <String>{};
  for (final doc in assets.docs) {
    final key = assetKeyText(doc.data());
    if (key != null && key.isNotEmpty) {
      keys.add(normalizeKeyText(key));
    }
  }

  final list = keys.toList();
  list.sort((a, b) {
    final byWeight = _keySortWeight(a).compareTo(_keySortWeight(b));
    if (byWeight != 0) return byWeight;
    return a.compareTo(b);
  });
  return list;
}
