import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../utils/firestore_id.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/browser_types.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/song_parser.dart';
import '../../utils/storage_helpers.dart';

class GlobalAdminRoutePage extends ConsumerWidget {
  const GlobalAdminRoutePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminState = ref.watch(globalAdminProvider);

    return adminState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('운영자 도구')),
        body: Center(child: Text('권한 확인 실패: $error')),
      ),
      data: (isAdmin) {
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('운영자 도구')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('운영자 권한이 필요합니다.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.go('/teams'),
                    child: const Text('팀 화면으로 이동'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('운영자 도구'),
            actions: [
              IconButton(
                onPressed: () => context.go('/teams'),
                icon: const Icon(Icons.groups),
                tooltip: '팀 화면',
              ),
            ],
          ),
          body: const SafeArea(child: GlobalAdminPage()),
        );
      },
    );
  }
}

class GlobalAdminPage extends ConsumerStatefulWidget {
  const GlobalAdminPage({super.key});

  @override
  ConsumerState<GlobalAdminPage> createState() => _GlobalAdminPageState();
}

class _GlobalAdminPageState extends ConsumerState<GlobalAdminPage> {
  bool _migrating = false;
  String _status = '';
  String? _uploadingSongId;
  final Map<String, Future<String?>> _assetUrlFutureCache = {};
  final Map<String, Future<Uint8List?>> _assetBytesFutureCache = {};

  Future<bool> _ensureGlobalAdmin(BuildContext context) async {
    try {
      final isAdmin = await ref.read(globalAdminProvider.future);
      if (isAdmin) return true;
    } catch (_) {
      // Fall through to message.
    }
    if (!context.mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('운영자 권한이 필요합니다.')));
    return false;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadTeams(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore.collection('teams').get();
    return snapshot.docs;
  }

  Future<void> _openTeamHome(BuildContext context, String teamId) async {
    final normalized = teamId.trim();
    if (!isValidFirestoreDocId(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀 ID가 올바르지 않아 팀 홈으로 이동할 수 없습니다.')),
      );
      return;
    }
    try {
      final teamDoc = await ref
          .read(firestoreProvider)
          .collection('teams')
          .doc(normalized)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!teamDoc.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택한 팀이 존재하지 않아 이동할 수 없습니다.')),
        );
        return;
      }
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('팀 확인 실패: ${error.message ?? error.code}')),
      );
      return;
    } on TimeoutException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('팀 정보 확인 시간이 초과되었습니다.')));
      return;
    }
    if (!context.mounted) return;
    context.go('/teams/${Uri.encodeComponent(normalized)}');
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadGlobalSongs(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore.collection('songs').orderBy('title').get();
    return snapshot.docs;
  }

  Future<String?> _resolveAssetUrl(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    final cachedFuture = _assetUrlFutureCache[normalized];
    if (cachedFuture != null) {
      return cachedFuture;
    }
    final future = _fetchAssetUrl(normalized);
    _assetUrlFutureCache[normalized] = future;
    final resolved = await future;
    if (resolved == null) {
      _assetUrlFutureCache.remove(normalized);
    }
    return resolved;
  }

  Future<String?> _resolveAssetUrlFromData(
    Map<String, dynamic> assetData,
  ) async {
    final path = (assetData['storagePath'] ?? '').toString();
    if (path.isNotEmpty) {
      final fresh = await _resolveAssetUrl(path);
      if (fresh != null && fresh.isNotEmpty) {
        return fresh;
      }
    }
    final stored = assetData['downloadUrl']?.toString().trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    return null;
  }

  Future<String?> _fetchAssetUrl(String normalizedPath) async {
    try {
      return await runWithRetry(
        () => ref.read(storageProvider).ref(normalizedPath).getDownloadURL(),
        maxAttempts: 2,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _resolveAssetBytes(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    final cachedFuture = _assetBytesFutureCache[normalized];
    if (cachedFuture != null) {
      return cachedFuture;
    }
    final future = _fetchAssetBytes(normalized);
    _assetBytesFutureCache[normalized] = future;
    final resolved = await future;
    if (resolved == null) {
      _assetBytesFutureCache.remove(normalized);
    }
    return resolved;
  }

  Future<Uint8List?> _resolveAssetBytesFromData(
    Map<String, dynamic> assetData,
  ) async {
    final path = (assetData['storagePath'] ?? '').toString();
    if (path.isEmpty) return null;
    return _resolveAssetBytes(path);
  }

  Future<Uint8List?> _fetchAssetBytes(String normalizedPath) async {
    try {
      return await runWithRetry(
        () => ref
            .read(storageProvider)
            .ref(normalizedPath)
            .getData(kMaxSongAssetBytes),
        maxAttempts: 2,
      );
    } catch (_) {
      return null;
    }
  }

  void _evictAssetUrlCache(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    _assetUrlFutureCache.remove(normalized);
    _assetBytesFutureCache.remove(normalized);
  }

  void _evictSongAssetCache(String songId) {
    final prefix = 'songs/$songId/';
    _assetUrlFutureCache.removeWhere((path, _) => path.startsWith(prefix));
    _assetBytesFutureCache.removeWhere((path, _) => path.startsWith(prefix));
  }

  Widget _buildAssetThumbnail({
    required Map<String, dynamic> assetData,
    required String contentType,
  }) {
    final isImage = contentType.startsWith('image/');
    if (!isImage) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          contentType.contains('pdf')
              ? Icons.picture_as_pdf
              : Icons.insert_drive_file,
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _resolveAssetBytesFromData(assetData),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }
        return FutureBuilder<String?>(
          future: _resolveAssetUrlFromData(assetData),
          builder: (context, urlSnapshot) {
            final url = urlSnapshot.data;
            if (url == null || url.isEmpty) {
              return Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.broken_image_outlined),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                errorBuilder: (_, _, _) => Container(
                  width: 72,
                  height: 72,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _previewAsset(
    BuildContext context, {
    String? knownUrl,
    required String path,
    required String fileName,
    required String contentType,
  }) async {
    if (path.trim().isEmpty) return;
    final isImage = contentType.startsWith('image/');
    BrowserPopupHandle? popupWindow;
    if (!isImage) {
      popupWindow = openBlankPopupWindow();
    }
    try {
      final url = (knownUrl != null && knownUrl.trim().isNotEmpty)
          ? knownUrl.trim()
          : await _resolveAssetUrl(path);
      if (url == null || url.isEmpty) {
        if (!context.mounted) return;
        popupWindow?.close();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('악보 링크를 불러오지 못했습니다.')));
        return;
      }
      if (!context.mounted) return;

      if (isImage) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(fileName),
            content: SizedBox(
              width: 920,
              child: FutureBuilder<Uint8List?>(
                future: _resolveAssetBytes(path),
                builder: (context, bytesSnapshot) {
                  final image = bytesSnapshot.data != null
                      ? Image.memory(
                          bytesSnapshot.data!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.contain,
                          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                          errorBuilder: (_, _, _) => const Center(
                            child: Text('이미지 미리보기를 불러오지 못했습니다.'),
                          ),
                        );
                  return InteractiveViewer(
                    maxScale: 6,
                    minScale: 0.5,
                    child: image,
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
        return;
      }

      if (popupWindow != null) {
        popupWindow.navigate(url);
      } else {
        final opened = openUrlInNewTab(url);
        if (!opened) {
          await copyTextWithFallback(
            context,
            text: url,
            successMessage: '팝업이 차단되어 링크를 복사했습니다.',
            failureTitle: '팝업이 차단되어 아래 링크를 복사해 주세요',
          );
        }
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('새 탭에서 악보를 열었습니다.')));
    } catch (error) {
      if (!context.mounted) return;
      popupWindow?.close();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainStorageError(error, action: '미리보기 열기'))),
      );
    }
  }

  Future<void> _migrateTeam(BuildContext context, String teamId) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) return;
    if (_migrating) return;
    setState(() {
      _migrating = true;
      _status = '마이그레이션 시작...';
    });

    final firestore = ref.read(firestoreProvider);
    final storage = ref.read(storageProvider);

    try {
      final teamSongs = await firestore
          .collection('teams')
          .doc(teamId)
          .collection('songs')
          .get();

      var migratedCount = 0;

      for (final songDoc in teamSongs.docs) {
        final songData = songDoc.data();
        final title = (songData['title'] ?? '').toString();
        if (title.isEmpty) continue;

        setState(() {
          _status = '곡 처리 중: $title';
        });

        final existing = await firestore
            .collection('songs')
            .where('title', isEqualTo: title)
            .limit(1)
            .get();

        String globalSongId;
        if (existing.docs.isNotEmpty) {
          globalSongId = existing.docs.first.id;
        } else {
          final newDoc = await firestore.collection('songs').add({
            'title': title,
            'aliases': songData['aliases'] ?? [],
            'tags': songData['tags'] ?? [],
            'searchTokens': songData['searchTokens'] ?? [],
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': songData['createdBy'] ?? 'migration',
          });
          globalSongId = newDoc.id;
        }

        await firestore
            .collection('teams')
            .doc(teamId)
            .collection('songRefs')
            .doc(globalSongId)
            .set({
              'songId': globalSongId,
              'title': title,
              'migratedFromTeamSongId': songDoc.id,
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        final teamAssets = await firestore
            .collection('teams')
            .doc(teamId)
            .collection('songs')
            .doc(songDoc.id)
            .collection('assets')
            .get();

        for (final assetDoc in teamAssets.docs) {
          final asset = assetDoc.data();
          final fileName = (asset['fileName'] ?? assetDoc.id).toString();
          final srcPath = (asset['storagePath'] ?? '').toString();
          if (srcPath.isEmpty) continue;

          final destPath = 'songs/$globalSongId/$fileName';

          try {
            final url = await storage.ref(srcPath).getDownloadURL();
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200) {
              await storage
                  .ref(destPath)
                  .putData(
                    Uint8List.fromList(response.bodyBytes),
                    SettableMetadata(
                      contentType: asset['contentType']?.toString(),
                    ),
                  );
              await firestore
                  .collection('songs')
                  .doc(globalSongId)
                  .collection('assets')
                  .doc(assetDoc.id)
                  .set({
                    ...asset,
                    'storagePath': destPath,
                    'migratedFromTeamId': teamId,
                    'migratedFromSongId': songDoc.id,
                  }, SetOptions(merge: true));
            }
          } catch (_) {
            // Skip failed asset
          }
        }

        migratedCount += 1;
      }

      if (!context.mounted) return;
      setState(() {
        _status = '완료: $migratedCount곡 마이그레이션';
      });
    } catch (error) {
      if (!context.mounted) return;
      setState(() {
        _status = '실패: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _migrating = false);
      }
    }
  }

  Future<void> _deleteGlobalSong(
    BuildContext context,
    String songId,
    String title,
  ) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) return;
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전역 곡 삭제'),
        content: Text('정말 "$title" 곡을 삭제할까요? 악보 파일도 함께 삭제됩니다.'),
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
    final storage = ref.read(storageProvider);

    try {
      final assets = await firestore
          .collection('songs')
          .doc(songId)
          .collection('assets')
          .get();

      for (final assetDoc in assets.docs) {
        final asset = assetDoc.data();
        final path = (asset['storagePath'] ?? '').toString();
        if (path.isNotEmpty) {
          try {
            await storage.ref(path).delete();
          } catch (_) {
            // ignore delete errors
          }
        }
        await assetDoc.reference.delete();
      }

      await firestore.collection('songs').doc(songId).delete();
      _evictSongAssetCache(songId);

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제 완료')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $error')));
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _createGlobalSong(BuildContext context) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) return;
    if (!context.mounted) return;
    final titleController = TextEditingController();
    final keyController = TextEditingController();
    final aliasController = TextEditingController();
    final tagController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('전역 곡 추가'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '곡 제목',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyController,
                    decoration: const InputDecoration(
                      labelText: '기본 키 (선택)',
                      hintText: '예: D, Eb, F#',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: '별칭 (쉼표 구분)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tagController,
                    decoration: const InputDecoration(
                      labelText: '태그 (쉼표 구분)',
                      border: OutlineInputBorder(),
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
              child: const Text('추가'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final title = titleController.text.trim();
      if (title.isEmpty) return;

      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) return;
      final firestore = ref.read(firestoreProvider);
      final aliases = aliasController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final tags = tagController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final defaultKeyRaw = keyController.text.trim();
      final defaultKey = defaultKeyRaw.isEmpty
          ? null
          : normalizeKeyText(defaultKeyRaw);

      await firestore.collection('songs').add({
        'title': title,
        'aliases': aliases,
        'tags': tags,
        if (defaultKey != null) 'defaultKey': defaultKey,
        'searchTokens': buildSearchTokens(title, aliases),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('전역 곡 추가 완료')));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('전역 곡 추가 실패: $error')));
    } finally {
      titleController.dispose();
      keyController.dispose();
      aliasController.dispose();
      tagController.dispose();
    }
  }

  Future<void> _editGlobalSong(
    BuildContext context,
    String songId,
    Map<String, dynamic> data,
  ) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) return;
    if (!context.mounted) return;
    final titleController = TextEditingController(
      text: data['title']?.toString() ?? '',
    );
    final keyController = TextEditingController(
      text: data['defaultKey']?.toString() ?? '',
    );
    final aliasController = TextEditingController(
      text: ((data['aliases'] as List?) ?? const []).join(', '),
    );
    final tagController = TextEditingController(
      text: ((data['tags'] as List?) ?? const []).join(', '),
    );
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('전역 곡 수정'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '곡 제목',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyController,
                    decoration: const InputDecoration(
                      labelText: '기본 키 (선택)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: '별칭 (쉼표 구분)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tagController,
                    decoration: const InputDecoration(
                      labelText: '태그 (쉼표 구분)',
                      border: OutlineInputBorder(),
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
      if (confirmed != true) return;
      final title = titleController.text.trim();
      if (title.isEmpty) return;
      final aliases = aliasController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final tags = tagController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final defaultKeyRaw = keyController.text.trim();
      final defaultKey = defaultKeyRaw.isEmpty
          ? null
          : normalizeKeyText(defaultKeyRaw);

      await ref.read(firestoreProvider).collection('songs').doc(songId).update({
        'title': title,
        'aliases': aliases,
        'tags': tags,
        'searchTokens': buildSearchTokens(title, aliases),
        'defaultKey': defaultKey ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('곡 정보 수정 완료')));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('곡 정보 수정 실패: $error')));
    } finally {
      titleController.dispose();
      keyController.dispose();
      aliasController.dispose();
      tagController.dispose();
    }
  }

  Future<void> _uploadAssetToSong(BuildContext context, String songId) async {
    final isAdmin = await _ensureGlobalAdmin(context);
    if (!isAdmin) return;
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
        SnackBar(content: Text(explainStorageError(error, action: '악보 업로드'))),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingSongId = null);
      }
    }
  }

  Future<void> _showSongAssetsDialog(
    BuildContext context,
    String songId,
    String title,
  ) async {
    final firestore = ref.read(firestoreProvider);
    final snapshot = await firestore
        .collection('songs')
        .doc(songId)
        .collection('assets')
        .orderBy('createdAt', descending: true)
        .get();
    final assets = snapshot.docs.toList();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$title 악보 목록'),
          content: SizedBox(
            width: 760,
            child: assets.isEmpty
                ? const Text('업로드된 악보가 없습니다.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: assets.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final data = assets[index].data();
                      final fileName =
                          data['fileName']?.toString() ??
                          'asset-${assets[index].id}';
                      final path = data['storagePath']?.toString() ?? '';
                      final knownUrl = data['downloadUrl']?.toString();
                      final contentType = data['contentType']?.toString() ?? '';
                      final keyText = assetKeyText(data) ?? '-';

                      Future<void> reloadAssets() async {
                        final refreshed = await firestore
                            .collection('songs')
                            .doc(songId)
                            .collection('assets')
                            .orderBy('createdAt', descending: true)
                            .get();
                        setDialogState(() {
                          assets
                            ..clear()
                            ..addAll(refreshed.docs);
                        });
                      }

                      Future<void> editAssetKey() async {
                        final controller = TextEditingController(
                          text: assetKeyText(data) ?? '',
                        );
                        try {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('키 버전 수정'),
                              content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  labelText: '키 (예: D, Eb, F#)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('취소'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('저장'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          final raw = controller.text.trim();
                          await assets[index].reference.update({
                            'keyText': raw.isEmpty
                                ? FieldValue.delete()
                                : normalizeKeyText(raw),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                          await reloadAssets();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('키 버전 수정 완료')),
                          );
                        } finally {
                          controller.dispose();
                        }
                      }

                      Future<void> deleteAsset() async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('악보 삭제'),
                            content: Text('"$fileName" 파일을 삭제할까요?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('취소'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('삭제'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        try {
                          if (path.isNotEmpty) {
                            await ref.read(storageProvider).ref(path).delete();
                          }
                          _evictAssetUrlCache(path);
                          await assets[index].reference.delete();
                          setDialogState(() {
                            assets.removeAt(index);
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('악보 삭제 완료')),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                explainStorageError(error, action: '악보 삭제'),
                              ),
                            ),
                          );
                        }
                      }

                      return ListTile(
                        leading: _buildAssetThumbnail(
                          assetData: data,
                          contentType: contentType,
                        ),
                        title: Text(fileName),
                        subtitle: Text(
                          [
                            'Key $keyText',
                            if (contentType.isNotEmpty) contentType,
                            path,
                          ].where((v) => v.isNotEmpty).join(' · '),
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: editAssetKey,
                              child: const Text('키 수정'),
                            ),
                            TextButton(
                              onPressed: path.isEmpty
                                  ? null
                                  : () => _previewAsset(
                                      context,
                                      knownUrl: knownUrl,
                                      path: path,
                                      fileName: fileName,
                                      contentType: contentType,
                                    ),
                              child: const Text('미리보기'),
                            ),
                            TextButton(
                              onPressed: deleteAsset,
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Text('전역 관리자 도구', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('팀별 기존 곡 데이터를 전역 songs로 마이그레이션합니다.'),
          const SizedBox(height: 12),
          if (_status.isNotEmpty)
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _loadTeams(firestore),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingState(message: '팀 목록을 불러오는 중...');
              }
              if (snapshot.hasError) {
                return AppStateCard(
                  icon: Icons.groups_2_outlined,
                  isError: true,
                  title: '팀 목록 로드 실패',
                  message: '${snapshot.error}',
                  actionLabel: '다시 시도',
                  onAction: () => setState(() {}),
                );
              }
              final teams = snapshot.data ?? [];
              if (teams.isEmpty) {
                return const AppStateCard(
                  icon: Icons.groups_2_outlined,
                  title: '팀이 없습니다',
                  message: '생성된 팀이 없거나 조회 가능한 팀이 없습니다.',
                );
              }
              return Column(
                children: teams.map((team) {
                  final data = team.data();
                  return ListTile(
                    onTap: () => unawaited(_openTeamHome(context, team.id)),
                    title: Text(data['name']?.toString() ?? team.id),
                    subtitle: Text('팀 ID: ${team.id}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(_openTeamHome(context, team.id)),
                          child: const Text('팀 홈 열기'),
                        ),
                        ElevatedButton(
                          onPressed: _migrating
                              ? null
                              : () => _migrateTeam(context, team.id),
                          child: const Text('이 팀 마이그레이션'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '전역 곡 관리 (관리자)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: () => _createGlobalSong(context),
                icon: const Icon(Icons.add),
                label: const Text('전역 곡 추가'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _loadGlobalSongs(firestore),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingState(message: '전역 곡 목록을 불러오는 중...');
              }
              if (snapshot.hasError) {
                return AppStateCard(
                  icon: Icons.library_music_outlined,
                  isError: true,
                  title: '전역 곡 목록 로드 실패',
                  message: '${snapshot.error}',
                  actionLabel: '다시 시도',
                  onAction: () => setState(() {}),
                );
              }
              final songs = snapshot.data ?? [];
              if (songs.isEmpty) {
                return const AppStateCard(
                  icon: Icons.library_music_outlined,
                  title: '전역 곡이 없습니다',
                  message: '전역 곡을 추가하면 운영자 도구에서 관리할 수 있습니다.',
                );
              }
              return Column(
                children: songs.map((doc) {
                  final data = doc.data();
                  final title = data['title']?.toString() ?? '곡';
                  return Card(
                    child: ListTile(
                      title: Text(title),
                      subtitle: Text(
                        '기본키: ${(data['defaultKey'] ?? '-').toString()}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          switch (value) {
                            case 'edit':
                              await _editGlobalSong(context, doc.id, data);
                              break;
                            case 'upload':
                              await _uploadAssetToSong(context, doc.id);
                              break;
                            case 'assets':
                              await _showSongAssetsDialog(
                                context,
                                doc.id,
                                title,
                              );
                              break;
                            case 'delete':
                              await _deleteGlobalSong(context, doc.id, title);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('제목/메타 수정'),
                          ),
                          PopupMenuItem(
                            value: 'upload',
                            enabled: _uploadingSongId != doc.id,
                            child: Text(
                              _uploadingSongId == doc.id
                                  ? '악보 업로드 중...'
                                  : '악보 추가 업로드',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'assets',
                            child: Text('악보 확인'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('삭제'),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
