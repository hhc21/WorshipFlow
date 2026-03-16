part of 'live_cue_page.dart';

Future<_LiveCueAssetPreview?> _loadCurrentPreview(
  FirebaseFirestore firestore,
  FirebaseStorage storage,
  String teamId,
  String? songId,
  String? keyText,
  String? fallbackTitle,
  bool preferStoredUrlForFirstRender,
  int? pageVisibleAtEpochMs,
) async {
  final totalStopwatch = Stopwatch()..start();
  final resolverStopwatch = Stopwatch()..start();
  final songIdCandidates = await _songIdCandidatesForPreview(
    firestore,
    teamId,
    songId,
    keyText,
    fallbackTitle,
  );
  resolverStopwatch.stop();
  if (songIdCandidates.isEmpty) {
    OpsMetrics.emit(
      'livecue_preview_selection',
      fields: <String, Object?>{
        'status': 'no_song_candidates',
        'resolverMs': resolverStopwatch.elapsedMilliseconds,
        if (pageVisibleAtEpochMs != null)
          'sincePageVisibleMs':
              DateTime.now().millisecondsSinceEpoch - pageVisibleAtEpochMs,
        'fallbackTitle': fallbackTitle,
        'songId': songId,
      },
    );
    return null;
  }
  final normalizedKey = (keyText == null || keyText.trim().isEmpty)
      ? null
      : normalizeKeyText(keyText);
  var assetQueryElapsedMs = 0;
  var totalAssetDocsRead = 0;

  for (final candidateSongId in songIdCandidates) {
    final assetQuery = await _queryLiveCuePreviewAssets(
      firestore,
      candidateSongId,
      normalizedKey,
    );
    assetQueryElapsedMs += assetQuery.elapsedMs;
    totalAssetDocsRead += assetQuery.docCount;
    if (assetQuery.docs.isEmpty) continue;

    final activeAssets = assetQuery.docs
        .where((doc) => doc.data()['active'] != false)
        .toList();
    final sourceAssets = activeAssets.isNotEmpty
        ? activeAssets
        : assetQuery.docs;

    final candidates = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (normalizedKey != null) {
      for (final doc in sourceAssets) {
        if (isAssetKeyMatch(doc.data(), normalizedKey)) {
          candidates.add(doc);
        }
      }
    }
    for (final doc in sourceAssets) {
      if (!candidates.contains(doc)) {
        candidates.add(doc);
      }
    }

    for (final selected in candidates) {
      final data = selected.data();
      final rawPath = data['storagePath']?.toString().trim() ?? '';
      final path = rawPath.isEmpty ? null : rawPath;
      final previewIdentity = path ?? 'legacy:$candidateSongId:${selected.id}';
      try {
        final urlResolution = await resolveAssetDownloadUrlWithMeta(
          storage,
          data,
          preferStoredUrlForFirstRender: preferStoredUrlForFirstRender,
        );
        final url = urlResolution?.url;
        if (url == null || url.isEmpty || urlResolution == null) {
          continue;
        }
        final contentType = data['contentType']?.toString().toLowerCase() ?? '';
        final fileName = data['fileName']?.toString().toLowerCase() ?? '';
        final isImage =
            contentType.startsWith('image/') ||
            fileName.endsWith('.png') ||
            fileName.endsWith('.jpg') ||
            fileName.endsWith('.jpeg') ||
            fileName.endsWith('.webp');

        final preview = _LiveCueAssetPreview(
          url: url,
          isImage: isImage,
          fileName: data['fileName']?.toString() ?? 'asset',
          storagePath: previewIdentity,
          resolvedSongId: candidateSongId,
          initialBytes: null,
          resolverElapsedMs: resolverStopwatch.elapsedMilliseconds,
          assetQueryElapsedMs: assetQueryElapsedMs,
          selectionElapsedMs: totalStopwatch.elapsedMilliseconds,
          urlSource: urlResolution.source,
          assetDocCount: totalAssetDocsRead,
          usedLimitedAssetQuery: assetQuery.usedLimitedQuery,
          selectedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        OpsMetrics.emit(
          'livecue_preview_selection',
          fields: <String, Object?>{
            'status': 'selected',
            'resolverMs': preview.resolverElapsedMs,
            'assetQueryMs': preview.assetQueryElapsedMs,
            'selectionMs': preview.selectionElapsedMs,
            if (pageVisibleAtEpochMs != null)
              'sincePageVisibleMs':
                  DateTime.now().millisecondsSinceEpoch - pageVisibleAtEpochMs,
            'urlSource': preview.urlSource,
            'songCandidateCount': songIdCandidates.length,
            'assetDocCount': preview.assetDocCount,
            'usedLimitedAssetQuery': preview.usedLimitedAssetQuery,
            'resolvedSongId': preview.resolvedSongId,
            'fileName': preview.fileName,
            'normalizedKey': normalizedKey,
          },
        );
        return preview;
      } catch (_) {
        continue;
      }
    }
  }

  OpsMetrics.emit(
    'livecue_preview_selection',
    fields: <String, Object?>{
      'status': 'no_asset_selected',
      'resolverMs': resolverStopwatch.elapsedMilliseconds,
      'assetQueryMs': assetQueryElapsedMs,
      'selectionMs': totalStopwatch.elapsedMilliseconds,
      if (pageVisibleAtEpochMs != null)
        'sincePageVisibleMs':
            DateTime.now().millisecondsSinceEpoch - pageVisibleAtEpochMs,
      'songCandidateCount': songIdCandidates.length,
      'assetDocCount': totalAssetDocsRead,
      'fallbackTitle': fallbackTitle,
      'songId': songId,
      'normalizedKey': normalizedKey,
    },
  );
  return null;
}

const int _liveCuePreviewHeadLimit = 6;

class _LiveCueMetadataSummary {
  final String? tempoText;
  final String? timeSignatureText;
  final String? sectionsText;

  const _LiveCueMetadataSummary({
    this.tempoText,
    this.timeSignatureText,
    this.sectionsText,
  });

  bool get hasMetadata =>
      (tempoText != null && tempoText!.isNotEmpty) ||
      (timeSignatureText != null && timeSignatureText!.isNotEmpty) ||
      (sectionsText != null && sectionsText!.isNotEmpty);
}

SetlistMusicMetadata? _extractMetadataFromItem(Map<String, dynamic>? item) {
  if (item == null || item.isEmpty) return null;
  final raw = item['musicMetadata'];
  if (raw == null) return null;
  final metadata = SetlistMusicMetadata.fromUnknown(raw);
  return metadata.isEmpty ? null : metadata;
}

String? _formatTempo(int? tempoBpm) {
  if (tempoBpm == null) return null;
  return '$tempoBpm BPM';
}

String? _formatTimeSignature(String? timeSignature) {
  final value = timeSignature?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

String? _formatSections(List<String>? sections) {
  if (sections == null || sections.isEmpty) return null;
  final normalized = sections
      .map((section) => section.trim())
      .where((section) => section.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) return null;
  return normalized.join(' • ');
}

_LiveCueMetadataSummary _buildMetadataSummary(SetlistMusicMetadata? metadata) {
  if (metadata == null || metadata.isEmpty) {
    return const _LiveCueMetadataSummary();
  }
  return _LiveCueMetadataSummary(
    tempoText: _formatTempo(metadata.tempoBpm),
    timeSignatureText: _formatTimeSignature(metadata.timeSignature),
    sectionsText: _formatSections(metadata.sectionMarkers),
  );
}

Widget _buildLiveCueOperatorMetadataBlock(
  BuildContext context,
  _LiveCueMetadataSummary summary,
) {
  if (!summary.hasMetadata) return const SizedBox.shrink();
  final textStyle = Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (summary.tempoText != null)
        Text('Tempo: ${summary.tempoText}', style: textStyle),
      if (summary.timeSignatureText != null)
        Text('Time Signature: ${summary.timeSignatureText}', style: textStyle),
      if (summary.sectionsText != null)
        Text('Sections: ${summary.sectionsText}', style: textStyle),
    ],
  );
}

Widget _buildLiveCueFullscreenMetadataBlock(_LiveCueMetadataSummary summary) {
  if (!summary.hasMetadata) return const SizedBox.shrink();
  final primaryParts = <String>[
    if (summary.tempoText != null) summary.tempoText!,
    if (summary.timeSignatureText != null) summary.timeSignatureText!,
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (primaryParts.isNotEmpty)
        Text(
          primaryParts.join(' • '),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      if (summary.sectionsText != null)
        Text(
          summary.sectionsText!,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
    ],
  );
}

class _LiveCuePreviewAssetQueryResult {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final int elapsedMs;
  final int docCount;
  final bool usedLimitedQuery;

  const _LiveCuePreviewAssetQueryResult({
    required this.docs,
    required this.elapsedMs,
    required this.docCount,
    required this.usedLimitedQuery,
  });
}

Future<_LiveCuePreviewAssetQueryResult> _queryLiveCuePreviewAssets(
  FirebaseFirestore firestore,
  String songId,
  String? normalizedKey,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    final baseQuery = firestore
        .collection('songs')
        .doc(songId)
        .collection('assets')
        .orderBy('createdAt', descending: true);
    final headSnapshot = await baseQuery.limit(_liveCuePreviewHeadLimit).get();
    final headDocs = headSnapshot.docs;
    final shouldRunFullQuery =
        normalizedKey != null &&
        headDocs.length == _liveCuePreviewHeadLimit &&
        headDocs.every((doc) => !isAssetKeyMatch(doc.data(), normalizedKey));
    if (!shouldRunFullQuery) {
      stopwatch.stop();
      return _LiveCuePreviewAssetQueryResult(
        docs: headDocs,
        elapsedMs: stopwatch.elapsedMilliseconds,
        docCount: headDocs.length,
        usedLimitedQuery: true,
      );
    }
    final fullSnapshot = await baseQuery.get();
    stopwatch.stop();
    return _LiveCuePreviewAssetQueryResult(
      docs: fullSnapshot.docs,
      elapsedMs: stopwatch.elapsedMilliseconds,
      docCount: fullSnapshot.docs.length,
      usedLimitedQuery: false,
    );
  } catch (_) {
    stopwatch.stop();
    return const _LiveCuePreviewAssetQueryResult(
      docs: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      elapsedMs: 0,
      docCount: 0,
      usedLimitedQuery: true,
    );
  }
}

typedef _LiveCuePreviewLoader =
    Future<_LiveCueAssetPreview?> Function(
      String songId,
      String? keyText,
      String? fallbackTitle,
    );

class _LiveCueRenderPresenter {
  static const int _maxResolvedPreviewEntries = 28;
  static const int _maxPrefetchedPreviewEntries = 40;
  static final Map<String, Future<_LiveCueAssetPreview?>> _sharedPreviewCache =
      <String, Future<_LiveCueAssetPreview?>>{};
  static final Map<String, _LiveCueAssetPreview> _sharedResolvedPreviewCache =
      <String, _LiveCueAssetPreview>{};
  static final Set<String> _sharedPrefetchedPreviewKeys = <String>{};
  static final Set<String> _sharedQueuedPrefetchKeys = <String>{};
  static final ListQueue<String> _sharedPreviewCacheOrder = ListQueue<String>();
  static final ListQueue<String> _sharedPrefetchCacheOrder =
      ListQueue<String>();

  final bool isWeb;
  final TransformationController viewerController = TransformationController();

  bool showOverlay = true;
  Timer? _overlayTimer;
  bool useNextViewer;
  bool _fallbackToHtmlImageElement = false;
  bool _switchingImageRenderer = false;
  String? _activeViewerAssetKey;
  String? _activeImageRendererKey;

  _LiveCueRenderPresenter({
    required this.isWeb,
    required bool initialUseNextViewer,
  }) : useNextViewer = initialUseNextViewer;

  bool get canUseNextViewer => isWeb && useNextViewer;
  bool get fallbackToHtmlImageElement => _fallbackToHtmlImageElement;
  bool get switchingImageRenderer => _switchingImageRenderer;

  _LiveCueAssetPreview? cachedPreview(String cacheKey) =>
      _sharedResolvedPreviewCache[cacheKey];

  void dispose() {
    _overlayTimer?.cancel();
    viewerController.dispose();
  }

  String previewCacheKey(
    String songId,
    String? keyText,
    String? fallbackTitle,
  ) {
    final normalized = (keyText == null || keyText.trim().isEmpty)
        ? '-'
        : normalizeKeyText(keyText);
    final normalizedFallback =
        (fallbackTitle == null || fallbackTitle.trim().isEmpty)
        ? '-'
        : normalizeQuery(fallbackTitle);
    return '$songId::$normalized::$normalizedFallback';
  }

  Future<_LiveCueAssetPreview?> loadPreviewCached({
    required String? songId,
    required String? keyText,
    required String? fallbackTitle,
    required _LiveCuePreviewLoader loader,
  }) {
    final safeSongId = songId?.trim() ?? '';
    final safeTitle = fallbackTitle?.trim() ?? '';
    if (safeSongId.isEmpty && safeTitle.isEmpty) {
      return Future.value(null);
    }
    final cacheKey = previewCacheKey(safeSongId, keyText, safeTitle);
    final existing = _sharedPreviewCache[cacheKey];
    if (existing != null) return existing;
    final future = loader(safeSongId, keyText, safeTitle)
        .then((preview) {
          if (preview == null) {
            _sharedPreviewCache.remove(cacheKey);
            _sharedResolvedPreviewCache.remove(cacheKey);
            _sharedPreviewCacheOrder.remove(cacheKey);
          } else {
            _sharedResolvedPreviewCache[cacheKey] = preview;
            _rememberResolvedPreview(cacheKey);
          }
          return preview;
        })
        .catchError((error, stackTrace) {
          _sharedPreviewCache.remove(cacheKey);
          _sharedResolvedPreviewCache.remove(cacheKey);
          _sharedPreviewCacheOrder.remove(cacheKey);
          throw error;
        });
    _sharedPreviewCache[cacheKey] = future;
    return future;
  }

  void evictPreviewCache(
    String songId,
    String? keyText,
    String? fallbackTitle,
  ) {
    final cacheKey = previewCacheKey(songId, keyText, fallbackTitle);
    _sharedPreviewCache.remove(cacheKey);
    _sharedResolvedPreviewCache.remove(cacheKey);
    _sharedPrefetchedPreviewKeys.remove(cacheKey);
    _sharedQueuedPrefetchKeys.remove(cacheKey);
    _sharedPreviewCacheOrder.remove(cacheKey);
    _sharedPrefetchCacheOrder.remove(cacheKey);
  }

  void ensureViewerAssetKey(String key) {
    if (_activeViewerAssetKey == key) return;
    _activeViewerAssetKey = key;
    viewerController.value = Matrix4.identity();
  }

  void syncImageRendererKey(String key) {
    if (_activeImageRendererKey == key) return;
    _activeImageRendererKey = key;
    resetHtmlImageFallback();
  }

  void resetHtmlImageFallback() {
    _fallbackToHtmlImageElement = false;
    _switchingImageRenderer = false;
  }

  bool tryActivateHtmlImageFallback({
    required bool hasInitialBytes,
    required bool drawingEnabled,
    required bool Function() isMounted,
    required VoidCallback requestRebuild,
  }) {
    if (!isWeb ||
        hasInitialBytes ||
        drawingEnabled ||
        _fallbackToHtmlImageElement ||
        _switchingImageRenderer) {
      return false;
    }
    _switchingImageRenderer = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) return;
      _fallbackToHtmlImageElement = true;
      _switchingImageRenderer = false;
      requestRebuild();
    });
    return true;
  }

  Future<_LiveCueAssetPreview?> warmPreview({
    required String? songId,
    required String? keyText,
    required String? fallbackTitle,
    required BuildContext context,
    required bool Function() isMounted,
    required _LiveCuePreviewLoader loader,
  }) {
    final safeSongId = songId?.trim() ?? '';
    final safeTitle = fallbackTitle?.trim() ?? '';
    if (safeSongId.isEmpty && safeTitle.isEmpty) {
      return Future<_LiveCueAssetPreview?>.value(null);
    }
    final cacheKey = previewCacheKey(safeSongId, keyText, safeTitle);
    final previewFuture = loadPreviewCached(
      songId: safeSongId,
      keyText: keyText,
      fallbackTitle: safeTitle,
      loader: loader,
    );
    _queuePreviewPrefetch(
      cacheKey: cacheKey,
      previewFuture: previewFuture,
      context: context,
      isMounted: isMounted,
    );
    return previewFuture;
  }

  void _queuePreviewPrefetch({
    required String cacheKey,
    required Future<_LiveCueAssetPreview?> previewFuture,
    required BuildContext context,
    required bool Function() isMounted,
  }) {
    if (_sharedPrefetchedPreviewKeys.contains(cacheKey)) return;
    if (!_sharedQueuedPrefetchKeys.add(cacheKey)) return;
    unawaited(
      previewFuture
          .then((preview) {
            if (!isMounted() || preview == null || !preview.isImage) return;
            final bytes = preview.initialBytes;
            if ((bytes == null || bytes.isEmpty) && isWeb) {
              return;
            }
            if (!context.mounted) return;
            final ImageProvider<Object> provider =
                bytes != null && bytes.isNotEmpty
                ? MemoryImage(bytes)
                : NetworkImage(preview.url);
            unawaited(precacheImage(provider, context));
            _rememberPrefetchedPreview(cacheKey);
          })
          .catchError((_) {
            // Prefetch is best effort only.
          })
          .whenComplete(() {
            _sharedQueuedPrefetchKeys.remove(cacheKey);
          }),
    );
  }

  void _rememberResolvedPreview(String cacheKey) {
    _sharedPreviewCacheOrder.remove(cacheKey);
    _sharedPreviewCacheOrder.addLast(cacheKey);
    while (_sharedPreviewCacheOrder.length > _maxResolvedPreviewEntries) {
      final oldest = _sharedPreviewCacheOrder.removeFirst();
      _sharedPreviewCache.remove(oldest);
      _sharedResolvedPreviewCache.remove(oldest);
      _sharedPrefetchedPreviewKeys.remove(oldest);
      _sharedQueuedPrefetchKeys.remove(oldest);
      _sharedPrefetchCacheOrder.remove(oldest);
    }
  }

  void _rememberPrefetchedPreview(String cacheKey) {
    _sharedPrefetchCacheOrder.remove(cacheKey);
    _sharedPrefetchCacheOrder.addLast(cacheKey);
    _sharedPrefetchedPreviewKeys.add(cacheKey);
    while (_sharedPrefetchCacheOrder.length > _maxPrefetchedPreviewEntries) {
      final oldest = _sharedPrefetchCacheOrder.removeFirst();
      _sharedPrefetchedPreviewKeys.remove(oldest);
    }
  }

  void cancelOverlayAutoHide() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
  }

  void scheduleOverlayAutoHide({
    required bool drawingEnabled,
    required bool Function() isMounted,
    required VoidCallback requestRebuild,
  }) {
    if (drawingEnabled) return;
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (!isMounted() || !showOverlay) return;
      showOverlay = false;
      requestRebuild();
    });
  }

  void showOverlayTemporarily({
    required bool drawingEnabled,
    required bool Function() isMounted,
    required VoidCallback requestRebuild,
  }) {
    final shouldRebuild = !showOverlay;
    showOverlay = true;
    if (shouldRebuild) {
      requestRebuild();
    }
    scheduleOverlayAutoHide(
      drawingEnabled: drawingEnabled,
      isMounted: isMounted,
      requestRebuild: requestRebuild,
    );
  }

  void toggleOverlay({
    required bool drawingEnabled,
    required bool Function() isMounted,
    required VoidCallback requestRebuild,
  }) {
    if (drawingEnabled) return;
    if (showOverlay) {
      cancelOverlayAutoHide();
      showOverlay = false;
      requestRebuild();
      return;
    }
    showOverlay = true;
    requestRebuild();
    scheduleOverlayAutoHide(
      drawingEnabled: drawingEnabled,
      isMounted: isMounted,
      requestRebuild: requestRebuild,
    );
  }
}

class _LiveCueContext {
  final DocumentSnapshot<Map<String, dynamic>> project;
  final DocumentSnapshot<Map<String, dynamic>> member;
  final bool isTeamCreator;

  const _LiveCueContext({
    required this.project,
    required this.member,
    required this.isTeamCreator,
  });
}

class _LiveCueAssetPreview {
  final String url;
  final bool isImage;
  final String fileName;
  final String storagePath;
  final String? resolvedSongId;
  final Uint8List? initialBytes;
  final int resolverElapsedMs;
  final int assetQueryElapsedMs;
  final int selectionElapsedMs;
  final String urlSource;
  final int assetDocCount;
  final bool usedLimitedAssetQuery;
  final int selectedAtEpochMs;

  const _LiveCueAssetPreview({
    required this.url,
    required this.isImage,
    required this.fileName,
    required this.storagePath,
    this.resolvedSongId,
    this.initialBytes,
    this.resolverElapsedMs = 0,
    this.assetQueryElapsedMs = 0,
    this.selectionElapsedMs = 0,
    this.urlSource = 'unknown',
    this.assetDocCount = 0,
    this.usedLimitedAssetQuery = true,
    this.selectedAtEpochMs = 0,
  });
}

class _LiveCueSketchPainter extends CustomPainter {
  final List<SketchStroke> Function() strokesProvider;

  _LiveCueSketchPainter({required this.strokesProvider, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = strokesProvider();
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.colorValue)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        final point = Offset(
          stroke.points.first.dx * size.width,
          stroke.points.first.dy * size.height,
        );
        final dotPaint = Paint()
          ..color = Color(stroke.colorValue)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, stroke.width * 0.55, dotPaint);
        continue;
      }

      final path = Path();
      final first = Offset(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      path.moveTo(first.dx, first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveCueSketchPainter oldDelegate) {
    return oldDelegate.strokesProvider != strokesProvider;
  }
}
