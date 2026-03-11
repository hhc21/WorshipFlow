import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/firebase_providers.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';

class SongDetailPage extends ConsumerStatefulWidget {
  final String teamId;
  final String songId;
  final String? keyText;

  const SongDetailPage({
    super.key,
    required this.teamId,
    required this.songId,
    this.keyText,
  });

  @override
  ConsumerState<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends ConsumerState<SongDetailPage> {
  final TextEditingController _noteController = TextEditingController();
  bool _uploading = false;
  bool _noteLoaded = false;
  bool _showAll = false;

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
    _noteController.dispose();
    super.dispose();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadSong(
    FirebaseFirestore firestore,
  ) {
    return firestore.collection('songs').doc(widget.songId).get();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadMember(
    FirebaseFirestore firestore,
    String userId,
  ) {
    return firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('members')
        .doc(userId)
        .get();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadAssets(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore
        .collection('songs')
        .doc(widget.songId)
        .collection('assets')
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs;
  }

  Future<void> _openAssetData(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final storage = ref.read(storageProvider);
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
    Map<String, dynamic> data,
  ) async {
    final storage = ref.read(storageProvider);
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
    Map<String, dynamic> data,
  ) async {
    final storage = ref.read(storageProvider);
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

  Future<void> _editAssetDisplayName(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> assetDoc,
  ) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin || !context.mounted) return;

    final data = assetDoc.data();
    final fileName = (data['fileName'] ?? '파일').toString();
    final currentDisplayName = (data['displayName'] ?? '').toString().trim();
    final controller = TextEditingController(
      text: currentDisplayName.isNotEmpty ? currentDisplayName : fileName,
    );

    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('악보 표시명 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '표시명',
            hintText: '예: D 버전 A',
            helperText: '목록에 보이는 이름만 바뀝니다. (원본 파일명은 유지)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('표시명 초기화'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (nextName == null || !context.mounted) return;

    try {
      await assetDoc.reference.set({
        'displayName': nextName.isEmpty ? FieldValue.delete() : nextName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextName.isEmpty ? '표시명을 초기화했습니다.' : '표시명을 저장했습니다.'),
        ),
      );
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('표시명 수정 실패: ${error.toString()}')));
    }
  }

  Future<void> _deleteAsset(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> assetDoc,
  ) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin || !context.mounted) return;

    final data = assetDoc.data();
    final displayName = (data['displayName'] ?? '').toString().trim();
    final fileName = (data['fileName'] ?? '파일').toString().trim();
    final name = displayName.isNotEmpty ? displayName : fileName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('악보 삭제'),
        content: Text('"$name" 항목을 삭제합니다. 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final storage = ref.read(storageProvider);
    try {
      final storagePath = data['storagePath']?.toString().trim() ?? '';
      if (storagePath.isNotEmpty) {
        try {
          await storage.ref(storagePath).delete();
        } on FirebaseException catch (error) {
          // If storage file is already gone, continue deleting metadata.
          if (error.code != 'object-not-found' && error.code != 'not-found') {
            rethrow;
          }
        }
      }
      await assetDoc.reference.delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('악보 항목을 삭제했습니다.')));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('악보 삭제 실패: $error')));
    }
  }

  Future<void> _uploadAsset(BuildContext context) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) return;
    setState(() => _uploading = true);
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

      final storagePath = buildSongAssetStoragePath(widget.songId, picked.name);
      final refStorage = storage.ref(storagePath);
      await runWithRetry(
        () => refStorage
            .putData(picked.bytes, SettableMetadata(contentType: contentType))
            .timeout(const Duration(seconds: 180)),
        maxAttempts: 2,
      );
      final downloadUrl = await resolveAssetDownloadUrl(storage, {
        'storagePath': storagePath,
      });

      final parsedKey = extractKeyFromFilename(picked.name);
      await firestore
          .collection('songs')
          .doc(widget.songId)
          .collection('assets')
          .add({
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
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _saveNote(BuildContext context) async {
    final auth = ref.read(firebaseAuthProvider);
    final firestore = ref.read(firestoreProvider);
    final user = auth.currentUser;
    if (user == null) return;

    final query = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userSongNotes')
        .where('userId', isEqualTo: user.uid)
        .where('songId', isEqualTo: widget.songId)
        .limit(1)
        .get();

    final content = _noteController.text.trim();
    if (query.docs.isEmpty) {
      await firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('userSongNotes')
          .add({
            'userId': user.uid,
            'songId': widget.songId,
            'content': content,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } else {
      await query.docs.first.reference.update({
        'content': content,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('개인 메모 저장')));
  }

  Future<String> _loadNote(FirebaseFirestore firestore, String userId) async {
    final query = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userSongNotes')
        .where('userId', isEqualTo: userId)
        .where('songId', isEqualTo: widget.songId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return '';
    return query.docs.first.data()['content']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;
    final isGlobalAdmin = ref.watch(globalAdminProvider).value ?? false;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _loadMember(firestore, user.uid),
      builder: (context, memberSnapshot) {
        if (memberSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (memberSnapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('권한 확인 실패: ${memberSnapshot.error}')),
          );
        }
        if (!(memberSnapshot.data?.exists ?? false)) {
          return const Scaffold(
            body: Center(child: Text('팀 멤버만 악보 상세에 접근할 수 있습니다.')),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _loadSong(firestore),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final songData = snapshot.data?.data();
                  if (songData == null) {
                    return const Center(child: Text('곡 정보를 찾을 수 없습니다.'));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            songData['title']?.toString() ?? '곡',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '태그: ${(songData['tags'] as List?)?.join(', ') ?? '-'}',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '악보 목록',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ElevatedButton.icon(
                            onPressed: !isGlobalAdmin || _uploading
                                ? null
                                : () => _uploadAsset(context),
                            icon: const Icon(Icons.upload_file),
                            label: _uploading
                                ? const Text('업로드 중...')
                                : const Text('악보 업로드'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!isGlobalAdmin)
                        Text(
                          '운영자만 악보 업로드/수정이 가능합니다.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (!isGlobalAdmin) const SizedBox(height: 8),
                      Expanded(
                        child:
                            FutureBuilder<
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>
                            >(
                              future: _loadAssets(firestore),
                              builder: (context, assetSnapshot) {
                                if (assetSnapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final assets = assetSnapshot.data ?? [];
                                if (assets.isEmpty) {
                                  return const Center(
                                    child: Text('등록된 악보가 없습니다.'),
                                  );
                                }

                                final keyText = widget.keyText?.trim();
                                final normalizedKey =
                                    (keyText == null || keyText.isEmpty)
                                    ? null
                                    : normalizeKeyText(keyText);
                                final matchingAssets = normalizedKey == null
                                    ? <
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                      >[]
                                    : assets.where((doc) {
                                        return isAssetKeyMatch(
                                          doc.data(),
                                          normalizedKey,
                                        );
                                      }).toList();
                                final showFiltered =
                                    normalizedKey != null &&
                                    !_showAll &&
                                    matchingAssets.isNotEmpty;
                                final visibleAssets = showFiltered
                                    ? matchingAssets
                                    : assets;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (normalizedKey != null) ...[
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              matchingAssets.isEmpty
                                                  ? '키 $normalizedKey 악보가 없습니다. 전체 목록을 표시합니다.'
                                                  : showFiltered
                                                  ? '키 $normalizedKey 악보만 표시 중'
                                                  : '전체 악보 표시 중',
                                            ),
                                          ),
                                          if (matchingAssets.isNotEmpty)
                                            TextButton(
                                              onPressed: () {
                                                setState(() {
                                                  _showAll = showFiltered;
                                                });
                                              },
                                              child: Text(
                                                showFiltered
                                                    ? '전체 보기'
                                                    : '키만 보기',
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (matchingAssets.isNotEmpty)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => _openAssetData(
                                              context,
                                              matchingAssets.first.data(),
                                            ),
                                            icon: const Icon(
                                              Icons.picture_as_pdf,
                                            ),
                                            label: Text(
                                              '키 $normalizedKey 악보 열기',
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                    ],
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: visibleAssets.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final assetDoc = visibleAssets[index];
                                          final data = assetDoc.data();
                                          final fileName =
                                              data['fileName']?.toString() ??
                                              '파일';
                                          final displayName =
                                              data['displayName']
                                                  ?.toString()
                                                  .trim() ??
                                              '';
                                          final fileKey = assetKeyText(data);
                                          final details = <String>[];
                                          final contentType =
                                              data['contentType']?.toString();
                                          if (contentType != null &&
                                              contentType.isNotEmpty) {
                                            details.add(contentType);
                                          }
                                          if (fileKey != null &&
                                              fileKey.isNotEmpty) {
                                            details.add('Key $fileKey');
                                          }
                                          if (displayName.isNotEmpty &&
                                              displayName != fileName) {
                                            details.add('원본: $fileName');
                                          }
                                          return ListTile(
                                            title: Text(
                                              displayName.isNotEmpty
                                                  ? displayName
                                                  : fileName,
                                            ),
                                            subtitle: details.isEmpty
                                                ? null
                                                : Text(details.join(' · ')),
                                            trailing: Wrap(
                                              spacing: 4,
                                              children: [
                                                if (isGlobalAdmin)
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit_outlined,
                                                    ),
                                                    tooltip: '표시명 수정',
                                                    onPressed: () =>
                                                        _editAssetDisplayName(
                                                          context,
                                                          assetDoc,
                                                        ),
                                                  ),
                                                IconButton(
                                                  icon: const Icon(Icons.link),
                                                  tooltip: '링크 복사',
                                                  onPressed: () =>
                                                      _copyAssetLink(
                                                        context,
                                                        data,
                                                      ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.open_in_new_rounded,
                                                  ),
                                                  tooltip: '미리보기',
                                                  onPressed: () =>
                                                      _openAssetData(
                                                        context,
                                                        data,
                                                      ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.download_rounded,
                                                  ),
                                                  tooltip: '다운로드',
                                                  onPressed: () =>
                                                      _downloadAssetData(
                                                        context,
                                                        data,
                                                      ),
                                                ),
                                                if (isGlobalAdmin)
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                    tooltip: '삭제',
                                                    onPressed: () =>
                                                        _deleteAsset(
                                                          context,
                                                          assetDoc,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '개인 메모',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<String>(
                        future: _loadNote(firestore, user.uid),
                        builder: (context, noteSnapshot) {
                          if (noteSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !_noteLoaded) {
                            return const LinearProgressIndicator();
                          }
                          if (!_noteLoaded) {
                            _noteController.text = noteSnapshot.data ?? '';
                            _noteLoaded = true;
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _noteController,
                                minLines: 3,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: '개인 메모를 입력하세요',
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => _saveNote(context),
                                child: const Text('메모 저장'),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
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
