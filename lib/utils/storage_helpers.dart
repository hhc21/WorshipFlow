import 'dart:async';
import 'dart:collection';

import 'package:firebase_storage/firebase_storage.dart';

import 'browser_types.dart';

const int kMaxSongAssetBytes = 25 * 1024 * 1024;
const int _maxResolvedAssetUrlEntries = 256;
const Duration _assetDownloadUrlTimeout = Duration(seconds: 3);

final Map<String, String> _resolvedAssetUrlCache = <String, String>{};
final ListQueue<String> _resolvedAssetUrlCacheOrder = ListQueue<String>();

class AssetDownloadUrlResolution {
  final String url;
  final String source;
  final bool hadStoredUrl;
  final String? storagePath;

  const AssetDownloadUrlResolution({
    required this.url,
    required this.source,
    required this.hadStoredUrl,
    required this.storagePath,
  });
}

void _rememberResolvedAssetUrl(String cacheKey, String url) {
  _resolvedAssetUrlCache[cacheKey] = url;
  _resolvedAssetUrlCacheOrder.remove(cacheKey);
  _resolvedAssetUrlCacheOrder.addLast(cacheKey);
  while (_resolvedAssetUrlCacheOrder.length > _maxResolvedAssetUrlEntries) {
    final oldest = _resolvedAssetUrlCacheOrder.removeFirst();
    _resolvedAssetUrlCache.remove(oldest);
  }
}

Future<String?> _resolveFreshAssetDownloadUrl(
  FirebaseStorage storage,
  String path, {
  required String cacheKey,
  required int maxAttempts,
}) async {
  try {
    final url = await runWithRetry(
      () =>
          storage.ref(path).getDownloadURL().timeout(_assetDownloadUrlTimeout),
      maxAttempts: maxAttempts,
    );
    if (url.isNotEmpty) {
      _rememberResolvedAssetUrl(cacheKey, url);
      return url;
    }
  } catch (_) {
    // Fall through to caller-managed fallback handling.
  }
  return null;
}

String buildSongAssetStoragePath(String songId, String originalFileName) {
  final ext = _normalizedExtension(originalFileName);
  final dotIndex = originalFileName.lastIndexOf('.');
  final rawBase = dotIndex <= 0
      ? originalFileName
      : originalFileName.substring(0, dotIndex);
  final safeBase = _sanitizeFileName(rawBase);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return 'songs/$songId/${safeBase}_$timestamp$ext';
}

String? resolveSongAssetContentType({
  required String fileName,
  String? rawContentType,
}) {
  final raw = rawContentType?.trim().toLowerCase();
  if (raw != null && raw.isNotEmpty) {
    if (raw == 'application/pdf' || raw.startsWith('image/')) {
      return raw;
    }
    return null;
  }

  final ext = _normalizedExtension(fileName);
  switch (ext) {
    case '.pdf':
      return 'application/pdf';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.bmp':
      return 'image/bmp';
    case '.tif':
    case '.tiff':
      return 'image/tiff';
    default:
      return null;
  }
}

String explainStorageError(Object error, {String action = '요청'}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '$action 권한이 없습니다. Firebase 규칙과 로그인 상태를 확인해주세요.';
      case 'unauthenticated':
      case 'unauthorized':
        return '로그인이 만료되었습니다. 다시 로그인 후 시도해주세요.';
      case 'object-not-found':
        return '파일을 찾을 수 없습니다. 업로드 후 파일 경로를 다시 확인해주세요.';
      case 'canceled':
        return '$action이 취소되었습니다.';
      case 'retry-limit-exceeded':
        return '네트워크가 불안정합니다. 잠시 후 다시 시도해주세요.';
      case 'quota-exceeded':
        return '스토리지 사용량 한도를 초과했습니다. 요금제/사용량을 확인해주세요.';
      case 'invalid-argument':
        return '$action 파라미터가 올바르지 않습니다. 파일 형식/크기/경로를 확인해주세요.';
    }
  }

  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('size') && lower.contains('25')) {
    return '$action 실패: 파일 크기가 25MB 제한을 초과했습니다.';
  }
  if (lower.contains('cors') || lower.contains('access-control-allow-origin')) {
    return '$action 실패: 브라우저 CORS 차단이 발생했습니다. storage rules 게시와 버킷 CORS 설정을 확인해주세요.';
  }
  return '$action 실패: $raw';
}

String? validateSongAssetSelection({
  required BrowserFileSelection picked,
  required String? resolvedContentType,
}) {
  if (picked.bytes.isEmpty || picked.sizeBytes <= 0) {
    return '파일이 비어 있습니다. 다른 파일을 선택해주세요.';
  }
  if (picked.sizeBytes > kMaxSongAssetBytes) {
    return '파일 크기가 ${formatBytes(picked.sizeBytes)}입니다. 최대 25MB까지 업로드할 수 있습니다.';
  }
  if (resolvedContentType == null) {
    return '지원되지 않는 파일 형식입니다. PDF 또는 이미지 파일만 업로드할 수 있습니다.';
  }
  return null;
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final text = unitIndex == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text${units[unitIndex]}';
}

Future<T> runWithRetry<T>(
  Future<T> Function() task, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 250),
}) async {
  Object? lastError;
  StackTrace? lastStack;
  var delay = initialDelay;

  for (var i = 0; i < maxAttempts; i++) {
    try {
      return await task();
    } catch (error, stack) {
      lastError = error;
      lastStack = stack;
      if (i == maxAttempts - 1) break;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }

  Error.throwWithStackTrace(lastError!, lastStack!);
}

Future<String?> resolveAssetDownloadUrl(
  FirebaseStorage storage,
  Map<String, dynamic> assetData,
) async {
  final resolved = await resolveAssetDownloadUrlWithMeta(storage, assetData);
  return resolved?.url;
}

Future<AssetDownloadUrlResolution?> resolveAssetDownloadUrlWithMeta(
  FirebaseStorage storage,
  Map<String, dynamic> assetData, {
  bool preferStoredUrlForFirstRender = false,
}) async {
  final path = assetData['storagePath']?.toString().trim();
  final storedUrl = assetData['downloadUrl']?.toString().trim();
  final hasStoredUrl = storedUrl != null && storedUrl.isNotEmpty;
  if (path != null && path.isNotEmpty) {
    final cacheKey = 'path:$path';
    final cached = _resolvedAssetUrlCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return AssetDownloadUrlResolution(
        url: cached,
        source: 'cache',
        hadStoredUrl: hasStoredUrl,
        storagePath: path,
      );
    }

    if (preferStoredUrlForFirstRender && hasStoredUrl) {
      unawaited(
        _resolveFreshAssetDownloadUrl(
          storage,
          path,
          cacheKey: cacheKey,
          maxAttempts: 2,
        ),
      );
      return AssetDownloadUrlResolution(
        url: storedUrl,
        source: 'stored_fast_path',
        hadStoredUrl: true,
        storagePath: path,
      );
    }

    final freshUrl = await _resolveFreshAssetDownloadUrl(
      storage,
      path,
      cacheKey: cacheKey,
      maxAttempts: storedUrl != null && storedUrl.isNotEmpty ? 1 : 2,
    );
    if (freshUrl != null && freshUrl.isNotEmpty) {
      return AssetDownloadUrlResolution(
        url: freshUrl,
        source: 'fresh',
        hadStoredUrl: hasStoredUrl,
        storagePath: path,
      );
    }

    // If a previously stored download URL exists, return it immediately for
    // first useful render and refresh the cache in the background.
    if (storedUrl != null && storedUrl.isNotEmpty) {
      unawaited(
        _resolveFreshAssetDownloadUrl(
          storage,
          path,
          cacheKey: cacheKey,
          maxAttempts: 2,
        ),
      );
      return AssetDownloadUrlResolution(
        url: storedUrl,
        source: 'stored_refresh_fallback',
        hadStoredUrl: true,
        storagePath: path,
      );
    }
  }
  if (storedUrl != null && storedUrl.isNotEmpty) {
    return AssetDownloadUrlResolution(
      url: storedUrl,
      source: 'stored_only',
      hadStoredUrl: true,
      storagePath: path,
    );
  }
  return null;
}

String _sanitizeFileName(String value) {
  final collapsed = value
      .trim()
      .replaceAll(RegExp(r'[^0-9A-Za-z._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (collapsed.isEmpty) {
    return 'asset';
  }
  return collapsed;
}

String _normalizedExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
    return '';
  }
  final ext = fileName.substring(dotIndex).toLowerCase();
  if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext)) {
    return '';
  }
  return ext;
}
