import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../services/song_search.dart';
import '../../utils/song_parser.dart';

class SegmentAPage extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;
  final bool canEdit;

  const SegmentAPage({
    super.key,
    required this.teamId,
    required this.projectId,
    required this.canEdit,
  });

  @override
  ConsumerState<SegmentAPage> createState() => _SegmentAPageState();
}

class _SegmentAPageState extends ConsumerState<SegmentAPage> {
  final TextEditingController _scriptureController = TextEditingController();
  final TextEditingController _setlistInputController = TextEditingController();
  final TextEditingController _bulkSetlistInputController =
      TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _referenceLinksController =
      TextEditingController();
  bool _saving = false;
  bool _scriptureLoaded = false;

  @override
  void dispose() {
    _scriptureController.dispose();
    _setlistInputController.dispose();
    _bulkSetlistInputController.dispose();
    _memoController.dispose();
    _referenceLinksController.dispose();
    super.dispose();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadProject(
    FirebaseFirestore firestore,
  ) {
    return firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .get();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadSetlist(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .collection('segmentA_setlist')
        .orderBy('order')
        .get();
    return snapshot.docs;
  }

  DocumentReference<Map<String, dynamic>> _liveCueRef(
    FirebaseFirestore firestore,
  ) {
    return firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .collection('liveCue')
        .doc('state');
  }

  bool _hasCueValue(Map<String, dynamic> cueData, String prefix) {
    final songId = cueData['${prefix}SongId']?.toString().trim() ?? '';
    final displayTitle =
        cueData['${prefix}DisplayTitle']?.toString().trim() ?? '';
    final freeText = cueData['${prefix}FreeTextTitle']?.toString().trim() ?? '';
    return songId.isNotEmpty || displayTitle.isNotEmpty || freeText.isNotEmpty;
  }

  String _normalizedKey(dynamic raw) {
    final key = raw?.toString().trim() ?? '';
    if (key.isEmpty) return '';
    return normalizeKeyText(key);
  }

  Future<SongCandidate?> _matchSongAutomatically(
    FirebaseFirestore firestore,
    String title,
  ) async {
    final normalizedTitle = normalizeQuery(title);
    if (normalizedTitle.isEmpty) return null;
    final candidates = await findSongCandidates(firestore, normalizedTitle);
    if (candidates.isEmpty) return null;
    for (final candidate in candidates) {
      if (normalizeQuery(candidate.title) == normalizedTitle) return candidate;
    }
    return candidates.first;
  }

  bool _isSameSong(
    Map<String, dynamic> cueData,
    String prefix,
    Map<String, dynamic> setlistItem,
  ) {
    final cueSongId = cueData['${prefix}SongId']?.toString().trim() ?? '';
    final setlistSongId = setlistItem['songId']?.toString().trim() ?? '';
    if (cueSongId.isNotEmpty && setlistSongId.isNotEmpty) {
      return cueSongId == setlistSongId;
    }

    final cueTitle =
        (cueData['${prefix}DisplayTitle'] ??
                cueData['${prefix}FreeTextTitle'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final setlistTitle =
        (setlistItem['displayTitle'] ?? setlistItem['freeTextTitle'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (cueTitle.isEmpty || setlistTitle.isEmpty || cueTitle != setlistTitle) {
      return false;
    }

    final cueKey = _normalizedKey(cueData['${prefix}KeyText']);
    final setlistKey = _normalizedKey(setlistItem['keyText']);
    if (cueKey.isEmpty || setlistKey.isEmpty) {
      return true;
    }
    return cueKey == setlistKey;
  }

  Future<Map<String, dynamic>> _cueFieldsFromSetlist(
    FirebaseFirestore firestore,
    Map<String, dynamic> setlistItem, {
    required String prefix,
  }) async {
    String? songId = setlistItem['songId']?.toString().trim();
    String? freeTextTitle = setlistItem['freeTextTitle']?.toString().trim();
    var displayTitle =
        setlistItem['displayTitle']?.toString().trim() ?? freeTextTitle ?? '곡';
    final keyText = _normalizedKey(setlistItem['keyText']);
    final rawCueLabel = setlistItem['cueLabel']?.toString().trim();
    final cueLabel = (rawCueLabel == null || rawCueLabel.isEmpty)
        ? (setlistItem['order']?.toString())
        : rawCueLabel;

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
      '${prefix}FreeTextTitle': hasSongId
          ? null
          : (freeTextTitle == null || freeTextTitle.isEmpty
                ? displayTitle
                : freeTextTitle),
      '${prefix}DisplayTitle': displayTitle,
      '${prefix}KeyText': keyText.isEmpty ? null : keyText,
      '${prefix}CueLabel': cueLabel,
    };
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

  Future<void> _syncLiveCueFromSetlist(FirebaseFirestore firestore) async {
    final setlistItems = await _loadSetlist(firestore);
    if (setlistItems.isEmpty) {
      await _liveCueRef(firestore).set({
        ..._clearCueFields(prefix: 'current'),
        ..._clearCueFields(prefix: 'next'),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final stateSnapshot = await _liveCueRef(firestore).get();
    final cueData = stateSnapshot.data() ?? {};
    final hasCurrent = _hasCueValue(cueData, 'current');
    final hasNext = _hasCueValue(cueData, 'next');

    final updates = <String, dynamic>{};
    if (!hasCurrent) {
      updates.addAll(
        await _cueFieldsFromSetlist(
          firestore,
          setlistItems.first.data(),
          prefix: 'current',
        ),
      );
      if (setlistItems.length > 1) {
        updates.addAll(
          await _cueFieldsFromSetlist(
            firestore,
            setlistItems[1].data(),
            prefix: 'next',
          ),
        );
      } else {
        updates.addAll(_clearCueFields(prefix: 'next'));
      }
    } else if (!hasNext) {
      for (final item in setlistItems) {
        final data = item.data();
        if (_isSameSong(cueData, 'current', data)) continue;
        updates.addAll(
          await _cueFieldsFromSetlist(firestore, data, prefix: 'next'),
        );
        break;
      }
    }

    if (updates.isEmpty) return;
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _liveCueRef(firestore).set(updates, SetOptions(merge: true));
  }

  Future<void> _saveScripture(BuildContext context) async {
    final firestore = ref.read(firestoreProvider);
    await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .update({'scriptureText': _scriptureController.text.trim()});

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('말씀 본문 저장 완료')));
  }

  Future<void> _addSetlistItem(BuildContext context) async {
    if (!widget.canEdit) return;
    final input = _setlistInputController.text.trim();
    if (input.isEmpty) return;

    setState(() => _saving = true);
    final firestore = ref.read(firestoreProvider);
    final cueInput = _parseCueInput(input);
    final parsed = parseSongInput(cueInput.songText);
    if (parsed.title.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    try {
      final candidates = await findSongCandidates(
        firestore,
        normalizeQuery(parsed.title),
      );

      if (!context.mounted) return;

      String? songId;
      String displayTitle = parsed.title;

      if (candidates.length == 1) {
        songId = candidates.first.id;
        displayTitle = candidates.first.title;
      } else if (candidates.length > 1) {
        final selected = await _selectCandidate(context, candidates);
        if (selected != null) {
          songId = selected.id;
          displayTitle = selected.title;
        }
      }

      final setlistRef = firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(widget.projectId)
          .collection('segmentA_setlist');

      final currentItems = await _loadSetlist(firestore);
      final lastOrder = currentItems.isEmpty
          ? 0
          : (currentItems.last.data()['order'] as num?)?.toInt() ??
                currentItems.length;
      final nextOrder = lastOrder + 1;
      final referenceLinks = _parseReferenceLinks(
        _referenceLinksController.text,
      );

      await setlistRef.add({
        'order': nextOrder,
        'cueLabel': cueInput.cueLabel ?? nextOrder.toString(),
        'songId': songId,
        'freeTextTitle': songId == null ? parsed.title : null,
        'displayTitle': displayTitle,
        'keyText': parsed.keyText == null
            ? null
            : normalizeKeyText(parsed.keyText!),
        'memoShared': _memoController.text.trim(),
        if (referenceLinks.isNotEmpty) 'referenceLinks': referenceLinks,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _syncLiveCueFromSetlist(firestore);

      _setlistInputController.clear();
      _memoController.clear();
      _referenceLinksController.clear();
      if (!context.mounted) return;
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('콘티 추가 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  List<String> _parseBulkLines(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<_ResolvedSetlistSong> _resolveSongForBulkLine(
    FirebaseFirestore firestore,
    String rawLine,
  ) async {
    final cueInput = _parseCueInput(rawLine);
    final parsed = parseSongInput(cueInput.songText);
    if (parsed.title.isEmpty) {
      return const _ResolvedSetlistSong.invalid();
    }

    final normalizedTitle = normalizeQuery(parsed.title);
    final candidates = await findSongCandidates(firestore, normalizedTitle);
    SongCandidate? matched;
    if (candidates.length == 1) {
      matched = candidates.first;
    } else if (candidates.length > 1) {
      final exactMatches = candidates
          .where(
            (candidate) => normalizeQuery(candidate.title) == normalizedTitle,
          )
          .toList();
      if (exactMatches.length == 1) {
        matched = exactMatches.first;
      }
    }

    final normalizedKey = parsed.keyText == null
        ? null
        : normalizeKeyText(parsed.keyText!);
    if (matched != null) {
      return _ResolvedSetlistSong(
        cueLabel: cueInput.cueLabel,
        songId: matched.id,
        displayTitle: matched.title,
        freeTextTitle: null,
        keyText: normalizedKey,
      );
    }

    return _ResolvedSetlistSong(
      cueLabel: cueInput.cueLabel,
      songId: null,
      displayTitle: parsed.title,
      freeTextTitle: parsed.title,
      keyText: normalizedKey,
    );
  }

  Future<void> _addSetlistItemsBulk(BuildContext context) async {
    if (!widget.canEdit) return;
    final raw = _bulkSetlistInputController.text.trim();
    if (raw.isEmpty) return;

    final lines = _parseBulkLines(raw);
    if (lines.isEmpty) return;

    setState(() => _saving = true);
    final firestore = ref.read(firestoreProvider);

    try {
      final setlistRef = firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(widget.projectId)
          .collection('segmentA_setlist');

      final currentItems = await _loadSetlist(firestore);
      var orderCursor = currentItems.isEmpty
          ? 0
          : (currentItems.last.data()['order'] as num?)?.toInt() ??
                currentItems.length;

      final batch = firestore.batch();
      var addedCount = 0;
      final skipped = <String>[];

      for (final line in lines) {
        final resolved = await _resolveSongForBulkLine(firestore, line);
        if (!resolved.isValid) {
          skipped.add(line);
          continue;
        }

        orderCursor += 1;
        final docRef = setlistRef.doc();
        batch.set(docRef, {
          'order': orderCursor,
          'cueLabel': resolved.cueLabel ?? orderCursor.toString(),
          'songId': resolved.songId,
          'freeTextTitle': resolved.freeTextTitle,
          'displayTitle': resolved.displayTitle,
          'keyText': resolved.keyText,
          'memoShared': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        addedCount += 1;
      }

      if (addedCount == 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('일괄 입력에서 유효한 콘티를 찾지 못했습니다.')),
          );
        }
        return;
      }

      await batch.commit();
      await _syncLiveCueFromSetlist(firestore);

      _bulkSetlistInputController.clear();
      if (!context.mounted) return;
      final skippedInfo = skipped.isEmpty ? '' : ' (건너뜀 ${skipped.length}줄)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('콘티 $addedCount곡을 일괄 추가했습니다.$skippedInfo')),
      );
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('콘티 일괄 추가 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<SongCandidate?> _selectCandidate(
    BuildContext context,
    List<SongCandidate> candidates,
  ) {
    return showDialog<SongCandidate>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('곡 선택'),
        children: candidates
            .map(
              (candidate) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(candidate),
                child: Text(candidate.title),
              ),
            )
            .toList(),
      ),
    );
  }

  List<String> _parseReferenceLinks(String raw) {
    final unique = <String>{};
    for (final chunk in raw.split(RegExp(r'[\n,]+'))) {
      final link = chunk.trim();
      if (link.isEmpty) continue;
      unique.add(link);
    }
    return unique.toList();
  }

  _CueInput _parseCueInput(String rawInput) {
    final input = rawInput.trim();
    final matched = RegExp(
      r'^(?<label>\d+(?:-\d+)?)(?:[.)])?\s+(?<rest>.+)$',
    ).firstMatch(input);
    if (matched == null) {
      return _CueInput(cueLabel: null, songText: input);
    }
    final label = matched.namedGroup('label')?.trim();
    final rest = matched.namedGroup('rest')?.trim() ?? input;
    if (rest.isEmpty) {
      return _CueInput(cueLabel: null, songText: input);
    }
    return _CueInput(cueLabel: label, songText: rest);
  }

  Future<void> _editSetlistItem(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> itemDoc,
  ) async {
    if (!widget.canEdit) return;
    final data = itemDoc.data();
    final titleController = TextEditingController(
      text:
          data['displayTitle']?.toString() ??
          data['freeTextTitle']?.toString() ??
          '',
    );
    final keyController = TextEditingController(
      text: data['keyText']?.toString() ?? '',
    );
    final memoController = TextEditingController(
      text: data['memoShared']?.toString() ?? '',
    );
    final cueLabelController = TextEditingController(
      text: (data['cueLabel'] ?? data['order'] ?? '').toString(),
    );
    final linksController = TextEditingController(
      text: ((data['referenceLinks'] as List?) ?? const []).join('\n'),
    );
    try {
      final updated = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('콘티 수정'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: cueLabelController,
                    decoration: appInputDecoration(
                      context,
                      label: '순서 라벨 (예: 1, 1-2)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: appInputDecoration(context, label: '제목'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyController,
                    decoration: appInputDecoration(context, label: '키 (선택)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: memoController,
                    decoration: appInputDecoration(context, label: '메모'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: linksController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: appInputDecoration(
                      context,
                      label: '레퍼런스 링크 (줄바꿈/쉼표 구분)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (updated != true) return;

      final firestore = ref.read(firestoreProvider);
      final referenceLinks = _parseReferenceLinks(linksController.text);
      final keyText = keyController.text.trim();
      final cueLabel = cueLabelController.text.trim();
      final updates = <String, dynamic>{
        'cueLabel': cueLabel.isEmpty
            ? (data['order']?.toString() ?? '')
            : cueLabel,
        'displayTitle': titleController.text.trim(),
        'keyText': keyText.isEmpty ? null : normalizeKeyText(keyText),
        'memoShared': memoController.text.trim(),
      };
      if (data['songId'] == null) {
        updates['freeTextTitle'] = titleController.text.trim();
      }
      if (referenceLinks.isEmpty) {
        updates['referenceLinks'] = FieldValue.delete();
      } else {
        updates['referenceLinks'] = referenceLinks;
      }

      await firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(widget.projectId)
          .collection('segmentA_setlist')
          .doc(itemDoc.id)
          .update(updates);
      await _syncLiveCueFromSetlist(firestore);
      if (!context.mounted) return;
      setState(() {});
    } finally {
      titleController.dispose();
      keyController.dispose();
      memoController.dispose();
      cueLabelController.dispose();
      linksController.dispose();
    }
  }

  Future<void> _deleteSetlistItem(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> itemDoc,
  ) async {
    if (!widget.canEdit) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('콘티 삭제'),
        content: const Text('이 콘티 항목을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final firestore = ref.read(firestoreProvider);
    await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .collection('segmentA_setlist')
        .doc(itemDoc.id)
        .delete();
    await _syncLiveCueFromSetlist(firestore);
    if (!context.mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _loadProject(firestore),
      builder: (context, projectSnapshot) {
        if (projectSnapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingState(message: '프로젝트 정보를 불러오는 중...');
        }
        if (projectSnapshot.hasError) {
          return AppContentFrame(
            child: AppStateCard(
              icon: Icons.error_outline,
              isError: true,
              title: '프로젝트 로드 실패',
              message: '${projectSnapshot.error}',
            ),
          );
        }
        final projectData = projectSnapshot.data?.data() ?? {};
        if (!_scriptureLoaded) {
          _scriptureController.text =
              projectData['scriptureText']?.toString() ?? '';
          _scriptureLoaded = true;
        }

        final scriptureSection = AppSectionCard(
          icon: Icons.menu_book_rounded,
          title: '말씀 본문',
          subtitle: '예배 본문을 기록하면 팀원이 동일 내용을 확인할 수 있습니다.',
          trailing: widget.canEdit
              ? FilledButton.tonal(
                  onPressed: () => _saveScripture(context),
                  child: const Text('본문 저장'),
                )
              : null,
          child: TextField(
            controller: _scriptureController,
            decoration: appInputDecoration(
              context,
              label: '말씀 본문',
              hint: '예: 마태복음 5:1-12',
            ),
            minLines: 2,
            maxLines: 4,
            readOnly: !widget.canEdit,
          ),
        );

        final composeSection = AppSectionCard(
          icon: Icons.playlist_add_check_rounded,
          title: '찬양 콘티 입력',
          subtitle: '단건 입력과 여러 줄 일괄 입력을 모두 지원합니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '단건 예시: 1 D 예배하는 이에게 / 1 예배하는 이에게 D',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _setlistInputController,
                decoration: appInputDecoration(
                  context,
                  label: '콘티 입력',
                  hint: '예: 1 D 주의 집에 거하는 자 또는 1 주의 집에 거하는 자 D',
                ),
                readOnly: !widget.canEdit,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _memoController,
                decoration: appInputDecoration(
                  context,
                  label: '메모 (공유용)',
                  hint: '팀과 공유할 편곡/주의사항',
                ),
                readOnly: !widget.canEdit,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _referenceLinksController,
                minLines: 1,
                maxLines: 2,
                decoration: appInputDecoration(
                  context,
                  label: '레퍼런스 링크',
                  hint: 'https://youtu.be/xxxxx (쉼표/줄바꿈 구분)',
                ),
                readOnly: !widget.canEdit,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: !widget.canEdit || _saving
                        ? null
                        : () => _addSetlistItem(context),
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add),
                    label: Text(_saving ? '추가 중...' : '콘티 추가'),
                  ),
                  const Chip(
                    avatar: Icon(Icons.auto_awesome, size: 16),
                    label: Text('입력 즉시 LiveCue 자동 반영'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bulkSetlistInputController,
                minLines: 4,
                maxLines: 8,
                decoration: appInputDecoration(
                  context,
                  label: '콘티 일괄 입력 (여러 줄)',
                  hint: '예:\n1 Db 당신의 날에\n2 Ab 새로운 생명\n3 하나님 나라 임하소서 A',
                  helper: '한 줄당 1곡 입력 후 [일괄 추가]. 순서/키는 자동 파싱됩니다.',
                ),
                readOnly: !widget.canEdit,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: !widget.canEdit || _saving
                      ? null
                      : () => _addSetlistItemsBulk(context),
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check),
                  label: const Text('일괄 추가'),
                ),
              ),
            ],
          ),
        );

        final setlistSection =
            FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              future: _loadSetlist(firestore),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingState(message: '콘티 목록 불러오는 중...');
                }
                if (snapshot.hasError) {
                  return AppStateCard(
                    icon: Icons.error_outline,
                    isError: true,
                    title: '콘티 로드 실패',
                    message: '${snapshot.error}',
                    actionLabel: '다시 시도',
                    onAction: () => setState(() {}),
                  );
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return AppStateCard(
                    icon: Icons.playlist_add_check_circle_outlined,
                    title: '등록된 콘티가 없습니다',
                    message: widget.canEdit
                        ? '왼쪽 입력 영역에서 첫 곡을 추가해 주세요.'
                        : '팀장이 콘티를 등록하면 이곳에 표시됩니다.',
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final data = items[index].data();
                    final key = data['keyText']?.toString();
                    final cueLabel =
                        data['cueLabel']?.toString().trim().isNotEmpty == true
                        ? data['cueLabel'].toString()
                        : (data['order']?.toString() ?? '${index + 1}');
                    final title =
                        data['displayTitle']?.toString() ??
                        data['freeTextTitle']?.toString() ??
                        '곡';
                    final memo = data['memoShared']?.toString();
                    final referenceLinks =
                        ((data['referenceLinks'] as List?) ?? const [])
                            .map((e) => e.toString().trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                    final subtitleParts = <String>[];
                    if (memo != null && memo.isNotEmpty) {
                      subtitleParts.add(memo);
                    }
                    if (referenceLinks.isNotEmpty) {
                      subtitleParts.add('레퍼런스 ${referenceLinks.length}개');
                    }
                    final songId = data['songId']?.toString();
                    final query = (key == null || key.isEmpty)
                        ? ''
                        : '?key=${Uri.encodeComponent(key)}';
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.46),
                      ),
                      child: ListTile(
                        title: Text('$cueLabel ${key ?? ''} $title'.trim()),
                        subtitle: subtitleParts.isEmpty
                            ? null
                            : Text(subtitleParts.join(' · ')),
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            if (songId != null)
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf),
                                tooltip: '악보 열기',
                                onPressed: () => context.go(
                                  '/teams/${widget.teamId}/songs/$songId$query',
                                ),
                              ),
                            if (widget.canEdit)
                              IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: '수정',
                                onPressed: () =>
                                    _editSetlistItem(context, items[index]),
                              ),
                            if (widget.canEdit)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '삭제',
                                onPressed: () =>
                                    _deleteSetlistItem(context, items[index]),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );

        return AppContentFrame(
          maxWidth: 1380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.canEdit) ...[
                const AppStateCard(
                  icon: Icons.info_outline,
                  title: '읽기 전용 화면',
                  message: '팀장/인도자 계정에서 콘티를 수정할 수 있습니다.',
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1180;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                scriptureSection,
                                const SizedBox(height: 12),
                                composeSection,
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 7,
                            child: AppSectionCard(
                              icon: Icons.format_list_numbered_rounded,
                              title: '등록 콘티',
                              subtitle: '라이브 운영에 사용할 순서표',
                              child: SizedBox(
                                height: 620,
                                child: setlistSection,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        scriptureSection,
                        const SizedBox(height: 12),
                        composeSection,
                        const SizedBox(height: 12),
                        Expanded(
                          child: AppSectionCard(
                            icon: Icons.format_list_numbered_rounded,
                            title: '등록 콘티',
                            subtitle: '라이브 운영에 사용할 순서표',
                            child: setlistSection,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CueInput {
  final String? cueLabel;
  final String songText;

  const _CueInput({required this.cueLabel, required this.songText});
}

class _ResolvedSetlistSong {
  final String? cueLabel;
  final String? songId;
  final String displayTitle;
  final String? freeTextTitle;
  final String? keyText;
  final bool isValid;

  const _ResolvedSetlistSong({
    required this.cueLabel,
    required this.songId,
    required this.displayTitle,
    required this.freeTextTitle,
    required this.keyText,
  }) : isValid = true;

  const _ResolvedSetlistSong.invalid()
    : cueLabel = null,
      songId = null,
      displayTitle = '',
      freeTextTitle = null,
      keyText = null,
      isValid = false;
}
