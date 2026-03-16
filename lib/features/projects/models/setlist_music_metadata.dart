const int setlistMusicMetadataMinTempoBpm = 20;
const int setlistMusicMetadataMaxTempoBpm = 300;
const int setlistMusicMetadataMaxSectionMarkers = 16;
const int setlistMusicMetadataMaxSectionMarkerLength = 32;
const Set<int> setlistMusicMetadataAllowedTimeSignatureDenominators = <int>{
  1,
  2,
  4,
  8,
  16,
  32,
};

class SetlistMusicMetadata {
  final int? tempoBpm;
  final String? timeSignature;
  final List<String>? sectionMarkers;

  const SetlistMusicMetadata({
    this.tempoBpm,
    this.timeSignature,
    this.sectionMarkers,
  });

  factory SetlistMusicMetadata.fromUnknown(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return SetlistMusicMetadata.fromFirestore(raw);
    }
    if (raw is Map) {
      return SetlistMusicMetadata.fromFirestore(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return const SetlistMusicMetadata();
  }

  factory SetlistMusicMetadata.fromFirestore(Map<String, dynamic> raw) {
    final tempoBpm = _parseTempoBpm(raw['tempoBpm']);
    final timeSignature = _parseTimeSignature(raw['timeSignature']);
    final sectionMarkers = _parseSectionMarkers(raw['sectionMarkers']);
    return SetlistMusicMetadata(
      tempoBpm: tempoBpm,
      timeSignature: timeSignature,
      sectionMarkers: sectionMarkers,
    );
  }

  bool get isEmpty =>
      tempoBpm == null &&
      (timeSignature == null || timeSignature!.isEmpty) &&
      (sectionMarkers == null || sectionMarkers!.isEmpty);

  String? get compactSummary {
    final parts = <String>[
      if (tempoBpm != null) '$tempoBpm BPM',
      if (timeSignature != null && timeSignature!.isNotEmpty) timeSignature!,
      if (sectionMarkers != null && sectionMarkers!.isNotEmpty)
        '${sectionMarkers!.length} sections',
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  Map<String, dynamic> toFirestore() {
    final payload = <String, dynamic>{};
    if (tempoBpm != null) {
      payload['tempoBpm'] = tempoBpm;
    }
    if (timeSignature != null && timeSignature!.isNotEmpty) {
      payload['timeSignature'] = timeSignature;
    }
    if (sectionMarkers != null && sectionMarkers!.isNotEmpty) {
      payload['sectionMarkers'] = List<String>.from(sectionMarkers!);
    }
    return payload;
  }

  static int? _parseTempoBpm(Object? raw) {
    if (raw is int) {
      return _normalizeTempoBpm(raw);
    }
    if (raw is num) {
      final value = raw.toDouble();
      if (value == value.roundToDouble()) {
        return _normalizeTempoBpm(value.toInt());
      }
    }
    return null;
  }

  static int? _normalizeTempoBpm(int raw) {
    if (raw < setlistMusicMetadataMinTempoBpm ||
        raw > setlistMusicMetadataMaxTempoBpm) {
      return null;
    }
    return raw;
  }

  static String? _parseTimeSignature(Object? raw) {
    if (raw is! String) return null;
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return null;
    final match = RegExp(r'^([1-9]\d?)/([1-9]\d?)$').firstMatch(compact);
    if (match == null) return null;
    final numerator = int.tryParse(match.group(1)!);
    final denominator = int.tryParse(match.group(2)!);
    if (numerator == null ||
        denominator == null ||
        !setlistMusicMetadataAllowedTimeSignatureDenominators.contains(
          denominator,
        )) {
      return null;
    }
    return '$numerator/$denominator';
  }

  static List<String>? _parseSectionMarkers(Object? raw) {
    if (raw is! List) return null;
    final markers = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final trimmed = item.trim();
      if (trimmed.isEmpty ||
          trimmed.length > setlistMusicMetadataMaxSectionMarkerLength) {
        continue;
      }
      markers.add(trimmed);
      if (markers.length >= setlistMusicMetadataMaxSectionMarkers) {
        break;
      }
    }
    if (markers.isEmpty) return null;
    return List<String>.unmodifiable(markers);
  }
}
