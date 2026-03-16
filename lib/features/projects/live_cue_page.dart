import 'dart:async';
import 'dart:collection';
import 'dart:ui' show PointerDeviceKind;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../core/ops/ops_metrics.dart';
import '../../core/roles.dart';
import '../../services/firebase_providers.dart';
import '../../services/song_search.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';
import 'live_cue_note_persistence_adapter.dart';
import 'models/setlist_music_metadata.dart';
import 'models/sketch_stroke.dart';
import 'live_cue_stroke_engine.dart';
import 'live_cue_sync_coordinator.dart';
import 'next_viewer_contract.dart';
import 'next_viewer_host.dart';

part 'live_cue_shared_helpers.dart';
part 'live_cue_render_support.dart';
part 'live_cue_operator_sections.dart';
part 'live_cue_fullscreen_sections.dart';

class LiveCuePage extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;
  final bool canEdit;

  const LiveCuePage({
    super.key,
    required this.teamId,
    required this.projectId,
    required this.canEdit,
  });

  @override
  ConsumerState<LiveCuePage> createState() => _LiveCuePageState();
}

class _LiveCuePageState extends ConsumerState<LiveCuePage> {
  static const Duration _cueSyncTimeout = Duration(seconds: 15);
  final FocusNode _focusNode = FocusNode();
  final Map<String, Future<List<String>>> _songKeysFutureCache = {};
  late final LiveCueSyncCoordinator _syncCoordinator;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestSetlist =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Map<String, dynamic> _latestCueData = const <String, dynamic>{};
  bool _autoSeeding = false;
  bool _saving = false;
  Timer? _cueWaitingTimer;
  DateTime? _cueWaitingSince;
  bool _cueAutoRetryAttempted = false;
  bool _cueAutoRetryPending = false;

  @override
  void initState() {
    super.initState();
    _syncCoordinator = LiveCueSyncCoordinator(
      scope: 'operator',
      teamId: widget.teamId,
      projectId: widget.projectId,
      isWeb: kIsWeb,
      isMounted: () => mounted,
      traceLogger: _traceLiveCueSync,
    );
  }

  @override
  void dispose() {
    unawaited(_syncCoordinator.dispose());
    _cueWaitingTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _beginCueWaitingWatchdog() {
    _cueWaitingSince ??= DateTime.now();
    _cueWaitingTimer ??= Timer(_cueSyncTimeout, () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _clearCueWaitingWatchdog() {
    _cueWaitingTimer?.cancel();
    _cueWaitingTimer = null;
    _cueWaitingSince = null;
  }

  bool get _isCueWaitingTimedOut {
    final startedAt = _cueWaitingSince;
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt) >= _cueSyncTimeout;
  }

  void _retryCueSync() {
    _clearCueWaitingWatchdog();
    _cueAutoRetryPending = false;
    unawaited(_syncCoordinator.requestRetry());
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleCueAutoRetry() {
    if (_cueAutoRetryAttempted || _cueAutoRetryPending) return;
    _cueAutoRetryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cueAutoRetryAttempted = true;
      _cueAutoRetryPending = false;
      _retryCueSync();
    });
  }

  void _resetCueRetryState() {
    _cueAutoRetryAttempted = false;
    _cueAutoRetryPending = false;
  }

  Future<List<String>> _loadAvailableKeysCached(
    FirebaseFirestore firestore,
    String songId,
  ) {
    if (!_songKeysFutureCache.containsKey(songId) &&
        _songKeysFutureCache.length >= 96) {
      _songKeysFutureCache.clear();
    }
    return _songKeysFutureCache.putIfAbsent(
      songId,
      () => _loadAvailableKeysForSong(firestore, songId),
    );
  }

  Future<void> _seedFromSetlistIfNeeded(
    FirebaseFirestore firestore,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    Map<String, dynamic> cueData,
  ) async {
    if (_autoSeeding || _hasCueValue(cueData, 'current')) return;
    if (items.isEmpty) return;

    _autoSeeding = true;
    try {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      final updates = <String, dynamic>{
        ...await _cueFieldsFromSetlist(
          firestore,
          items.first.data(),
          prefix: 'current',
          teamId: widget.teamId,
        ),
      };
      if (items.length > 1) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            items[1].data(),
            prefix: 'next',
            teamId: widget.teamId,
          ),
        );
      } else {
        updates.addAll(_clearCueFields(prefix: 'next'));
      }
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedBy'] =
          user?.displayName ?? user?.email ?? user?.uid ?? '-';
      await _liveCueRefFor(
        firestore,
        widget.teamId,
        widget.projectId,
      ).set(updates, SetOptions(merge: true));
    } finally {
      _autoSeeding = false;
    }
  }

  Future<void> _applySetlistAsCurrent(
    FirebaseFirestore firestore,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    int index, {
    bool showFeedback = true,
  }) async {
    if (!widget.canEdit) return;
    if (index < 0 || index >= items.length) return;

    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final updates = <String, dynamic>{
        ...await _cueFieldsFromSetlist(
          firestore,
          items[index].data(),
          prefix: 'current',
          teamId: widget.teamId,
        ),
      };
      if (index + 1 < items.length) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            items[index + 1].data(),
            prefix: 'next',
            teamId: widget.teamId,
          ),
        );
      } else {
        updates.addAll(_clearCueFields(prefix: 'next'));
      }
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedBy'] = user.displayName ?? user.email ?? user.uid;

      await _liveCueRefFor(
        firestore,
        widget.teamId,
        widget.projectId,
      ).set(updates, SetOptions(merge: true));
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('현재 곡을 변경했습니다.')));
      }
    } catch (error) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('곡 전환 실패: $error')));
      }
    }
  }

  Future<void> _moveByStep(
    FirebaseFirestore firestore,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    Map<String, dynamic> cueData,
    int step,
  ) async {
    if (!widget.canEdit || _saving) return;
    if (items.isEmpty) return;

    setState(() => _saving = true);
    try {
      var index = LiveCueResolvedState.findCurrentIndex(
        items: items,
        cueData: cueData,
        cueLabelFromItem: _cueLabelFromItem,
        normalizeKeyText: normalizeKeyText,
      );
      if (index < 0) index = 0;
      final nextIndex = (index + step).clamp(0, items.length - 1);
      await _applySetlistAsCurrent(
        firestore,
        items,
        nextIndex.toInt(),
        showFeedback: false,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _setCurrentKey(
    FirebaseFirestore firestore,
    String keyText,
  ) async {
    if (!widget.canEdit) return;
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      await _liveCueRefFor(firestore, widget.teamId, widget.projectId).set({
        'currentKeyText': normalizeKeyText(keyText),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.displayName ?? user.email ?? user.uid,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('현재 키를 ${normalizeKeyText(keyText)}로 변경')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('키 변경 실패: $error')));
      }
    }
  }

  void _requestPageRebuild() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      _buildLiveCueOperatorPage(this, context);
}

class LiveCueFullScreenPage extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;
  final bool startInDrawMode;
  final int entryStartedAtEpochMs;

  const LiveCueFullScreenPage({
    super.key,
    required this.teamId,
    required this.projectId,
    this.startInDrawMode = false,
    required this.entryStartedAtEpochMs,
  });

  @override
  ConsumerState<LiveCueFullScreenPage> createState() =>
      _LiveCueFullScreenPageState();
}

class _LiveCueFullScreenPageState extends ConsumerState<LiveCueFullScreenPage>
    with WidgetsBindingObserver {
  static const Duration _cueSyncTimeout = Duration(seconds: 15);
  final FocusNode _focusNode = FocusNode();
  late final LiveCueStrokeEngine _strokeEngine;
  late final _LiveCueRenderPresenter _renderPresenter;
  final Map<String, Future<List<String>>> _songKeysFutureCache = {};
  late final LiveCueSyncCoordinator _syncCoordinator;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestSetlist =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Map<String, dynamic> _latestCueData = const <String, dynamic>{};
  bool _autoSeeding = false;
  bool _moving = false;
  bool _loadingNoteLayers = false;
  bool _savingNoteLayers = false;
  bool _noteLayersLoaded = false;
  String? _noteLayersKey;
  Future<_LiveCueContext>? _contextFuture;
  String? _contextFutureUserId;
  String? _lastWarmPreviewSignature;
  bool _nextViewerDirty = false;
  int _nextViewerSyncRevision = 0;
  String? _nextViewerStatus;
  String? _viewerIdToken;
  String? _viewerTokenUserId;
  bool _refreshingViewerIdToken = false;
  Timer? _viewerIdTokenRefreshTimer;
  StreamSubscription<User?>? _viewerAuthSubscription;
  String _privateNoteContent = '';
  String _sharedNoteContent = '';
  int? _activeDrawingPointer;
  bool _showDrawingToolPanel = false;
  Timer? _cueWaitingTimer;
  DateTime? _cueWaitingSince;
  bool _cueAutoRetryAttempted = false;
  bool _cueAutoRetryPending = false;
  final ValueNotifier<int> _viewerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _overlayRevision = ValueNotifier<int>(0);
  int? _previousImageCacheMaxEntries;
  int? _previousImageCacheMaxBytes;
  Size _lastViewPhysicalSize = Size.zero;
  String? _lastVisiblePreviewMetricKey;
  final Set<String> _forceFreshPreviewCacheKeys = <String>{};
  final Set<String> _viewerReadyMetricKeys = <String>{};
  final Set<String> _nextViewerInitAppliedKeys = <String>{};
  static const Duration _adjacentPreviewDelay = Duration(milliseconds: 700);
  int? _pageVisibleAtEpochMs;
  bool _contextReadyMetricEmitted = false;
  bool _syncReadyMetricEmitted = false;
  bool _bootstrapPreviewLoading = false;
  bool _bootstrapPreviewReady = false;
  bool _firstPreviewBeforeSyncMetricEmitted = false;
  String? _bootstrapPreviewScopeKey;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _bootstrapSetlist =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Map<String, dynamic> _bootstrapCueData = const <String, dynamic>{};

  TransformationController get _viewerController =>
      _renderPresenter.viewerController;
  ValueNotifier<int> get _strokeRevision => _strokeEngine.strokeRevision;
  ValueNotifier<int> get _toolRevision => _strokeEngine.toolRevision;
  bool get _drawingEnabled => _strokeEngine.drawingEnabled;
  bool get _eraserEnabled => _strokeEngine.eraserEnabled;
  bool get _editingSharedLayer => _strokeEngine.editingSharedLayer;
  bool get _showPrivateLayer => _strokeEngine.showPrivateLayer;
  bool get _showSharedLayer => _strokeEngine.showSharedLayer;
  double get _drawingStrokeWidth => _strokeEngine.drawingStrokeWidth;
  int get _drawingColorValue => _strokeEngine.drawingColorValue;
  List<SketchStroke> get _privateLayerStrokes =>
      _strokeEngine.privateLayerStrokes;
  List<SketchStroke> get _sharedLayerStrokes =>
      _strokeEngine.sharedLayerStrokes;
  bool get _showOverlay => _renderPresenter.showOverlay;
  set _showOverlay(bool value) => _renderPresenter.showOverlay = value;
  bool get _useNextViewer => _renderPresenter.useNextViewer;
  set _useNextViewer(bool value) => _renderPresenter.useNextViewer = value;
  bool get _fallbackToHtmlImageElement =>
      _renderPresenter.fallbackToHtmlImageElement;

  Size _primaryViewPhysicalSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return Size.zero;
    return views.first.physicalSize;
  }

  void _configureImageCacheBudget() {
    final imageCache = PaintingBinding.instance.imageCache;
    _previousImageCacheMaxEntries ??= imageCache.maximumSize;
    _previousImageCacheMaxBytes ??= imageCache.maximumSizeBytes;
    if (imageCache.maximumSize > _liveCueImageCacheMaxEntries) {
      imageCache.maximumSize = _liveCueImageCacheMaxEntries;
    }
    if (imageCache.maximumSizeBytes > _liveCueImageCacheMaxBytes) {
      imageCache.maximumSizeBytes = _liveCueImageCacheMaxBytes;
    }
  }

  void _restoreImageCacheBudget() {
    final imageCache = PaintingBinding.instance.imageCache;
    if (_previousImageCacheMaxEntries != null) {
      imageCache.maximumSize = _previousImageCacheMaxEntries!;
    }
    if (_previousImageCacheMaxBytes != null) {
      imageCache.maximumSizeBytes = _previousImageCacheMaxBytes!;
    }
  }

  bool _supportsDrawingPointer(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.unknown;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastViewPhysicalSize = _primaryViewPhysicalSize();
    _configureImageCacheBudget();
    _strokeEngine = LiveCueStrokeEngine();
    _renderPresenter = _LiveCueRenderPresenter(
      isWeb: kIsWeb,
      initialUseNextViewer: kIsWeb && _nextViewerUrl.trim().isNotEmpty,
    );
    _syncCoordinator = LiveCueSyncCoordinator(
      scope: 'fullscreen',
      teamId: widget.teamId,
      projectId: widget.projectId,
      isWeb: kIsWeb,
      isMounted: () => mounted,
      traceLogger: _traceLiveCueSync,
    );
    if (widget.startInDrawMode) {
      _strokeEngine.setDrawingEnabled(true);
      _showOverlay = true;
    }
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user != null) {
      final firestore = ref.read(firestoreProvider);
      _contextFutureUserId = user.uid;
      _contextFuture = _loadContext(firestore, user.uid);
    }
    _startViewerAuthSync();
    _scheduleOverlayAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pageVisibleAtEpochMs != null) return;
      _pageVisibleAtEpochMs = DateTime.now().millisecondsSinceEpoch;
      OpsMetrics.emit(
        'livecue_entry_page_visible',
        fields: <String, Object?>{
          'teamId': widget.teamId,
          'projectId': widget.projectId,
          'elapsedMs': _pageVisibleAtEpochMs! - widget.entryStartedAtEpochMs,
        },
      );
    });
  }

  @override
  void didChangeMetrics() {
    final nextPhysicalSize = _primaryViewPhysicalSize();
    if (nextPhysicalSize == _lastViewPhysicalSize) return;
    _lastViewPhysicalSize = nextPhysicalSize;
    _lastWarmPreviewSignature = null;
    _activeDrawingPointer = null;
    _showOverlay = true;
    _renderPresenter.viewerController.value = Matrix4.identity();
    _markViewerNeedsBuild();
    _markOverlayNeedsBuild();
    if (!_drawingEnabled) {
      _scheduleOverlayAutoHide();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_syncCoordinator.dispose());
    _viewerAuthSubscription?.cancel();
    _viewerIdTokenRefreshTimer?.cancel();
    _cueWaitingTimer?.cancel();
    _restoreImageCacheBudget();
    _viewerRevision.dispose();
    _overlayRevision.dispose();
    _renderPresenter.dispose();
    _focusNode.dispose();
    _strokeEngine.dispose();
    super.dispose();
  }

  bool get _nextViewerWillReadFrequently =>
      _nextViewerReadbackMode.trim().toLowerCase() != 'disabled';

  void _startViewerAuthSync() {
    if (!_useNextViewer) return;
    final auth = ref.read(firebaseAuthProvider);
    _syncViewerTokenOwner(auth.currentUser);
    _viewerAuthSubscription?.cancel();
    _viewerAuthSubscription = auth.idTokenChanges().listen((user) {
      if (!mounted) return;
      _syncViewerTokenOwner(user);
    });
  }

  void _stopViewerAuthSync() {
    _viewerAuthSubscription?.cancel();
    _viewerAuthSubscription = null;
    _viewerIdTokenRefreshTimer?.cancel();
    _viewerIdTokenRefreshTimer = null;
    _viewerTokenUserId = null;
    _viewerIdToken = null;
  }

  void _beginCueWaitingWatchdog() {
    _cueWaitingSince ??= DateTime.now();
    _cueWaitingTimer ??= Timer(_cueSyncTimeout, () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _clearCueWaitingWatchdog() {
    _cueWaitingTimer?.cancel();
    _cueWaitingTimer = null;
    _cueWaitingSince = null;
  }

  bool get _isCueWaitingTimedOut {
    final startedAt = _cueWaitingSince;
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt) >= _cueSyncTimeout;
  }

  void _retryCueSync() {
    _clearCueWaitingWatchdog();
    _cueAutoRetryPending = false;
    unawaited(_syncCoordinator.requestRetry());
    if (mounted) {
      _markViewerNeedsBuild();
      _markOverlayNeedsBuild();
      setState(() {});
    }
  }

  void _scheduleCueAutoRetry() {
    if (_cueAutoRetryAttempted || _cueAutoRetryPending) return;
    _cueAutoRetryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cueAutoRetryAttempted = true;
      _cueAutoRetryPending = false;
      _retryCueSync();
    });
  }

  void _resetCueRetryState() {
    _cueAutoRetryAttempted = false;
    _cueAutoRetryPending = false;
  }

  void _syncViewerTokenOwner(User? user) {
    if (!_useNextViewer) {
      _stopViewerAuthSync();
      return;
    }
    if (user == null) {
      _viewerTokenUserId = null;
      _viewerIdToken = null;
      _viewerIdTokenRefreshTimer?.cancel();
      _viewerIdTokenRefreshTimer = null;
      return;
    }
    if (_viewerTokenUserId != user.uid) {
      _viewerTokenUserId = user.uid;
      _viewerIdToken = null;
      _viewerIdTokenRefreshTimer?.cancel();
      _viewerIdTokenRefreshTimer = Timer.periodic(
        const Duration(minutes: 40),
        (_) => unawaited(_refreshViewerIdToken(user, forceRefresh: true)),
      );
      unawaited(_refreshViewerIdToken(user));
      return;
    }
    if (_viewerIdToken == null && !_refreshingViewerIdToken) {
      unawaited(_refreshViewerIdToken(user));
    }
  }

  Future<void> _refreshViewerIdToken(
    User user, {
    bool forceRefresh = false,
  }) async {
    if (!_useNextViewer) return;
    if (_refreshingViewerIdToken) return;
    _refreshingViewerIdToken = true;
    try {
      final token = await user.getIdToken(forceRefresh);
      if (!mounted || token == null || token.isEmpty) return;
      if (_viewerIdToken == token) return;
      _viewerIdToken = token;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      OpsMetrics.emit(
        'livecue_viewer_token_ready',
        fields: <String, Object?>{
          'forceRefresh': forceRefresh,
          'teamId': widget.teamId,
          'projectId': widget.projectId,
          'sinceEntryMs': nowMs - widget.entryStartedAtEpochMs,
          if (_pageVisibleAtEpochMs != null)
            'sincePageVisibleMs': nowMs - _pageVisibleAtEpochMs!,
        },
      );
      _markViewerNeedsBuild();
    } finally {
      _refreshingViewerIdToken = false;
    }
  }

  void _onNextViewerInkCommit(NextViewerInkState state) {
    if (!mounted) return;
    _strokeEngine.applyViewerCommit(
      privateStrokes: state.privateStrokes,
      sharedStrokes: state.sharedStrokes,
      editingSharedLayer: state.editingSharedLayer,
    );
    _nextViewerDirty = true;
    _markOverlayNeedsBuild();
  }

  void _onNextViewerDirtyChanged(bool dirty) {
    if (!mounted) return;
    if (_nextViewerDirty == dirty) return;
    _nextViewerDirty = dirty;
    _markOverlayNeedsBuild();
  }

  void _onNextViewerAssetError(NextViewerAssetError error) {
    if (!mounted) return;
    if (!_useNextViewer) return;
    _useNextViewer = false;
    _nextViewerStatus = '${error.code}: ${error.message}';
    _markViewerNeedsBuild();
    _markOverlayNeedsBuild();
    _stopViewerAuthSync();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Next.js 뷰어 자산 로드 실패(${error.code})로 기본 렌더러로 전환합니다.'),
      ),
    );
  }

  void _onNextViewerProtocolLog(String viewerAssetKey, String message) {
    if (message.contains('init-applied')) {
      final added = _nextViewerInitAppliedKeys.add(viewerAssetKey);
      if (added) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        OpsMetrics.emit(
          'livecue_viewer_handoff_ready',
          fields: <String, Object?>{
            'viewerKey': viewerAssetKey,
            'teamId': widget.teamId,
            'projectId': widget.projectId,
            'sinceEntryMs': nowMs - widget.entryStartedAtEpochMs,
            if (_pageVisibleAtEpochMs != null)
              'sincePageVisibleMs': nowMs - _pageVisibleAtEpochMs!,
          },
        );
        _markViewerNeedsBuild();
      }
    }
    if (_nextViewerStatus == message) return;
    if (!mounted) return;
    _nextViewerStatus = message;
    _markOverlayNeedsBuild();
  }

  Future<void> _handleBackNavigation() async {
    if (!_nextViewerDirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('미저장 필기 감지'),
        content: const Text('저장되지 않은 필기가 있습니다. 저장하지 않고 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (shouldLeave == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  String _previewCacheKey(
    String songId,
    String? keyText,
    String? fallbackTitle,
  ) => _renderPresenter.previewCacheKey(songId, keyText, fallbackTitle);

  Future<_LiveCueAssetPreview?> _loadPreviewCached(
    FirebaseFirestore firestore,
    FirebaseStorage storage,
    String? songId,
    String? keyText,
    String? fallbackTitle,
  ) {
    final cacheKey = _previewCacheKey(
      songId?.trim() ?? '',
      keyText,
      fallbackTitle,
    );
    final preferStoredUrlForFirstRender = !_forceFreshPreviewCacheKeys.contains(
      cacheKey,
    );
    return _renderPresenter.loadPreviewCached(
      songId: songId,
      keyText: keyText,
      fallbackTitle: fallbackTitle,
      loader: (resolvedSongId, resolvedKeyText, resolvedFallbackTitle) =>
          _loadCurrentPreview(
            firestore,
            storage,
            widget.teamId,
            resolvedSongId,
            resolvedKeyText,
            resolvedFallbackTitle,
            preferStoredUrlForFirstRender,
            _pageVisibleAtEpochMs,
          ),
    );
  }

  Future<List<String>> _loadAvailableKeysCached(
    FirebaseFirestore firestore,
    String songId,
  ) {
    if (!_songKeysFutureCache.containsKey(songId) &&
        _songKeysFutureCache.length >= 96) {
      _songKeysFutureCache.clear();
    }
    return _songKeysFutureCache.putIfAbsent(
      songId,
      () => _loadAvailableKeysForSong(firestore, songId),
    );
  }

  bool _canRenderPreviewBeforeSync({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    required Map<String, dynamic> cueData,
  }) {
    if (items.isEmpty) return false;
    if (items.length == 1) return true;
    return _hasCueValue(cueData, 'current');
  }

  void _ensureBootstrapPreviewSeed(FirebaseFirestore firestore) {
    if (!kIsWeb) return;
    if (_bootstrapPreviewLoading) return;
    final scopeKey = '${widget.teamId}/${widget.projectId}';
    if (_bootstrapPreviewScopeKey == scopeKey && _bootstrapPreviewReady) {
      return;
    }
    _bootstrapPreviewLoading = true;
    _bootstrapPreviewScopeKey = scopeKey;
    unawaited(_loadBootstrapPreviewSeed(firestore));
  }

  Future<void> _loadBootstrapPreviewSeed(FirebaseFirestore firestore) async {
    final setlistQuery = _setlistRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
    ).orderBy('order');
    final liveCueRef = _liveCueRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
    );
    final cueFuture = () async {
      try {
        return await liveCueRef.get().timeout(const Duration(seconds: 4));
      } catch (_) {
        return null;
      }
    }();
    try {
      final results = await Future.wait<Object?>([
        setlistQuery.get().timeout(const Duration(seconds: 4)),
        cueFuture,
      ]);
      if (!mounted) return;
      final setlistSnapshot =
          results[0]! as QuerySnapshot<Map<String, dynamic>>;
      final cueSnapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>?;
      final cueData = cueSnapshot?.data() ?? const <String, dynamic>{};
      final items = setlistSnapshot.docs;
      setState(() {
        _bootstrapSetlist = items;
        _bootstrapCueData = cueData;
        _bootstrapPreviewReady = _canRenderPreviewBeforeSync(
          items: items,
          cueData: cueData,
        );
      });
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      OpsMetrics.emit(
        'livecue_first_candidate_ready',
        fields: <String, Object?>{
          'teamId': widget.teamId,
          'projectId': widget.projectId,
          'setlistCount': items.length,
          'hasCurrentCue': _hasCueValue(cueData, 'current'),
          'previewReady': _bootstrapPreviewReady,
          'source': 'bootstrap_get',
          if (_pageVisibleAtEpochMs != null)
            'sincePageVisibleMs': nowMs - _pageVisibleAtEpochMs!,
          'sinceEntryMs': nowMs - widget.entryStartedAtEpochMs,
        },
      );
    } catch (_) {
      if (!mounted) return;
      _bootstrapPreviewScopeKey = null;
    } finally {
      _bootstrapPreviewLoading = false;
    }
  }

  void _emitFirstPreviewBeforeSyncMetric({
    required String? songId,
    required String? keyText,
    required String title,
  }) {
    if (_firstPreviewBeforeSyncMetricEmitted) return;
    _firstPreviewBeforeSyncMetricEmitted = true;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    OpsMetrics.emit(
      'livecue_first_preview_before_sync',
      fields: <String, Object?>{
        'teamId': widget.teamId,
        'projectId': widget.projectId,
        'songId': songId,
        'keyText': keyText,
        'title': title,
        'sinceEntryMs': nowMs - widget.entryStartedAtEpochMs,
        if (_pageVisibleAtEpochMs != null)
          'sincePageVisibleMs': nowMs - _pageVisibleAtEpochMs!,
      },
    );
  }

  Widget _buildPendingSyncPreview({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    required Map<String, dynamic> cueData,
  }) => _buildLiveCuePendingSyncPreview(
    state: this,
    firestore: firestore,
    storage: storage,
    items: items,
    cueData: cueData,
  );

  void _ensureViewerAssetKey(String key) =>
      _renderPresenter.ensureViewerAssetKey(key);

  void _syncImageRendererKey(String key) =>
      _renderPresenter.syncImageRendererKey(key);

  Future<_LiveCueAssetPreview?> _warmPreview(
    FirebaseFirestore firestore,
    FirebaseStorage storage,
    String? songId,
    String? keyText,
    String? fallbackTitle,
  ) => _renderPresenter.warmPreview(
    songId: songId,
    keyText: keyText,
    fallbackTitle: fallbackTitle,
    context: context,
    isMounted: () => mounted,
    loader: (resolvedSongId, resolvedKeyText, resolvedFallbackTitle) =>
        _loadCurrentPreview(
          firestore,
          storage,
          widget.teamId,
          resolvedSongId,
          resolvedKeyText,
          resolvedFallbackTitle,
          !_forceFreshPreviewCacheKeys.contains(
            _previewCacheKey(
              resolvedSongId,
              resolvedKeyText,
              resolvedFallbackTitle,
            ),
          ),
          _pageVisibleAtEpochMs,
        ),
  );

  void _evictPreviewCache(
    String songId,
    String? keyText,
    String? fallbackTitle,
  ) => _renderPresenter.evictPreviewCache(songId, keyText, fallbackTitle);

  void _scheduleOverlayAutoHide() => _renderPresenter.scheduleOverlayAutoHide(
    drawingEnabled: _drawingEnabled,
    isMounted: () => mounted,
    requestRebuild: _requestRenderPresenterRebuild,
  );

  void _showOverlayTemporarily() => _renderPresenter.showOverlayTemporarily(
    drawingEnabled: _drawingEnabled,
    isMounted: () => mounted,
    requestRebuild: _requestRenderPresenterRebuild,
  );

  void _toggleOverlay() => _renderPresenter.toggleOverlay(
    drawingEnabled: _drawingEnabled,
    isMounted: () => mounted,
    requestRebuild: _requestRenderPresenterRebuild,
  );

  void _markViewerNeedsBuild() {
    _viewerRevision.value = _viewerRevision.value + 1;
  }

  void _markOverlayNeedsBuild() {
    _overlayRevision.value = _overlayRevision.value + 1;
  }

  void _requestRenderPresenterRebuild() {
    if (!mounted) return;
    _markViewerNeedsBuild();
    _markOverlayNeedsBuild();
  }

  void _emitPreviewVisibleMetric(
    String previewMetricKey,
    _LiveCueAssetPreview preview,
  ) {
    if (_lastVisiblePreviewMetricKey == previewMetricKey) return;
    _lastVisiblePreviewMetricKey = previewMetricKey;
    final visibleLagMs =
        DateTime.now().millisecondsSinceEpoch - preview.selectedAtEpochMs;
    OpsMetrics.emit(
      'livecue_preview_visible',
      fields: <String, Object?>{
        'previewKey': previewMetricKey,
        'resolvedSongId': preview.resolvedSongId,
        'fileName': preview.fileName,
        'urlSource': preview.urlSource,
        'resolverMs': preview.resolverElapsedMs,
        'assetQueryMs': preview.assetQueryElapsedMs,
        'selectionMs': preview.selectionElapsedMs,
        'visibleLagMs': visibleLagMs,
        'totalVisibleMs': preview.selectionElapsedMs + visibleLagMs,
        'assetDocCount': preview.assetDocCount,
        'usedLimitedAssetQuery': preview.usedLimitedAssetQuery,
      },
    );
  }

  void _emitViewerReadyMetric(
    String viewerMetricKey,
    _LiveCueAssetPreview preview, {
    required String renderer,
  }) {
    if (_viewerReadyMetricKeys.contains(viewerMetricKey)) return;
    _viewerReadyMetricKeys.add(viewerMetricKey);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    OpsMetrics.emit(
      'livecue_viewer_ready',
      fields: <String, Object?>{
        'viewerKey': viewerMetricKey,
        'renderer': renderer,
        'resolvedSongId': preview.resolvedSongId,
        'fileName': preview.fileName,
        'urlSource': preview.urlSource,
        'sinceSelectionMs': nowMs - preview.selectedAtEpochMs,
        if (_pageVisibleAtEpochMs != null)
          'sincePageVisibleMs': nowMs - _pageVisibleAtEpochMs!,
      },
    );
  }

  void _retryPreviewWithFreshUrl({
    required String cacheKey,
    required String? songId,
    required String? keyText,
    required String? fallbackTitle,
    required _LiveCueAssetPreview preview,
  }) {
    if (!_forceFreshPreviewCacheKeys.add(cacheKey)) {
      return;
    }
    OpsMetrics.emit(
      'livecue_preview_stored_url_retry',
      fields: <String, Object?>{
        'cacheKey': cacheKey,
        'resolvedSongId': preview.resolvedSongId,
        'fileName': preview.fileName,
        'urlSource': preview.urlSource,
      },
    );
    _evictPreviewCache(songId ?? '', keyText, fallbackTitle);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markViewerNeedsBuild();
    });
  }

  Future<_LiveCueContext> _ensureContextFuture(
    FirebaseFirestore firestore,
    String userId,
  ) {
    if (_contextFuture == null || _contextFutureUserId != userId) {
      _contextFutureUserId = userId;
      _contextFuture = _loadContext(firestore, userId);
      _noteLayersLoaded = false;
      _noteLayersKey = null;
    }
    return _contextFuture!;
  }

  Future<void> _ensureNoteLayersLoaded(
    LiveCueNotePersistenceAdapter notePersistence,
    String userId,
  ) async {
    final key = '${widget.teamId}/${widget.projectId}/$userId';
    if (_noteLayersLoaded && _noteLayersKey == key) return;
    if (_loadingNoteLayers) return;

    setState(() {
      _loadingNoteLayers = true;
    });
    try {
      final noteLayers = await notePersistence.loadNoteLayers(userId: userId);
      if (!mounted) return;
      setState(() {
        _privateNoteContent = noteLayers.privateLayer.text;
        _sharedNoteContent = noteLayers.sharedLayer.text;
        _strokeEngine.replaceLayerStrokes(
          privateStrokes: noteLayers.privateLayer.strokes,
          sharedStrokes: noteLayers.sharedLayer.strokes,
        );
        _noteLayersLoaded = true;
        _noteLayersKey = key;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _noteLayersLoaded = true;
        _noteLayersKey = key;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingNoteLayers = false;
        });
      }
    }
  }

  void _eraseLayerAt(Offset localPosition, Size size) {
    if (!_strokeEngine.eraseAt(localPosition, size)) return;
  }

  void _startLayerStroke(Offset localPosition, Size size) {
    if (!_strokeEngine.beginStroke(localPosition, size)) return;
  }

  void _appendLayerStroke(Offset localPosition, Size size) {
    _strokeEngine.appendStroke(localPosition, size);
  }

  void _endLayerStroke() {
    if (!_strokeEngine.endStroke()) return;
  }

  void _handleDrawingPointerDown(PointerDownEvent event, Size size) {
    if (!_supportsDrawingPointer(event.kind)) return;
    if (_activeDrawingPointer != null) return;
    _activeDrawingPointer = event.pointer;
    if (_eraserEnabled) {
      _eraseLayerAt(event.localPosition, size);
      return;
    }
    _startLayerStroke(event.localPosition, size);
  }

  void _handleDrawingPointerMove(PointerMoveEvent event, Size size) {
    if (!_supportsDrawingPointer(event.kind)) return;
    if (_activeDrawingPointer != event.pointer) return;
    if (_eraserEnabled) {
      _eraseLayerAt(event.localPosition, size);
      return;
    }
    _appendLayerStroke(event.localPosition, size);
  }

  void _handleDrawingPointerUpOrCancel(PointerEvent event) {
    if (_activeDrawingPointer != event.pointer) return;
    if (!_eraserEnabled) {
      _endLayerStroke();
    }
    _activeDrawingPointer = null;
  }

  void _undoLayerStroke() {
    _strokeEngine.undoCurrentLayer();
  }

  void _clearLayerStroke() {
    _strokeEngine.clearCurrentLayer();
  }

  void _setDrawingEnabled(bool value) {
    if (_drawingEnabled == value) return;
    final shouldResetHtmlFallback = value && _fallbackToHtmlImageElement;
    _strokeEngine.setDrawingEnabled(value);
    if (!value) {
      _activeDrawingPointer = null;
      _showDrawingToolPanel = false;
    } else {
      _showDrawingToolPanel = false;
    }
    _showOverlay = true;
    if (shouldResetHtmlFallback) {
      // Prefer canvas-backed renderer while drawing to keep pointer events stable.
      _renderPresenter.resetHtmlImageFallback();
      _markViewerNeedsBuild();
    }
    _markOverlayNeedsBuild();
    if (value) {
      _renderPresenter.cancelOverlayAutoHide();
    } else {
      _scheduleOverlayAutoHide();
    }
  }

  void _setEraserEnabled(bool value) {
    if (_eraserEnabled == value) return;
    _strokeEngine.setEraserEnabled(value);
  }

  void _setEditingSharedLayer(bool value) {
    if (_editingSharedLayer == value) return;
    _strokeEngine.setEditingSharedLayer(value);
  }

  void _setLayerVisibility({bool? showPrivateLayer, bool? showSharedLayer}) {
    _strokeEngine.setLayerVisibility(
      showPrivateLayer: showPrivateLayer,
      showSharedLayer: showSharedLayer,
    );
  }

  void _setDrawingColorValue(int colorValue) {
    if (_drawingColorValue == colorValue) return;
    _strokeEngine.setBrush(colorValue: colorValue);
  }

  void _setDrawingStrokeWidth(double strokeWidth) {
    if ((_drawingStrokeWidth - strokeWidth).abs() < 0.05) return;
    _strokeEngine.setBrush(strokeWidth: strokeWidth);
  }

  void _toggleDrawingToolPanel() {
    if (!mounted || !_drawingEnabled) return;
    _showDrawingToolPanel = !_showDrawingToolPanel;
    if (_showDrawingToolPanel) {
      _showOverlay = true;
    }
    _markOverlayNeedsBuild();
  }

  List<SketchStroke> _overlayStrokesForRender() {
    return _strokeEngine.overlayStrokesForRender();
  }

  Future<bool> _saveLayerNotes(
    LiveCueNotePersistenceAdapter notePersistence,
    String userId, {
    bool saveBothLayers = false,
  }) async {
    if (_savingNoteLayers) return false;
    _savingNoteLayers = true;
    _markOverlayNeedsBuild();
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    final actor = user?.displayName ?? user?.email ?? user?.uid;
    var saved = false;

    try {
      final saveResult = await notePersistence.saveNoteLayers(
        userId: userId,
        actor: actor,
        privateText: _privateNoteContent,
        sharedText: _sharedNoteContent,
        privateStrokes: _privateLayerStrokes,
        sharedStrokes: _sharedLayerStrokes,
        editingSharedLayer: _editingSharedLayer,
        saveBothLayers: saveBothLayers,
      );
      saved = true;
      if (!mounted) return saved;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saveResult.wroteBoth
                ? '개인/공유 레이어 저장 완료'
                : (_editingSharedLayer ? '공유 레이어 저장 완료' : '개인 레이어 저장 완료'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return saved;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('레이어 메모 저장 실패: $error')));
    } finally {
      _savingNoteLayers = false;
      if (mounted) {
        _markOverlayNeedsBuild();
      }
    }
    return saved;
  }

  Future<_LiveCueContext> _loadContext(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    final teamRef = firestore.collection('teams').doc(widget.teamId);
    final projectRef = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId);
    final memberRef = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('members')
        .doc(userId);

    final results = await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
      projectRef.get().timeout(const Duration(seconds: 12)),
      memberRef.get().timeout(const Duration(seconds: 12)),
      teamRef.get().timeout(const Duration(seconds: 12)),
    ]);
    final project = results[0];
    final member = results[1];
    final team = results[2];
    final createdBy = (team.data()?['createdBy'] ?? '').toString();
    final isTeamCreator = team.exists && createdBy == userId;
    return _LiveCueContext(
      project: project,
      member: member,
      isTeamCreator: isTeamCreator,
    );
  }

  void _warmScoreTripletIfNeeded({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required String? currentSongId,
    required String? currentKey,
    required String currentTitle,
    required String? prevSongId,
    required String? prevKey,
    required String prevTitle,
    required String? nextSongId,
    required String? nextKey,
    required String nextTitle,
  }) {
    // Avoid cache/prefetch churn while actively drawing (Apple Pencil/touch).
    if (_drawingEnabled && _activeDrawingPointer != null) return;
    final signature =
        '${currentSongId ?? ''}|${currentKey ?? ''}|$currentTitle|'
        '${prevSongId ?? ''}|${prevKey ?? ''}|$prevTitle|'
        '${nextSongId ?? ''}|${nextKey ?? ''}|$nextTitle';
    if (_lastWarmPreviewSignature == signature) return;
    _lastWarmPreviewSignature = signature;

    final currentWarmStartedAt = DateTime.now().millisecondsSinceEpoch;
    final currentWarm = _warmPreview(
      firestore,
      storage,
      currentSongId,
      currentKey,
      currentTitle,
    );
    unawaited(
      currentWarm.whenComplete(() {
        Future<void>.delayed(_adjacentPreviewDelay, () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_drawingEnabled && _activeDrawingPointer != null) return;
            OpsMetrics.emit(
              'livecue_adjacent_preload_start',
              fields: <String, Object?>{
                'elapsedSinceCurrentWarmMs':
                    DateTime.now().millisecondsSinceEpoch -
                    currentWarmStartedAt,
                'currentSongId': currentSongId,
                'prevSongId': prevSongId,
                'nextSongId': nextSongId,
              },
            );
            _warmPreview(firestore, storage, prevSongId, prevKey, prevTitle);
            _warmPreview(firestore, storage, nextSongId, nextKey, nextTitle);
          });
        });
      }),
    );
  }

  Future<void> _seedFromSetlistIfNeeded(
    FirebaseFirestore firestore,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    Map<String, dynamic> cueData,
  ) async {
    if (_autoSeeding || _hasCueValue(cueData, 'current')) return;
    if (items.isEmpty) return;

    _autoSeeding = true;
    try {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      final updates = <String, dynamic>{
        ...await _cueFieldsFromSetlist(
          firestore,
          items.first.data(),
          prefix: 'current',
          teamId: widget.teamId,
        ),
      };
      if (items.length > 1) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            items[1].data(),
            prefix: 'next',
            teamId: widget.teamId,
          ),
        );
      } else {
        updates.addAll(_clearCueFields(prefix: 'next'));
      }
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedBy'] =
          user?.displayName ?? user?.email ?? user?.uid ?? '-';

      await _liveCueRefFor(
        firestore,
        widget.teamId,
        widget.projectId,
      ).set(updates, SetOptions(merge: true));
    } finally {
      _autoSeeding = false;
    }
  }

  Future<void> _applySetlistAsCurrent(
    FirebaseFirestore firestore,
    bool canEdit,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    int index,
  ) async {
    if (!canEdit) return;
    if (index < 0 || index >= items.length) return;

    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) return;

    final updates = <String, dynamic>{
      ...await _cueFieldsFromSetlist(
        firestore,
        items[index].data(),
        prefix: 'current',
        teamId: widget.teamId,
      ),
    };
    if (index + 1 < items.length) {
      updates.addAll(
        await _cueFieldsFromSetlist(
          firestore,
          items[index + 1].data(),
          prefix: 'next',
          teamId: widget.teamId,
        ),
      );
    } else {
      updates.addAll(_clearCueFields(prefix: 'next'));
    }
    updates['updatedAt'] = FieldValue.serverTimestamp();
    updates['updatedBy'] = user.displayName ?? user.email ?? user.uid;

    await _liveCueRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
    ).set(updates, SetOptions(merge: true));
    if (mounted) {
      _markOverlayNeedsBuild();
    }
  }

  Future<void> _moveByStep(
    FirebaseFirestore firestore,
    bool canEdit,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    Map<String, dynamic> cueData,
    int step,
  ) async {
    if (!canEdit || items.isEmpty || _moving) return;
    _moving = true;
    try {
      var index = LiveCueResolvedState.findCurrentIndex(
        items: items,
        cueData: cueData,
        cueLabelFromItem: _cueLabelFromItem,
        normalizeKeyText: normalizeKeyText,
      );
      if (index < 0) index = 0;
      final nextIndex = (index + step).clamp(0, items.length - 1);
      await _applySetlistAsCurrent(
        firestore,
        canEdit,
        items,
        nextIndex.toInt(),
      );
      _showOverlayTemporarily();
    } finally {
      _moving = false;
      if (mounted) {
        _markOverlayNeedsBuild();
      }
    }
  }

  Future<void> _setCurrentKey(
    FirebaseFirestore firestore,
    bool canEdit,
    String keyText,
  ) async {
    if (!canEdit) return;
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) return;

    await _liveCueRefFor(firestore, widget.teamId, widget.projectId).set({
      'currentKeyText': normalizeKeyText(keyText),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.displayName ?? user.email ?? user.uid,
    }, SetOptions(merge: true));
    if (mounted) {
      _showOverlayTemporarily();
      _markOverlayNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) =>
      _buildLiveCueFullScreenPage(this, context);
}
