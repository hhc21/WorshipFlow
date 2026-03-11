import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';

class GlobalSongPanel extends ConsumerStatefulWidget {
  const GlobalSongPanel({super.key});

  @override
  ConsumerState<GlobalSongPanel> createState() => _GlobalSongPanelState();
}

class _GlobalSongPanelState extends ConsumerState<GlobalSongPanel> {
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
        .limit(30)
        .get();
    return snapshot.docs;
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
      await firestore.collection('songs').add({
        if (defaultKey != null) 'defaultKey': defaultKey,
        'title': title,
        'aliases': aliases,
        'tags': tags,
        'searchTokens': buildSearchTokens(title, aliases),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
      });

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

  Future<void> _uploadAsset(BuildContext context, String songId) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) {
      return;
    }
    if (_uploadingSongId != null) return;
    setState(() => _uploadingSongId = songId);

    final firestore = ref.read(firestoreProvider);
    final storage = ref.read(storageProvider);

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
      final refStorage = storage.ref(storagePath);
      await runWithRetry(
        () => refStorage
            .putData(
              picked.bytes,
              SettableMetadata(
                contentType: contentType,
                customMetadata: {
                  'uploadedBy':
                      ref.read(firebaseAuthProvider).currentUser?.uid ??
                      'unknown',
                },
              ),
            )
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

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadSongAssets(
    FirebaseFirestore firestore,
    String songId,
  ) async {
    final snapshot = await firestore
        .collection('songs')
        .doc(songId)
        .collection('assets')
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs;
  }

  Future<void> _openAssetData(
    BuildContext context,
    FirebaseStorage storage,
    Map<String, dynamic> data,
  ) async {
    try {
      final url = await resolveAssetDownloadUrl(storage, data);
      if (url == null || url.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('악보 링크를 불러오지 못했습니다.')));
        return;
      }
      if (!context.mounted) return;
      await _showAssetPreviewDialog(context, data, url);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainStorageError(error, action: '악보 열기'))),
      );
    }
  }

  bool _isImageAsset(Map<String, dynamic> data) {
    final contentType = data['contentType']?.toString().toLowerCase() ?? '';
    final fileName = data['fileName']?.toString().toLowerCase() ?? '';
    return contentType.startsWith('image/') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.webp');
  }

  Future<void> _showAssetPreviewDialog(
    BuildContext context,
    Map<String, dynamic> data,
    String url,
  ) async {
    final fileName = data['displayName']?.toString().trim().isNotEmpty == true
        ? data['displayName'].toString().trim()
        : (data['fileName']?.toString().trim().isNotEmpty == true
              ? data['fileName'].toString().trim()
              : '악보');
    final isImage = _isImageAsset(data);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fileName,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: isImage
                      ? Container(
                          color: Colors.black12,
                          child: InteractiveViewer(
                            minScale: 0.6,
                            maxScale: 4,
                            child: Center(child: Image.network(url)),
                          ),
                        )
                      : Container(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.surfaceContainerHighest,
                          padding: const EdgeInsets.all(12),
                          child: const Text(
                            '이 파일 형식은 앱 내 미리보기를 지원하지 않습니다. 아래 버튼으로 새 탭에서 열거나 링크를 복사할 수 있습니다.',
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('닫기'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => copyTextWithFallback(
                        dialogContext,
                        text: url,
                        successMessage: '악보 링크 복사됨',
                        failureTitle: '악보 링크를 아래에서 복사하세요',
                      ),
                      child: const Text('링크 복사'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final opened = openUrlInNewTab(url);
                        if (!opened) {
                          copyTextWithFallback(
                            dialogContext,
                            text: url,
                            successMessage: '악보 링크 복사됨',
                            failureTitle: '악보 링크를 아래에서 복사하세요',
                          );
                        }
                      },
                      child: const Text('새 탭에서 열기'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyAssetLink(
    BuildContext context,
    FirebaseStorage storage,
    Map<String, dynamic> data,
  ) async {
    try {
      final url = await resolveAssetDownloadUrl(storage, data);
      if (url == null || url.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('악보 링크를 불러오지 못했습니다.')));
        return;
      }
      if (!context.mounted) return;
      await copyTextWithFallback(
        context,
        text: url,
        successMessage: '악보 링크 복사됨',
        failureTitle: '악보 링크를 아래에서 복사하세요',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainStorageError(error, action: '링크 복사'))),
      );
    }
  }

  Future<void> _downloadAssetData(
    BuildContext context,
    FirebaseStorage storage,
    Map<String, dynamic> data,
  ) async {
    try {
      final url = await resolveAssetDownloadUrl(storage, data);
      if (url == null || url.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('악보 링크를 불러오지 못했습니다.')));
        return;
      }
      final fileName = data['fileName']?.toString();
      final downloaded = downloadUrlInBrowser(url, fileName: fileName);
      if (downloaded) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('다운로드를 시작했습니다.')));
        return;
      }
      final opened = openUrlInNewTab(url);
      if (!context.mounted) return;
      if (opened) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('브라우저에서 파일을 열었습니다.')));
        return;
      }
      await copyTextWithFallback(
        context,
        text: url,
        successMessage: '다운로드 링크 복사됨',
        failureTitle: '다운로드 링크를 아래에서 복사하세요',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainStorageError(error, action: '다운로드'))),
      );
    }
  }

  Future<void> _showSongAssetsSheet(
    BuildContext context,
    FirebaseFirestore firestore,
    FirebaseStorage storage,
    String songId,
    String songTitle,
    bool canInlineEdit,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var reloadToken = 0;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$songTitle · 악보 목록',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (canInlineEdit)
                            FilledButton.tonalIcon(
                              onPressed: _uploadingSongId == songId
                                  ? null
                                  : () async {
                                      await _uploadAsset(context, songId);
                                      if (!sheetContext.mounted) return;
                                      setSheetState(() {
                                        reloadToken += 1;
                                      });
                                    },
                              icon: _uploadingSongId == songId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(
                                _uploadingSongId == songId
                                    ? '업로드 중...'
                                    : '악보 업로드',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            FutureBuilder<
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>
                            >(
                              key: ValueKey('asset-list-$songId-$reloadToken'),
                              future: _loadSongAssets(firestore, songId),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return AppStateCard(
                                    icon: Icons.error_outline,
                                    isError: true,
                                    title: '악보 목록 로드 실패',
                                    message: '${snapshot.error}',
                                    actionLabel: '다시 시도',
                                    onAction: () {
                                      setSheetState(() {
                                        reloadToken += 1;
                                      });
                                    },
                                  );
                                }
                                final assets = snapshot.data ?? [];
                                if (assets.isEmpty) {
                                  return AppStateCard(
                                    icon: Icons.upload_file_rounded,
                                    title: '등록된 악보가 없습니다',
                                    message: canInlineEdit
                                        ? '오른쪽 위 [악보 업로드]로 첫 파일을 등록해 주세요.'
                                        : '운영자에게 악보 업로드를 요청해 주세요.',
                                  );
                                }
                                return ListView.separated(
                                  itemCount: assets.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final data = assets[index].data();
                                    final fileName =
                                        data['fileName']?.toString() ?? '파일';
                                    final fileKey = assetKeyText(data);
                                    final details = <String>[];
                                    final contentType = data['contentType']
                                        ?.toString();
                                    if (contentType != null &&
                                        contentType.isNotEmpty) {
                                      details.add(contentType);
                                    }
                                    if (fileKey != null && fileKey.isNotEmpty) {
                                      details.add('Key $fileKey');
                                    }
                                    return ListTile(
                                      title: Text(fileName),
                                      subtitle: details.isEmpty
                                          ? null
                                          : Text(details.join(' · ')),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.link),
                                            tooltip: '링크 복사',
                                            onPressed: () => _copyAssetLink(
                                              context,
                                              storage,
                                              data,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.open_in_new_rounded,
                                            ),
                                            tooltip: '미리보기',
                                            onPressed: () => _openAssetData(
                                              context,
                                              storage,
                                              data,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.download_rounded,
                                            ),
                                            tooltip: '다운로드',
                                            onPressed: () => _downloadAssetData(
                                              context,
                                              storage,
                                              data,
                                            ),
                                          ),
                                        ],
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
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);
    final storage = ref.watch(storageProvider);
    final adminValue = ref.watch(globalAdminProvider);
    final isAdmin = adminValue.value ?? false;
    final adminLoading = adminValue.isLoading;
    final canInlineEdit =
        isAdmin &&
        (ModalRoute.of(context)?.settings.name == '/admin-inline-edit');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('전역 악보 관리', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '팀과 관계없이 전역 곡을 검색하고 악보를 조회합니다.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (adminLoading) ...[
          const SizedBox(height: 6),
          Text('운영자 권한 확인 중...', style: Theme.of(context).textTheme.bodySmall),
        ] else if (!isAdmin) ...[
          const SizedBox(height: 6),
          Text(
            '읽기 전용: 운영자만 전역 곡 생성/악보 업로드/수정이 가능합니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                '관리 기능(곡 추가/수정/업로드)은 운영자 도구에서만 수행합니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: () => context.go('/admin'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('운영자 도구 열기'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: '전역 곡 검색 (제목/별칭)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _query = _searchController.text;
                });
              },
              child: const Text('검색'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: _loadGlobalSongs(firestore),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final songs = snapshot.data ?? [];
            if (songs.isEmpty) {
              return const Text('검색 결과가 없습니다.');
            }
            return Column(
              children: songs.map((doc) {
                final data = doc.data();
                return Card(
                  child: ListTile(
                    title: Text(data['title']?.toString() ?? '제목 없음'),
                    subtitle: Text(
                      (data['tags'] as List?)?.join(', ') ?? '태그 없음',
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (adminLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => _showSongAssetsSheet(
                                  context,
                                  firestore,
                                  storage,
                                  doc.id,
                                  data['title']?.toString() ?? '곡',
                                  canInlineEdit,
                                ),
                                child: const Text('악보 목록'),
                              ),
                              if (canInlineEdit)
                                TextButton(
                                  onPressed: _uploadingSongId == doc.id
                                      ? null
                                      : () => _uploadAsset(context, doc.id),
                                  child: _uploadingSongId == doc.id
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('악보 업로드'),
                                )
                              else
                                Text(
                                  '읽기 전용',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                            ],
                          ),
                        Text(
                          "예: [D ${data['title'] ?? '곡명'}].pdf",
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        if (canInlineEdit) ...[
          const SizedBox(height: 24),
          Text('전역 곡 새로 추가', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Text(
                        '입력 가이드',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Spacer(),
                      CircleOfFifthsHelpButton(label: '5도권 참고', compact: true),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text('• 곡 제목은 순수 제목만 입력합니다.'),
                  Text('• 키는 콘티/LiveCue 입력에서 “D 곡명” 형태로 입력하세요.'),
                  Text('• 악보 파일명 예시: [D 곡명].pdf (키 자동 필터용)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '곡 제목',
              helperText: '예: 주의 집에 거하는 자',
              hintText: '[주의 집에 거하는 자 D]',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: '키 (선택)',
              hintText: '예: D, Eb, F#',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aliasController,
            decoration: const InputDecoration(
              labelText: '별칭 (쉼표로 구분)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: '태그 (쉼표로 구분)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _saving || adminLoading
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
      ],
    );
  }
}
