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
import '../../core/roles.dart';
import '../../services/firebase_providers.dart';
import '../../services/song_search.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';
import 'live_cue_note_persistence_adapter.dart';
import 'models/sketch_stroke.dart';
import 'live_cue_stroke_engine.dart';
import 'live_cue_sync_coordinator.dart';
import 'next_viewer_contract.dart';
import 'next_viewer_host.dart';

DocumentReference<Map<String, dynamic>> _liveCueRefFor(
  FirebaseFirestore firestore,
  String teamId,
  String projectId,
) {
  return firestore
      .collection('teams')
      .doc(teamId)
      .collection('projects')
      .doc(projectId)
      .collection('liveCue')
      .doc('state');
}

CollectionReference<Map<String, dynamic>> _setlistRefFor(
  FirebaseFirestore firestore,
  String teamId,
  String projectId,
) {
  return firestore
      .collection('teams')
      .doc(teamId)
      .collection('projects')
      .doc(projectId)
      .collection('segmentA_setlist');
}

bool _hasCueValue(Map<String, dynamic> cueData, String prefix) {
  final songId = cueData['${prefix}SongId']?.toString().trim() ?? '';
  final displayTitle =
      cueData['${prefix}DisplayTitle']?.toString().trim() ?? '';
  final freeText = cueData['${prefix}FreeTextTitle']?.toString().trim() ?? '';
  return songId.isNotEmpty || displayTitle.isNotEmpty || freeText.isNotEmpty;
}

Map<String, dynamic> _clearCueFields({required String prefix}) {
  return {
    '${prefix}SongId': null,
    '${prefix}FreeTextTitle': null,
    '${prefix}DisplayTitle': null,
    '${prefix}KeyText': null,
    '${prefix}CueLabel': null,
  };
}

String _cueLabelFromItem(Map<String, dynamic> item, int fallbackOrder) {
  final raw = item['cueLabel']?.toString().trim();
  if (raw != null && raw.isNotEmpty) return raw;
  final order = item['order'];
  if (order is num) return order.toInt().toString();
  return fallbackOrder.toString();
}

String _titleFromItem(Map<String, dynamic> item) {
  return (item['displayTitle'] ?? item['freeTextTitle'] ?? '곡')
      .toString()
      .trim();
}

String? _keyFromItem(Map<String, dynamic> item) {
  final key = item['keyText']?.toString().trim();
  if (key == null || key.isEmpty) return null;
  return normalizeKeyText(key);
}

String _lineText({
  required String label,
  required String title,
  String? keyText,
}) {
  final parts = <String>[label, title];
  if (keyText != null && keyText.trim().isNotEmpty) {
    parts.add(normalizeKeyText(keyText));
  }
  return parts.join(' ');
}

const List<int> _liveCueDrawingPalette = <int>[
  0xFFD32F2F,
  0xFF1976D2,
  0xFF2E7D32,
  0xFFF9A825,
  0xFF000000,
  0xFFFFFFFF,
];

const String _nextViewerUrl = String.fromEnvironment(
  'WF_NEXT_VIEWER_URL',
  defaultValue: '',
);
const String _nextViewerReadbackMode = String.fromEnvironment(
  'WF_NEXT_WILL_READ_FREQUENTLY',
  defaultValue: 'enabled',
);
const int _liveCueImageCacheMaxEntries = 120;
const int _liveCueImageCacheMaxBytes = 80 * 1024 * 1024;

void _traceLiveCueSync(
  String scope,
  String event, {
  int? generation,
  int? sequence,
  String? detail,
}) {
  final buffer = StringBuffer('[LiveCueSync][$scope] $event');
  if (generation != null) {
    buffer.write(' generation=$generation');
  }
  if (sequence != null) {
    buffer.write(' seq=$sequence');
  }
  if (detail != null && detail.isNotEmpty) {
    buffer.write(' detail=$detail');
  }
  debugPrint(buffer.toString());
}

Future<SongCandidate?> _matchSongAutomatically(
  FirebaseFirestore firestore,
  String title,
) async {
  final exactTitle = title.trim();
  if (exactTitle.isNotEmpty) {
    try {
      final exactQuery = await firestore
          .collection('songs')
          .where('title', isEqualTo: exactTitle)
          .limit(1)
          .get();
      if (exactQuery.docs.isNotEmpty) {
        final doc = exactQuery.docs.first;
        return SongCandidate(
          id: doc.id,
          title: (doc.data()['title'] ?? '').toString(),
        );
      }
    } catch (_) {
      // Continue to normalized search fallback.
    }
  }
  final normalizedTitle = normalizeQuery(title);
  if (normalizedTitle.isEmpty) return null;
  final candidates = await findSongCandidates(firestore, normalizedTitle);
  if (candidates.isEmpty) return null;
  for (final candidate in candidates) {
    if (normalizeQuery(candidate.title) == normalizedTitle) return candidate;
  }
  return candidates.first;
}

List<String> _candidateTitlesFromFallback(String? fallbackTitle) {
  final seed = fallbackTitle?.trim() ?? '';
  if (seed.isEmpty) return const [];

  final titles = <String>{seed};
  final parsedSeed = parseSongInput(seed).title.trim();
  if (parsedSeed.isNotEmpty) {
    titles.add(parsedSeed);
  }

  final withoutCueLabel = seed
      .replaceFirst(RegExp(r'^\s*\d+(?:-\d+)?\s+'), '')
      .trim();
  if (withoutCueLabel.isNotEmpty) {
    titles.add(withoutCueLabel);
    final parsedWithoutLabel = parseSongInput(withoutCueLabel).title.trim();
    if (parsedWithoutLabel.isNotEmpty) {
      titles.add(parsedWithoutLabel);
    }
  }

  return titles.toList();
}

Future<List<String>> _songIdCandidatesForPreview(
  FirebaseFirestore firestore,
  String? preferredSongId,
  String? fallbackTitle,
) async {
  final candidateIds = <String>[];
  final seen = <String>{};
  void addId(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return;
    if (seen.add(value)) {
      candidateIds.add(value);
    }
  }

  addId(preferredSongId);

  final titleCandidates = _candidateTitlesFromFallback(fallbackTitle);
  for (final title in titleCandidates) {
    try {
      final exactQuery = await firestore
          .collection('songs')
          .where('title', isEqualTo: title)
          .limit(10)
          .get();
      for (final doc in exactQuery.docs) {
        addId(doc.id);
      }
    } catch (_) {
      // Continue with token-based matching.
    }

    final normalizedTitle = normalizeQuery(title);
    if (normalizedTitle.isEmpty) continue;
    try {
      final candidates = await findSongCandidates(firestore, normalizedTitle);
      for (final candidate in candidates) {
        addId(candidate.id);
      }
    } catch (_) {
      // Ignore and keep already resolved candidates.
    }
  }

  return candidateIds;
}

Future<Map<String, dynamic>> _cueFieldsFromSetlist(
  FirebaseFirestore firestore,
  Map<String, dynamic> setlistItem, {
  required String prefix,
}) async {
  String? songId = setlistItem['songId']?.toString().trim();
  String displayTitle =
      (setlistItem['displayTitle'] ?? setlistItem['freeTextTitle'] ?? '곡')
          .toString()
          .trim();
  String? freeTextTitle = setlistItem['freeTextTitle']?.toString().trim();

  final rawKey = setlistItem['keyText']?.toString().trim();
  final keyText = (rawKey == null || rawKey.isEmpty)
      ? null
      : normalizeKeyText(rawKey);

  final cueLabel = setlistItem['cueLabel']?.toString().trim();
  final orderValue = setlistItem['order'];
  final normalizedLabel = (cueLabel == null || cueLabel.isEmpty)
      ? orderValue?.toString()
      : cueLabel;

  if ((songId == null || songId.isEmpty) && displayTitle.isNotEmpty) {
    final matched = await _matchSongAutomatically(firestore, displayTitle);
    if (matched != null) {
      songId = matched.id;
      displayTitle = matched.title;
      freeTextTitle = null;
    }
  }

  final hasSongId = songId != null && songId.isNotEmpty;
  return {
    '${prefix}SongId': hasSongId ? songId : null,
    '${prefix}FreeTextTitle': hasSongId ? null : freeTextTitle,
    '${prefix}DisplayTitle': displayTitle,
    '${prefix}KeyText': keyText,
    '${prefix}CueLabel': normalizedLabel,
  };
}

Future<_LiveCueAssetPreview?> _loadCurrentPreview(
  FirebaseFirestore firestore,
  FirebaseStorage storage,
  String? songId,
  String? keyText,
  String? fallbackTitle,
) async {
  final songIdCandidates = await _songIdCandidatesForPreview(
    firestore,
    songId,
    fallbackTitle,
  );
  if (songIdCandidates.isEmpty) return null;
  final normalizedKey = (keyText == null || keyText.trim().isEmpty)
      ? null
      : normalizeKeyText(keyText);

  for (final candidateSongId in songIdCandidates) {
    QuerySnapshot<Map<String, dynamic>> assetsSnapshot;
    try {
      assetsSnapshot = await firestore
          .collection('songs')
          .doc(candidateSongId)
          .collection('assets')
          .orderBy('createdAt', descending: true)
          .get();
    } catch (_) {
      continue;
    }
    if (assetsSnapshot.docs.isEmpty) continue;

    final activeAssets = assetsSnapshot.docs
        .where((doc) => doc.data()['active'] != false)
        .toList();
    final sourceAssets = activeAssets.isNotEmpty
        ? activeAssets
        : assetsSnapshot.docs;

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
        final url = await resolveAssetDownloadUrl(
          storage,
          data,
        ).timeout(const Duration(seconds: 12));
        if (url == null || url.isEmpty) {
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

        Uint8List? initialBytes;
        if (isImage && !kIsWeb) {
          try {
            if (path != null) {
              initialBytes = await runWithRetry(
                () => storage.ref(path).getData(kMaxSongAssetBytes),
                maxAttempts: 2,
              );
            }
          } catch (_) {
            // Keep URL fallback path for environments where getData is flaky.
            initialBytes = null;
          }
        }

        return _LiveCueAssetPreview(
          url: url,
          isImage: isImage,
          fileName: data['fileName']?.toString() ?? 'asset',
          storagePath: previewIdentity,
          resolvedSongId: candidateSongId,
          initialBytes: initialBytes,
        );
      } catch (_) {
        // Skip broken or inaccessible asset and try the next candidate.
        continue;
      }
    }
  }

  return null;
}

int _keySortWeight(String keyText) {
  final normalized = canonicalKeyText(keyText);
  const canonicalOrder = [
    'C',
    'C#',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];
  final idx = canonicalOrder.indexOf(normalized);
  return idx < 0 ? 999 : idx;
}

Future<List<String>> _loadAvailableKeysForSong(
  FirebaseFirestore firestore,
  String songId,
) async {
  final assets = await firestore
      .collection('songs')
      .doc(songId)
      .collection('assets')
      .orderBy('createdAt', descending: true)
      .get();

  final keys = <String>{};
  for (final doc in assets.docs) {
    final key = assetKeyText(doc.data());
    if (key != null && key.isNotEmpty) {
      keys.add(normalizeKeyText(key));
    }
  }

  final list = keys.toList();
  list.sort((a, b) {
    final byWeight = _keySortWeight(a).compareTo(_keySortWeight(b));
    if (byWeight != 0) return byWeight;
    return a.compareTo(b);
  });
  return list;
}

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
        ),
      };
      if (items.length > 1) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            items[1].data(),
            prefix: 'next',
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
        ),
      };
      if (index + 1 < items.length) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            items[index + 1].data(),
            prefix: 'next',
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

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);
    final setlistRef = _setlistRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
    );
    final liveCueRef = _liveCueRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
    );
    final setlistQuery = setlistRef.orderBy('order');
    final syncStreams = _syncCoordinator.attach(
      setlistQuery: setlistQuery,
      liveCueRef: liveCueRef,
    );
    final setlistStream = syncStreams.setlist;
    final cueStream = syncStreams.cue;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!widget.canEdit) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (_latestSetlist.isEmpty) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.keyA) {
          _moveByStep(firestore, _latestSetlist, _latestCueData, -1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.keyD) {
          _moveByStep(firestore, _latestSetlist, _latestCueData, 1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AppContentFrame(
        maxWidth: 1260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionCard(
              icon: Icons.equalizer_rounded,
              title: 'LiveCue',
              subtitle: widget.canEdit
                  ? '운영 모드에서 곡을 전환하고, 악보보기에서 전체화면 악보를 확인합니다.'
                  : '운영 모드 상태와 악보보기를 실시간으로 확인합니다.',
              trailing: FilledButton.tonalIcon(
                onPressed: () => context.go(
                  '/teams/${widget.teamId}/projects/${widget.projectId}/live',
                ),
                icon: const Icon(Icons.fullscreen),
                label: const Text('악보보기'),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Chip(
                    avatar: Icon(Icons.swipe, size: 16),
                    label: Text('운영 모드'),
                  ),
                  const Chip(
                    avatar: Icon(Icons.fullscreen, size: 16),
                    label: Text('악보보기'),
                  ),
                  const Chip(
                    avatar: Icon(Icons.auto_awesome, size: 16),
                    label: Text('콘티 입력 자동 반영'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: setlistStream,
                builder: (context, setlistSnapshot) {
                  if (setlistSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const AppLoadingState(message: '콘티를 불러오는 중...');
                  }
                  if (setlistSnapshot.hasError) {
                    return AppStateCard(
                      icon: Icons.error_outline,
                      isError: true,
                      title: '콘티 로드 실패',
                      message: '${setlistSnapshot.error}',
                      actionLabel: '다시 시도',
                      onAction: () => setState(() {}),
                    );
                  }
                  final items = setlistSnapshot.data?.docs ?? [];
                  _latestSetlist = items;

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: cueStream,
                    builder: (context, cueSnapshot) {
                      if (cueSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        _beginCueWaitingWatchdog();
                        if (_isCueWaitingTimedOut) {
                          return AppStateCard(
                            icon: Icons.sync_problem_outlined,
                            isError: true,
                            title: 'LiveCue 상태 동기화 지연',
                            message:
                                '상태 문서를 읽지 못하고 있습니다. 권한/네트워크를 확인한 뒤 다시 시도해 주세요.',
                            actionLabel: '다시 시도',
                            onAction: () => setState(() {}),
                          );
                        }
                        return const AppLoadingState(
                          message: 'LiveCue 상태 동기화 중...',
                        );
                      }
                      _clearCueWaitingWatchdog();
                      if (cueSnapshot.hasError) {
                        return AppStateCard(
                          icon: Icons.sync_problem_outlined,
                          isError: true,
                          title: 'LiveCue 상태 로드 실패',
                          message: '${cueSnapshot.error}',
                          actionLabel: '다시 시도',
                          onAction: () => setState(() {}),
                        );
                      }

                      final cueData = cueSnapshot.data?.data() ?? {};
                      _latestCueData = cueData;
                      if (items.isNotEmpty &&
                          !_hasCueValue(cueData, 'current') &&
                          !_autoSeeding) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _seedFromSetlistIfNeeded(firestore, items, cueData);
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
                      final currentTitle = syncState.currentTitle;
                      final currentKey = syncState.currentKey;
                      final currentLabel = syncState.currentLabel;
                      final nextTitle = syncState.nextTitle;
                      final nextKey = syncState.nextKey;
                      final nextLabel = syncState.nextLabel;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (details) {
                          if (!widget.canEdit) return;
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity > 220) {
                            _moveByStep(firestore, items, cueData, -1);
                          } else if (velocity < -220) {
                            _moveByStep(firestore, items, cueData, 1);
                          }
                        },
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 1120;

                            final livePanel = AppSectionCard(
                              icon: Icons.equalizer_rounded,
                              title: '실시간 진행 라인',
                              subtitle: '운영 모드: 현재/다음 곡 전환',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.34),
                                    ),
                                    child: Text(
                                      _lineText(
                                        label: currentLabel,
                                        title: currentTitle,
                                        keyText: currentKey,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.46),
                                    ),
                                    child: Text(
                                      _lineText(
                                        label: nextLabel,
                                        title: nextTitle,
                                        keyText: nextKey,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: widget.canEdit
                                            ? () => _moveByStep(
                                                firestore,
                                                items,
                                                cueData,
                                                -1,
                                              )
                                            : null,
                                        icon: const Icon(Icons.chevron_left),
                                        label: const Text('이전'),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: widget.canEdit
                                            ? () => _moveByStep(
                                                firestore,
                                                items,
                                                cueData,
                                                1,
                                              )
                                            : null,
                                        icon: const Icon(Icons.chevron_right),
                                        label: const Text('다음'),
                                      ),
                                      const Chip(
                                        avatar: Icon(Icons.swipe, size: 16),
                                        label: Text('스와이프/화살표 전환'),
                                      ),
                                      const CircleOfFifthsHelpButton(
                                        label: '5도권 참고',
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );

                            final keysPanel =
                                (currentSongId != null &&
                                    currentSongId.isNotEmpty)
                                ? FutureBuilder<List<String>>(
                                    future: _loadAvailableKeysCached(
                                      firestore,
                                      currentSongId,
                                    ),
                                    builder: (context, keySnapshot) {
                                      final keys =
                                          keySnapshot.data ?? const <String>[];
                                      if (keys.length <= 1) {
                                        return const SizedBox.shrink();
                                      }
                                      final selectedKey =
                                          cueData['currentKeyText']
                                              ?.toString() ??
                                          '';
                                      return AppSectionCard(
                                        icon: Icons.piano_rounded,
                                        title: '현재 곡 키 선택',
                                        subtitle: '키 전환 시 악보 매칭 우선순위가 바뀝니다.',
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: keys
                                              .map(
                                                (key) => ChoiceChip(
                                                  label: Text(key),
                                                  selected:
                                                      normalizeKeyText(
                                                        selectedKey,
                                                      ) ==
                                                      normalizeKeyText(key),
                                                  onSelected: widget.canEdit
                                                      ? (_) => _setCurrentKey(
                                                          firestore,
                                                          key,
                                                        )
                                                      : null,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink();

                            final setlistPanel = AppSectionCard(
                              icon: Icons.format_list_numbered_rounded,
                              title: '세트리스트',
                              subtitle: 'LiveCue 반영 기준 목록',
                              child: items.isEmpty
                                  ? AppStateCard(
                                      icon: Icons
                                          .playlist_add_check_circle_outlined,
                                      title: '콘티가 비어 있습니다',
                                      message: widget.canEdit
                                          ? '예배 전 탭에서 콘티를 입력하면 자동으로 LiveCue에 반영됩니다.'
                                          : '팀장이 콘티를 입력하면 여기에서 곡 전환 상태를 볼 수 있습니다.',
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: items.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final data = items[index].data();
                                        final label = _cueLabelFromItem(
                                          data,
                                          index + 1,
                                        );
                                        final title = _titleFromItem(data);
                                        final key = _keyFromItem(data);
                                        final line = _lineText(
                                          label: label,
                                          title: title,
                                          keyText: key,
                                        );
                                        final isCurrent = index == currentIndex;
                                        return Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            color: isCurrent
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.1)
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.45),
                                          ),
                                          child: ListTile(
                                            title: Text(
                                              line,
                                              style: isCurrent
                                                  ? const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 17,
                                                    )
                                                  : const TextStyle(
                                                      fontSize: 16,
                                                    ),
                                            ),
                                            trailing: isCurrent
                                                ? const Icon(Icons.music_note)
                                                : (widget.canEdit
                                                      ? TextButton(
                                                          onPressed: () =>
                                                              _applySetlistAsCurrent(
                                                                firestore,
                                                                items,
                                                                index,
                                                              ),
                                                          child: const Text(
                                                            '현재로',
                                                          ),
                                                        )
                                                      : null),
                                            onTap: widget.canEdit
                                                ? () => _applySetlistAsCurrent(
                                                    firestore,
                                                    items,
                                                    index,
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                            );

                            if (isWide) {
                              return SingleChildScrollView(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 7,
                                      child: Column(
                                        children: [
                                          livePanel,
                                          const SizedBox(height: 10),
                                          keysPanel,
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(flex: 5, child: setlistPanel),
                                  ],
                                ),
                              );
                            }

                            return ListView(
                              children: [
                                livePanel,
                                const SizedBox(height: 10),
                                keysPanel,
                                const SizedBox(height: 10),
                                setlistPanel,
                              ],
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveCueFullScreenPage extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;
  final bool startInDrawMode;

  const LiveCueFullScreenPage({
    super.key,
    required this.teamId,
    required this.projectId,
    this.startInDrawMode = false,
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
  final ValueNotifier<int> _viewerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _overlayRevision = ValueNotifier<int>(0);
  int? _previousImageCacheMaxEntries;
  int? _previousImageCacheMaxBytes;
  Size _lastViewPhysicalSize = Size.zero;

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
      unawaited(_refreshViewerIdToken(user, forceRefresh: true));
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

  void _onNextViewerProtocolLog(String message) {
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
  ) => _renderPresenter.loadPreviewCached(
    songId: songId,
    keyText: keyText,
    fallbackTitle: fallbackTitle,
    loader: (resolvedSongId, resolvedKeyText, resolvedFallbackTitle) =>
        _loadCurrentPreview(
          firestore,
          storage,
          resolvedSongId,
          resolvedKeyText,
          resolvedFallbackTitle,
        ),
  );

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

  void _ensureViewerAssetKey(String key) =>
      _renderPresenter.ensureViewerAssetKey(key);

  void _syncImageRendererKey(String key) =>
      _renderPresenter.syncImageRendererKey(key);

  void _warmPreview(
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
          resolvedSongId,
          resolvedKeyText,
          resolvedFallbackTitle,
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

    final project = await projectRef.get().timeout(const Duration(seconds: 12));
    final member = await memberRef.get().timeout(const Duration(seconds: 12));
    final team = await teamRef.get().timeout(const Duration(seconds: 12));
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

    _warmPreview(firestore, storage, currentSongId, currentKey, currentTitle);
    _warmPreview(firestore, storage, prevSongId, prevKey, prevTitle);
    _warmPreview(firestore, storage, nextSongId, nextKey, nextTitle);
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
        ),
      };
      if (items.length > 1) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            items[1].data(),
            prefix: 'next',
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
      ),
    };
    if (index + 1 < items.length) {
      updates.addAll(
        await _cueFieldsFromSetlist(
          firestore,
          items[index + 1].data(),
          prefix: 'next',
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
  Widget build(BuildContext context) {
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
      future: _ensureContextFuture(firestore, user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final contextData = snapshot.data;
        if (contextData == null || contextData.project.data() == null) {
          return const Scaffold(body: Center(child: Text('프로젝트를 찾을 수 없습니다.')));
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
        final noteLayersKey =
            '${widget.teamId}/${widget.projectId}/${user.uid}';
        if ((!_noteLayersLoaded || _noteLayersKey != noteLayersKey) &&
            !_loadingNoteLayers) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ensureNoteLayersLoaded(notePersistence, user.uid);
          });
        }

        final setlistRef = _setlistRefFor(
          firestore,
          widget.teamId,
          widget.projectId,
        );
        final liveCueRef = _liveCueRefFor(
          firestore,
          widget.teamId,
          widget.projectId,
        );
        final setlistQuery = setlistRef.orderBy('order');
        final syncStreams = _syncCoordinator.attach(
          setlistQuery: setlistQuery,
          liveCueRef: liveCueRef,
        );
        final setlistStream = syncStreams.setlist;
        final cueStream = syncStreams.cue;

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (!canEdit || event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                if (_latestSetlist.isEmpty) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                    event.logicalKey == LogicalKeyboardKey.keyA) {
                  _moveByStep(
                    firestore,
                    canEdit,
                    _latestSetlist,
                    _latestCueData,
                    -1,
                  );
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                    event.logicalKey == LogicalKeyboardKey.keyD) {
                  _moveByStep(
                    firestore,
                    canEdit,
                    _latestSetlist,
                    _latestCueData,
                    1,
                  );
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: setlistStream,
                builder: (context, setlistSnapshot) {
                  if (setlistSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  if (setlistSnapshot.hasError) {
                    return Center(
                      child: Text(
                        '콘티 로드 실패: ${setlistSnapshot.error}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  final items = setlistSnapshot.data?.docs ?? [];
                  _latestSetlist = items;

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: cueStream,
                    builder: (context, cueSnapshot) {
                      if (cueSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        _beginCueWaitingWatchdog();
                        if (_isCueWaitingTimedOut) {
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
                                onAction: () => setState(() {}),
                              ),
                            ),
                          );
                        }
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      }
                      _clearCueWaitingWatchdog();
                      if (cueSnapshot.hasError) {
                        return Center(
                          child: Text(
                            'LiveCue 상태 로드 실패: ${cueSnapshot.error}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        );
                      }

                      final cueData = cueSnapshot.data?.data() ?? {};
                      _latestCueData = cueData;
                      if (items.isNotEmpty &&
                          !_hasCueValue(cueData, 'current') &&
                          !_autoSeeding) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _seedFromSetlistIfNeeded(firestore, items, cueData);
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
                      final currentPreviewTitle =
                          syncState.setlistCurrentTitle.isNotEmpty
                          ? syncState.setlistCurrentTitle
                          : currentTitle;
                      final currentPreviewCacheKey = _previewCacheKey(
                        currentSongId?.trim() ?? '',
                        currentKey,
                        currentPreviewTitle,
                      );
                      final cachedCurrentPreview = _renderPresenter
                          .cachedPreview(currentPreviewCacheKey);
                      final nextSongId = cueData['nextSongId']?.toString();
                      final nextKey = syncState.nextKey;
                      final nextTitle = syncState.nextTitle;

                      String? prevSongId;
                      String? prevKey;
                      String prevTitle = '';
                      if (currentIndex > 0 && currentIndex < items.length) {
                        final prevData = items[currentIndex - 1].data();
                        prevSongId = prevData['songId']?.toString();
                        prevKey = _keyFromItem(prevData);
                        prevTitle = _titleFromItem(prevData);
                      }

                      _warmScoreTripletIfNeeded(
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
                              behavior: _drawingEnabled
                                  ? HitTestBehavior.deferToChild
                                  : HitTestBehavior.opaque,
                              onTap: _drawingEnabled ? null : _toggleOverlay,
                              onHorizontalDragEnd: _drawingEnabled
                                  ? null
                                  : (details) {
                                      final velocity =
                                          details.primaryVelocity ?? 0;
                                      if (velocity > 220) {
                                        _moveByStep(
                                          firestore,
                                          canEdit,
                                          items,
                                          cueData,
                                          -1,
                                        );
                                      } else if (velocity < -220) {
                                        _moveByStep(
                                          firestore,
                                          canEdit,
                                          items,
                                          cueData,
                                          1,
                                        );
                                      }
                                    },
                              child: ValueListenableBuilder<int>(
                                valueListenable: _viewerRevision,
                                builder: (context, viewerVersion, child) {
                                  return FutureBuilder<_LiveCueAssetPreview?>(
                                    future: _loadPreviewCached(
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
                                                  _evictPreviewCache(
                                                    currentSongId ?? '',
                                                    currentKey,
                                                    currentPreviewTitle,
                                                  );
                                                  if (mounted) {
                                                    _markViewerNeedsBuild();
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
                                                    _showOverlayTemporarily();
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
                                                  final opened =
                                                      openUrlInNewTab(
                                                        preview.url,
                                                      );
                                                  if (!opened && mounted) {
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
                                          _ensureViewerAssetKey(viewerAssetKey);
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
                                                            (currentKey ==
                                                                    null ||
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
                                                      if (!opened && mounted) {
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
                                          _syncImageRendererKey(viewerAssetKey);
                                          final shouldUseHtmlStrategy =
                                              kIsWeb &&
                                              _fallbackToHtmlImageElement &&
                                              !_drawingEnabled;
                                          final htmlImageStrategy =
                                              shouldUseHtmlStrategy
                                              ? WebHtmlElementStrategy.prefer
                                              : WebHtmlElementStrategy.never;

                                          Widget buildImageLoadError(
                                            Object error,
                                          ) {
                                            final switched = _renderPresenter
                                                .tryActivateHtmlImageFallback(
                                                  hasInitialBytes:
                                                      bytes != null &&
                                                      bytes.isNotEmpty,
                                                  drawingEnabled:
                                                      _drawingEnabled,
                                                  isMounted: () => mounted,
                                                  requestRebuild:
                                                      _requestRenderPresenterRebuild,
                                                );
                                            if (switched) {
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(
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
                                                          return child;
                                                        }
                                                        return const Center(
                                                          child:
                                                              CircularProgressIndicator(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        );
                                                      },
                                                  errorBuilder:
                                                      (context, error, stack) =>
                                                          buildImageLoadError(
                                                            error,
                                                          ),
                                                );
                                          final canUseNextViewer =
                                              _renderPresenter.canUseNextViewer;
                                          if (canUseNextViewer &&
                                              _viewerIdToken == null) {
                                            return const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            );
                                          }
                                          if (canUseNextViewer &&
                                              _viewerIdToken != null) {
                                            final nextHostProps =
                                                NextViewerHostProps(
                                                  viewerUrl: _nextViewerUrl,
                                                  initData: NextViewerInitData(
                                                    teamId: widget.teamId,
                                                    projectId: widget.projectId,
                                                    currentSongId:
                                                        currentSongId,
                                                    currentKeyText: currentKey,
                                                    scoreImageUrl: preview.url,
                                                    idToken: _viewerIdToken!,
                                                    canEdit:
                                                        canEdit &&
                                                        _drawingEnabled,
                                                    editingSharedLayer:
                                                        _editingSharedLayer,
                                                    willReadFrequently:
                                                        _nextViewerWillReadFrequently,
                                                    privateStrokes:
                                                        _privateLayerStrokes,
                                                    sharedStrokes:
                                                        _sharedLayerStrokes,
                                                  ),
                                                  syncRevision:
                                                      _nextViewerSyncRevision,
                                                  onInkCommit:
                                                      _onNextViewerInkCommit,
                                                  onDirtyChanged:
                                                      _onNextViewerDirtyChanged,
                                                  onAssetError:
                                                      _onNextViewerAssetError,
                                                  onProtocolLog:
                                                      _onNextViewerProtocolLog,
                                                );
                                            return Center(
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
                                          }
                                          final canvasSize = Size(
                                            constraints.maxWidth,
                                            constraints.maxHeight,
                                          );
                                          final shouldShowStrokeOverlay =
                                              (_drawingEnabled && canEdit) ||
                                              _privateLayerStrokes.isNotEmpty ||
                                              _sharedLayerStrokes.isNotEmpty ||
                                              _strokeEngine.activeLayerStroke !=
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
                                                        painter: _LiveCueSketchPainter(
                                                          strokesProvider:
                                                              _overlayStrokesForRender,
                                                          repaint:
                                                              _strokeRevision,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (_drawingEnabled && canEdit)
                                                  Listener(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onPointerDown: (event) =>
                                                        _handleDrawingPointerDown(
                                                          event,
                                                          canvasSize,
                                                        ),
                                                    onPointerMove: (event) =>
                                                        _handleDrawingPointerMove(
                                                          event,
                                                          canvasSize,
                                                        ),
                                                    onPointerUp:
                                                        _handleDrawingPointerUpOrCancel,
                                                    onPointerCancel:
                                                        _handleDrawingPointerUpOrCancel,
                                                  ),
                                              ],
                                            ),
                                          );
                                          final viewWidget =
                                              _drawingEnabled && canEdit
                                              ? viewerContent
                                              : InteractiveViewer(
                                                  transformationController:
                                                      _viewerController,
                                                  minScale: 0.7,
                                                  maxScale: 8,
                                                  panEnabled: true,
                                                  scaleEnabled: true,
                                                  boundaryMargin:
                                                      const EdgeInsets.all(320),
                                                  clipBehavior: Clip.none,
                                                  child: viewerContent,
                                                );

                                          return Center(
                                            child: SizedBox(
                                              width: constraints.maxWidth,
                                              height: constraints.maxHeight,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  viewWidget,
                                                  if (kIsWeb &&
                                                      _fallbackToHtmlImageElement &&
                                                      _drawingEnabled &&
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
                                                            color:
                                                                Colors.white70,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
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
                                _overlayRevision,
                                _toolRevision,
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
                                          backgroundColor: _showOverlay
                                              ? Colors.black54
                                              : Colors.black26,
                                        ),
                                        onPressed: _handleBackNavigation,
                                        icon: const Icon(
                                          Icons.arrow_back,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (canEdit && _drawingEnabled)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: IconButton(
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                _showDrawingToolPanel
                                                ? Colors.white24
                                                : Colors.black54,
                                          ),
                                          tooltip: _showDrawingToolPanel
                                              ? '도구 패널 숨기기'
                                              : '도구 패널 보기',
                                          onPressed: _toggleDrawingToolPanel,
                                          icon: Icon(
                                            _showDrawingToolPanel
                                                ? Icons
                                                      .keyboard_arrow_down_rounded
                                                : Icons.tune_rounded,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    if (_showOverlay)
                                      Positioned(
                                        top: 8,
                                        right: canEdit && _drawingEnabled
                                            ? 56
                                            : 8,
                                        child: Row(
                                          children: [
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.black54,
                                              ),
                                              onPressed: canEdit
                                                  ? () => _moveByStep(
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
                                                  ? () => _moveByStep(
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
                                                  backgroundColor:
                                                      _drawingEnabled
                                                      ? Colors.white24
                                                      : Colors.black54,
                                                ),
                                                tooltip: _drawingEnabled
                                                    ? '필기 모드 끄기'
                                                    : '필기 모드 켜기',
                                                onPressed: () =>
                                                    _setDrawingEnabled(
                                                      !_drawingEnabled,
                                                    ),
                                                icon: Icon(
                                                  _drawingEnabled
                                                      ? Icons.edit_off_rounded
                                                      : Icons.draw_rounded,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                            if (canEdit && _drawingEnabled) ...[
                                              const SizedBox(width: 8),
                                              IconButton(
                                                style: IconButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.black54,
                                                ),
                                                tooltip: _editingSharedLayer
                                                    ? '현재: 공유 레이어'
                                                    : '현재: 개인 레이어',
                                                onPressed: () =>
                                                    _setEditingSharedLayer(
                                                      !_editingSharedLayer,
                                                    ),
                                                icon: Icon(
                                                  _editingSharedLayer
                                                      ? Icons.groups_rounded
                                                      : Icons.person_rounded,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              if (!(kIsWeb &&
                                                  _useNextViewer)) ...[
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        _eraserEnabled
                                                        ? Colors.white24
                                                        : Colors.black54,
                                                  ),
                                                  tooltip: _eraserEnabled
                                                      ? '지우개 모드'
                                                      : '펜 모드',
                                                  onPressed: () =>
                                                      _setEraserEnabled(
                                                        !_eraserEnabled,
                                                      ),
                                                  icon: Icon(
                                                    _eraserEnabled
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
                                    if (_showOverlay &&
                                        (!_drawingEnabled ||
                                            _showDrawingToolPanel))
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
                                                      _drawingEnabled
                                                          ? 460.0
                                                          : 380.0,
                                                    )
                                                    .toDouble(),
                                            maxHeight:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                (_drawingEnabled &&
                                                        _showDrawingToolPanel
                                                    ? 0.68
                                                    : 0.56),
                                          ),
                                          child: RepaintBoundary(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
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
                                                    if (currentSongId != null &&
                                                        currentSongId
                                                            .isNotEmpty)
                                                      FutureBuilder<
                                                        List<String>
                                                      >(
                                                        future:
                                                            _loadAvailableKeysCached(
                                                              firestore,
                                                              currentSongId,
                                                            ),
                                                        builder: (context, keySnapshot) {
                                                          final keys =
                                                              keySnapshot
                                                                  .data ??
                                                              const <String>[];
                                                          if (keys.length <=
                                                              1) {
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
                                                                      label:
                                                                          Text(
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
                                                                            ) => _setCurrentKey(
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
                                                    if (_loadingNoteLayers) ...[
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
                                                              _showPrivateLayer,
                                                          onSelected: (value) =>
                                                              _setLayerVisibility(
                                                                showPrivateLayer:
                                                                    value,
                                                              ),
                                                        ),
                                                        FilterChip(
                                                          label: const Text(
                                                            '공유 레이어',
                                                          ),
                                                          selected:
                                                              _showSharedLayer,
                                                          onSelected: (value) =>
                                                              _setLayerVisibility(
                                                                showSharedLayer:
                                                                    value,
                                                              ),
                                                        ),
                                                        if (kIsWeb &&
                                                            _useNextViewer)
                                                          Chip(
                                                            avatar: Icon(
                                                              _nextViewerDirty
                                                                  ? Icons
                                                                        .sync_problem_rounded
                                                                  : Icons
                                                                        .verified_rounded,
                                                              size: 16,
                                                              color:
                                                                  _nextViewerDirty
                                                                  ? Colors
                                                                        .orange
                                                                        .shade200
                                                                  : Colors
                                                                        .lightGreenAccent,
                                                            ),
                                                            label: Text(
                                                              _nextViewerDirty
                                                                  ? '미저장 필기 있음'
                                                                  : '필기 동기화 완료',
                                                            ),
                                                          ),
                                                        if (kIsWeb &&
                                                            _useNextViewer &&
                                                            _nextViewerStatus !=
                                                                null &&
                                                            _nextViewerStatus!
                                                                .isNotEmpty)
                                                          Chip(
                                                            label: Text(
                                                              _nextViewerStatus!,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        if (canEdit)
                                                          FilledButton.tonalIcon(
                                                            onPressed: () =>
                                                                _setDrawingEnabled(
                                                                  !_drawingEnabled,
                                                                ),
                                                            icon: Icon(
                                                              _drawingEnabled
                                                                  ? Icons
                                                                        .edit_off_rounded
                                                                  : Icons
                                                                        .draw_rounded,
                                                            ),
                                                            label: Text(
                                                              _drawingEnabled
                                                                  ? '필기 모드 종료'
                                                                  : '필기 모드 시작',
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (canEdit &&
                                                        _drawingEnabled) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        _editingSharedLayer
                                                            ? '공유 레이어 편집 중 (팀원 모두에게 공유)'
                                                            : '개인 레이어 편집 중 (나만 보임)',
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      if (kIsWeb &&
                                                          _useNextViewer) ...[
                                                        const Text(
                                                          'Next.js Viewer가 필기/지우개/되돌리기를 처리합니다. Host는 저장과 동기화만 담당합니다.',
                                                          style: TextStyle(
                                                            color:
                                                                Colors.white70,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            ChoiceChip(
                                                              label: const Text(
                                                                '개인 레이어 편집',
                                                              ),
                                                              selected:
                                                                  !_editingSharedLayer,
                                                              onSelected: (_) =>
                                                                  _setEditingSharedLayer(
                                                                    false,
                                                                  ),
                                                            ),
                                                            ChoiceChip(
                                                              label: const Text(
                                                                '공유 레이어 편집',
                                                              ),
                                                              selected:
                                                                  _editingSharedLayer,
                                                              onSelected: (_) =>
                                                                  _setEditingSharedLayer(
                                                                    true,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: FilledButton.icon(
                                                            onPressed:
                                                                _savingNoteLayers
                                                                ? null
                                                                : () async {
                                                                    final saved = await _saveLayerNotes(
                                                                      notePersistence,
                                                                      user.uid,
                                                                      saveBothLayers:
                                                                          true,
                                                                    );
                                                                    if (!saved ||
                                                                        !mounted) {
                                                                      return;
                                                                    }
                                                                    _nextViewerDirty =
                                                                        false;
                                                                    _nextViewerSyncRevision =
                                                                        _nextViewerSyncRevision +
                                                                        1;
                                                                    _markViewerNeedsBuild();
                                                                    _markOverlayNeedsBuild();
                                                                  },
                                                            icon:
                                                                _savingNoteLayers
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
                                                                  !_eraserEnabled,
                                                              onSelected: (_) =>
                                                                  _setEraserEnabled(
                                                                    false,
                                                                  ),
                                                            ),
                                                            ChoiceChip(
                                                              label: const Text(
                                                                '지우개',
                                                              ),
                                                              selected:
                                                                  _eraserEnabled,
                                                              onSelected: (_) =>
                                                                  _setEraserEnabled(
                                                                    true,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        if (_eraserEnabled)
                                                          const Text(
                                                            '선을 문지르면 해당 획이 지워집니다.',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white70,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        if (_eraserEnabled)
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                        if (!_eraserEnabled)
                                                          Wrap(
                                                            spacing: 8,
                                                            runSpacing: 8,
                                                            children: _liveCueDrawingPalette
                                                                .map(
                                                                  (
                                                                    colorValue,
                                                                  ) => GestureDetector(
                                                                    onTap: () =>
                                                                        _setDrawingColorValue(
                                                                          colorValue,
                                                                        ),
                                                                    child: Container(
                                                                      width: 26,
                                                                      height:
                                                                          26,
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
                                                                              _drawingColorValue ==
                                                                                  colorValue
                                                                              ? Colors.white
                                                                              : Colors.white38,
                                                                          width:
                                                                              _drawingColorValue ==
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
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
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
                                                                      (_drawingStrokeWidth -
                                                                              width)
                                                                          .abs() <
                                                                      0.05,
                                                                  onSelected: (_) =>
                                                                      _setDrawingStrokeWidth(
                                                                        width,
                                                                      ),
                                                                ),
                                                              )
                                                              .toList(),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            OutlinedButton.icon(
                                                              onPressed:
                                                                  _undoLayerStroke,
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
                                                                  _clearLayerStroke,
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
                                                                  _savingNoteLayers
                                                                  ? null
                                                                  : () async {
                                                                      final saved = await _saveLayerNotes(
                                                                        notePersistence,
                                                                        user.uid,
                                                                      );
                                                                      if (!saved ||
                                                                          !mounted) {
                                                                        return;
                                                                      }
                                                                    },
                                                              icon:
                                                                  _savingNoteLayers
                                                                  ? const SizedBox(
                                                                      width: 14,
                                                                      height:
                                                                          14,
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
                                                                _editingSharedLayer
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

  final bool isWeb;
  final TransformationController viewerController = TransformationController();
  final Map<String, Future<_LiveCueAssetPreview?>> _previewCache = {};
  final Map<String, _LiveCueAssetPreview> _resolvedPreviewCache = {};
  final Set<String> _prefetchedPreviewKeys = <String>{};
  final Set<String> _queuedPrefetchKeys = <String>{};
  final ListQueue<String> _previewCacheOrder = ListQueue<String>();
  final ListQueue<String> _prefetchCacheOrder = ListQueue<String>();

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
      _resolvedPreviewCache[cacheKey];

  void dispose() {
    _overlayTimer?.cancel();
    _previewCache.clear();
    _resolvedPreviewCache.clear();
    _prefetchedPreviewKeys.clear();
    _queuedPrefetchKeys.clear();
    _previewCacheOrder.clear();
    _prefetchCacheOrder.clear();
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
    final existing = _previewCache[cacheKey];
    if (existing != null) return existing;
    final future = loader(safeSongId, keyText, safeTitle)
        .then((preview) {
          if (preview == null) {
            _previewCache.remove(cacheKey);
            _resolvedPreviewCache.remove(cacheKey);
            _previewCacheOrder.remove(cacheKey);
          } else {
            _resolvedPreviewCache[cacheKey] = preview;
            _rememberResolvedPreview(cacheKey);
          }
          return preview;
        })
        .catchError((error, stackTrace) {
          _previewCache.remove(cacheKey);
          _resolvedPreviewCache.remove(cacheKey);
          _previewCacheOrder.remove(cacheKey);
          throw error;
        });
    _previewCache[cacheKey] = future;
    return future;
  }

  void evictPreviewCache(
    String songId,
    String? keyText,
    String? fallbackTitle,
  ) {
    final cacheKey = previewCacheKey(songId, keyText, fallbackTitle);
    _previewCache.remove(cacheKey);
    _resolvedPreviewCache.remove(cacheKey);
    _prefetchedPreviewKeys.remove(cacheKey);
    _queuedPrefetchKeys.remove(cacheKey);
    _previewCacheOrder.remove(cacheKey);
    _prefetchCacheOrder.remove(cacheKey);
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

  void warmPreview({
    required String? songId,
    required String? keyText,
    required String? fallbackTitle,
    required BuildContext context,
    required bool Function() isMounted,
    required _LiveCuePreviewLoader loader,
  }) {
    final safeSongId = songId?.trim() ?? '';
    final safeTitle = fallbackTitle?.trim() ?? '';
    if (safeSongId.isEmpty && safeTitle.isEmpty) return;
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
  }

  void _queuePreviewPrefetch({
    required String cacheKey,
    required Future<_LiveCueAssetPreview?> previewFuture,
    required BuildContext context,
    required bool Function() isMounted,
  }) {
    if (_prefetchedPreviewKeys.contains(cacheKey)) return;
    if (!_queuedPrefetchKeys.add(cacheKey)) return;
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
            _queuedPrefetchKeys.remove(cacheKey);
          }),
    );
  }

  void _rememberResolvedPreview(String cacheKey) {
    _previewCacheOrder.remove(cacheKey);
    _previewCacheOrder.addLast(cacheKey);
    while (_previewCacheOrder.length > _maxResolvedPreviewEntries) {
      final oldest = _previewCacheOrder.removeFirst();
      _previewCache.remove(oldest);
      _resolvedPreviewCache.remove(oldest);
      _prefetchedPreviewKeys.remove(oldest);
      _queuedPrefetchKeys.remove(oldest);
      _prefetchCacheOrder.remove(oldest);
    }
  }

  void _rememberPrefetchedPreview(String cacheKey) {
    _prefetchCacheOrder.remove(cacheKey);
    _prefetchCacheOrder.addLast(cacheKey);
    _prefetchedPreviewKeys.add(cacheKey);
    while (_prefetchCacheOrder.length > _maxPrefetchedPreviewEntries) {
      final oldest = _prefetchCacheOrder.removeFirst();
      _prefetchedPreviewKeys.remove(oldest);
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

  const _LiveCueAssetPreview({
    required this.url,
    required this.isImage,
    required this.fileName,
    required this.storagePath,
    this.resolvedSongId,
    this.initialBytes,
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
