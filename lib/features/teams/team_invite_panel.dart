import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../utils/browser_helpers.dart';
import '../../utils/clipboard_helper.dart';

class TeamInvitePanel extends ConsumerStatefulWidget {
  final String teamId;
  final String teamName;
  final bool isAdmin;

  const TeamInvitePanel({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.isAdmin,
  });

  @override
  ConsumerState<TeamInvitePanel> createState() => _TeamInvitePanelState();
}

class _TeamInvitePanelState extends ConsumerState<TeamInvitePanel> {
  final TextEditingController _emailController = TextEditingController();
  bool _saving = false;
  bool _copyingLink = false;
  bool _sharingLink = false;
  String? _cachedInviteUrl;
  Future<String>? _inviteUrlFuture;
  String? _inviteUrlError;
  bool _preparingInviteUrl = false;
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    _primeInviteUrl();
  }

  @override
  void didUpdateWidget(covariant TeamInvitePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId ||
        oldWidget.teamName != widget.teamName ||
        oldWidget.isAdmin != widget.isAdmin) {
      _cachedInviteUrl = null;
      _inviteUrlFuture = null;
      _inviteUrlError = null;
      _primeInviteUrl();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendInvite(BuildContext context) async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;
    if (!_emailPattern.hasMatch(email)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('유효한 이메일 형식을 입력해 주세요.')));
      return;
    }

    setState(() => _saving = true);
    final firestore = ref.read(firestoreProvider);
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _saving = false);
      }
      return;
    }

    try {
      final inviteRef = firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('invites')
          .doc(email);
      final existing = await inviteRef.get();
      if (existing.exists) {
        await inviteRef.update({
          'email': email,
          'role': 'member',
          'teamId': widget.teamId,
          'teamName': widget.teamName,
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await inviteRef.set({
          'email': email,
          'role': 'member',
          'teamId': widget.teamId,
          'teamName': widget.teamName,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        });
      }

      _emailController.clear();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('초대가 전송되었습니다.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('초대 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _primeInviteUrl() {
    if (!widget.isAdmin) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cachedInviteUrl != null || _inviteUrlFuture != null) {
        return;
      }
      () async {
        try {
          await _resolveInviteUrl();
        } catch (_) {}
      }();
    });
  }

  String _buildInviteUrl(String linkId) {
    final base = Uri.base;
    final query = Uri(
      queryParameters: {'inviteTeam': widget.teamId, 'inviteCode': linkId},
    ).query;
    final port = base.hasPort ? base.port : null;
    final usesHashRouting = base.fragment.startsWith('/');

    if (usesHashRouting) {
      var appPath = base.path.isEmpty ? '/' : base.path;
      if (appPath.endsWith('.html')) {
        appPath = '/';
      }
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: port,
        path: appPath,
        fragment: '/teams?$query',
      ).toString();
    }

    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: port,
      path: '/teams',
      queryParameters: {'inviteTeam': widget.teamId, 'inviteCode': linkId},
    ).toString();
  }

  Future<String> _createInviteUrl() async {
    final firestore = ref.read(firestoreProvider);
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final linksRef = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('inviteLinks');
    final activeLink = await linksRef
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    final linkId = activeLink.docs.isNotEmpty
        ? activeLink.docs.first.id
        : linksRef.doc().id;
    if (activeLink.docs.isEmpty) {
      await linksRef.doc(linkId).set({
        'teamId': widget.teamId,
        'teamName': widget.teamName,
        'role': 'member',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
      });
    }

    return _buildInviteUrl(linkId);
  }

  Future<String> _resolveInviteUrl({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedInviteUrl != null &&
        _cachedInviteUrl!.isNotEmpty) {
      return _cachedInviteUrl!;
    }
    if (!forceRefresh && _inviteUrlFuture != null) {
      return _inviteUrlFuture!;
    }

    if (mounted) {
      setState(() => _preparingInviteUrl = true);
    } else {
      _preparingInviteUrl = true;
    }

    final task = _createInviteUrl()
        .then((url) {
          if (mounted) {
            setState(() {
              _cachedInviteUrl = url;
              _inviteUrlError = null;
            });
          } else {
            _cachedInviteUrl = url;
            _inviteUrlError = null;
          }
          return url;
        })
        .catchError((error) {
          if (mounted) {
            setState(() {
              _inviteUrlError = error.toString();
            });
          } else {
            _inviteUrlError = error.toString();
          }
          throw error;
        })
        .whenComplete(() {
          _inviteUrlFuture = null;
          if (mounted) {
            setState(() => _preparingInviteUrl = false);
          } else {
            _preparingInviteUrl = false;
          }
        });

    _inviteUrlFuture = task;
    return task;
  }

  Future<void> _copyInviteLink(BuildContext context) async {
    if (_copyingLink || _sharingLink || _preparingInviteUrl) return;
    setState(() => _copyingLink = true);
    try {
      final inviteUrl = await _resolveInviteUrl();
      final copied = await _copyInviteUrl(inviteUrl);
      if (copied) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('카카오 초대 링크 복사됨')));
        return;
      }
      if (!context.mounted) return;
      await copyTextWithFallback(
        context,
        text: inviteUrl,
        successMessage: '카카오 초대 링크 복사됨',
        failureTitle: '초대 링크를 아래에서 복사하세요',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('링크 생성 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _copyingLink = false);
      }
    }
  }

  Future<void> _shareInviteLink(BuildContext context) async {
    if (_sharingLink || _copyingLink || _preparingInviteUrl) return;
    setState(() => _sharingLink = true);
    try {
      final inviteUrl = await _resolveInviteUrl();
      final shared = await _shareInviteUrl(inviteUrl);
      if (shared) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('공유 시트가 열렸습니다.')));
        return;
      }
      final copied = await _copyInviteUrl(inviteUrl);
      if (copied) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('카카오 초대 링크 복사됨')));
        return;
      }
      if (!context.mounted) return;
      await copyTextWithFallback(
        context,
        text: inviteUrl,
        successMessage: '카카오 초대 링크 복사됨',
        failureTitle: '초대 링크를 아래에서 복사하세요',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('공유 링크 생성 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _sharingLink = false);
      }
    }
  }

  Future<bool> _copyInviteUrl(String inviteUrl) async {
    return copyTextInBrowser(inviteUrl);
  }

  Future<bool> _shareInviteUrl(String inviteUrl) async {
    return shareTextLinkInBrowser(
      title: 'WorshipFlow 팀 초대',
      text: '${widget.teamName} 팀에 참여해 주세요.',
      url: inviteUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _emailController,
                decoration: appInputDecoration(
                  context,
                  label: '초대할 이메일',
                  hint: 'example@church.org',
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _saving ? null : () => _sendInvite(context),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('초대'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '카카오 참여 링크를 복사하거나 바로 공유할 수 있습니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: (_copyingLink || _sharingLink || _preparingInviteUrl)
                  ? null
                  : () => _copyInviteLink(context),
              icon: const Icon(Icons.content_copy),
              label: _copyingLink
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _preparingInviteUrl
                  ? const Text('링크 준비 중...')
                  : const Text('카카오 링크 복사'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: (_sharingLink || _copyingLink || _preparingInviteUrl)
                  ? null
                  : () => _shareInviteLink(context),
              icon: const Icon(Icons.share),
              label: _sharingLink
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _preparingInviteUrl
                  ? const Text('링크 준비 중...')
                  : const Text('카카오 공유'),
            ),
          ],
        ),
        if (_cachedInviteUrl != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            _cachedInviteUrl!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_inviteUrlError != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '링크 준비 실패: $_inviteUrlError',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: (_copyingLink || _sharingLink)
                    ? null
                    : () async {
                        try {
                          await _resolveInviteUrl(forceRefresh: true);
                        } catch (_) {}
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('재시도'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
