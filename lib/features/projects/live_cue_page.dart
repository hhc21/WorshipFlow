import 'dart:async';

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
import '../../services/ops_metrics.dart';
import '../../services/song_search.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/firestore_id.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';

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

DocumentReference<Map<String, dynamic>> _privateProjectNoteRefFor(
  FirebaseFirestore firestore,
  String teamId,
  String projectId,
  String userId,
) {
  return firestore
      .collection('teams')
      .doc(teamId)
      .collection('userProjectNotes')
      .doc(privateProjectNoteDocIdV2(projectId, userId));
}

DocumentReference<Map<String, dynamic>> _sharedProjectNoteRefFor(
  FirebaseFirestore firestore,
  String teamId,
  String projectId,
) {
  return firestore
      .collection('teams')
      .doc(teamId)
      .collection('projects')
      .doc(projectId)
      .collection('sharedNotes')
      .doc('main');
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

const Duration _webSetlistPollInterval = Duration(milliseconds: 3500);
const Duration _webCuePollInterval = Duration(milliseconds: 1000);

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

int _findCurrentIndex(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  Map<String, dynamic> liveCueData,
) {
  final currentSongId =
      liveCueData['currentSongId']?.toString().trim().toLowerCase() ?? '';
  final currentTitle =
      (liveCueData['currentDisplayTitle'] ??
              liveCueData['currentFreeTextTitle'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();

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
      return i;
    }
  }
  return -1;
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
  final FocusNode _focusNode = FocusNode();
  final Map<String, Future<List<String>>> _songKeysFutureCache = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestSetlist =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Map<String, dynamic> _latestCueData = const <String, dynamic>{};
  bool _autoSeeding = false;
  bool _saving = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<List<String>> _loadAvailableKeysCached(
    FirebaseFirestore firestore,
    String songId,
  ) {
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
      var index = _findCurrentIndex(items, cueData);
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
                stream: setlistRef.orderBy('order').snapshots(),
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
                    stream: liveCueRef.snapshots(),
                    builder: (context, cueSnapshot) {
                      if (cueSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const AppLoadingState(
                          message: 'LiveCue 상태 동기화 중...',
                        );
                      }
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

                      var currentIndex = _findCurrentIndex(items, cueData);
                      if (currentIndex < 0 && items.isNotEmpty) {
                        currentIndex = 0;
                      }

                      final currentLabel =
                          cueData['currentCueLabel']?.toString() ??
                          (currentIndex >= 0 && currentIndex < items.length
                              ? _cueLabelFromItem(
                                  items[currentIndex].data(),
                                  currentIndex + 1,
                                )
                              : '현재');
                      final currentTitle =
                          cueData['currentDisplayTitle']?.toString() ??
                          cueData['currentFreeTextTitle']?.toString() ??
                          (currentIndex >= 0 && currentIndex < items.length
                              ? _titleFromItem(items[currentIndex].data())
                              : '현재 곡 없음');
                      final currentKey = cueData['currentKeyText']?.toString();

                      final nextIndex =
                          currentIndex >= 0 && currentIndex + 1 < items.length
                          ? currentIndex + 1
                          : -1;
                      final nextLabel =
                          cueData['nextCueLabel']?.toString() ??
                          (nextIndex >= 0
                              ? _cueLabelFromItem(
                                  items[nextIndex].data(),
                                  nextIndex + 1,
                                )
                              : '다음');
                      final nextTitle =
                          cueData['nextDisplayTitle']?.toString() ??
                          cueData['nextFreeTextTitle']?.toString() ??
                          (nextIndex >= 0
                              ? _titleFromItem(items[nextIndex].data())
                              : '다음 곡 없음');
                      final nextKey = cueData['nextKeyText']?.toString();

                      final currentSongId = cueData['currentSongId']
                          ?.toString();

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

class _LiveCueFullScreenPageState extends ConsumerState<LiveCueFullScreenPage> {
  final FocusNode _focusNode = FocusNode();
  final TransformationController _viewerController = TransformationController();
  final ValueNotifier<int> _strokeRevision = ValueNotifier<int>(0);
  final Map<String, Future<_LiveCueAssetPreview?>> _previewCache = {};
  final Map<String, _LiveCueAssetPreview> _resolvedPreviewCache = {};
  final Set<String> _prefetchedPreviewKeys = <String>{};
  final Set<String> _queuedPrefetchKeys = <String>{};
  final Map<String, Future<List<String>>> _songKeysFutureCache = {};
  String? _webPollingScopeKey;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _webSetlistStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _webCueStream;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestSetlist =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Map<String, dynamic> _latestCueData = const <String, dynamic>{};
  String? _activeViewerAssetKey;
  String? _activeImageRendererKey;
  bool _fallbackToHtmlImageElement = false;
  bool _switchingImageRenderer = false;
  bool _autoSeeding = false;
  bool _moving = false;
  bool _showOverlay = true;
  Timer? _overlayTimer;
  bool _drawingEnabled = false;
  bool _eraserEnabled = false;
  bool _editingSharedLayer = false;
  bool _showPrivateLayer = true;
  bool _showSharedLayer = true;
  bool _loadingNoteLayers = false;
  bool _savingNoteLayers = false;
  bool _noteLayersLoaded = false;
  String? _noteLayersKey;
  double _drawingStrokeWidth = 2.8;
  int _drawingColorValue = 0xFFD32F2F;
  String _privateNoteContent = '';
  String _sharedNoteContent = '';
  List<_LiveCueSketchStroke> _privateLayerStrokes = <_LiveCueSketchStroke>[];
  List<_LiveCueSketchStroke> _sharedLayerStrokes = <_LiveCueSketchStroke>[];
  _LiveCueSketchStroke? _activeLayerStroke;

  @override
  void initState() {
    super.initState();
    if (widget.startInDrawMode) {
      _drawingEnabled = true;
      _showOverlay = true;
    }
    _scheduleOverlayAutoHide();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _focusNode.dispose();
    _viewerController.dispose();
    _strokeRevision.dispose();
    super.dispose();
  }

  String _previewCacheKey(
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

  Future<_LiveCueAssetPreview?> _loadPreviewCached(
    FirebaseFirestore firestore,
    FirebaseStorage storage,
    String? songId,
    String? keyText,
    String? fallbackTitle,
  ) {
    final safeSongId = songId?.trim() ?? '';
    final safeTitle = fallbackTitle?.trim() ?? '';
    if (safeSongId.isEmpty && safeTitle.isEmpty) {
      return Future.value(null);
    }
    final cacheKey = _previewCacheKey(safeSongId, keyText, safeTitle);
    final existing = _previewCache[cacheKey];
    if (existing != null) return existing;
    final future =
        _loadCurrentPreview(firestore, storage, safeSongId, keyText, safeTitle)
            .then((preview) {
              // Do not keep null results cached forever. Otherwise newly uploaded
              // assets never appear until full page reload.
              if (preview == null) {
                _previewCache.remove(cacheKey);
                _resolvedPreviewCache.remove(cacheKey);
              }
              if (preview != null) {
                _resolvedPreviewCache[cacheKey] = preview;
              }
              return preview;
            })
            .catchError((error, stackTrace) {
              _previewCache.remove(cacheKey);
              _resolvedPreviewCache.remove(cacheKey);
              throw error;
            });
    _previewCache[cacheKey] = future;
    return future;
  }

  Future<List<String>> _loadAvailableKeysCached(
    FirebaseFirestore firestore,
    String songId,
  ) {
    return _songKeysFutureCache.putIfAbsent(
      songId,
      () => _loadAvailableKeysForSong(firestore, songId),
    );
  }

  void _ensureViewerAssetKey(String key) {
    if (_activeViewerAssetKey == key) return;
    _activeViewerAssetKey = key;
    _viewerController.value = Matrix4.identity();
  }

  void _syncImageRendererKey(String key) {
    if (_activeImageRendererKey == key) return;
    _activeImageRendererKey = key;
    _fallbackToHtmlImageElement = false;
    _switchingImageRenderer = false;
  }

  void _warmPreview(
    FirebaseFirestore firestore,
    FirebaseStorage storage,
    String? songId,
    String? keyText,
    String? fallbackTitle,
  ) {
    final safeSongId = songId?.trim() ?? '';
    final safeTitle = fallbackTitle?.trim() ?? '';
    if (safeSongId.isEmpty && safeTitle.isEmpty) return;
    final cacheKey = _previewCacheKey(safeSongId, keyText, safeTitle);
    final previewFuture = _loadPreviewCached(
      firestore,
      storage,
      safeSongId,
      keyText,
      safeTitle,
    );
    _queuePreviewPrefetch(cacheKey, previewFuture);
  }

  void _queuePreviewPrefetch(
    String cacheKey,
    Future<_LiveCueAssetPreview?> previewFuture,
  ) {
    if (_prefetchedPreviewKeys.contains(cacheKey)) return;
    if (!_queuedPrefetchKeys.add(cacheKey)) return;
    unawaited(
      previewFuture
          .then((preview) async {
            if (!mounted || preview == null || !preview.isImage) return;
            final bytes = preview.initialBytes;
            if (bytes == null || bytes.isEmpty) {
              // Web prefetch via XHR is CORS-sensitive for token URLs.
              // Runtime viewer uses WebHtmlElementStrategy.prefer instead.
              if (kIsWeb) return;
            }
            final ImageProvider<Object> provider =
                bytes != null && bytes.isNotEmpty
                ? MemoryImage(bytes)
                : NetworkImage(preview.url);
            await precacheImage(provider, context);
            _prefetchedPreviewKeys.add(cacheKey);
          })
          .catchError((_) {
            // Prefetch is best effort only.
          })
          .whenComplete(() {
            _queuedPrefetchKeys.remove(cacheKey);
          }),
    );
  }

  void _ensureWebPollingStreams(
    Query<Map<String, dynamic>> setlistQuery,
    DocumentReference<Map<String, dynamic>> liveCueRef,
  ) {
    if (!kIsWeb) return;
    final scopeKey = '${widget.teamId}/${widget.projectId}';
    if (_webPollingScopeKey == scopeKey &&
        _webSetlistStream != null &&
        _webCueStream != null) {
      return;
    }
    _webPollingScopeKey = scopeKey;
    _webSetlistStream = _setlistPollingStream(setlistQuery).asBroadcastStream();
    _webCueStream = _liveCuePollingStream(liveCueRef).asBroadcastStream();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _setlistPollingStream(
    Query<Map<String, dynamic>> query,
  ) async* {
    QuerySnapshot<Map<String, dynamic>>? lastGoodSnapshot;
    String? lastSignature;
    while (mounted) {
      try {
        final snapshot = await query.get().timeout(const Duration(seconds: 12));
        final signature = _setlistSignature(snapshot);
        if (signature != lastSignature) {
          lastSignature = signature;
          lastGoodSnapshot = snapshot;
          yield snapshot;
        }
      } catch (_) {
        if (lastGoodSnapshot != null) {
          yield lastGoodSnapshot;
        }
      }
      await Future<void>.delayed(_webSetlistPollInterval);
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _liveCuePollingStream(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async* {
    DocumentSnapshot<Map<String, dynamic>>? lastGoodSnapshot;
    String? lastSignature;
    while (mounted) {
      try {
        final snapshot = await docRef.get().timeout(
          const Duration(seconds: 12),
        );
        final signature = _liveCueSignature(snapshot);
        if (signature != lastSignature) {
          lastSignature = signature;
          lastGoodSnapshot = snapshot;
          yield snapshot;
        }
      } catch (_) {
        if (lastGoodSnapshot != null) {
          yield lastGoodSnapshot;
        }
      }
      await Future<void>.delayed(_webCuePollInterval);
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

  void _scheduleOverlayAutoHide() {
    if (_drawingEnabled) return;
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showOverlay = false);
    });
  }

  void _showOverlayTemporarily() {
    if (!_showOverlay) {
      setState(() => _showOverlay = true);
    }
    _scheduleOverlayAutoHide();
  }

  void _toggleOverlay() {
    if (_drawingEnabled) return;
    if (_showOverlay) {
      _overlayTimer?.cancel();
      setState(() => _showOverlay = false);
      return;
    }
    setState(() => _showOverlay = true);
    _scheduleOverlayAutoHide();
  }

  Future<_LiveCueNotePayload> _loadPrivateNotePayload(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    final v2Ref = _privateProjectNoteRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
      userId,
    );
    final v2Doc = await v2Ref.get();
    final v2Data = v2Doc.data();
    if (v2Data != null) {
      return _LiveCueNotePayload.fromMap(v2Data);
    }

    final legacyDoc = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userProjectNotes')
        .doc(privateProjectNoteDocIdLegacy(widget.projectId, userId))
        .get();
    final legacyData = legacyDoc.data();
    if (legacyData != null) {
      unawaited(
        logLegacyFallbackUsage(
          firestore: firestore,
          teamId: widget.teamId,
          path: 'live_cue.legacy_doc_id',
          detail: widget.projectId,
        ),
      );
      final merged = {
        ...legacyData,
        'visibility': 'private',
        'ownerUserId': userId,
        'teamId': widget.teamId,
        'projectId': widget.projectId,
      };
      try {
        await v2Ref.set(merged, SetOptions(merge: true));
      } on FirebaseException {
        // Ignore migration failure; use loaded payload as-is.
      }
      return _LiveCueNotePayload.fromMap(merged);
    }

    final legacyQuery = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userProjectNotes')
        .where('userId', isEqualTo: userId)
        .where('projectId', isEqualTo: widget.projectId)
        .limit(1)
        .get();
    if (legacyQuery.docs.isEmpty) return _LiveCueNotePayload();
    unawaited(
      logLegacyFallbackUsage(
        firestore: firestore,
        teamId: widget.teamId,
        path: 'live_cue.legacy_query',
        detail: widget.projectId,
      ),
    );
    final queryData = legacyQuery.docs.first.data();
    final merged = {
      ...queryData,
      'visibility': 'private',
      'ownerUserId': userId,
      'teamId': widget.teamId,
      'projectId': widget.projectId,
    };
    try {
      await v2Ref.set(merged, SetOptions(merge: true));
    } on FirebaseException {
      // Ignore migration failure; use loaded payload as-is.
    }
    return _LiveCueNotePayload.fromMap(merged);
  }

  Future<_LiveCueNotePayload> _loadSharedNotePayload(
    FirebaseFirestore firestore,
  ) async {
    final doc = await _sharedProjectNoteRefFor(
      firestore,
      widget.teamId,
      widget.projectId,
    ).get();
    final data = doc.data();
    if (data == null) return _LiveCueNotePayload();
    return _LiveCueNotePayload.fromMap(data);
  }

  Future<void> _ensureNoteLayersLoaded(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    final key = '${widget.teamId}/${widget.projectId}/$userId';
    if (_noteLayersLoaded && _noteLayersKey == key) return;
    if (_loadingNoteLayers) return;

    setState(() {
      _loadingNoteLayers = true;
    });
    try {
      final privatePayload = await _loadPrivateNotePayload(firestore, userId);
      final sharedPayload = await _loadSharedNotePayload(firestore);
      if (!mounted) return;
      setState(() {
        _privateNoteContent = privatePayload.text;
        _sharedNoteContent = sharedPayload.text;
        _privateLayerStrokes = List<_LiveCueSketchStroke>.from(
          privatePayload.strokes,
        );
        _sharedLayerStrokes = List<_LiveCueSketchStroke>.from(
          sharedPayload.strokes,
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

  Offset _normalizeOffset(Offset local, Size size) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = (local.dx / safeWidth).clamp(0.0, 1.0);
    final dy = (local.dy / safeHeight).clamp(0.0, 1.0);
    return Offset(dx, dy);
  }

  void _bumpStrokeRevision() {
    _strokeRevision.value = _strokeRevision.value + 1;
  }

  void _eraseLayerAt(Offset localPosition, Size size) {
    if (!_drawingEnabled || !_eraserEnabled) return;
    final point = _normalizeOffset(localPosition, size);
    final target = _editingSharedLayer
        ? _sharedLayerStrokes
        : _privateLayerStrokes;
    final hasHit = target.any((stroke) => _strokeHit(stroke, point));
    if (!hasHit) return;
    setState(() {
      target.removeWhere((stroke) => _strokeHit(stroke, point));
      _activeLayerStroke = null;
    });
    _bumpStrokeRevision();
  }

  bool _strokeHit(_LiveCueSketchStroke stroke, Offset point) {
    if (stroke.points.isEmpty) return false;
    final radius = (0.018 + (stroke.width / 450.0)).clamp(0.012, 0.04);
    final radiusSquared = radius * radius;
    if (stroke.points.length == 1) {
      final dot = stroke.points.first;
      final dx = dot.dx - point.dx;
      final dy = dot.dy - point.dy;
      return (dx * dx + dy * dy) <= radiusSquared;
    }
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1];
      final b = stroke.points[i];
      if (_distanceSquaredToSegment(point, a, b) <= radiusSquared) {
        return true;
      }
    }
    return false;
  }

  double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final apx = p.dx - a.dx;
    final apy = p.dy - a.dy;
    final abSquared = (abx * abx) + (aby * aby);
    if (abSquared <= 1e-12) {
      return (apx * apx) + (apy * apy);
    }
    final t = ((apx * abx) + (apy * aby)) / abSquared;
    final clampedT = t.clamp(0.0, 1.0);
    final closestX = a.dx + (abx * clampedT);
    final closestY = a.dy + (aby * clampedT);
    final dx = p.dx - closestX;
    final dy = p.dy - closestY;
    return (dx * dx) + (dy * dy);
  }

  void _startLayerStroke(DragStartDetails details, Size size) {
    if (!_drawingEnabled || _eraserEnabled) return;
    final point = _normalizeOffset(details.localPosition, size);
    setState(() {
      _activeLayerStroke = _LiveCueSketchStroke(
        points: <Offset>[point],
        colorValue: _drawingColorValue,
        width: _drawingStrokeWidth,
      );
    });
  }

  void _appendLayerStroke(DragUpdateDetails details, Size size) {
    if (_eraserEnabled) return;
    final active = _activeLayerStroke;
    if (active == null) return;
    final point = _normalizeOffset(details.localPosition, size);
    active.points.add(point);
    _bumpStrokeRevision();
  }

  void _endLayerStroke() {
    final active = _activeLayerStroke;
    if (active == null) return;
    setState(() {
      if (active.points.isNotEmpty) {
        if (_editingSharedLayer) {
          _sharedLayerStrokes.add(active);
        } else {
          _privateLayerStrokes.add(active);
        }
      }
      _activeLayerStroke = null;
    });
    _bumpStrokeRevision();
  }

  void _tapLayerStroke(TapDownDetails details, Size size) {
    if (!_drawingEnabled || _eraserEnabled) return;
    final point = _normalizeOffset(details.localPosition, size);
    final dotStroke = _LiveCueSketchStroke(
      points: <Offset>[point],
      colorValue: _drawingColorValue,
      width: _drawingStrokeWidth,
    );
    setState(() {
      if (_editingSharedLayer) {
        _sharedLayerStrokes.add(dotStroke);
      } else {
        _privateLayerStrokes.add(dotStroke);
      }
      _activeLayerStroke = null;
    });
    _bumpStrokeRevision();
  }

  void _undoLayerStroke() {
    setState(() {
      if (_activeLayerStroke != null) {
        _activeLayerStroke = null;
        return;
      }
      final target = _editingSharedLayer
          ? _sharedLayerStrokes
          : _privateLayerStrokes;
      if (target.isNotEmpty) {
        target.removeLast();
      }
    });
    _bumpStrokeRevision();
  }

  void _clearLayerStroke() {
    setState(() {
      if (_editingSharedLayer) {
        _sharedLayerStrokes.clear();
      } else {
        _privateLayerStrokes.clear();
      }
      _activeLayerStroke = null;
    });
    _bumpStrokeRevision();
  }

  void _setDrawingEnabled(bool value) {
    if (_drawingEnabled == value) return;
    setState(() {
      _drawingEnabled = value;
      _showOverlay = true;
      if (value && _fallbackToHtmlImageElement) {
        // Prefer canvas-backed renderer while drawing to keep pointer events stable.
        _fallbackToHtmlImageElement = false;
        _switchingImageRenderer = false;
      }
      if (!value) {
        _activeLayerStroke = null;
        _eraserEnabled = false;
        _bumpStrokeRevision();
      }
    });
    if (value) {
      _overlayTimer?.cancel();
    } else {
      _scheduleOverlayAutoHide();
    }
  }

  List<_LiveCueSketchStroke> _overlayStrokesForRender() {
    final strokes = <_LiveCueSketchStroke>[];
    if (_showPrivateLayer) {
      strokes.addAll(_privateLayerStrokes);
    }
    if (_showSharedLayer) {
      strokes.addAll(_sharedLayerStrokes);
    }
    if (_activeLayerStroke != null) {
      strokes.add(_activeLayerStroke!);
    }
    return strokes;
  }

  Future<void> _saveLayerNotes(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    if (_savingNoteLayers) return;
    setState(() {
      _savingNoteLayers = true;
    });
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    final actor = user?.displayName ?? user?.email ?? user?.uid;

    try {
      if (_editingSharedLayer) {
        await _sharedProjectNoteRefFor(
          firestore,
          widget.teamId,
          widget.projectId,
        ).set({
          'teamId': widget.teamId,
          'projectId': widget.projectId,
          'visibility': 'team',
          'content': _sharedNoteContent,
          'drawingStrokes': _sharedLayerStrokes
              .map((stroke) => stroke.toMap())
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actor,
        }, SetOptions(merge: true));
      } else {
        await _privateProjectNoteRefFor(
          firestore,
          widget.teamId,
          widget.projectId,
          userId,
        ).set({
          'userId': userId,
          'ownerUserId': userId,
          'projectId': widget.projectId,
          'teamId': widget.teamId,
          'visibility': 'private',
          'content': _privateNoteContent,
          'drawingStrokes': _privateLayerStrokes
              .map((stroke) => stroke.toMap())
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actor,
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editingSharedLayer ? '공유 레이어 저장 완료' : '개인 레이어 저장 완료'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('레이어 메모 저장 실패: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _savingNoteLayers = false;
        });
      }
    }
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
    var member = await memberRef.get().timeout(const Duration(seconds: 12));
    final team = await teamRef.get().timeout(const Duration(seconds: 12));
    final createdBy = (team.data()?['createdBy'] ?? '').toString();
    if (!member.exists && team.exists && createdBy == userId) {
      final authUser = ref.read(firebaseAuthProvider).currentUser;
      // Keep creator access resilient when legacy member docs are missing.
      await memberRef.set({
        'userId': userId,
        'uid': userId,
        'email': authUser?.email?.toLowerCase(),
        'displayName': authUser?.displayName,
        'nickname': null,
        'role': 'admin',
        'teamName': (team.data()?['name'] ?? '팀').toString(),
        'capabilities': {'songEditor': true},
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await teamRef.set({
        'memberUids': FieldValue.arrayUnion([userId]),
      }, SetOptions(merge: true));
      member = await memberRef.get().timeout(const Duration(seconds: 12));
    }
    return _LiveCueContext(project: project, member: member);
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
      setState(() {});
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
    setState(() => _moving = true);
    try {
      var index = _findCurrentIndex(items, cueData);
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
      if (mounted) {
        setState(() => _moving = false);
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
      setState(() {});
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

    return FutureBuilder<_LiveCueContext>(
      future: _loadContext(firestore, user.uid),
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
        if (!contextData.member.exists) {
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
        final canEdit = leaderId == user.uid || isAdminRole(role);
        final noteLayersKey =
            '${widget.teamId}/${widget.projectId}/${user.uid}';
        if ((!_noteLayersLoaded || _noteLayersKey != noteLayersKey) &&
            !_loadingNoteLayers) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ensureNoteLayersLoaded(firestore, user.uid);
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
        _ensureWebPollingStreams(setlistQuery, liveCueRef);
        final setlistStream = kIsWeb
            ? _webSetlistStream!
            : setlistQuery.snapshots();
        final cueStream = kIsWeb ? _webCueStream! : liveCueRef.snapshots();

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
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      }
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

                      var currentIndex = _findCurrentIndex(items, cueData);
                      if (currentIndex < 0 && items.isNotEmpty) {
                        currentIndex = 0;
                      }

                      final currentSongId = cueData['currentSongId']
                          ?.toString();
                      final currentLabel =
                          cueData['currentCueLabel']?.toString() ??
                          (currentIndex >= 0 && currentIndex < items.length
                              ? _cueLabelFromItem(
                                  items[currentIndex].data(),
                                  currentIndex + 1,
                                )
                              : '현재');
                      final currentTitle =
                          cueData['currentDisplayTitle']?.toString() ??
                          cueData['currentFreeTextTitle']?.toString() ??
                          (currentIndex >= 0 && currentIndex < items.length
                              ? _titleFromItem(items[currentIndex].data())
                              : '현재 곡 없음');
                      final currentKey = cueData['currentKeyText']?.toString();
                      final currentPreviewCacheKey = _previewCacheKey(
                        currentSongId?.trim() ?? '',
                        currentKey,
                        currentTitle,
                      );
                      final cachedCurrentPreview =
                          _resolvedPreviewCache[currentPreviewCacheKey];
                      final nextSongId = cueData['nextSongId']?.toString();
                      final nextKey = cueData['nextKeyText']?.toString();
                      final nextTitle =
                          cueData['nextDisplayTitle']?.toString() ??
                          cueData['nextFreeTextTitle']?.toString() ??
                          '';

                      String? prevSongId;
                      String? prevKey;
                      String prevTitle = '';
                      if (currentIndex > 0 && currentIndex < items.length) {
                        final prevData = items[currentIndex - 1].data();
                        prevSongId = prevData['songId']?.toString();
                        prevKey = _keyFromItem(prevData);
                        prevTitle = _titleFromItem(prevData);
                      }

                      _warmPreview(
                        firestore,
                        storage,
                        currentSongId,
                        currentKey,
                        currentTitle,
                      );
                      _warmPreview(
                        firestore,
                        storage,
                        prevSongId,
                        prevKey,
                        prevTitle,
                      );
                      _warmPreview(
                        firestore,
                        storage,
                        nextSongId,
                        nextKey,
                        nextTitle,
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
                              child: FutureBuilder<_LiveCueAssetPreview?>(
                                future: _loadPreviewCached(
                                  firestore,
                                  storage,
                                  currentSongId,
                                  currentKey,
                                  currentTitle,
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
                                      preview?.resolvedSongId ?? currentSongId;
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
                                              _previewCache.remove(
                                                _previewCacheKey(
                                                  currentSongId ?? '',
                                                  currentKey,
                                                  currentTitle,
                                                ),
                                              );
                                              if (mounted) {
                                                setState(() {});
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
                                              final opened = openUrlInNewTab(
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
                                                        (currentKey == null ||
                                                            currentKey.isEmpty)
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

                                      Widget buildImageLoadError(Object error) {
                                        if (kIsWeb &&
                                            bytes == null &&
                                            !_drawingEnabled &&
                                            !_fallbackToHtmlImageElement &&
                                            !_switchingImageRenderer) {
                                          _switchingImageRenderer = true;
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (!mounted) return;
                                                setState(() {
                                                  _fallbackToHtmlImageElement =
                                                      true;
                                                  _switchingImageRenderer =
                                                      false;
                                                });
                                              });
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
                                              filterQuality: FilterQuality.high,
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
                                              filterQuality: FilterQuality.high,
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
                                                            color: Colors.white,
                                                          ),
                                                    );
                                                  },
                                              errorBuilder:
                                                  (context, error, stack) =>
                                                      buildImageLoadError(
                                                        error,
                                                      ),
                                            );
                                      final renderStrokes =
                                          _overlayStrokesForRender();
                                      final canvasSize = Size(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      );
                                      final viewerContent = SizedBox(
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            RepaintBoundary(child: imageWidget),
                                            if (renderStrokes.isNotEmpty)
                                              IgnorePointer(
                                                child: RepaintBoundary(
                                                  child: CustomPaint(
                                                    painter:
                                                        _LiveCueSketchPainter(
                                                          strokes:
                                                              renderStrokes,
                                                          repaint:
                                                              _strokeRevision,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            if (_drawingEnabled && canEdit)
                                              GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTapDown: (details) {
                                                  if (_eraserEnabled) {
                                                    _eraseLayerAt(
                                                      details.localPosition,
                                                      canvasSize,
                                                    );
                                                    return;
                                                  }
                                                  _tapLayerStroke(
                                                    details,
                                                    canvasSize,
                                                  );
                                                },
                                                onPanStart: (details) {
                                                  if (_eraserEnabled) {
                                                    _eraseLayerAt(
                                                      details.localPosition,
                                                      canvasSize,
                                                    );
                                                    return;
                                                  }
                                                  _startLayerStroke(
                                                    details,
                                                    canvasSize,
                                                  );
                                                },
                                                onPanUpdate: (details) {
                                                  if (_eraserEnabled) {
                                                    _eraseLayerAt(
                                                      details.localPosition,
                                                      canvasSize,
                                                    );
                                                    return;
                                                  }
                                                  _appendLayerStroke(
                                                    details,
                                                    canvasSize,
                                                  );
                                                },
                                                onPanEnd: (_) {
                                                  if (!_eraserEnabled) {
                                                    _endLayerStroke();
                                                  }
                                                },
                                                onPanCancel: () {
                                                  if (!_eraserEnabled) {
                                                    _endLayerStroke();
                                                  }
                                                },
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
                                                        const EdgeInsets.all(8),
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
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: _showOverlay
                                    ? Colors.black54
                                    : Colors.black26,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (_showOverlay)
                            Positioned(
                              top: 8,
                              right: 8,
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
                                        backgroundColor: _drawingEnabled
                                            ? Colors.white24
                                            : Colors.black54,
                                      ),
                                      tooltip: _drawingEnabled
                                          ? '필기 모드 끄기'
                                          : '필기 모드 켜기',
                                      onPressed: () =>
                                          _setDrawingEnabled(!_drawingEnabled),
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
                                        backgroundColor: Colors.black54,
                                      ),
                                      tooltip: _editingSharedLayer
                                          ? '현재: 공유 레이어'
                                          : '현재: 개인 레이어',
                                      onPressed: () {
                                        setState(() {
                                          _editingSharedLayer =
                                              !_editingSharedLayer;
                                        });
                                      },
                                      icon: Icon(
                                        _editingSharedLayer
                                            ? Icons.groups_rounded
                                            : Icons.person_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: _eraserEnabled
                                            ? Colors.white24
                                            : Colors.black54,
                                      ),
                                      tooltip: _eraserEnabled
                                          ? '지우개 모드'
                                          : '펜 모드',
                                      onPressed: () {
                                        setState(() {
                                          _eraserEnabled = !_eraserEnabled;
                                          _activeLayerStroke = null;
                                        });
                                      },
                                      icon: Icon(
                                        _eraserEnabled
                                            ? Icons.cleaning_services_rounded
                                            : Icons.brush_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (_showOverlay)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (currentSongId != null &&
                                        currentSongId.isNotEmpty)
                                      FutureBuilder<List<String>>(
                                        future: _loadAvailableKeysCached(
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
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
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
                                                      onSelected: canEdit
                                                          ? (_) =>
                                                                _setCurrentKey(
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
                                          label: const Text('개인 레이어'),
                                          selected: _showPrivateLayer,
                                          onSelected: (value) {
                                            setState(() {
                                              _showPrivateLayer = value;
                                            });
                                          },
                                        ),
                                        FilterChip(
                                          label: const Text('공유 레이어'),
                                          selected: _showSharedLayer,
                                          onSelected: (value) {
                                            setState(() {
                                              _showSharedLayer = value;
                                            });
                                          },
                                        ),
                                        if (canEdit)
                                          FilledButton.tonalIcon(
                                            onPressed: () => _setDrawingEnabled(
                                              !_drawingEnabled,
                                            ),
                                            icon: Icon(
                                              _drawingEnabled
                                                  ? Icons.edit_off_rounded
                                                  : Icons.draw_rounded,
                                            ),
                                            label: Text(
                                              _drawingEnabled
                                                  ? '필기 모드 종료'
                                                  : '필기 모드 시작',
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (canEdit && _drawingEnabled) ...[
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
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ChoiceChip(
                                            label: const Text('펜'),
                                            selected: !_eraserEnabled,
                                            onSelected: (_) {
                                              setState(() {
                                                _eraserEnabled = false;
                                              });
                                            },
                                          ),
                                          ChoiceChip(
                                            label: const Text('지우개'),
                                            selected: _eraserEnabled,
                                            onSelected: (_) {
                                              setState(() {
                                                _eraserEnabled = true;
                                                _activeLayerStroke = null;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (_eraserEnabled)
                                        const Text(
                                          '선을 문지르면 해당 획이 지워집니다.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      if (_eraserEnabled)
                                        const SizedBox(height: 8),
                                      if (!_eraserEnabled)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _liveCueDrawingPalette
                                              .map(
                                                (colorValue) => GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _drawingColorValue =
                                                          colorValue;
                                                    });
                                                  },
                                                  child: Container(
                                                    width: 26,
                                                    height: 26,
                                                    decoration: BoxDecoration(
                                                      color: Color(colorValue),
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
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          ...<double>[1.8, 2.8, 4.2, 6.0].map(
                                            (width) => ChoiceChip(
                                              label: Text(
                                                '펜 ${width.toStringAsFixed(width == 6.0 ? 0 : 1)}',
                                              ),
                                              selected:
                                                  (_drawingStrokeWidth - width)
                                                      .abs() <
                                                  0.05,
                                              onSelected: (_) {
                                                setState(() {
                                                  _drawingStrokeWidth = width;
                                                });
                                              },
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _undoLayerStroke,
                                            icon: const Icon(
                                              Icons.undo_rounded,
                                            ),
                                            label: const Text('되돌리기'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _clearLayerStroke,
                                            icon: const Icon(
                                              Icons.delete_sweep_rounded,
                                            ),
                                            label: const Text('레이어 지우기'),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _savingNoteLayers
                                                ? null
                                                : () => _saveLayerNotes(
                                                    firestore,
                                                    user.uid,
                                                  ),
                                            icon: _savingNoteLayers
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.save_rounded,
                                                  ),
                                            label: const Text('레이어 저장'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
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

class _LiveCueContext {
  final DocumentSnapshot<Map<String, dynamic>> project;
  final DocumentSnapshot<Map<String, dynamic>> member;

  const _LiveCueContext({required this.project, required this.member});
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
  final List<_LiveCueSketchStroke> strokes;

  _LiveCueSketchPainter({required this.strokes, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
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
    return oldDelegate.strokes != strokes;
  }
}

class _LiveCueNotePayload {
  final String text;
  final List<_LiveCueSketchStroke> strokes;

  _LiveCueNotePayload({this.text = '', List<_LiveCueSketchStroke>? strokes})
    : strokes = strokes ?? <_LiveCueSketchStroke>[];

  factory _LiveCueNotePayload.fromMap(Map<String, dynamic> data) {
    return _LiveCueNotePayload(
      text: data['content']?.toString() ?? '',
      strokes: _LiveCueSketchStroke.decodeList(data['drawingStrokes']),
    );
  }
}

class _LiveCueSketchStroke {
  final List<Offset> points;
  final int colorValue;
  final double width;

  _LiveCueSketchStroke({
    required this.points,
    required this.colorValue,
    required this.width,
  });

  Map<String, dynamic> toMap() {
    return {
      'colorValue': colorValue,
      'width': width,
      'points': points
          .map(
            (point) => {
              'x': point.dx.clamp(0.0, 1.0),
              'y': point.dy.clamp(0.0, 1.0),
            },
          )
          .toList(),
    };
  }

  static List<_LiveCueSketchStroke> decodeList(dynamic raw) {
    if (raw is! List) return <_LiveCueSketchStroke>[];
    final decoded = <_LiveCueSketchStroke>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final width = (item['width'] as num?)?.toDouble() ?? 2.8;
      final colorValue = (item['colorValue'] as num?)?.toInt() ?? 0xFFD32F2F;
      final pointsRaw = item['points'];
      if (pointsRaw is! List) continue;
      final points = <Offset>[];
      for (final point in pointsRaw) {
        if (point is! Map) continue;
        final dx = (point['x'] as num?)?.toDouble() ?? 0;
        final dy = (point['y'] as num?)?.toDouble() ?? 0;
        points.add(Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0)));
      }
      if (points.isEmpty) continue;
      decoded.add(
        _LiveCueSketchStroke(
          points: points,
          colorValue: colorValue,
          width: width,
        ),
      );
    }
    return decoded;
  }
}
