import 'models/setlist_music_metadata.dart';

class SetlistMusicMetadataInputValidationResult {
  final SetlistMusicMetadata metadata;
  final String? tempoBpmError;
  final String? timeSignatureError;
  final String? sectionMarkersError;

  const SetlistMusicMetadataInputValidationResult({
    required this.metadata,
    this.tempoBpmError,
    this.timeSignatureError,
    this.sectionMarkersError,
  });

  bool get isValid =>
      tempoBpmError == null &&
      timeSignatureError == null &&
      sectionMarkersError == null;
}

SetlistMusicMetadataInputValidationResult validateSetlistMusicMetadataInput({
  required String tempoBpmInput,
  required String timeSignatureInput,
  required String sectionMarkersInput,
}) {
  final trimmedTempo = tempoBpmInput.trim();
  final trimmedTimeSignature = timeSignatureInput.trim();
  final trimmedSectionMarkers = sectionMarkersInput.trim();

  String? tempoBpmError;
  int? tempoBpm;
  if (trimmedTempo.isNotEmpty) {
    final parsedTempo = int.tryParse(trimmedTempo);
    if (parsedTempo == null) {
      tempoBpmError = '템포는 정수로 입력해 주세요.';
    } else if (parsedTempo < setlistMusicMetadataMinTempoBpm ||
        parsedTempo > setlistMusicMetadataMaxTempoBpm) {
      tempoBpmError =
          '템포는 $setlistMusicMetadataMinTempoBpm~$setlistMusicMetadataMaxTempoBpm 사이여야 합니다.';
    } else {
      tempoBpm = parsedTempo;
    }
  }

  String? timeSignatureError;
  String? timeSignature;
  if (trimmedTimeSignature.isNotEmpty) {
    final compact = trimmedTimeSignature.replaceAll(RegExp(r'\s+'), '');
    final match = RegExp(r'^([1-9]\d?)/([1-9]\d?)$').firstMatch(compact);
    final denominator = match == null ? null : int.tryParse(match.group(2)!);
    if (match == null ||
        denominator == null ||
        !setlistMusicMetadataAllowedTimeSignatureDenominators.contains(
          denominator,
        )) {
      timeSignatureError = '박자표는 4/4, 3/4, 6/8 형식으로 입력해 주세요.';
    } else {
      timeSignature = '${match.group(1)!}/$denominator';
    }
  }

  String? sectionMarkersError;
  List<String>? sectionMarkers;
  if (trimmedSectionMarkers.isNotEmpty) {
    final parsedMarkers = trimmedSectionMarkers
        .replaceAll('\n', ',')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (parsedMarkers.isEmpty) {
      sectionMarkersError = '섹션 마커를 쉼표로 구분해 입력해 주세요.';
    } else if (parsedMarkers.length > setlistMusicMetadataMaxSectionMarkers) {
      sectionMarkersError =
          '섹션 마커는 최대 $setlistMusicMetadataMaxSectionMarkers개까지 입력할 수 있습니다.';
    } else if (parsedMarkers.any(
      (item) => item.length > setlistMusicMetadataMaxSectionMarkerLength,
    )) {
      sectionMarkersError =
          '각 섹션 마커는 $setlistMusicMetadataMaxSectionMarkerLength자 이하여야 합니다.';
    } else {
      sectionMarkers = List<String>.unmodifiable(parsedMarkers);
    }
  }

  return SetlistMusicMetadataInputValidationResult(
    metadata: SetlistMusicMetadata(
      tempoBpm: tempoBpm,
      timeSignature: timeSignature,
      sectionMarkers: sectionMarkers,
    ),
    tempoBpmError: tempoBpmError,
    timeSignatureError: timeSignatureError,
    sectionMarkersError: sectionMarkersError,
  );
}
