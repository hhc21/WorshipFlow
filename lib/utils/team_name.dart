String normalizeTeamName(String rawName) {
  var text = rawName.trim();
  if (text.isEmpty) return '';
  text = text.replaceAll('/', ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

String buildTeamNameKey(String rawName) {
  final normalized = normalizeTeamName(rawName).toLowerCase();
  if (normalized.isEmpty) return '';
  return Uri.encodeComponent(normalized);
}
