class ParsedSongInput {
  final String title;
  final String? keyText;

  const ParsedSongInput({required this.title, this.keyText});
}

String _normalizeCompoundKey(String key) {
  final compact = key.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return '';
  return compact.replaceAllMapped(RegExp(r'[A-Ga-g](?:#|b)?'), (match) {
    final token = match.group(0)!;
    return token[0].toUpperCase() + token.substring(1);
  });
}

ParsedSongInput parseSongInput(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return const ParsedSongInput(title: '', keyText: null);
  }

  text = text.replaceAll(RegExp(r'[\[\]]'), '').trim();
  String? key;
  const keyPattern = r'[A-G](?:#|b)?(?:\s*(?:-|/|→)\s*[A-G](?:#|b)?)*';

  final match = RegExp(
    '^(?<key>$keyPattern)(\\s+)(?<title>.+)\$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match != null) {
    key = match.namedGroup('key');
    text = match.namedGroup('title') ?? text;
    if (key != null && key.isNotEmpty) {
      key = _normalizeCompoundKey(key);
    }
  } else {
    final trailing = RegExp(
      '^(?<title>.+?)(\\s+)(?<key>$keyPattern)\$',
      caseSensitive: false,
    ).firstMatch(text);
    if (trailing != null) {
      key = trailing.namedGroup('key');
      text = trailing.namedGroup('title') ?? text;
      if (key != null && key.isNotEmpty) {
        key = _normalizeCompoundKey(key);
      }
    }
  }

  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return ParsedSongInput(title: text, keyText: key);
}

List<String> buildSearchTokens(String title, List<String> aliases) {
  final tokens = <String>{};
  void addTokens(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    tokens.add(lower);
    tokens.addAll(lower.split(RegExp(r'\s+')).where((t) => t.isNotEmpty));
  }

  addTokens(title);
  for (final alias in aliases) {
    addTokens(alias);
  }

  return tokens.toList();
}

String normalizeQuery(String input) {
  return input.trim().toLowerCase();
}

String normalizeKeyText(String key) {
  return _normalizeCompoundKey(key.trim());
}

String canonicalKeyText(String key) {
  final normalized = normalizeKeyText(key);
  const aliases = {
    'Db': 'C#',
    'D#': 'Eb',
    'Gb': 'F#',
    'G#': 'Ab',
    'A#': 'Bb',
    'Cb': 'B',
    'B#': 'C',
    'E#': 'F',
    'Fb': 'E',
  };
  return aliases[normalized] ?? normalized;
}

String? extractKeyFromFilename(String fileName) {
  final baseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
  var text = baseName.replaceAll(RegExp(r'[\[\]\(\)]'), ' ');
  text = text.replaceAll(RegExp(r'[_\-]+'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;

  final leading = RegExp(
    r'^(?<key>[A-G](?:#|b)?)(?:\s+)(?<title>.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (leading != null) {
    final key = leading.namedGroup('key');
    if (key != null && key.isNotEmpty) {
      return normalizeKeyText(key);
    }
  }

  final trailing = RegExp(
    r'^(?<title>.+?)(?:\s+)(?<key>[A-G](?:#|b)?)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (trailing != null) {
    final key = trailing.namedGroup('key');
    if (key != null && key.isNotEmpty) {
      return normalizeKeyText(key);
    }
  }

  return null;
}

bool isKeyMatch(String? keyText, String fileName) {
  if (keyText == null || keyText.trim().isEmpty) return false;
  final target = canonicalKeyText(keyText);
  if (target.isEmpty) return false;
  final fileKey = extractKeyFromFilename(fileName);
  return fileKey != null && canonicalKeyText(fileKey) == target;
}

String? assetKeyText(Map<String, dynamic> assetData) {
  final rawKey = assetData['keyText']?.toString().trim();
  if (rawKey != null && rawKey.isNotEmpty) {
    final normalized = normalizeKeyText(rawKey);
    if (normalized.isNotEmpty) return normalized;
  }
  final fileName = assetData['fileName']?.toString() ?? '';
  return extractKeyFromFilename(fileName);
}

bool isAssetKeyMatch(Map<String, dynamic> assetData, String? keyText) {
  if (keyText == null || keyText.trim().isEmpty) return false;
  final target = canonicalKeyText(keyText);
  if (target.isEmpty) return false;
  final resolved = assetKeyText(assetData);
  return resolved != null && canonicalKeyText(resolved) == target;
}

String transposeKey(String keyText, int semitones) {
  final key = normalizeKeyText(keyText);
  if (key.isEmpty || semitones == 0) return key;
  const chromatic = [
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
  final canonical = canonicalKeyText(key);
  final baseIndex = chromatic.indexOf(canonical);
  if (baseIndex < 0) return key;
  final nextIndex = (baseIndex + semitones) % chromatic.length;
  final normalizedIndex = nextIndex < 0
      ? nextIndex + chromatic.length
      : nextIndex;
  return chromatic[normalizedIndex];
}
