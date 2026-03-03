import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';

class SongLibraryPanel extends ConsumerStatefulWidget {
  final String teamId;

  const SongLibraryPanel({super.key, required this.teamId});

  @override
  ConsumerState<SongLibraryPanel> createState() => _SongLibraryPanelState();
}

class _SongLibraryPanelState extends ConsumerState<SongLibraryPanel> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  String _query = '';
  bool _saving = false;
  String? _uploadingSongId;

  Future<bool> _ensureGlobalAdmin(BuildContext context) async {
    try {
      final isAdmin = await ref.read(globalAdminProvider.future);
      if (isAdmin) return true;
    } catch (_) {
      // Fall through to guidance snackbar.
    }
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('운영자 권한이 없습니다. globalAdmins/{uid} 문서를 확인해 주세요.'),
      ),
    );
    return false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _keyController.dispose();
    _aliasController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadTeamSongs(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('songRefs')
        .orderBy('title')
        .get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadGlobalSongs(
    FirebaseFirestore firestore,
  ) async {
    final query = _query.trim();
    final collection = firestore.collection('songs');

    if (query.isEmpty) {
      final snapshot = await collection.orderBy('title').limit(30).get();
      return snapshot.docs;
    }

    final snapshot = await collection
        .where('searchTokens', arrayContains: normalizeQuery(query))
        .limit(20)
        .get();
    return snapshot.docs;
  }

  Future<void> _addSongRef(
    FirebaseFirestore firestore,
    String songId,
    String title,
  ) async {
    final ref = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('songRefs')
        .doc(songId);
    await ref.set({
      'songId': songId,
      'title': title,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _createGlobalSong(BuildContext context) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) {
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final aliases = _aliasController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tags = _tagsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final rawKey = _keyController.text.trim();
    final defaultKey = rawKey.isEmpty ? null : normalizeKeyText(rawKey);

    final firestore = ref.read(firestoreProvider);
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final doc = await firestore.collection('songs').add({
        if (defaultKey != null) 'defaultKey': defaultKey,
        'title': title,
        'aliases': aliases,
        'tags': tags,
        'searchTokens': buildSearchTokens(title, aliases),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
      });

      await _addSongRef(firestore, doc.id, title);

      _titleController.clear();
      _keyController.clear();
      _aliasController.clear();
      _tagsController.clear();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('전역 곡 추가 완료')));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('곡 생성 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _uploadSongAsset(BuildContext context, String songId) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) {
      return;
    }
    if (_uploadingSongId != null) return;

    setState(() => _uploadingSongId = songId);
    final storage = ref.read(storageProvider);
    final firestore = ref.read(firestoreProvider);

    try {
      final picked = await pickFileForUpload(accept: 'application/pdf,image/*');
      if (picked == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('파일 선택이 취소되었습니다.')));
        return;
      }
      final contentType = resolveSongAssetContentType(
        fileName: picked.name,
        rawContentType: picked.contentType,
      );
      final selectionError = validateSongAssetSelection(
        picked: picked,
        resolvedContentType: contentType,
      );
      if (selectionError != null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(selectionError)));
        return;
      }

      final storagePath = buildSongAssetStoragePath(songId, picked.name);
      await runWithRetry(
        () => storage
            .ref(storagePath)
            .putData(picked.bytes, SettableMetadata(contentType: contentType))
            .timeout(const Duration(seconds: 180)),
        maxAttempts: 2,
      );
      final downloadUrl = await resolveAssetDownloadUrl(storage, {
        'storagePath': storagePath,
      });
      final parsedKey = extractKeyFromFilename(picked.name);
      await firestore.collection('songs').doc(songId).collection('assets').add({
        'fileName': picked.name,
        'contentType': contentType,
        'storagePath': storagePath,
        if (downloadUrl != null && downloadUrl.isNotEmpty)
          'downloadUrl': downloadUrl,
        if (parsedKey != null) 'keyText': normalizeKeyText(parsedKey),
        'sizeBytes': picked.sizeBytes,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('악보 업로드 완료')));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainStorageError(error, action: '업로드'))),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingSongId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);
    final isAdmin = ref.watch(globalAdminProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionCard(
          icon: Icons.linked_camera_rounded,
          title: '팀에서 사용하는 곡',
          subtitle: '현재 팀에 연결된 곡',
          child:
              FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                future: _loadTeamSongs(firestore),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoadingState(message: '팀 곡 목록 불러오는 중...');
                  }
                  if (snapshot.hasError) {
                    return AppStateCard(
                      icon: Icons.error_outline,
                      isError: true,
                      title: '팀 곡 목록 로드 실패',
                      message: '${snapshot.error}',
                      actionLabel: '다시 시도',
                      onAction: () => setState(() {}),
                    );
                  }
                  final songs = snapshot.data ?? [];
                  if (songs.isEmpty) {
                    return const AppStateCard(
                      icon: Icons.queue_music_outlined,
                      title: '아직 연결된 곡이 없습니다',
                      message: '아래 전역 곡 검색에서 팀에 추가해 주세요.',
                    );
                  }
                  return Column(
                    children: songs.map((doc) {
                      final data = doc.data();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.42),
                          ),
                          child: ListTile(
                            title: Text(data['title']?.toString() ?? '곡'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              '/teams/${widget.teamId}/songs/${doc.id}',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
        ),
        const SizedBox(height: 12),
        AppSectionCard(
          icon: Icons.search_rounded,
          title: '전역 곡 검색/추가',
          subtitle: '전역 DB에서 곡을 검색하고 팀에 연결합니다.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: appInputDecoration(
                        context,
                        label: '전역 곡 검색 (제목/별칭)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _query = _searchController.text;
                      });
                    },
                    child: const Text('검색'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                future: _loadGlobalSongs(firestore),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoadingState(message: '전역 곡 불러오는 중...');
                  }
                  if (snapshot.hasError) {
                    return AppStateCard(
                      icon: Icons.error_outline,
                      isError: true,
                      title: '전역 곡 로드 실패',
                      message: '${snapshot.error}',
                      actionLabel: '다시 시도',
                      onAction: () => setState(() {}),
                    );
                  }
                  final songs = snapshot.data ?? [];
                  if (songs.isEmpty) {
                    return const AppStateCard(
                      icon: Icons.find_in_page_outlined,
                      title: '검색 결과가 없습니다',
                      message: '다른 키워드로 검색하거나 새 전역 곡을 생성해 주세요.',
                    );
                  }
                  return Column(
                    children: songs.map((doc) {
                      final data = doc.data();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.42),
                          ),
                          child: ListTile(
                            title: Text(data['title']?.toString() ?? '제목 없음'),
                            subtitle: Text(
                              (data['tags'] as List?)?.join(', ') ?? '태그 없음',
                            ),
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isAdmin)
                                    OutlinedButton(
                                      onPressed: _uploadingSongId == doc.id
                                          ? null
                                          : () => _uploadSongAsset(
                                              context,
                                              doc.id,
                                            ),
                                      child: _uploadingSongId == doc.id
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('악보 업로드'),
                                    ),
                                  if (isAdmin) const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await _addSongRef(
                                          firestore,
                                          doc.id,
                                          data['title']?.toString() ?? '곡',
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('팀에 추가됨'),
                                          ),
                                        );
                                        setState(() {});
                                      } catch (error) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('팀에 곡 추가 실패: $error'),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('팀에 추가'),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () => context.go(
                              '/teams/${widget.teamId}/songs/${doc.id}',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppSectionCard(
          icon: Icons.add_circle_outline_rounded,
          title: '전역 곡 새로 추가',
          subtitle: isAdmin
              ? '운영자 모드: 전역 곡 생성 후 악보 업로드 가능'
              : '운영자 계정에서만 전역 곡 생성이 가능합니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '입력 가이드',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Spacer(),
                        CircleOfFifthsHelpButton(
                          label: '5도권 참고',
                          compact: true,
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text('• 곡 제목은 순수 제목만 입력합니다.'),
                    Text('• 키는 콘티/LiveCue 입력에서 “D 곡명” 형태로 입력하세요.'),
                    Text('• 악보 파일명 예시: [D 곡명].pdf (키 자동 필터용)'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: appInputDecoration(
                  context,
                  label: '곡 제목',
                  helper: '예: 주의 집에 거하는 자',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                decoration: appInputDecoration(
                  context,
                  label: '키 (선택)',
                  hint: '예: D, Eb, F#',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _aliasController,
                decoration: appInputDecoration(context, label: '별칭 (쉼표로 구분)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tagsController,
                decoration: appInputDecoration(context, label: '태그 (쉼표로 구분)'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: !isAdmin || _saving
                      ? null
                      : () => _createGlobalSong(context),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('전역 곡 추가'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
