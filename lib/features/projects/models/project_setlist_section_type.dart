enum ProjectSetlistSectionType {
  worship,
  sermonResponse,
  prayer;

  static ProjectSetlistSectionType fromUnknown(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'sermon_response':
        return ProjectSetlistSectionType.sermonResponse;
      case 'prayer':
        return ProjectSetlistSectionType.prayer;
      case 'worship':
      default:
        return ProjectSetlistSectionType.worship;
    }
  }

  String toFirestoreValue() {
    switch (this) {
      case ProjectSetlistSectionType.worship:
        return 'worship';
      case ProjectSetlistSectionType.sermonResponse:
        return 'sermon_response';
      case ProjectSetlistSectionType.prayer:
        return 'prayer';
    }
  }

  String displayLabel() {
    switch (this) {
      case ProjectSetlistSectionType.worship:
        return '찬양';
      case ProjectSetlistSectionType.sermonResponse:
        return '설교 응답';
      case ProjectSetlistSectionType.prayer:
        return '기도';
    }
  }
}
