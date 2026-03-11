import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef LiveCueSyncTraceLogger =
    void Function(
      String scope,
      String event, {
      int? generation,
      int? sequence,
      String? detail,
    });

typedef LiveCueCueLabelResolver =
    String Function(Map<String, dynamic> item, int fallbackOrder);
typedef LiveCueTitleResolver = String Function(Map<String, dynamic> item);
typedef LiveCueKeyResolver = String? Function(Map<String, dynamic> item);
typedef LiveCueKeyNormalizer = String Function(String keyText);

class LiveCueSyncStreams {
  final Stream<QuerySnapshot<Map<String, dynamic>>> setlist;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> cue;

  const LiveCueSyncStreams({required this.setlist, required this.cue});
}

class LiveCueResolvedState {
  final int matchedCurrentIndex;
  final int currentIndex;
  final int nextIndex;
  final String? currentSongId;
  final String currentTitle;
  final String? currentKey;
  final String currentLabel;
  final String nextTitle;
  final String? nextKey;
  final String nextLabel;
  final String setlistCurrentTitle;
  final Map<String, dynamic>? matchedCurrentSetlistData;

  const LiveCueResolvedState({
    required this.matchedCurrentIndex,
    required this.currentIndex,
    required this.nextIndex,
    required this.currentSongId,
    required this.currentTitle,
    required this.currentKey,
    required this.currentLabel,
    required this.nextTitle,
    required this.nextKey,
    required this.nextLabel,
    required this.setlistCurrentTitle,
    required this.matchedCurrentSetlistData,
  });

  static String _normalizeCueLabel(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return '';
    if (RegExp(r'^\\d+$').hasMatch(value)) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed.toString();
    }
    return value.toLowerCase();
  }

  static int findCurrentIndex({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    required Map<String, dynamic> cueData,
    required LiveCueCueLabelResolver cueLabelFromItem,
    required LiveCueKeyNormalizer normalizeKeyText,
  }) {
    final currentCueLabel = _normalizeCueLabel(cueData['currentCueLabel']);
    final currentSongId =
        cueData['currentSongId']?.toString().trim().toLowerCase() ?? '';
    final currentTitle =
        (cueData['currentDisplayTitle'] ??
                cueData['currentFreeTextTitle'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final rawCurrentKey = cueData['currentKeyText']?.toString().trim();
    final currentKey = (rawCurrentKey == null || rawCurrentKey.isEmpty)
        ? ''
        : normalizeKeyText(rawCurrentKey);

    if (currentCueLabel.isNotEmpty) {
      for (var i = 0; i < items.length; i++) {
        final itemCueLabel = _normalizeCueLabel(
          cueLabelFromItem(items[i].data(), i + 1),
        );
        if (itemCueLabel.isNotEmpty && itemCueLabel == currentCueLabel) {
          return i;
        }
      }
    }

    int titleFallbackIndex = -1;
    for (var i = 0; i < items.length; i++) {
      final data = items[i].data();
      final songId = data['songId']?.toString().trim().toLowerCase() ?? '';
      if (currentSongId.isNotEmpty &&
          songId.isNotEmpty &&
          currentSongId == songId) {
        return i;
      }
      final title = (data['displayTitle'] ?? data['freeTextTitle'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (currentTitle.isNotEmpty && title == currentTitle) {
        if (currentKey.isNotEmpty) {
          final itemRawKey = data['keyText']?.toString().trim();
          final itemKey = (itemRawKey == null || itemRawKey.isEmpty)
              ? ''
              : normalizeKeyText(itemRawKey);
          if (itemKey.isNotEmpty && itemKey == currentKey) {
            return i;
          }
        }
        titleFallbackIndex = i;
      }
    }
    return titleFallbackIndex;
  }

  static LiveCueResolvedState resolve({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    required Map<String, dynamic> cueData,
    required LiveCueCueLabelResolver cueLabelFromItem,
    required LiveCueTitleResolver titleFromItem,
    required LiveCueKeyResolver keyFromItem,
    required LiveCueKeyNormalizer normalizeKeyText,
  }) {
    final matchedCurrentIndex = findCurrentIndex(
      items: items,
      cueData: cueData,
      cueLabelFromItem: cueLabelFromItem,
      normalizeKeyText: normalizeKeyText,
    );
    final currentIndex = matchedCurrentIndex < 0 && items.isNotEmpty
        ? 0
        : matchedCurrentIndex;

    final matchedCurrentSetlistData =
        (matchedCurrentIndex >= 0 && matchedCurrentIndex < items.length)
        ? items[matchedCurrentIndex].data()
        : null;

    final cueCurrentSongId = cueData['currentSongId']?.toString().trim();
    final fallbackCurrentSongId = matchedCurrentSetlistData?['songId']
        ?.toString()
        .trim();
    final currentSongId =
        (cueCurrentSongId != null && cueCurrentSongId.isNotEmpty)
        ? cueCurrentSongId
        : (fallbackCurrentSongId == null || fallbackCurrentSongId.isEmpty)
        ? null
        : fallbackCurrentSongId;

    final setlistCurrentTitle = matchedCurrentSetlistData == null
        ? ''
        : titleFromItem(matchedCurrentSetlistData);
    final cueCurrentTitle =
        cueData['currentDisplayTitle']?.toString().trim() ??
        cueData['currentFreeTextTitle']?.toString().trim() ??
        '';
    final currentTitle =
        (cueCurrentSongId != null && cueCurrentSongId.isNotEmpty)
        ? (cueCurrentTitle.isNotEmpty
              ? cueCurrentTitle
              : (setlistCurrentTitle.isNotEmpty
                    ? setlistCurrentTitle
                    : '현재 곡 없음'))
        : (setlistCurrentTitle.isNotEmpty
              ? setlistCurrentTitle
              : (cueCurrentTitle.isNotEmpty ? cueCurrentTitle : '현재 곡 없음'));

    final cueCurrentKey = cueData['currentKeyText']?.toString().trim();
    final setlistCurrentKey = keyFromItem(
      matchedCurrentSetlistData ?? const {},
    );
    final currentKey = (cueCurrentSongId != null && cueCurrentSongId.isNotEmpty)
        ? ((cueCurrentKey == null || cueCurrentKey.isEmpty)
              ? setlistCurrentKey
              : cueCurrentKey)
        : ((setlistCurrentKey == null || setlistCurrentKey.isEmpty)
              ? cueCurrentKey
              : setlistCurrentKey);

    final currentLabel =
        cueData['currentCueLabel']?.toString() ??
        (currentIndex >= 0 && currentIndex < items.length
            ? cueLabelFromItem(items[currentIndex].data(), currentIndex + 1)
            : '현재');

    final nextIndex = currentIndex >= 0 && currentIndex + 1 < items.length
        ? currentIndex + 1
        : -1;
    final nextLabel =
        cueData['nextCueLabel']?.toString() ??
        (nextIndex >= 0
            ? cueLabelFromItem(items[nextIndex].data(), nextIndex + 1)
            : '다음');
    final nextTitle =
        cueData['nextDisplayTitle']?.toString() ??
        cueData['nextFreeTextTitle']?.toString() ??
        (nextIndex >= 0 ? titleFromItem(items[nextIndex].data()) : '다음 곡 없음');
    final nextKey = cueData['nextKeyText']?.toString();

    return LiveCueResolvedState(
      matchedCurrentIndex: matchedCurrentIndex,
      currentIndex: currentIndex,
      nextIndex: nextIndex,
      currentSongId: currentSongId,
      currentTitle: currentTitle,
      currentKey: currentKey,
      currentLabel: currentLabel,
      nextTitle: nextTitle,
      nextKey: nextKey,
      nextLabel: nextLabel,
      setlistCurrentTitle: setlistCurrentTitle,
      matchedCurrentSetlistData: matchedCurrentSetlistData,
    );
  }
}

class LiveCueSyncCoordinator {
  final String scope;
  final String teamId;
  final String projectId;
  final bool isWeb;
  final bool Function() isMounted;
  final LiveCueSyncTraceLogger traceLogger;
  final Duration webSetlistPollInterval;
  final Duration webCuePollInterval;

  String? _webPollingScopeKey;
  int _webPollingGeneration = 0;
  String? _nativePollingScopeKey;
  int _nativePollingGeneration = 0;
  int _nativeSetlistSequence = 0;
  int _nativeCueSequence = 0;
  int _setlistEmissionSequence = 0;
  int _cueEmissionSequence = 0;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _nativeSetlistStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _nativeCueStream;
  Future<void> _webPollingSwitchQueue = Future<void>.value();
  StreamController<QuerySnapshot<Map<String, dynamic>>>? _webSetlistController;
  StreamController<DocumentSnapshot<Map<String, dynamic>>>? _webCueController;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _webSetlistSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _webCueSubscription;

  LiveCueSyncCoordinator({
    required this.scope,
    required this.teamId,
    required this.projectId,
    required this.isWeb,
    required this.isMounted,
    required this.traceLogger,
    this.webSetlistPollInterval = const Duration(milliseconds: 3500),
    this.webCuePollInterval = const Duration(milliseconds: 1000),
  }) {
    if (isWeb) {
      _webSetlistController =
          StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
      _webCueController =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
    }
  }

  LiveCueSyncStreams attach({
    required Query<Map<String, dynamic>> setlistQuery,
    required DocumentReference<Map<String, dynamic>> liveCueRef,
  }) {
    _ensureNativeSnapshotStreams(setlistQuery, liveCueRef);
    if (isWeb) {
      _ensureWebPollingStreams(setlistQuery, liveCueRef);
    }
    return LiveCueSyncStreams(
      setlist: isWeb
          ? _webSetlistController!.stream
          : (_nativeSetlistStream ?? setlistQuery.snapshots()),
      cue: isWeb
          ? _webCueController!.stream
          : (_nativeCueStream ?? liveCueRef.snapshots()),
    );
  }

  Future<void> dispose() async {
    if (!isWeb) return;
    _webPollingGeneration += 1;
    await _cancelWebPollingSubscriptions();
    await _webSetlistController?.close();
    await _webCueController?.close();
  }

  void _trace(String event, {int? generation, int? sequence, String? detail}) {
    traceLogger(
      scope,
      event,
      generation: generation,
      sequence: sequence,
      detail: detail,
    );
  }

  void _ensureNativeSnapshotStreams(
    Query<Map<String, dynamic>> setlistQuery,
    DocumentReference<Map<String, dynamic>> liveCueRef,
  ) {
    if (isWeb) return;
    final scopeKey = '$teamId/$projectId';
    if (_nativePollingScopeKey == scopeKey &&
        _nativeSetlistStream != null &&
        _nativeCueStream != null) {
      return;
    }

    _nativePollingScopeKey = scopeKey;
    final generation = ++_nativePollingGeneration;
    _nativeSetlistSequence = 0;
    _nativeCueSequence = 0;
    _trace('native-stream-switch', generation: generation);

    _nativeSetlistStream = setlistQuery.snapshots().map((snapshot) {
      if (generation != _nativePollingGeneration) {
        _trace('setlist-native-drop-stale', generation: generation);
      }
      _nativeSetlistSequence += 1;
      _trace(
        'setlist-native-emit',
        generation: generation,
        sequence: _nativeSetlistSequence,
        detail: '${snapshot.docs.length} docs',
      );
      return snapshot;
    });

    _nativeCueStream = liveCueRef.snapshots().map((snapshot) {
      if (generation != _nativePollingGeneration) {
        _trace('cue-native-drop-stale', generation: generation);
      }
      _nativeCueSequence += 1;
      _trace(
        'cue-native-emit',
        generation: generation,
        sequence: _nativeCueSequence,
      );
      return snapshot;
    });
  }

  Future<void> _cancelWebPollingSubscriptions() async {
    final setlistSubscription = _webSetlistSubscription;
    final cueSubscription = _webCueSubscription;
    _webSetlistSubscription = null;
    _webCueSubscription = null;

    final pending = <Future<void>>[];
    if (setlistSubscription != null) {
      pending.add(setlistSubscription.cancel());
    }
    if (cueSubscription != null) {
      pending.add(cueSubscription.cancel());
    }
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  Future<void> _replaceWebPollingStreams(
    Query<Map<String, dynamic>> setlistQuery,
    DocumentReference<Map<String, dynamic>> liveCueRef,
  ) async {
    if (!isWeb) return;
    final generation = ++_webPollingGeneration;
    _setlistEmissionSequence = 0;
    _cueEmissionSequence = 0;
    _trace('polling-switch-start', generation: generation);

    await _cancelWebPollingSubscriptions();

    if (!isMounted() || generation != _webPollingGeneration) {
      return;
    }

    final setlistController = _webSetlistController;
    final cueController = _webCueController;
    if (setlistController == null ||
        cueController == null ||
        setlistController.isClosed ||
        cueController.isClosed) {
      return;
    }

    _webSetlistSubscription = _setlistPollingStream(setlistQuery).listen(
      (snapshot) {
        if (generation != _webPollingGeneration || setlistController.isClosed) {
          return;
        }
        _trace(
          'setlist-forward',
          generation: generation,
          sequence: _setlistEmissionSequence,
          detail: '${snapshot.docs.length} docs',
        );
        setlistController.add(snapshot);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _webPollingGeneration || setlistController.isClosed) {
          return;
        }
        _trace(
          'setlist-forward-error',
          generation: generation,
          detail: '$error',
        );
        setlistController.addError(error, stackTrace);
      },
      onDone: () {
        if (generation != _webPollingGeneration) {
          return;
        }
        _trace('setlist-forward-done', generation: generation);
        _webSetlistSubscription = null;
      },
    );

    _webCueSubscription = _liveCuePollingStream(liveCueRef).listen(
      (snapshot) {
        if (generation != _webPollingGeneration || cueController.isClosed) {
          return;
        }
        _trace(
          'cue-forward',
          generation: generation,
          sequence: _cueEmissionSequence,
        );
        cueController.add(snapshot);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _webPollingGeneration || cueController.isClosed) {
          return;
        }
        _trace('cue-forward-error', generation: generation, detail: '$error');
        cueController.addError(error, stackTrace);
      },
      onDone: () {
        if (generation != _webPollingGeneration) {
          return;
        }
        _trace('cue-forward-done', generation: generation);
        _webCueSubscription = null;
      },
    );
    _trace('polling-switch-ready', generation: generation);
  }

  void _ensureWebPollingStreams(
    Query<Map<String, dynamic>> setlistQuery,
    DocumentReference<Map<String, dynamic>> liveCueRef,
  ) {
    if (!isWeb) return;
    final scopeKey = '$teamId/$projectId';
    if (_webPollingScopeKey == scopeKey &&
        _webSetlistSubscription != null &&
        _webCueSubscription != null) {
      return;
    }
    _webPollingScopeKey = scopeKey;
    _webPollingSwitchQueue = _webPollingSwitchQueue
        .catchError((Object _) {})
        .then((_) async {
          await _replaceWebPollingStreams(setlistQuery, liveCueRef);
        })
        .catchError((Object error, StackTrace stackTrace) {
          _trace(
            'polling-switch-error',
            generation: _webPollingGeneration,
            detail: '$error',
          );
        });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _setlistPollingStream(
    Query<Map<String, dynamic>> query,
  ) async* {
    QuerySnapshot<Map<String, dynamic>>? lastGoodSnapshot;
    String? lastSignature;
    while (isMounted()) {
      try {
        final snapshot = await query.get().timeout(const Duration(seconds: 12));
        final signature = _setlistSignature(snapshot);
        if (signature != lastSignature) {
          lastSignature = signature;
          lastGoodSnapshot = snapshot;
          _setlistEmissionSequence += 1;
          _trace(
            'setlist-emit',
            generation: _webPollingGeneration,
            sequence: _setlistEmissionSequence,
            detail: '${snapshot.docs.length} docs',
          );
          yield snapshot;
        }
      } catch (error, stackTrace) {
        _trace(
          'setlist-poll-error',
          generation: _webPollingGeneration,
          detail: '$error',
        );
        if (lastGoodSnapshot != null) {
          yield lastGoodSnapshot;
        } else {
          yield* Stream<QuerySnapshot<Map<String, dynamic>>>.error(
            error,
            stackTrace,
          );
          return;
        }
      }
      await Future<void>.delayed(webSetlistPollInterval);
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _liveCuePollingStream(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async* {
    DocumentSnapshot<Map<String, dynamic>>? lastGoodSnapshot;
    String? lastSignature;
    while (isMounted()) {
      try {
        final snapshot = await docRef.get().timeout(
          const Duration(seconds: 12),
        );
        final signature = _liveCueSignature(snapshot);
        if (signature != lastSignature) {
          lastSignature = signature;
          lastGoodSnapshot = snapshot;
          _cueEmissionSequence += 1;
          _trace(
            'cue-emit',
            generation: _webPollingGeneration,
            sequence: _cueEmissionSequence,
          );
          yield snapshot;
        }
      } catch (error, stackTrace) {
        _trace(
          'cue-poll-error',
          generation: _webPollingGeneration,
          detail: '$error',
        );
        if (lastGoodSnapshot != null) {
          yield lastGoodSnapshot;
        } else {
          yield* Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
            error,
            stackTrace,
          );
          return;
        }
      }
      await Future<void>.delayed(webCuePollInterval);
    }
  }

  String _setlistSignature(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty) return '<empty>';
    final buffer = StringBuffer();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      buffer
        ..write(doc.id)
        ..write('|')
        ..write(data['order'])
        ..write('|')
        ..write(data['songId'])
        ..write('|')
        ..write(data['displayTitle'])
        ..write('|')
        ..write(data['freeTextTitle'])
        ..write('|')
        ..write(data['keyText'])
        ..write(';');
    }
    return buffer.toString();
  }

  String _liveCueSignature(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final watchedKeys = <String>[
      'currentSongId',
      'currentDisplayTitle',
      'currentFreeTextTitle',
      'currentKeyText',
      'currentCueLabel',
      'nextSongId',
      'nextDisplayTitle',
      'nextFreeTextTitle',
      'nextKeyText',
      'nextCueLabel',
      'updatedAt',
      'updatedBy',
    ];
    final buffer = StringBuffer(snapshot.id);
    for (final key in watchedKeys) {
      buffer
        ..write('|')
        ..write(key)
        ..write('=')
        ..write(data[key]);
    }
    return buffer.toString();
  }
}
