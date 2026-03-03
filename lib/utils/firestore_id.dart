bool isValidFirestoreDocId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '.' || trimmed == '..') return false;
  if (trimmed.contains('/')) return false;
  return true;
}
