import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../services/song_search.dart';
import '../../utils/song_parser.dart';

class SegmentBPage extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;
  final bool canEdit;

  const SegmentBPage({
    super.key,
    required this.teamId,
    required this.projectId,
    required this.canEdit,
  });

  @override
  ConsumerState<SegmentBPage> createState() => _SegmentBPageState();
}

class _SegmentBPageState extends ConsumerState<SegmentBPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _bulkInputController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _inputController.dispose();
    _bulkInputController.dispose();
    super.dispose();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadItems(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .collection('segmentB_application')
        .orderBy('order')
        .get();
    return snapshot.docs;
  }

  Future<void> _addItem(BuildContext context) async {
    if (!widget.canEdit) return;
    final raw = _inputController.text.trim();
    if (raw.isEmpty) return;

    setState(() => _saving = true);
    final firestore = ref.read(firestoreProvider);
    final parsed = parseSongInput(_parseCueInput(raw).songText);

    try {
      final candidates = await resolveSongCandidates(
        firestore,
        songId: null,
        rawTitle: parsed.title,
        keyText: parsed.keyText,
        teamId: widget.teamId,
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

      final collection = firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(widget.projectId)
          .collection('segmentB_application');

      final currentItems = await _loadItems(firestore);
      final lastOrder = currentItems.isEmpty
          ? 0
          : (currentItems.last.data()['order'] as num?)?.toInt() ??
                currentItems.length;
      final nextOrder = lastOrder + 1;

      await collection.add({
        'order': nextOrder,
        'songId': songId,
        'freeTextTitle': songId == null ? parsed.title : null,
        'displayTitle': displayTitle,
        'keyText': parsed.keyText,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _inputController.clear();
      if (!context.mounted) return;
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('적용찬양 추가 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  _CueInput _parseCueInput(String rawInput) {
    final input = rawInput.trim();
    final matched = RegExp(
      r'^(?<label>\d+(?:-\d+)?)(?:[.)])?\s+(?<rest>.+)$',
    ).firstMatch(input);
    if (matched == null) {
      return _CueInput(songText: input);
    }
    final rest = matched.namedGroup('rest')?.trim() ?? input;
    if (rest.isEmpty) {
      return _CueInput(songText: input);
    }
    return _CueInput(songText: rest);
  }

  List<String> _parseBulkLines(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<_ResolvedApplicationSong?> _resolveBulkItem(
    FirebaseFirestore firestore,
    String rawLine,
  ) async {
    final parsed = parseSongInput(_parseCueInput(rawLine).songText);
    if (parsed.title.isEmpty) return null;

    final normalizedKey = parsed.keyText == null
        ? null
        : normalizeKeyText(parsed.keyText!);
    final matched = await resolvePrimarySongCandidate(
      firestore,
      songId: null,
      rawTitle: parsed.title,
      keyText: parsed.keyText,
      teamId: widget.teamId,
    );
    if (matched != null) {
      return _ResolvedApplicationSong(
        songId: matched.id,
        displayTitle: matched.title,
        freeTextTitle: null,
        keyText: normalizedKey,
      );
    }
    return _ResolvedApplicationSong(
      songId: null,
      displayTitle: parsed.title,
      freeTextTitle: parsed.title,
      keyText: normalizedKey,
    );
  }

  Future<void> _addItemsBulk(BuildContext context) async {
    if (!widget.canEdit) return;
    final raw = _bulkInputController.text.trim();
    if (raw.isEmpty) return;

    final lines = _parseBulkLines(raw);
    if (lines.isEmpty) return;

    setState(() => _saving = true);
    final firestore = ref.read(firestoreProvider);

    try {
      final collection = firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(widget.projectId)
          .collection('segmentB_application');

      final currentItems = await _loadItems(firestore);
      var orderCursor = currentItems.isEmpty
          ? 0
          : (currentItems.last.data()['order'] as num?)?.toInt() ??
                currentItems.length;

      final batch = firestore.batch();
      var addedCount = 0;
      final skipped = <String>[];

      for (final line in lines) {
        final resolved = await _resolveBulkItem(firestore, line);
        if (resolved == null) {
          skipped.add(line);
          continue;
        }
        orderCursor += 1;
        batch.set(collection.doc(), {
          'order': orderCursor,
          'songId': resolved.songId,
          'freeTextTitle': resolved.freeTextTitle,
          'displayTitle': resolved.displayTitle,
          'keyText': resolved.keyText,
          'createdAt': FieldValue.serverTimestamp(),
        });
        addedCount += 1;
      }

      if (addedCount == 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('일괄 입력에서 유효한 적용찬양을 찾지 못했습니다.')),
          );
        }
        return;
      }

      await batch.commit();
      _bulkInputController.clear();
      if (!context.mounted) return;
      final skippedInfo = skipped.isEmpty ? '' : ' (건너뜀 ${skipped.length}줄)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('적용찬양 $addedCount곡을 일괄 추가했습니다.$skippedInfo')),
      );
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('적용찬양 일괄 추가 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _reorderItem(
    FirebaseFirestore firestore,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items, {
    required int oldIndex,
    required int newIndex,
  }) async {
    if (!widget.canEdit ||
        oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex >= items.length ||
        oldIndex == newIndex) {
      return;
    }

    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _saving = true);
    try {
      final batch = firestore.batch();
      for (var i = 0; i < reordered.length; i++) {
        batch.update(reordered[i].reference, {'order': i + 1});
      }
      await batch.commit();
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteItem(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> itemDoc,
  ) async {
    if (!widget.canEdit || _saving) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('적용찬양 삭제'),
        content: const Text('이 적용찬양 항목을 삭제할까요?'),
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

    setState(() => _saving = true);
    try {
      await itemDoc.reference.delete();
      if (!mounted) return;
      setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);

    final composeSection = AppSectionCard(
      icon: Icons.queue_music_rounded,
      title: '적용찬양 입력',
      subtitle: '단건 입력과 여러 줄 일괄 입력을 모두 지원합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '단건 예시: 1 D 새로운 생명 / 1 새로운 생명 D',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _inputController,
            readOnly: !widget.canEdit,
            decoration: appInputDecoration(
              context,
              label: '적용찬양 입력',
              hint: '예: 1 D 새로운 생명 또는 1 새로운 생명 D',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: !widget.canEdit || _saving
                    ? null
                    : () => _addItem(context),
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add),
                label: Text(_saving ? '추가 중...' : '적용찬양 추가'),
              ),
              const Chip(
                avatar: Icon(Icons.auto_awesome, size: 16),
                label: Text('번호 prefix / 키 자동 정리'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bulkInputController,
            minLines: 4,
            maxLines: 8,
            readOnly: !widget.canEdit,
            decoration: appInputDecoration(
              context,
              label: '적용찬양 일괄 입력 (여러 줄)',
              hint: '예:\n1 새로운 생명 G\n2 주의 집에 거하는 자 D\n3 나를 지으신 이가 하나님 G',
              helper: '한 줄당 1곡 입력 후 [일괄 추가]. 번호 prefix는 자동 제거됩니다.',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: !widget.canEdit || _saving
                  ? null
                  : () => _addItemsBulk(context),
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

    final listSection =
        FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: _loadItems(firestore),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoadingState(message: '적용찬양 목록 불러오는 중...');
            }
            if (snapshot.hasError) {
              return AppStateCard(
                icon: Icons.error_outline,
                isError: true,
                title: '적용찬양 로드 실패',
                message: '${snapshot.error}',
                actionLabel: '다시 시도',
                onAction: () => setState(() {}),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return AppStateCard(
                icon: Icons.queue_music_outlined,
                title: '등록된 적용찬양이 없습니다',
                message: widget.canEdit
                    ? '위 입력창에서 적용찬양을 추가해 주세요.'
                    : '팀장이 적용찬양을 등록하면 여기에서 확인할 수 있습니다.',
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final data = items[index].data();
                final key = data['keyText']?.toString();
                final title =
                    data['displayTitle']?.toString() ??
                    data['freeTextTitle']?.toString() ??
                    '곡';
                final songId = data['songId']?.toString();
                final query = (key == null || key.isEmpty)
                    ? ''
                    : '?key=${Uri.encodeComponent(key)}';
                return AppActionListTile(
                  title: Text('${data['order']} ${key ?? ''} $title'.trim()),
                  subtitle: songId == null ? const Text('미연결 제목') : null,
                  actions: [
                    if (widget.canEdit && index > 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_upward),
                        tooltip: '위로 이동',
                        onPressed: _saving
                            ? null
                            : () => _reorderItem(
                                firestore,
                                items,
                                oldIndex: index,
                                newIndex: index - 1,
                              ),
                      ),
                    if (widget.canEdit && index < items.length - 1)
                      IconButton(
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: '아래로 이동',
                        onPressed: _saving
                            ? null
                            : () => _reorderItem(
                                firestore,
                                items,
                                oldIndex: index,
                                newIndex: index + 1,
                              ),
                      ),
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
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '삭제',
                        onPressed: _saving
                            ? null
                            : () => _deleteItem(context, items[index]),
                      ),
                  ],
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
              message: '팀장/인도자 계정에서만 적용찬양을 편집할 수 있습니다.',
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1180;
                final listCard = AppSectionCard(
                  icon: Icons.format_list_numbered_rounded,
                  title: '적용찬양 목록',
                  subtitle: '현재 등록된 적용찬양 순서',
                  child: isWide
                      ? SizedBox(height: 620, child: listSection)
                      : listSection,
                );
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: composeSection),
                      const SizedBox(width: 12),
                      Expanded(flex: 7, child: listCard),
                    ],
                  );
                }
                return Column(
                  children: [
                    composeSection,
                    const SizedBox(height: 12),
                    Expanded(child: listCard),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CueInput {
  final String songText;

  const _CueInput({required this.songText});
}

class _ResolvedApplicationSong {
  final String? songId;
  final String displayTitle;
  final String? freeTextTitle;
  final String? keyText;

  const _ResolvedApplicationSong({
    required this.songId,
    required this.displayTitle,
    required this.freeTextTitle,
    required this.keyText,
  });
}
