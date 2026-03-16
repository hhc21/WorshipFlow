import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/models/setlist_music_metadata.dart';
import 'package:worshipflow/features/projects/setlist_music_metadata_validator.dart';

void main() {
  group('SetlistMusicMetadata.fromFirestore', () {
    test('parses valid metadata fields', () {
      final metadata = SetlistMusicMetadata.fromFirestore({
        'tempoBpm': 120,
        'timeSignature': ' 6 / 8 ',
        'sectionMarkers': ['Intro', ' Verse ', 'Chorus'],
      });

      expect(metadata.tempoBpm, 120);
      expect(metadata.timeSignature, '6/8');
      expect(metadata.sectionMarkers, <String>['Intro', 'Verse', 'Chorus']);
    });

    test('ignores malformed fields without throwing', () {
      final metadata = SetlistMusicMetadata.fromUnknown({
        'tempoBpm': '120',
        'timeSignature': 'abc',
        'sectionMarkers': ['Intro', '', 1, List.filled(40, 'A').join()],
      });

      expect(metadata.tempoBpm, isNull);
      expect(metadata.timeSignature, isNull);
      expect(metadata.sectionMarkers, <String>['Intro']);
    });

    test('serializes only populated fields', () {
      const metadata = SetlistMusicMetadata(tempoBpm: 98, timeSignature: '4/4');

      expect(metadata.toFirestore(), {'tempoBpm': 98, 'timeSignature': '4/4'});
    });
  });

  group('validateSetlistMusicMetadataInput', () {
    test('accepts valid values and normalizes output', () {
      final result = validateSetlistMusicMetadataInput(
        tempoBpmInput: '128',
        timeSignatureInput: ' 3 / 4 ',
        sectionMarkersInput: 'Intro, Verse, Chorus',
      );

      expect(result.isValid, isTrue);
      expect(result.metadata.tempoBpm, 128);
      expect(result.metadata.timeSignature, '3/4');
      expect(result.metadata.sectionMarkers, <String>[
        'Intro',
        'Verse',
        'Chorus',
      ]);
    });

    test('rejects tempo outside allowed range', () {
      final result = validateSetlistMusicMetadataInput(
        tempoBpmInput: '500',
        timeSignatureInput: '',
        sectionMarkersInput: '',
      );

      expect(result.isValid, isFalse);
      expect(result.tempoBpmError, contains('20~300'));
    });

    test('rejects invalid time signature format', () {
      final result = validateSetlistMusicMetadataInput(
        tempoBpmInput: '',
        timeSignatureInput: 'three four',
        sectionMarkersInput: '',
      );

      expect(result.isValid, isFalse);
      expect(result.timeSignatureError, isNotNull);
    });

    test('rejects oversized section marker input', () {
      final result = validateSetlistMusicMetadataInput(
        tempoBpmInput: '',
        timeSignatureInput: '',
        sectionMarkersInput: '${List.filled(33, 'A').join()}, Verse',
      );

      expect(result.isValid, isFalse);
      expect(result.sectionMarkersError, contains('32자'));
    });

    test('treats empty inputs as valid and omits metadata', () {
      final result = validateSetlistMusicMetadataInput(
        tempoBpmInput: '',
        timeSignatureInput: '',
        sectionMarkersInput: '',
      );

      expect(result.isValid, isTrue);
      expect(result.metadata.isEmpty, isTrue);
      expect(result.metadata.toFirestore(), isEmpty);
    });
  });
}
