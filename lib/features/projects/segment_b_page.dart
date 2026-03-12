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
  bool _saving = false;

  @override
  void dispose() {
    _inputController.dispose();
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
    final parsed = parseSongInput(raw);

    try {
      final candidates = await findSongCandidates(firestore, parsed.title);

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

    return AppContentFrame(
      maxWidth: 1360,
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
          AppSectionCard(
            icon: Icons.queue_music_rounded,
            title: '적용찬양 입력',
            subtitle: '예: [G 주 예수 내 맘에 오사]',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    readOnly: !widget.canEdit,
                    decoration: appInputDecoration(
                      context,
                      label: '적용찬양 입력',
                      hint: '예: [G 주 예수 내 맘에 오사]',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                      : const Icon(Icons.add),
                  label: Text(_saving ? '추가 중...' : '추가'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppSectionCard(
              icon: Icons.format_list_numbered_rounded,
              title: '적용찬양 목록',
              subtitle: '현재 등록된 적용찬양 순서',
              child:
                  FutureBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >(
                    future: _loadItems(firestore),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const AppLoadingState(
                          message: '적용찬양 목록 불러오는 중...',
                        );
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
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.46),
                            ),
                            child: ListTile(
                              title: Text(
                                '${data['order']} ${key ?? ''} $title'.trim(),
                              ),
                              trailing: songId == null
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.picture_as_pdf),
                                      tooltip: '악보 열기',
                                      onPressed: () => context.go(
                                        '/teams/${widget.teamId}/songs/$songId$query',
                                      ),
                                    ),
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
