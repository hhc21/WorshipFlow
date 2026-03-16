part of 'live_cue_page.dart';

Widget _buildLiveCuePendingSyncPreview({
  required _LiveCueFullScreenPageState state,
  required FirebaseFirestore firestore,
  required FirebaseStorage storage,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  required Map<String, dynamic> cueData,
}) {
  final renderPresenter = state._renderPresenter;
  final emitFirstPreviewBeforeSyncMetric =
      state._emitFirstPreviewBeforeSyncMetric;
  final previewCacheKey = state._previewCacheKey;
  final loadPreviewCached = state._loadPreviewCached;
  final emitViewerReadyMetric = state._emitViewerReadyMetric;
  final emitPreviewVisibleMetric = state._emitPreviewVisibleMetric;
  final handleBackNavigation = state._handleBackNavigation;
  final syncState = LiveCueResolvedState.resolve(
    items: items,
    cueData: cueData,
    cueLabelFromItem: _cueLabelFromItem,
    titleFromItem: _titleFromItem,
    keyFromItem: _keyFromItem,
    normalizeKeyText: normalizeKeyText,
  );
  final currentSongId = syncState.currentSongId;
  final currentTitle = syncState.currentTitle;
  final currentKey = syncState.currentKey;
  final currentLabel = syncState.currentLabel;
  final currentPreviewTitle = syncState.setlistCurrentTitle.isNotEmpty
      ? syncState.setlistCurrentTitle
      : currentTitle;
  emitFirstPreviewBeforeSyncMetric(
    songId: currentSongId,
    keyText: currentKey,
    title: currentPreviewTitle,
  );
  final currentPreviewCacheKey = previewCacheKey(
    currentSongId?.trim() ?? '',
    currentKey,
    currentPreviewTitle,
  );
  final cachedCurrentPreview = renderPresenter.cachedPreview(
    currentPreviewCacheKey,
  );

  return Stack(
    fit: StackFit.expand,
    children: [
      FutureBuilder<_LiveCueAssetPreview?>(
        future: loadPreviewCached(
          firestore,
          storage,
          currentSongId,
          currentKey,
          currentPreviewTitle,
        ),
        builder: (context, previewSnapshot) {
          final preview = previewSnapshot.data ?? cachedCurrentPreview;
          if (preview == null) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          emitViewerReadyMetric(
            'flutter-before-sync:$currentPreviewCacheKey',
            preview,
            renderer: 'flutter_before_sync',
          );
          if (!preview.isImage) {
            return Center(
              child: Text(
                '악보 준비 중... (${_lineText(label: currentLabel, title: currentTitle, keyText: currentKey)})',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          final bytes = preview.initialBytes;
          final imageWidget = bytes != null && bytes.isNotEmpty
              ? Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!state.mounted) return;
                            emitPreviewVisibleMetric(
                              currentPreviewCacheKey,
                              preview,
                            );
                          });
                        }
                        return child;
                      },
                )
              : Image.network(
                  preview.url,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      emitPreviewVisibleMetric(currentPreviewCacheKey, preview);
                      return child;
                    }
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stack) => Center(
                    child: Text(
                      '악보 로드 실패: ${preview.fileName}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
          return Center(child: imageWidget);
        },
      ),
      Positioned(
        top: 8,
        left: 8,
        child: IconButton(
          style: IconButton.styleFrom(backgroundColor: Colors.black54),
          onPressed: handleBackNavigation,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      Positioned(
        top: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'LiveCue 동기화 중... 미리보기 먼저 표시',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

Widget _buildLiveCueFullScreenPage(
  _LiveCueFullScreenPageState state,
  BuildContext context,
) {
  final ref = state.ref;
  final widget = state.widget;
  final pageVisibleAtEpochMs = state._pageVisibleAtEpochMs;
  final noteLayersLoaded = state._noteLayersLoaded;
  final loadingNoteLayers = state._loadingNoteLayers;
  final ensureContextFuture = state._ensureContextFuture;
  final ensureNoteLayersLoaded = state._ensureNoteLayersLoaded;
  final ensureBootstrapPreviewSeed = state._ensureBootstrapPreviewSeed;
  final syncCoordinator = state._syncCoordinator;
  final bootstrapPreviewReady = state._bootstrapPreviewReady;
  final bootstrapSetlist = state._bootstrapSetlist;
  final bootstrapCueData = state._bootstrapCueData;
  final buildPendingSyncPreview = state._buildPendingSyncPreview;
  final beginCueWaitingWatchdog = state._beginCueWaitingWatchdog;
  final isCueWaitingTimedOut = state._isCueWaitingTimedOut;
  final cueAutoRetryAttempted = state._cueAutoRetryAttempted;
  final scheduleCueAutoRetry = state._scheduleCueAutoRetry;
  final retryCueSync = state._retryCueSync;
  final clearCueWaitingWatchdog = state._clearCueWaitingWatchdog;
  final resetCueRetryState = state._resetCueRetryState;
  final previewCacheKey = state._previewCacheKey;
  final renderPresenter = state._renderPresenter;
  final warmScoreTripletIfNeeded = state._warmScoreTripletIfNeeded;
  final drawingEnabled = state._drawingEnabled;
  final toggleOverlay = state._toggleOverlay;
  final viewerRevision = state._viewerRevision;
  final showOverlayTemporarily = state._showOverlayTemporarily;
  final ensureViewerAssetKey = state._ensureViewerAssetKey;
  final syncImageRendererKey = state._syncImageRendererKey;
  final fallbackToHtmlImageElement = state._fallbackToHtmlImageElement;
  final retryPreviewWithFreshUrl = state._retryPreviewWithFreshUrl;
  final emitPreviewVisibleMetric = state._emitPreviewVisibleMetric;
  final strokeEngine = state._strokeEngine;
  final privateLayerStrokes = state._privateLayerStrokes;
  final sharedLayerStrokes = state._sharedLayerStrokes;
  final handleDrawingPointerDown = state._handleDrawingPointerDown;
  final handleDrawingPointerMove = state._handleDrawingPointerMove;
  final handleDrawingPointerUpOrCancel = state._handleDrawingPointerUpOrCancel;
  final useNextViewer = state._useNextViewer;
  final viewerIdToken = state._viewerIdToken;
  final emitViewerReadyMetric = state._emitViewerReadyMetric;
  final editingSharedLayer = state._editingSharedLayer;
  final overlayRevision = state._overlayRevision;
  final showOverlay = state._showOverlay;
  final showDrawingToolPanel = state._showDrawingToolPanel;
  final toggleDrawingToolPanel = state._toggleDrawingToolPanel;
  final setDrawingEnabled = state._setDrawingEnabled;
  final setEditingSharedLayer = state._setEditingSharedLayer;
  final eraserEnabled = state._eraserEnabled;
  final setEraserEnabled = state._setEraserEnabled;
  final setLayerVisibility = state._setLayerVisibility;
  final savingNoteLayers = state._savingNoteLayers;
  final saveLayerNotes = state._saveLayerNotes;
  final setDrawingColorValue = state._setDrawingColorValue;
  final drawingColorValue = state._drawingColorValue;
  final drawingStrokeWidth = state._drawingStrokeWidth;
  final setDrawingStrokeWidth = state._setDrawingStrokeWidth;
  final undoLayerStroke = state._undoLayerStroke;
  final clearLayerStroke = state._clearLayerStroke;
  final markViewerNeedsBuild = state._markViewerNeedsBuild;
  final markOverlayNeedsBuild = state._markOverlayNeedsBuild;
  final focusNode = state._focusNode;
  final canRenderPreviewBeforeSync = state._canRenderPreviewBeforeSync;
  final seedFromSetlistIfNeeded = state._seedFromSetlistIfNeeded;
  final moveByStep = state._moveByStep;
  final loadPreviewCached = state._loadPreviewCached;
  final evictPreviewCache = state._evictPreviewCache;
  final forceFreshPreviewCacheKeys = state._forceFreshPreviewCacheKeys;
  final requestRenderPresenterRebuild = state._requestRenderPresenterRebuild;
  final overlayStrokesForRender = state._overlayStrokesForRender;
  final strokeRevision = state._strokeRevision;
  final viewerController = state._viewerController;
  final nextViewerInitAppliedKeys = state._nextViewerInitAppliedKeys;
  final nextViewerWillReadFrequently = state._nextViewerWillReadFrequently;
  final onNextViewerInkCommit = state._onNextViewerInkCommit;
  final onNextViewerDirtyChanged = state._onNextViewerDirtyChanged;
  final onNextViewerAssetError = state._onNextViewerAssetError;
  final onNextViewerProtocolLog = state._onNextViewerProtocolLog;
  final toolRevision = state._toolRevision;
  final handleBackNavigation = state._handleBackNavigation;
  final loadAvailableKeysCached = state._loadAvailableKeysCached;
  final setCurrentKey = state._setCurrentKey;
  final showPrivateLayer = state._showPrivateLayer;
  final showSharedLayer = state._showSharedLayer;
  final nextViewerStatus = state._nextViewerStatus;
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) {
    return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
  }

  final firestore = ref.watch(firestoreProvider);
  final storage = ref.watch(storageProvider);
  final notePersistence = LiveCueNotePersistenceAdapter(
    firestore: firestore,
    teamId: widget.teamId,
    projectId: widget.projectId,
  );

  return FutureBuilder<_LiveCueContext>(
    future: ensureContextFuture(firestore, user.uid),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final contextData = snapshot.data;
      if (contextData == null || contextData.project.data() == null) {
        return const Scaffold(body: Center(child: Text('프로젝트를 찾을 수 없습니다.')));
      }
      if (!state._contextReadyMetricEmitted) {
        state._contextReadyMetricEmitted = true;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        OpsMetrics.emit(
          'livecue_context_ready',
          fields: <String, Object?>{
            'teamId': widget.teamId,
            'projectId': widget.projectId,
            'sinceEntryMs': nowMs - widget.entryStartedAtEpochMs,
            if (pageVisibleAtEpochMs != null)
              'sincePageVisibleMs': nowMs - pageVisibleAtEpochMs,
          },
        );
      }
      if (!contextData.member.exists && !contextData.isTeamCreator) {
        return Scaffold(
          body: Center(
            child: AppStateCard(
              icon: Icons.lock_outline_rounded,
              isError: true,
              title: '악보보기 접근 권한이 없습니다',
              message: '이 팀의 멤버만 LiveCue 악보보기에 접근할 수 있습니다.',
              actionLabel: '팀 목록으로',
              onAction: () => context.go('/teams'),
            ),
          ),
        );
      }

      final projectData = contextData.project.data()!;
      final leaderId = projectData['leaderUserId']?.toString();
      final role = contextData.member.data()?['role']?.toString();
      final canEdit =
          leaderId == user.uid ||
          isAdminRole(role) ||
          contextData.isTeamCreator;
      final noteLayersKey = '${widget.teamId}/${widget.projectId}/${user.uid}';
      if ((!noteLayersLoaded || state._noteLayersKey != noteLayersKey) &&
          !loadingNoteLayers) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!state.mounted) return;
          ensureNoteLayersLoaded(notePersistence, user.uid);
        });
      }

      final setlistRef = _setlistRefFor(
        firestore,
        widget.teamId,
        widget.projectId,
      );
      ensureBootstrapPreviewSeed(firestore);
      final liveCueRef = _liveCueRefFor(
        firestore,
        widget.teamId,
        widget.projectId,
      );
      final setlistQuery = setlistRef.orderBy('order');
      final syncStreams = syncCoordinator.attach(
        setlistQuery: setlistQuery,
        liveCueRef: liveCueRef,
      );
      final setlistStream = syncStreams.setlist;
      final cueStream = syncStreams.cue;

      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Focus(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (!canEdit ||
                  !state._syncReadyMetricEmitted ||
                  event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              if (state._latestSetlist.isEmpty) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.keyA) {
                moveByStep(
                  firestore,
                  canEdit,
                  state._latestSetlist,
                  state._latestCueData,
                  -1,
                );
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  event.logicalKey == LogicalKeyboardKey.keyD) {
                moveByStep(
                  firestore,
                  canEdit,
                  state._latestSetlist,
                  state._latestCueData,
                  1,
                );
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: setlistStream,
              builder: (context, setlistSnapshot) {
                final bootstrapSetlistReady =
                    bootstrapPreviewReady && bootstrapSetlist.isNotEmpty;
                final items =
                    setlistSnapshot.data?.docs ??
                    (bootstrapSetlistReady
                        ? bootstrapSetlist
                        : const <
                            QueryDocumentSnapshot<Map<String, dynamic>>
                          >[]);
                if (setlistSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    items.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                if (setlistSnapshot.hasError && items.isEmpty) {
                  return Center(
                    child: Text(
                      '콘티 로드 실패: ${setlistSnapshot.error}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }
                state._latestSetlist = items;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: cueStream,
                  builder: (context, cueSnapshot) {
                    final bootstrapCueReady =
                        bootstrapPreviewReady &&
                        canRenderPreviewBeforeSync(
                          items: items,
                          cueData: bootstrapCueData,
                        );
                    if (cueSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      beginCueWaitingWatchdog();
                      if (bootstrapCueReady) {
                        return buildPendingSyncPreview(
                          firestore: firestore,
                          storage: storage,
                          items: items,
                          cueData: bootstrapCueData,
                        );
                      }
                      if (isCueWaitingTimedOut) {
                        if (!cueAutoRetryAttempted) {
                          scheduleCueAutoRetry();
                          return const Center(
                            child: AppLoadingState(
                              message: 'LiveCue 자동 재연결 시도 중...',
                            ),
                          );
                        }
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: AppStateCard(
                              icon: Icons.sync_problem_outlined,
                              isError: true,
                              title: 'LiveCue 상태 동기화 지연',
                              message:
                                  '상태 문서를 읽지 못하고 있습니다. 권한/네트워크를 확인한 뒤 다시 시도해 주세요.',
                              actionLabel: '다시 시도',
                              onAction: retryCueSync,
                            ),
                          ),
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    clearCueWaitingWatchdog();
                    if (cueSnapshot.hasError) {
                      if (!cueAutoRetryAttempted) {
                        scheduleCueAutoRetry();
                        return const Center(
                          child: AppLoadingState(
                            message: 'LiveCue 상태 복구 시도 중...',
                          ),
                        );
                      }
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: AppStateCard(
                            icon: Icons.sync_problem_outlined,
                            isError: true,
                            title: 'LiveCue 상태 로드 실패',
                            message: '${cueSnapshot.error}',
                            actionLabel: '다시 시도',
                            onAction: retryCueSync,
                          ),
                        ),
                      );
                    }

                    resetCueRetryState();
                    if (!state._syncReadyMetricEmitted) {
                      state._syncReadyMetricEmitted = true;
                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                      OpsMetrics.emit(
                        'livecue_sync_ready',
                        fields: <String, Object?>{
                          'teamId': widget.teamId,
                          'projectId': widget.projectId,
                          'sinceEntryMs': nowMs - widget.entryStartedAtEpochMs,
                          if (pageVisibleAtEpochMs != null)
                            'sincePageVisibleMs': nowMs - pageVisibleAtEpochMs,
                        },
                      );
                    }
                    final cueData = cueSnapshot.data?.data() ?? {};
                    state._latestCueData = cueData;
                    if (items.isNotEmpty &&
                        !_hasCueValue(cueData, 'current') &&
                        !state._autoSeeding) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!state.mounted) return;
                        seedFromSetlistIfNeeded(firestore, items, cueData);
                      });
                    }

                    final syncState = LiveCueResolvedState.resolve(
                      items: items,
                      cueData: cueData,
                      cueLabelFromItem: _cueLabelFromItem,
                      titleFromItem: _titleFromItem,
                      keyFromItem: _keyFromItem,
                      normalizeKeyText: normalizeKeyText,
                    );
                    final currentIndex = syncState.currentIndex;
                    final currentSongId = syncState.currentSongId;
                    final currentLabel = syncState.currentLabel;
                    final currentTitle = syncState.currentTitle;
                    final currentKey = syncState.currentKey;
                    final currentMetadataSummary = _buildMetadataSummary(
                      _extractMetadataFromItem(
                        syncState.matchedCurrentSetlistData,
                      ),
                    );
                    final currentPreviewTitle =
                        syncState.setlistCurrentTitle.isNotEmpty
                        ? syncState.setlistCurrentTitle
                        : currentTitle;
                    final currentPreviewCacheKey = previewCacheKey(
                      currentSongId?.trim() ?? '',
                      currentKey,
                      currentPreviewTitle,
                    );
                    final cachedCurrentPreview = renderPresenter.cachedPreview(
                      currentPreviewCacheKey,
                    );
                    final nextSongId = cueData['nextSongId']?.toString();
                    final nextLabel = syncState.nextLabel;
                    final nextKey = syncState.nextKey;
                    final nextTitle = syncState.nextTitle;
                    final nextMetadataSummary = _buildMetadataSummary(
                      _extractMetadataFromItem(
                        syncState.nextIndex >= 0 &&
                                syncState.nextIndex < items.length
                            ? items[syncState.nextIndex].data()
                            : null,
                      ),
                    );

                    String? prevSongId;
                    String? prevKey;
                    String prevTitle = '';
                    if (currentIndex > 0 && currentIndex < items.length) {
                      final prevData = items[currentIndex - 1].data();
                      prevSongId = prevData['songId']?.toString();
                      prevKey = _keyFromItem(prevData);
                      prevTitle = _titleFromItem(prevData);
                    }

                    warmScoreTripletIfNeeded(
                      firestore: firestore,
                      storage: storage,
                      currentSongId: currentSongId,
                      currentKey: currentKey,
                      currentTitle: currentPreviewTitle,
                      prevSongId: prevSongId,
                      prevKey: prevKey,
                      prevTitle: prevTitle,
                      nextSongId: nextSongId,
                      nextKey: nextKey,
                      nextTitle: nextTitle,
                    );

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: drawingEnabled
                                ? HitTestBehavior.deferToChild
                                : HitTestBehavior.opaque,
                            onTap: drawingEnabled ? null : toggleOverlay,
                            onHorizontalDragEnd: drawingEnabled
                                ? null
                                : (details) {
                                    final velocity =
                                        details.primaryVelocity ?? 0;
                                    if (velocity > 220) {
                                      moveByStep(
                                        firestore,
                                        canEdit,
                                        items,
                                        cueData,
                                        -1,
                                      );
                                    } else if (velocity < -220) {
                                      moveByStep(
                                        firestore,
                                        canEdit,
                                        items,
                                        cueData,
                                        1,
                                      );
                                    }
                                  },
                            child: ValueListenableBuilder<int>(
                              valueListenable: viewerRevision,
                              builder: (context, viewerVersion, child) {
                                return FutureBuilder<_LiveCueAssetPreview?>(
                                  future: loadPreviewCached(
                                    firestore,
                                    storage,
                                    currentSongId,
                                    currentKey,
                                    currentPreviewTitle,
                                  ),
                                  builder: (context, previewSnapshot) {
                                    final preview =
                                        previewSnapshot.data ??
                                        cachedCurrentPreview;
                                    if (previewSnapshot.connectionState ==
                                            ConnectionState.waiting &&
                                        preview == null) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      );
                                    }
                                    final songIdForDetail =
                                        preview?.resolvedSongId ??
                                        currentSongId;
                                    if (preview == null) {
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '악보가 없습니다. (${_lineText(label: currentLabel, title: currentTitle, keyText: currentKey)})',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            TextButton(
                                              onPressed: () {
                                                evictPreviewCache(
                                                  currentSongId ?? '',
                                                  currentKey,
                                                  currentPreviewTitle,
                                                );
                                                if (state.mounted) {
                                                  markViewerNeedsBuild();
                                                }
                                              },
                                              child: const Text(
                                                '다시 불러오기',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    if (!preview.isImage) {
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.picture_as_pdf,
                                              size: 72,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              preview.fileName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (songIdForDetail != null)
                                              TextButton(
                                                onPressed: () {
                                                  showOverlayTemporarily();
                                                  final keyQuery =
                                                      (currentKey == null ||
                                                          currentKey.isEmpty)
                                                      ? ''
                                                      : '?key=${Uri.encodeComponent(currentKey)}';
                                                  context.go(
                                                    '/teams/${widget.teamId}/songs/$songIdForDetail$keyQuery',
                                                  );
                                                },
                                                child: const Text(
                                                  '악보 열기',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            TextButton(
                                              onPressed: () {
                                                final opened = openUrlInNewTab(
                                                  preview.url,
                                                );
                                                if (!opened && state.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '팝업이 차단되었습니다. 브라우저 설정에서 팝업 차단을 해제해 주세요.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              child: const Text(
                                                '파일 직접 열기',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return LayoutBuilder(
                                      builder: (context, constraints) {
                                        final normalizedViewerKey =
                                            (currentKey == null ||
                                                currentKey.trim().isEmpty)
                                            ? '-'
                                            : normalizeKeyText(currentKey);
                                        final viewerAssetKey =
                                            '${preview.storagePath}|$normalizedViewerKey';
                                        ensureViewerAssetKey(viewerAssetKey);
                                        Widget buildScoreLoadError() {
                                          return Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '악보 로드 실패: ${preview.fileName}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                if (songIdForDetail != null)
                                                  TextButton(
                                                    onPressed: () {
                                                      final keyQuery =
                                                          (currentKey == null ||
                                                              currentKey
                                                                  .isEmpty)
                                                          ? ''
                                                          : '?key=${Uri.encodeComponent(currentKey)}';
                                                      context.go(
                                                        '/teams/${widget.teamId}/songs/$songIdForDetail$keyQuery',
                                                      );
                                                    },
                                                    child: const Text(
                                                      '악보 상세에서 열기',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                TextButton(
                                                  onPressed: () {
                                                    final opened =
                                                        openUrlInNewTab(
                                                          preview.url,
                                                        );
                                                    if (!opened &&
                                                        state.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '팝업이 차단되었습니다. 브라우저 설정에서 팝업 차단을 해제해 주세요.',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  child: const Text(
                                                    '파일 직접 열기',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }

                                        final bytes = preview.initialBytes;
                                        syncImageRendererKey(viewerAssetKey);
                                        final shouldUseHtmlStrategy =
                                            kIsWeb &&
                                            fallbackToHtmlImageElement &&
                                            !drawingEnabled;
                                        final htmlImageStrategy =
                                            shouldUseHtmlStrategy
                                            ? WebHtmlElementStrategy.prefer
                                            : WebHtmlElementStrategy.never;

                                        Widget buildImageLoadError(
                                          Object error,
                                        ) {
                                          if (preview.urlSource.startsWith(
                                                'stored',
                                              ) &&
                                              !forceFreshPreviewCacheKeys
                                                  .contains(
                                                    currentPreviewCacheKey,
                                                  )) {
                                            retryPreviewWithFreshUrl(
                                              cacheKey: currentPreviewCacheKey,
                                              songId: currentSongId,
                                              keyText: currentKey,
                                              fallbackTitle:
                                                  currentPreviewTitle,
                                              preview: preview,
                                            );
                                            return const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            );
                                          }
                                          final switched = renderPresenter
                                              .tryActivateHtmlImageFallback(
                                                hasInitialBytes:
                                                    bytes != null &&
                                                    bytes.isNotEmpty,
                                                drawingEnabled: drawingEnabled,
                                                isMounted: () => state.mounted,
                                                requestRebuild:
                                                    requestRenderPresenterRebuild,
                                              );
                                          if (switched) {
                                            return const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            );
                                          }
                                          return buildScoreLoadError();
                                        }

                                        final imageWidget =
                                            bytes != null && bytes.isNotEmpty
                                            ? Image.memory(
                                                bytes,
                                                key: ValueKey(
                                                  'asset-memory-$viewerAssetKey',
                                                ),
                                                fit: BoxFit.contain,
                                                filterQuality:
                                                    FilterQuality.high,
                                                gaplessPlayback: true,
                                                frameBuilder:
                                                    (
                                                      context,
                                                      child,
                                                      frame,
                                                      wasSynchronouslyLoaded,
                                                    ) {
                                                      if (wasSynchronouslyLoaded ||
                                                          frame != null) {
                                                        WidgetsBinding.instance
                                                            .addPostFrameCallback((
                                                              _,
                                                            ) {
                                                              if (!state
                                                                  .mounted) {
                                                                return;
                                                              }
                                                              emitPreviewVisibleMetric(
                                                                viewerAssetKey,
                                                                preview,
                                                              );
                                                            });
                                                      }
                                                      return child;
                                                    },
                                                errorBuilder:
                                                    (context, error, stack) =>
                                                        buildImageLoadError(
                                                          error,
                                                        ),
                                              )
                                            : Image.network(
                                                preview.url,
                                                key: ValueKey(
                                                  'asset-url-$viewerAssetKey',
                                                ),
                                                fit: BoxFit.contain,
                                                filterQuality:
                                                    FilterQuality.high,
                                                webHtmlElementStrategy:
                                                    htmlImageStrategy,
                                                gaplessPlayback: true,
                                                loadingBuilder:
                                                    (
                                                      context,
                                                      child,
                                                      loadingProgress,
                                                    ) {
                                                      if (loadingProgress ==
                                                          null) {
                                                        emitPreviewVisibleMetric(
                                                          viewerAssetKey,
                                                          preview,
                                                        );
                                                        return child;
                                                      }
                                                      return const Center(
                                                        child:
                                                            CircularProgressIndicator(
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      );
                                                    },
                                                errorBuilder:
                                                    (context, error, stack) =>
                                                        buildImageLoadError(
                                                          error,
                                                        ),
                                              );
                                        final canvasSize = Size(
                                          constraints.maxWidth,
                                          constraints.maxHeight,
                                        );
                                        final shouldShowStrokeOverlay =
                                            (drawingEnabled && canEdit) ||
                                            privateLayerStrokes.isNotEmpty ||
                                            sharedLayerStrokes.isNotEmpty ||
                                            strokeEngine.activeLayerStroke !=
                                                null;
                                        final viewerContent = SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              RepaintBoundary(
                                                child: imageWidget,
                                              ),
                                              if (shouldShowStrokeOverlay)
                                                IgnorePointer(
                                                  child: RepaintBoundary(
                                                    child: CustomPaint(
                                                      painter:
                                                          _LiveCueSketchPainter(
                                                            strokesProvider:
                                                                overlayStrokesForRender,
                                                            repaint:
                                                                strokeRevision,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              if (drawingEnabled && canEdit)
                                                Listener(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onPointerDown: (event) =>
                                                      handleDrawingPointerDown(
                                                        event,
                                                        canvasSize,
                                                      ),
                                                  onPointerMove: (event) =>
                                                      handleDrawingPointerMove(
                                                        event,
                                                        canvasSize,
                                                      ),
                                                  onPointerUp:
                                                      handleDrawingPointerUpOrCancel,
                                                  onPointerCancel:
                                                      handleDrawingPointerUpOrCancel,
                                                ),
                                            ],
                                          ),
                                        );
                                        final viewWidget =
                                            drawingEnabled && canEdit
                                            ? viewerContent
                                            : InteractiveViewer(
                                                transformationController:
                                                    viewerController,
                                                minScale: 0.7,
                                                maxScale: 8,
                                                panEnabled: true,
                                                scaleEnabled: true,
                                                boundaryMargin:
                                                    const EdgeInsets.all(320),
                                                clipBehavior: Clip.none,
                                                child: viewerContent,
                                              );
                                        final flutterRenderer = Center(
                                          child: SizedBox(
                                            width: constraints.maxWidth,
                                            height: constraints.maxHeight,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                viewWidget,
                                                if (kIsWeb &&
                                                    fallbackToHtmlImageElement &&
                                                    drawingEnabled &&
                                                    canEdit)
                                                  Positioned(
                                                    left: 16,
                                                    right: 16,
                                                    top: 12,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black87,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        '브라우저 렌더링 호환 모드(prefer)로 전환되어 필기 입력이 불안정할 수 있습니다.',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                        final canUseNextViewer =
                                            renderPresenter.canUseNextViewer;
                                        if (canUseNextViewer &&
                                            viewerIdToken == null) {
                                          emitViewerReadyMetric(
                                            'flutter-token-wait:$viewerAssetKey',
                                            preview,
                                            renderer: 'flutter_token_wait',
                                          );
                                          return flutterRenderer;
                                        }
                                        if (canUseNextViewer &&
                                            viewerIdToken != null) {
                                          final nextViewerInitApplied =
                                              nextViewerInitAppliedKeys
                                                  .contains(viewerAssetKey);
                                          emitViewerReadyMetric(
                                            nextViewerInitApplied
                                                ? 'next-viewer:$viewerAssetKey'
                                                : 'next-viewer-boot:$viewerAssetKey',
                                            preview,
                                            renderer: nextViewerInitApplied
                                                ? 'next_viewer'
                                                : 'next_viewer_boot',
                                          );
                                          final nextHostProps =
                                              NextViewerHostProps(
                                                viewerUrl: _nextViewerUrl,
                                                initData: NextViewerInitData(
                                                  teamId: widget.teamId,
                                                  projectId: widget.projectId,
                                                  currentSongId: currentSongId,
                                                  currentKeyText: currentKey,
                                                  scoreImageUrl: preview.url,
                                                  idToken: viewerIdToken,
                                                  canEdit:
                                                      canEdit && drawingEnabled,
                                                  editingSharedLayer:
                                                      editingSharedLayer,
                                                  willReadFrequently:
                                                      nextViewerWillReadFrequently,
                                                  privateStrokes:
                                                      privateLayerStrokes,
                                                  sharedStrokes:
                                                      sharedLayerStrokes,
                                                ),
                                                syncRevision: state
                                                    ._nextViewerSyncRevision,
                                                onInkCommit:
                                                    onNextViewerInkCommit,
                                                onDirtyChanged:
                                                    onNextViewerDirtyChanged,
                                                onAssetError:
                                                    onNextViewerAssetError,
                                                onProtocolLog: (message) =>
                                                    onNextViewerProtocolLog(
                                                      viewerAssetKey,
                                                      message,
                                                    ),
                                              );
                                          final nextViewerWidget = Center(
                                            child: SizedBox(
                                              width: constraints.maxWidth,
                                              height: constraints.maxHeight,
                                              child: NextViewerHostView(
                                                key: ValueKey(
                                                  'next-viewer-$viewerAssetKey',
                                                ),
                                                props: nextHostProps,
                                              ),
                                            ),
                                          );
                                          if (!nextViewerInitApplied) {
                                            return Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                flutterRenderer,
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: Opacity(
                                                      opacity: 0.0,
                                                      child: nextViewerWidget,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }
                                          return nextViewerWidget;
                                        }
                                        emitViewerReadyMetric(
                                          'flutter:$viewerAssetKey',
                                          preview,
                                          renderer: 'flutter',
                                        );
                                        return flutterRenderer;
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: Listenable.merge(<Listenable>[
                              overlayRevision,
                              toolRevision,
                            ]),
                            builder: (context, child) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: showOverlay
                                            ? Colors.black54
                                            : Colors.black26,
                                      ),
                                      onPressed: handleBackNavigation,
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (canEdit && drawingEnabled)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton(
                                        style: IconButton.styleFrom(
                                          backgroundColor: showDrawingToolPanel
                                              ? Colors.white24
                                              : Colors.black54,
                                        ),
                                        tooltip: showDrawingToolPanel
                                            ? '도구 패널 숨기기'
                                            : '도구 패널 보기',
                                        onPressed: toggleDrawingToolPanel,
                                        icon: Icon(
                                          showDrawingToolPanel
                                              ? Icons
                                                    .keyboard_arrow_down_rounded
                                              : Icons.tune_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (showOverlay)
                                    Positioned(
                                      top: 8,
                                      right: canEdit && drawingEnabled ? 56 : 8,
                                      child: Row(
                                        children: [
                                          IconButton(
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.black54,
                                            ),
                                            onPressed: canEdit
                                                ? () => moveByStep(
                                                    firestore,
                                                    canEdit,
                                                    items,
                                                    cueData,
                                                    -1,
                                                  )
                                                : null,
                                            icon: const Icon(
                                              Icons.chevron_left,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.black54,
                                            ),
                                            onPressed: canEdit
                                                ? () => moveByStep(
                                                    firestore,
                                                    canEdit,
                                                    items,
                                                    cueData,
                                                    1,
                                                  )
                                                : null,
                                            icon: const Icon(
                                              Icons.chevron_right,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (canEdit) ...[
                                            const SizedBox(width: 8),
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: drawingEnabled
                                                    ? Colors.white24
                                                    : Colors.black54,
                                              ),
                                              tooltip: drawingEnabled
                                                  ? '필기 모드 끄기'
                                                  : '필기 모드 켜기',
                                              onPressed: () =>
                                                  setDrawingEnabled(
                                                    !drawingEnabled,
                                                  ),
                                              icon: Icon(
                                                drawingEnabled
                                                    ? Icons.edit_off_rounded
                                                    : Icons.draw_rounded,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                          if (canEdit && drawingEnabled) ...[
                                            const SizedBox(width: 8),
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.black54,
                                              ),
                                              tooltip: editingSharedLayer
                                                  ? '현재: 공유 레이어'
                                                  : '현재: 개인 레이어',
                                              onPressed: () =>
                                                  setEditingSharedLayer(
                                                    !editingSharedLayer,
                                                  ),
                                              icon: Icon(
                                                editingSharedLayer
                                                    ? Icons.groups_rounded
                                                    : Icons.person_rounded,
                                                color: Colors.white,
                                              ),
                                            ),
                                            if (!(kIsWeb && useNextViewer)) ...[
                                              const SizedBox(width: 8),
                                              IconButton(
                                                style: IconButton.styleFrom(
                                                  backgroundColor: eraserEnabled
                                                      ? Colors.white24
                                                      : Colors.black54,
                                                ),
                                                tooltip: eraserEnabled
                                                    ? '지우개 모드'
                                                    : '펜 모드',
                                                onPressed: () =>
                                                    setEraserEnabled(
                                                      !eraserEnabled,
                                                    ),
                                                icon: Icon(
                                                  eraserEnabled
                                                      ? Icons
                                                            .cleaning_services_rounded
                                                      : Icons.brush_rounded,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (showOverlay &&
                                      (!drawingEnabled || showDrawingToolPanel))
                                    Positioned(
                                      left: 12,
                                      bottom: 12,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              (MediaQuery.of(
                                                        context,
                                                      ).size.width -
                                                      24)
                                                  .clamp(
                                                    280.0,
                                                    drawingEnabled
                                                        ? 460.0
                                                        : 380.0,
                                                  )
                                                  .toDouble(),
                                          maxHeight:
                                              MediaQuery.of(
                                                context,
                                              ).size.height *
                                              (drawingEnabled &&
                                                      showDrawingToolPanel
                                                  ? 0.68
                                                  : 0.56),
                                        ),
                                        child: RepaintBoundary(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _lineText(
                                                      label: currentLabel,
                                                      title: currentTitle,
                                                      keyText: currentKey,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  if (currentMetadataSummary
                                                      .hasMetadata) ...[
                                                    const SizedBox(height: 6),
                                                    _buildLiveCueFullscreenMetadataBlock(
                                                      currentMetadataSummary,
                                                    ),
                                                  ],
                                                  if (nextTitle.isNotEmpty &&
                                                      nextTitle !=
                                                          '다음 곡 없음') ...[
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      _lineText(
                                                        label: nextLabel,
                                                        title: nextTitle,
                                                        keyText: nextKey,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (nextMetadataSummary
                                                        .hasMetadata) ...[
                                                      const SizedBox(height: 4),
                                                      _buildLiveCueFullscreenMetadataBlock(
                                                        nextMetadataSummary,
                                                      ),
                                                    ],
                                                  ],
                                                  if (currentSongId != null &&
                                                      currentSongId.isNotEmpty)
                                                    FutureBuilder<List<String>>(
                                                      future:
                                                          loadAvailableKeysCached(
                                                            firestore,
                                                            currentSongId,
                                                          ),
                                                      builder: (context, keySnapshot) {
                                                        final keys =
                                                            keySnapshot.data ??
                                                            const <String>[];
                                                        if (keys.length <= 1) {
                                                          return const SizedBox.shrink();
                                                        }
                                                        final selectedKey =
                                                            cueData['currentKeyText']
                                                                ?.toString() ??
                                                            '';
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 8,
                                                              ),
                                                          child: Wrap(
                                                            spacing: 8,
                                                            runSpacing: 8,
                                                            children: keys
                                                                .map(
                                                                  (
                                                                    key,
                                                                  ) => ChoiceChip(
                                                                    label: Text(
                                                                      key,
                                                                    ),
                                                                    selected:
                                                                        normalizeKeyText(
                                                                          selectedKey,
                                                                        ) ==
                                                                        normalizeKeyText(
                                                                          key,
                                                                        ),
                                                                    onSelected:
                                                                        canEdit
                                                                        ? (
                                                                            _,
                                                                          ) => setCurrentKey(
                                                                            firestore,
                                                                            canEdit,
                                                                            key,
                                                                          )
                                                                        : null,
                                                                  ),
                                                                )
                                                                .toList(),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  if (loadingNoteLayers) ...[
                                                    const SizedBox(height: 8),
                                                    const LinearProgressIndicator(
                                                      minHeight: 2,
                                                    ),
                                                  ],
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: [
                                                      FilterChip(
                                                        label: const Text(
                                                          '개인 레이어',
                                                        ),
                                                        selected:
                                                            showPrivateLayer,
                                                        onSelected: (value) =>
                                                            setLayerVisibility(
                                                              showPrivateLayer:
                                                                  value,
                                                            ),
                                                      ),
                                                      FilterChip(
                                                        label: const Text(
                                                          '공유 레이어',
                                                        ),
                                                        selected:
                                                            showSharedLayer,
                                                        onSelected: (value) =>
                                                            setLayerVisibility(
                                                              showSharedLayer:
                                                                  value,
                                                            ),
                                                      ),
                                                      if (kIsWeb &&
                                                          useNextViewer)
                                                        Chip(
                                                          avatar: Icon(
                                                            state._nextViewerDirty
                                                                ? Icons
                                                                      .sync_problem_rounded
                                                                : Icons
                                                                      .verified_rounded,
                                                            size: 16,
                                                            color:
                                                                state
                                                                    ._nextViewerDirty
                                                                ? Colors
                                                                      .orange
                                                                      .shade200
                                                                : Colors
                                                                      .lightGreenAccent,
                                                          ),
                                                          label: Text(
                                                            state._nextViewerDirty
                                                                ? '미저장 필기 있음'
                                                                : '필기 동기화 완료',
                                                          ),
                                                        ),
                                                      if (kIsWeb &&
                                                          useNextViewer &&
                                                          nextViewerStatus !=
                                                              null &&
                                                          nextViewerStatus
                                                              .isNotEmpty)
                                                        Chip(
                                                          label: Text(
                                                            nextViewerStatus,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      if (canEdit)
                                                        FilledButton.tonalIcon(
                                                          onPressed: () =>
                                                              setDrawingEnabled(
                                                                !drawingEnabled,
                                                              ),
                                                          icon: Icon(
                                                            drawingEnabled
                                                                ? Icons
                                                                      .edit_off_rounded
                                                                : Icons
                                                                      .draw_rounded,
                                                          ),
                                                          label: Text(
                                                            drawingEnabled
                                                                ? '필기 모드 종료'
                                                                : '필기 모드 시작',
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (canEdit &&
                                                      drawingEnabled) ...[
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      editingSharedLayer
                                                          ? '공유 레이어 편집 중 (팀원 모두에게 공유)'
                                                          : '개인 레이어 편집 중 (나만 보임)',
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    if (kIsWeb &&
                                                        useNextViewer) ...[
                                                      const Text(
                                                        'Next.js Viewer가 필기/지우개/되돌리기를 처리합니다. Host는 저장과 동기화만 담당합니다.',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '개인 레이어 편집',
                                                            ),
                                                            selected:
                                                                !editingSharedLayer,
                                                            onSelected: (_) =>
                                                                setEditingSharedLayer(
                                                                  false,
                                                                ),
                                                          ),
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '공유 레이어 편집',
                                                            ),
                                                            selected:
                                                                editingSharedLayer,
                                                            onSelected: (_) =>
                                                                setEditingSharedLayer(
                                                                  true,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: FilledButton.icon(
                                                          onPressed:
                                                              savingNoteLayers
                                                              ? null
                                                              : () async {
                                                                  final saved = await saveLayerNotes(
                                                                    notePersistence,
                                                                    user.uid,
                                                                    saveBothLayers:
                                                                        true,
                                                                  );
                                                                  if (!saved ||
                                                                      !state
                                                                          .mounted) {
                                                                    return;
                                                                  }
                                                                  state._nextViewerDirty =
                                                                      false;
                                                                  state._nextViewerSyncRevision =
                                                                      state
                                                                          ._nextViewerSyncRevision +
                                                                      1;
                                                                  markViewerNeedsBuild();
                                                                  markOverlayNeedsBuild();
                                                                },
                                                          icon: savingNoteLayers
                                                              ? const SizedBox(
                                                                  width: 14,
                                                                  height: 14,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                )
                                                              : const Icon(
                                                                  Icons
                                                                      .save_rounded,
                                                                ),
                                                          label: const Text(
                                                            '레이어 저장(개인+공유)',
                                                          ),
                                                        ),
                                                      ),
                                                    ] else ...[
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '펜',
                                                            ),
                                                            selected:
                                                                !eraserEnabled,
                                                            onSelected: (_) =>
                                                                setEraserEnabled(
                                                                  false,
                                                                ),
                                                          ),
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '지우개',
                                                            ),
                                                            selected:
                                                                eraserEnabled,
                                                            onSelected: (_) =>
                                                                setEraserEnabled(
                                                                  true,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      if (eraserEnabled)
                                                        const Text(
                                                          '선을 문지르면 해당 획이 지워집니다.',
                                                          style: TextStyle(
                                                            color:
                                                                Colors.white70,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      if (eraserEnabled)
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                      if (!eraserEnabled)
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: _liveCueDrawingPalette
                                                              .map(
                                                                (
                                                                  colorValue,
                                                                ) => GestureDetector(
                                                                  onTap: () =>
                                                                      setDrawingColorValue(
                                                                        colorValue,
                                                                      ),
                                                                  child: Container(
                                                                    width: 26,
                                                                    height: 26,
                                                                    decoration: BoxDecoration(
                                                                      color: Color(
                                                                        colorValue,
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            13,
                                                                          ),
                                                                      border: Border.all(
                                                                        color:
                                                                            drawingColorValue ==
                                                                                colorValue
                                                                            ? Colors.white
                                                                            : Colors.white38,
                                                                        width:
                                                                            drawingColorValue ==
                                                                                colorValue
                                                                            ? 2
                                                                            : 1,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(),
                                                        ),
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: <double>[1.8, 2.8, 4.2, 6.0]
                                                            .map(
                                                              (
                                                                width,
                                                              ) => ChoiceChip(
                                                                label: Text(
                                                                  '펜 ${width.toStringAsFixed(width == 6.0 ? 0 : 1)}',
                                                                ),
                                                                selected:
                                                                    (drawingStrokeWidth -
                                                                            width)
                                                                        .abs() <
                                                                    0.05,
                                                                onSelected: (_) =>
                                                                    setDrawingStrokeWidth(
                                                                      width,
                                                                    ),
                                                              ),
                                                            )
                                                            .toList(),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          OutlinedButton.icon(
                                                            onPressed:
                                                                undoLayerStroke,
                                                            icon: const Icon(
                                                              Icons
                                                                  .undo_rounded,
                                                            ),
                                                            label: const Text(
                                                              '되돌리기',
                                                            ),
                                                          ),
                                                          OutlinedButton.icon(
                                                            onPressed:
                                                                clearLayerStroke,
                                                            icon: const Icon(
                                                              Icons
                                                                  .delete_sweep_rounded,
                                                            ),
                                                            label: const Text(
                                                              '레이어 지우기',
                                                            ),
                                                          ),
                                                          FilledButton.icon(
                                                            onPressed:
                                                                savingNoteLayers
                                                                ? null
                                                                : () async {
                                                                    final saved =
                                                                        await saveLayerNotes(
                                                                          notePersistence,
                                                                          user.uid,
                                                                        );
                                                                    if (!saved ||
                                                                        !state
                                                                            .mounted) {
                                                                      return;
                                                                    }
                                                                  },
                                                            icon:
                                                                savingNoteLayers
                                                                ? const SizedBox(
                                                                    width: 14,
                                                                    height: 14,
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                                  )
                                                                : const Icon(
                                                                    Icons
                                                                        .save_rounded,
                                                                  ),
                                                            label: Text(
                                                              editingSharedLayer
                                                                  ? '공유 레이어 저장'
                                                                  : '개인 레이어 저장',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
