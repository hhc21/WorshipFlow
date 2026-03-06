bool isValidFirestoreDocId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '.' || trimmed == '..') return false;
  if (trimmed.contains('/')) return false;
  return true;
}

String privateProjectNoteDocIdV2(String projectId, String userId) {
  return 'v2__${projectId}__$userId';
}

String privateProjectNoteDocIdLegacy(String projectId, String userId) {
  return '${projectId}__$userId';
}
