import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/models/project_setlist_section_type.dart';

void main() {
  test('fromUnknown defaults missing or invalid values to worship', () {
    expect(
      ProjectSetlistSectionType.fromUnknown(null),
      ProjectSetlistSectionType.worship,
    );
    expect(
      ProjectSetlistSectionType.fromUnknown(''),
      ProjectSetlistSectionType.worship,
    );
    expect(
      ProjectSetlistSectionType.fromUnknown('unexpected'),
      ProjectSetlistSectionType.worship,
    );
  });

  test('fromUnknown parses firestore section type values', () {
    expect(
      ProjectSetlistSectionType.fromUnknown('worship'),
      ProjectSetlistSectionType.worship,
    );
    expect(
      ProjectSetlistSectionType.fromUnknown('sermon_response'),
      ProjectSetlistSectionType.sermonResponse,
    );
    expect(
      ProjectSetlistSectionType.fromUnknown('prayer'),
      ProjectSetlistSectionType.prayer,
    );
  });

  test('helpers expose canonical firestore and display values', () {
    expect(ProjectSetlistSectionType.worship.toFirestoreValue(), 'worship');
    expect(
      ProjectSetlistSectionType.sermonResponse.toFirestoreValue(),
      'sermon_response',
    );
    expect(ProjectSetlistSectionType.prayer.toFirestoreValue(), 'prayer');

    expect(ProjectSetlistSectionType.worship.displayLabel(), '찬양');
    expect(ProjectSetlistSectionType.sermonResponse.displayLabel(), '설교 응답');
    expect(ProjectSetlistSectionType.prayer.displayLabel(), '기도');
  });
}
