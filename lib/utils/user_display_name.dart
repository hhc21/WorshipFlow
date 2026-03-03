String memberDisplayName(
  Map<String, dynamic>? data, {
  String fallback = '이름 미설정',
}) {
  if (data == null) return fallback;
  final nickname = (data['nickname'] ?? '').toString().trim();
  if (nickname.isNotEmpty) return nickname;
  final displayName = (data['displayName'] ?? '').toString().trim();
  if (displayName.isNotEmpty) return displayName;
  final email = (data['email'] ?? '').toString().trim();
  if (email.isNotEmpty) return email;
  return fallback;
}

String memberDisplayNameWithFallback(
  String? userId,
  Map<String, dynamic>? data, {
  String fallback = '이름 확인 중',
}) {
  final resolved = memberDisplayName(data, fallback: '');
  if (resolved.isNotEmpty) return resolved;
  if (userId != null && userId.trim().isNotEmpty) {
    // Never expose raw uid in UI. Keep backend id internal only.
    return fallback;
  }
  return fallback;
}
