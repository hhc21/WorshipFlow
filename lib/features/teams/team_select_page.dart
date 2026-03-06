import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../core/roles.dart';
import '../../services/firebase_providers.dart';
import '../../utils/firestore_id.dart';
import '../../utils/team_name.dart';
import '../songs/global_song_panel.dart';

class TeamSelectPage extends ConsumerStatefulWidget {
  final String? inviteTeamId;
  final String? inviteCode;

  const TeamSelectPage({super.key, this.inviteTeamId, this.inviteCode});

  @override
  ConsumerState<TeamSelectPage> createState() => _TeamSelectPageState();
}

class _TeamSelectPageState extends ConsumerState<TeamSelectPage> {
  final TextEditingController _teamNameController = TextEditingController();
  bool _creating = false;
  int _tabIndex = 0;
  String? _lastAuthKey;
  String? _cachedNickname;
  Future<List<_TeamMembership>>? _teamsFuture;
  String? _teamsFutureUid;
  Future<List<_InviteInfo>>? _invitesFuture;
  String? _invitesFutureEmail;

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  void _invalidateMembershipCaches() {
    _teamsFuture = null;
    _teamsFutureUid = null;
    _invitesFuture = null;
    _invitesFutureEmail = null;
  }

  Future<List<_TeamMembership>> _fetchTeamsCached(String uid) {
    if (_teamsFuture != null && _teamsFutureUid == uid) {
      return _teamsFuture!;
    }
    _teamsFutureUid = uid;
    _teamsFuture = _fetchTeams(uid);
    return _teamsFuture!;
  }

  Future<List<_InviteInfo>> _fetchInvitesCached(String email) {
    final normalized = email.toLowerCase();
    if (_invitesFuture != null && _invitesFutureEmail == normalized) {
      return _invitesFuture!;
    }
    _invitesFutureEmail = normalized;
    _invitesFuture = _fetchInvites(normalized);
    return _invitesFuture!;
  }

  void _refreshMembershipData() {
    setState(_invalidateMembershipCaches);
  }

  String _fallbackUserName(User user) {
    final displayName = (user.displayName ?? '').trim();
    if (displayName.isNotEmpty) return displayName;
    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) return email;
    return '사용자';
  }

  Future<String> _resolveOwnNickname(
    FirebaseFirestore firestore,
    User user,
  ) async {
    final cached = (_cachedNickname ?? '').trim();
    if (cached.isNotEmpty) return cached;
    try {
      final profile = await firestore.collection('users').doc(user.uid).get();
      final nickname = (profile.data()?['nickname'] ?? '').toString().trim();
      if (nickname.isNotEmpty) return nickname;
    } on FirebaseException {
      // Use fallback name when profile read is temporarily unavailable.
    }
    return _fallbackUserName(user);
  }

  Future<void> _syncOwnProfile(User user) async {
    final firestore = ref.read(firestoreProvider);
    final nickname = await _resolveOwnNickname(firestore, user);
    try {
      await firestore.collection('users').doc(user.uid).set({
        'nickname': nickname,
        'displayName': user.displayName,
        'email': user.email?.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException {
      // Profile sync is best-effort and should not block screen rendering.
    }
    if (!mounted) return;
    setState(() {
      _cachedNickname = nickname;
    });
  }

  Future<void> _syncOwnNicknameToMemberDocs({
    required FirebaseFirestore firestore,
    required User user,
    required String nickname,
  }) async {
    final seen = <String>{};
    final docs = <DocumentSnapshot<Map<String, dynamic>>>[];

    Future<void> collect(
      Future<QuerySnapshot<Map<String, dynamic>>> Function() loader,
    ) async {
      try {
        final snapshot = await loader();
        for (final doc in snapshot.docs) {
          if (seen.add(doc.reference.path)) {
            docs.add(doc);
          }
        }
      } on FirebaseException {
        // Ignore individual query failures to keep nickname save resilient.
      }
    }

    await collect(
      () => firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: user.uid)
          .get(),
    );
    await collect(
      () => firestore
          .collectionGroup('members')
          .where('uid', isEqualTo: user.uid)
          .get(),
    );

    for (final doc in docs) {
      try {
        await doc.reference.set({
          'nickname': nickname,
          'displayName': user.displayName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } on FirebaseException {
        // Best-effort update; some legacy docs can be read-only for this user.
      }
    }
  }

  Future<void> _openNicknameDialog(BuildContext context, User user) async {
    final firestore = ref.read(firestoreProvider);
    final initialNickname = await _resolveOwnNickname(firestore, user);
    if (!context.mounted) return;

    final controller = TextEditingController(text: initialNickname);
    var saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('닉네임 설정'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              decoration: appInputDecoration(
                context,
                label: '표시 이름',
                helper: '모든 화면에서 UID 대신 이 이름이 표시됩니다.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final nickname = controller.text.trim();
                        if (nickname.isEmpty) return;
                        if (nickname.length > 24) return;
                        setDialogState(() => saving = true);
                        try {
                          await firestore
                              .collection('users')
                              .doc(user.uid)
                              .set({
                                'nickname': nickname,
                                'displayName': user.displayName,
                                'email': user.email?.toLowerCase(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                          await _syncOwnNicknameToMemberDocs(
                            firestore: firestore,
                            user: user,
                            nickname: nickname,
                          );
                          if (!mounted) return;
                          setState(() {
                            _cachedNickname = nickname;
                          });
                          _refreshMembershipData();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('닉네임을 저장했습니다.')),
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('닉네임 저장 실패: $error')),
                          );
                          setDialogState(() => saving = false);
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteUserTeamMembershipMirror({
    required FirebaseFirestore firestore,
    required String uid,
    required String teamId,
  }) async {
    try {
      await _userTeamMembershipRef(
        firestore: firestore,
        uid: uid,
        teamId: teamId,
      ).delete();
    } on FirebaseException {
      // Ignore cleanup failure; this is best-effort hygiene.
    }
  }

  Future<void> _reserveTeamNameKey({
    required FirebaseFirestore firestore,
    required String teamId,
    required String teamName,
    required String teamNameKey,
    required String userId,
  }) async {
    final indexRef = firestore.collection('teamNameIndex').doc(teamNameKey);
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(indexRef);
      if (existing.exists) {
        throw const _TeamNameAlreadyExistsException();
      }
      transaction.set(indexRef, {
        'teamId': teamId,
        'teamName': teamName,
        'normalizedName': teamNameKey,
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<_JoinRequestOutcome> _requestJoinForExistingTeam({
    required FirebaseFirestore firestore,
    required User user,
    required String teamId,
    required String fallbackTeamName,
    required String teamNameKey,
  }) async {
    final email = user.email?.toLowerCase().trim() ?? '';
    if (email.isEmpty) {
      return _JoinRequestOutcome.requiresEmail;
    }
    if (!isValidFirestoreDocId(teamId)) {
      return _JoinRequestOutcome.unavailable;
    }

    final teamRef = firestore.collection('teams').doc(teamId);
    final teamSnapshot = await teamRef.get().timeout(
      const Duration(seconds: 10),
    );
    if (!teamSnapshot.exists) {
      return _JoinRequestOutcome.unavailable;
    }

    final teamData = teamSnapshot.data() ?? const <String, dynamic>{};
    final teamName = (teamData['name'] ?? fallbackTeamName).toString().trim();
    final memberUidsRaw = teamData['memberUids'];
    final memberUids = memberUidsRaw is List
        ? memberUidsRaw.map((value) => value.toString()).toList()
        : const <String>[];
    if (memberUids.contains(user.uid)) {
      return _JoinRequestOutcome.alreadyMember;
    }

    final memberDoc = await teamRef
        .collection('members')
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 10));
    if (memberDoc.exists) {
      return _JoinRequestOutcome.alreadyMember;
    }

    final requestRef = teamRef.collection('joinRequests').doc(user.uid);
    final existingRequest = await requestRef.get().timeout(
      const Duration(seconds: 10),
    );
    if (existingRequest.exists) {
      final status = (existingRequest.data()?['status'] ?? '')
          .toString()
          .trim();
      if (status == 'pending' || status == 'invited') {
        return _JoinRequestOutcome.alreadyRequested;
      }
    }

    final nickname = await _resolveOwnNickname(firestore, user).timeout(
      const Duration(seconds: 8),
      onTimeout: () => _fallbackUserName(user),
    );
    await requestRef.set({
      'requesterUid': user.uid,
      'requesterEmail': email,
      'requesterDisplayName': user.displayName,
      'requesterNickname': nickname,
      'teamId': teamId,
      'teamName': teamName.isEmpty ? fallbackTeamName : teamName,
      'teamNameKey': teamNameKey,
      'source': 'duplicate_team_name',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return _JoinRequestOutcome.submitted;
  }

  Future<void> _createTeam(BuildContext context) async {
    if (_creating) return;
    final rawName = _teamNameController.text;
    final name = normalizeTeamName(rawName);
    if (name.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('팀 이름을 입력해 주세요.')));
      return;
    }
    if (name.length > 40) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('팀 이름은 40자 이내로 입력해 주세요.')));
      return;
    }

    final auth = ref.read(firebaseAuthProvider);
    final firestore = ref.read(firestoreProvider);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _creating = true);
    var nameReserved = false;
    var teamCreated = false;
    final teamNameKey = buildTeamNameKey(name);
    final teamRef = firestore.collection('teams').doc();
    final nameIndexRef = firestore.collection('teamNameIndex').doc(teamNameKey);
    try {
      final nickname = await _resolveOwnNickname(firestore, user).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          return _fallbackUserName(user);
        },
      );

      if (teamNameKey.isEmpty) {
        throw const _InvalidTeamNameException();
      }

      DocumentSnapshot<Map<String, dynamic>> existingName;
      try {
        existingName = await nameIndexRef.get().timeout(
          const Duration(seconds: 10),
        );
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'failed-precondition' ||
            error.code == 'unavailable') {
          throw const _TeamNameCheckUnavailableException();
        }
        rethrow;
      }
      if (existingName.exists) {
        final existingData = existingName.data() ?? const <String, dynamic>{};
        final indexedTeamId = (existingData['teamId'] ?? '').toString().trim();
        var staleIndex =
            indexedTeamId.isEmpty || !isValidFirestoreDocId(indexedTeamId);
        if (!staleIndex) {
          try {
            final indexedTeam = await firestore
                .collection('teams')
                .doc(indexedTeamId)
                .get();
            staleIndex = !indexedTeam.exists;
          } on FirebaseException catch (error) {
            if (error.code == 'permission-denied') {
              staleIndex = false;
            } else {
              rethrow;
            }
          }
        }

        if (staleIndex) {
          try {
            await nameIndexRef.delete();
            existingName = await nameIndexRef.get();
          } on FirebaseException {
            throw const _TeamNameAlreadyExistsException();
          }
        }
      }
      if (existingName.exists) {
        final existingData = existingName.data() ?? const <String, dynamic>{};
        final indexedTeamId = (existingData['teamId'] ?? '').toString().trim();
        final outcome = await _requestJoinForExistingTeam(
          firestore: firestore,
          user: user,
          teamId: indexedTeamId,
          fallbackTeamName: name,
          teamNameKey: teamNameKey,
        );
        if (!context.mounted) return;
        switch (outcome) {
          case _JoinRequestOutcome.submitted:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '동일 이름 팀이 이미 있어 팀장에게 초대 요청을 보냈습니다. 받은 초대를 수락해 주세요.',
                ),
              ),
            );
            return;
          case _JoinRequestOutcome.alreadyRequested:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('이미 초대 요청을 보냈습니다. 팀장의 초대를 기다려 주세요.'),
              ),
            );
            return;
          case _JoinRequestOutcome.alreadyMember:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('이미 해당 팀에 참여 중입니다. 내 팀 목록에서 기존 팀을 선택해 주세요.'),
              ),
            );
            _refreshMembershipData();
            return;
          case _JoinRequestOutcome.requiresEmail:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('초대 요청을 보내려면 이메일 계정으로 로그인해 주세요.')),
            );
            return;
          case _JoinRequestOutcome.unavailable:
            throw const _TeamNameAlreadyExistsException();
        }
      }

      try {
        await _reserveTeamNameKey(
          firestore: firestore,
          teamId: teamRef.id,
          teamName: name,
          teamNameKey: teamNameKey,
          userId: user.uid,
        ).timeout(const Duration(seconds: 10));
        nameReserved = true;
      } on _TeamNameAlreadyExistsException {
        rethrow;
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'failed-precondition' ||
            error.code == 'unavailable') {
          throw const _TeamNameCheckUnavailableException();
        } else {
          rethrow;
        }
      }

      final memberRef = teamRef.collection('members').doc(user.uid);
      // NOTE:
      // Firestore rules for members create rely on reading parent team doc.
      // Write team first, then member/membership mirror to avoid rule-eval order issues.
      await teamRef
          .set({
            'name': name,
            'nameKey': teamNameKey,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': user.uid,
            'memberUids': [user.uid],
          })
          .timeout(const Duration(seconds: 10));
      teamCreated = true;
      await memberRef
          .set({
            'userId': user.uid,
            'uid': user.uid,
            'email': user.email?.toLowerCase(),
            'displayName': user.displayName,
            'nickname': nickname,
            'role': 'admin',
            'teamName': name,
            'capabilities': {'songEditor': true},
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
      await _userTeamMembershipRef(
            firestore: firestore,
            uid: user.uid,
            teamId: teamRef.id,
          )
          .set({
            'teamId': teamRef.id,
            'teamName': name,
            'role': 'admin',
            'joinedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      if (!context.mounted) return;
      _invalidateMembershipCaches();
      context.go('/teams/${teamRef.id}');
    } on _TeamNameAlreadyExistsException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 존재하는 팀 이름입니다. 팀장에게 초대를 요청해 주세요.')),
      );
    } on _TeamNameCheckUnavailableException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '팀명 중복 확인 권한을 불러오지 못했습니다. 잠시 후 다시 시도하거나 관리자에게 문의해 주세요.',
          ),
        ),
      );
    } on _InvalidTeamNameException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('유효한 팀 이름을 입력해 주세요.')));
    } on TimeoutException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('팀 생성 요청이 지연되고 있습니다. 네트워크 상태를 확인 후 다시 시도해 주세요.'),
        ),
      );
    } catch (error) {
      if (!teamCreated && nameReserved) {
        try {
          await nameIndexRef.delete();
        } on FirebaseException {
          // Best-effort rollback only.
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('팀 생성 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<List<_TeamMembership>> _fetchTeams(String uid) async {
    final firestore = ref.read(firestoreProvider);
    final auth = ref.read(firebaseAuthProvider);
    final currentUser = auth.currentUser;
    final email = auth.currentUser?.email?.toLowerCase();
    final byTeamId = <String, _TeamMembership>{};
    final teamDocById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    var memberQueryPermissionDenied = false;
    var teamQueryPermissionDenied = false;
    final memberDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seenMemberPaths = <String>{};
    try {
      try {
        final membershipSnapshot = await firestore
            .collection('users')
            .doc(uid)
            .collection('teamMemberships')
            .get()
            .timeout(const Duration(seconds: 12));
        for (final doc in membershipSnapshot.docs) {
          final data = doc.data();
          final teamId = (data['teamId'] ?? doc.id).toString().trim();
          if (!isValidFirestoreDocId(teamId)) continue;
          byTeamId[teamId] = _TeamMembership(
            teamId: teamId,
            teamName: (data['teamName'] ?? '팀').toString().trim().isEmpty
                ? '팀'
                : (data['teamName'] ?? '팀').toString().trim(),
            role: teamRoleKey((data['role'] ?? 'member').toString()),
            lastProjectId: (data['lastProjectId'] ?? '').toString().trim(),
          );
        }
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' &&
            error.code != 'failed-precondition') {
          rethrow;
        }
      } on TimeoutException {
        // Continue with fallback queries.
      }

      Future<void> collectTeams({
        required Future<QuerySnapshot<Map<String, dynamic>>> Function() loader,
      }) async {
        try {
          final snapshot = await loader().timeout(const Duration(seconds: 12));
          for (final doc in snapshot.docs) {
            teamDocById[doc.id] = doc;
            final name = (doc.data()['name'] ?? '').toString().trim();
            final fallbackRole =
                (doc.data()['createdBy'] ?? '').toString() == uid
                ? 'admin'
                : 'member';
            final rawLastProjectId = (doc.data()['lastProjectId'] ?? '')
                .toString()
                .trim();
            final existing = byTeamId[doc.id];
            byTeamId[doc.id] = _TeamMembership(
              teamId: doc.id,
              teamName: name.isEmpty ? (existing?.teamName ?? '팀') : name,
              role: existing?.role ?? fallbackRole,
              lastProjectId: rawLastProjectId.isNotEmpty
                  ? rawLastProjectId
                  : existing?.lastProjectId,
            );
          }
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied') {
            teamQueryPermissionDenied = true;
            return;
          }
          if (error.code == 'failed-precondition') {
            return;
          }
          rethrow;
        } on TimeoutException {
          teamQueryPermissionDenied = true;
          return;
        }
      }

      Future<void> collectMembers({
        required Future<QuerySnapshot<Map<String, dynamic>>> Function() loader,
      }) async {
        try {
          final snapshot = await loader().timeout(const Duration(seconds: 12));
          for (final doc in snapshot.docs) {
            if (!seenMemberPaths.add(doc.reference.path)) continue;
            memberDocs.add(doc);
          }
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied') {
            memberQueryPermissionDenied = true;
            return;
          }
          if (error.code == 'failed-precondition' ||
              error.code == 'invalid-argument') {
            return;
          }
          rethrow;
        } on TimeoutException {
          memberQueryPermissionDenied = true;
          return;
        }
      }

      // Primary source: teams collection query by membership fields.
      await collectTeams(
        loader: () => firestore
            .collection('teams')
            .where('memberUids', arrayContains: uid)
            .get(),
      );
      await collectTeams(
        loader: () => firestore
            .collection('teams')
            .where('createdBy', isEqualTo: uid)
            .get(),
      );

      // Legacy fallback: membership docs (older data / migrated structures).
      await collectMembers(
        loader: () => firestore
            .collectionGroup('members')
            .where('userId', isEqualTo: uid)
            .get(),
      );
      await collectMembers(
        loader: () => firestore
            .collectionGroup('members')
            .where('uid', isEqualTo: uid)
            .get(),
      );
      if (email != null && email.isNotEmpty) {
        await collectMembers(
          loader: () => firestore
              .collectionGroup('members')
              .where('email', isEqualTo: email)
              .get(),
        );
      }

      for (final doc in memberDocs) {
        final data = doc.data();
        final teamId = doc.reference.parent.parent?.id ?? '';
        if (!isValidFirestoreDocId(teamId)) continue;

        final normalizedRole = teamRoleKey(
          (data['role'] ?? 'member').toString(),
        );
        final fallbackName = (data['teamName'] ?? '팀').toString().trim();
        final existing = byTeamId[teamId];
        byTeamId[teamId] = _TeamMembership(
          teamId: teamId,
          teamName: fallbackName.isEmpty
              ? (existing?.teamName ?? '팀')
              : fallbackName,
          role: existing?.role ?? normalizedRole,
          lastProjectId: existing?.lastProjectId,
        );
      }

      // Hydrate team names/roles and self-heal missing fields.
      for (final teamId in byTeamId.keys.toList()) {
        if (!isValidFirestoreDocId(teamId)) {
          byTeamId.remove(teamId);
          await _deleteUserTeamMembershipMirror(
            firestore: firestore,
            uid: uid,
            teamId: teamId,
          );
          continue;
        }
        final current = byTeamId[teamId];
        if (current == null) continue;
        try {
          final teamRef = firestore.collection('teams').doc(teamId);
          final memberRef = teamRef.collection('members').doc(uid);
          final cachedTeamDoc = teamDocById[teamId];
          final DocumentSnapshot<Map<String, dynamic>> teamDoc =
              cachedTeamDoc ??
              await teamRef.get().timeout(const Duration(seconds: 12));
          if (!teamDoc.exists) {
            byTeamId.remove(teamId);
            await _deleteUserTeamMembershipMirror(
              firestore: firestore,
              uid: uid,
              teamId: teamId,
            );
            continue;
          }

          final memberDoc = await memberRef.get().timeout(
            const Duration(seconds: 12),
          );
          final teamData = teamDoc.data() ?? const <String, dynamic>{};
          final createdBy = (teamData['createdBy'] ?? '').toString();
          final isCreator = createdBy == uid;
          final memberUidsRaw = teamData['memberUids'];
          final memberUids = memberUidsRaw is List
              ? memberUidsRaw.map((e) => e.toString()).toList()
              : const <String>[];
          final inMemberUids = memberUids.contains(uid);

          if (!memberDoc.exists && !isCreator && !inMemberUids) {
            byTeamId.remove(teamId);
            await _deleteUserTeamMembershipMirror(
              firestore: firestore,
              uid: uid,
              teamId: teamId,
            );
            continue;
          }

          var nextName = current.teamName;
          var nextRole = current.role;
          var nextLastProjectId = current.lastProjectId;
          final remoteName = (teamData['name'] ?? '').toString().trim();
          if (remoteName.isNotEmpty) {
            nextName = remoteName;
          }
          final remoteLastProjectId = (teamData['lastProjectId'] ?? '')
              .toString()
              .trim();
          if (remoteLastProjectId.isNotEmpty) {
            nextLastProjectId = remoteLastProjectId;
          }

          if (!inMemberUids) {
            await teamRef.set({
              'memberUids': FieldValue.arrayUnion([uid]),
            }, SetOptions(merge: true));
          }

          if (memberDoc.exists) {
            final memberData = memberDoc.data() ?? const <String, dynamic>{};
            final role = memberData['role']?.toString().trim();
            if (role != null && role.isNotEmpty) {
              nextRole = teamRoleKey(role);
            }

            final needsBackfillUserId = (memberData['userId'] ?? '')
                .toString()
                .trim()
                .isEmpty;
            final needsBackfillUid = (memberData['uid'] ?? '')
                .toString()
                .trim()
                .isEmpty;
            final needsBackfillEmail =
                email != null &&
                email.isNotEmpty &&
                (memberData['email'] ?? '').toString().trim().isEmpty;
            final needsBackfillNickname = (memberData['nickname'] ?? '')
                .toString()
                .trim()
                .isEmpty;
            if (needsBackfillUserId ||
                needsBackfillUid ||
                needsBackfillEmail ||
                needsBackfillNickname) {
              final fallbackNickname =
                  (auth.currentUser?.displayName ?? email ?? '사용자')
                      .toString()
                      .trim();
              final nickname = currentUser == null
                  ? (fallbackNickname.isEmpty ? '사용자' : fallbackNickname)
                  : await _resolveOwnNickname(firestore, currentUser);
              await memberRef.set({
                'userId': uid,
                'uid': uid,
                if (email != null && email.isNotEmpty) 'email': email,
                'nickname': nickname,
              }, SetOptions(merge: true));
            }
          } else if (nextRole == 'admin') {
            // Legacy self-heal: ensure creator has a member doc.
            final nickname = currentUser == null
                ? (auth.currentUser?.displayName ?? email ?? '사용자')
                : await _resolveOwnNickname(firestore, currentUser);
            await memberRef.set({
              'userId': uid,
              'uid': uid,
              'email': email,
              'displayName': auth.currentUser?.displayName,
              'nickname': nickname,
              'role': 'admin',
              'teamName': nextName,
              'capabilities': {'songEditor': true},
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }

          await _userTeamMembershipRef(
            firestore: firestore,
            uid: uid,
            teamId: teamId,
          ).set({
            'teamId': teamId,
            'teamName': nextName,
            'role': nextRole,
            if (nextLastProjectId != null && nextLastProjectId.isNotEmpty)
              'lastProjectId': nextLastProjectId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          byTeamId[teamId] = _TeamMembership(
            teamId: teamId,
            teamName: nextName,
            role: nextRole,
            lastProjectId: nextLastProjectId,
          );
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied') {
            byTeamId.remove(teamId);
            await _deleteUserTeamMembershipMirror(
              firestore: firestore,
              uid: uid,
              teamId: teamId,
            );
            continue;
          }
          rethrow;
        } on TimeoutException {
          byTeamId.remove(teamId);
          continue;
        }
      }

      if (byTeamId.isEmpty &&
          (memberQueryPermissionDenied || teamQueryPermissionDenied)) {
        return const <_TeamMembership>[];
      }

      final teams = byTeamId.values.toList()
        ..sort((a, b) => a.teamName.compareTo(b.teamName));
      return teams;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'failed-precondition' ||
          error.code == 'invalid-argument') {
        return const <_TeamMembership>[];
      }
      rethrow;
    } on TimeoutException {
      final teams = byTeamId.values.toList()
        ..sort((a, b) => a.teamName.compareTo(b.teamName));
      return teams;
    }
  }

  Future<List<_InviteInfo>> _fetchInvites(String email) async {
    final firestore = ref.read(firestoreProvider);
    final inviteDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};
    final candidates = {email, email.toLowerCase()}
      ..removeWhere((value) => value.trim().isEmpty);

    for (final candidate in candidates) {
      try {
        final snapshot = await firestore
            .collectionGroup('invites')
            .where('email', isEqualTo: candidate)
            .where('status', isEqualTo: 'pending')
            .get()
            .timeout(const Duration(seconds: 12));
        for (final doc in snapshot.docs) {
          if (seen.add(doc.reference.path)) {
            inviteDocs.add(doc);
          }
        }
      } on FirebaseException catch (error) {
        if (error.code == 'failed-precondition') {
          final fallback = await firestore
              .collectionGroup('invites')
              .where('email', isEqualTo: candidate)
              .get()
              .timeout(const Duration(seconds: 12));
          for (final doc in fallback.docs) {
            final data = doc.data();
            if ((data['status'] ?? '').toString() != 'pending') continue;
            if (seen.add(doc.reference.path)) {
              inviteDocs.add(doc);
            }
          }
          continue;
        }
        if (error.code == 'permission-denied') {
          return [];
        }
        rethrow;
      } on TimeoutException {
        return [];
      }
    }

    final invites =
        inviteDocs
            .map((doc) {
              final data = doc.data();
              final teamId = doc.reference.parent.parent?.id ?? '';
              if (!isValidFirestoreDocId(teamId)) {
                return null;
              }
              return _InviteInfo(
                teamId: teamId,
                teamName: (data['teamName'] ?? '팀').toString(),
                role: (data['role'] ?? 'member').toString(),
                docId: doc.id,
              );
            })
            .whereType<_InviteInfo>()
            .toList()
          ..sort((a, b) => a.teamName.compareTo(b.teamName));
    return invites;
  }

  Future<void> _acceptInvite(BuildContext context, _InviteInfo invite) async {
    final auth = ref.read(firebaseAuthProvider);
    final firestore = ref.read(firestoreProvider);
    final user = auth.currentUser;
    if (user == null) return;
    if (!isValidFirestoreDocId(invite.teamId)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('잘못된 팀 초대 정보입니다.')));
      return;
    }

    try {
      final nickname = await _resolveOwnNickname(firestore, user);
      final memberRef = firestore
          .collection('teams')
          .doc(invite.teamId)
          .collection('members')
          .doc(user.uid);
      final existingMember = await memberRef.get();
      if (existingMember.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미 해당 팀에 참여 중입니다.')));
        _refreshMembershipData();
        return;
      }
      final teamRef = firestore.collection('teams').doc(invite.teamId);
      final inviteRef = teamRef.collection('invites').doc(invite.docId);
      final inviteSnapshot = await inviteRef.get();
      if (!inviteSnapshot.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('초대가 만료되었거나 삭제되었습니다.')));
        _refreshMembershipData();
        return;
      }
      final inviteData = inviteSnapshot.data() ?? const <String, dynamic>{};
      final inviteStatus = (inviteData['status'] ?? '').toString();
      if (inviteStatus != 'pending') {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미 처리된 초대입니다.')));
        _refreshMembershipData();
        return;
      }
      final resolvedTeamName = (inviteData['teamName'] ?? invite.teamName)
          .toString();
      final resolvedRole = teamRoleKey(
        (inviteData['role'] ?? invite.role).toString(),
      );
      await memberRef.set({
        'userId': user.uid,
        'uid': user.uid,
        'email': user.email?.toLowerCase(),
        'displayName': user.displayName,
        'nickname': nickname,
        'role': resolvedRole,
        'teamName': resolvedTeamName,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _userTeamMembershipRef(
        firestore: firestore,
        uid: user.uid,
        teamId: invite.teamId,
      ).set({
        'teamId': invite.teamId,
        'teamName': resolvedTeamName,
        'role': resolvedRole,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await teamRef.set({
        'memberUids': FieldValue.arrayUnion([user.uid]),
      }, SetOptions(merge: true));
      await inviteRef.set({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': user.uid,
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('팀 초대를 수락했습니다.')));
      _refreshMembershipData();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('초대 수락 실패: $error')));
    }
  }

  Future<_InviteLinkInfo?> _fetchInviteLink(
    String teamId,
    String inviteCode,
  ) async {
    if (!isValidFirestoreDocId(teamId) || !isValidFirestoreDocId(inviteCode)) {
      return null;
    }
    final firestore = ref.read(firestoreProvider);
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await firestore
          .collection('teams')
          .doc(teamId)
          .collection('inviteLinks')
          .doc(inviteCode)
          .get();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    if ((data['status'] ?? '').toString() != 'active') return null;
    return _InviteLinkInfo(
      teamId: teamId,
      inviteCode: inviteCode,
      teamName: (data['teamName'] ?? '팀').toString(),
      role: (data['role'] ?? 'member').toString(),
    );
  }

  Future<void> _acceptInviteLink(
    BuildContext context,
    _InviteLinkInfo invite,
  ) async {
    final auth = ref.read(firebaseAuthProvider);
    final firestore = ref.read(firestoreProvider);
    final user = auth.currentUser;
    if (user == null) return;
    if (!isValidFirestoreDocId(invite.teamId) ||
        !isValidFirestoreDocId(invite.inviteCode)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('잘못된 링크 초대 정보입니다.')));
      return;
    }

    try {
      final nickname = await _resolveOwnNickname(firestore, user);
      final memberRef = firestore
          .collection('teams')
          .doc(invite.teamId)
          .collection('members')
          .doc(user.uid);
      final existingMember = await memberRef.get();
      if (existingMember.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미 해당 팀에 참여 중입니다.')));
        _invalidateMembershipCaches();
        context.go('/teams/${invite.teamId}');
        return;
      }
      final teamRef = firestore.collection('teams').doc(invite.teamId);
      final inviteLinkRef = teamRef
          .collection('inviteLinks')
          .doc(invite.inviteCode);
      final inviteLinkSnapshot = await inviteLinkRef.get();
      if (!inviteLinkSnapshot.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('초대 링크가 만료되었습니다.')));
        return;
      }
      final inviteLinkData =
          inviteLinkSnapshot.data() ?? const <String, dynamic>{};
      if ((inviteLinkData['status'] ?? '').toString() != 'active') {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('비활성화된 링크입니다.')));
        return;
      }
      final resolvedTeamName = (inviteLinkData['teamName'] ?? invite.teamName)
          .toString();
      final resolvedRole = teamRoleKey(
        (inviteLinkData['role'] ?? invite.role).toString(),
      );
      await memberRef.set({
        'userId': user.uid,
        'uid': user.uid,
        'email': user.email?.toLowerCase(),
        'displayName': user.displayName,
        'nickname': nickname,
        'role': resolvedRole,
        'teamName': resolvedTeamName,
        'inviteLinkId': invite.inviteCode,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _userTeamMembershipRef(
        firestore: firestore,
        uid: user.uid,
        teamId: invite.teamId,
      ).set({
        'teamId': invite.teamId,
        'teamName': resolvedTeamName,
        'role': resolvedRole,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await teamRef.set({
        'memberUids': FieldValue.arrayUnion([user.uid]),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      _invalidateMembershipCaches();
      context.go('/teams/${invite.teamId}');
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('링크 권한이 만료되었거나 이미 사용되었습니다. 팀장에게 새 링크를 요청해 주세요.'),
          ),
        );
        return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크 초대 수락 실패: ${error.message ?? error.code}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('링크 초대 수락 실패: $error')));
    }
  }

  void _setTab(int index) {
    setState(() => _tabIndex = index);
  }

  DocumentReference<Map<String, dynamic>> _userTeamMembershipRef({
    required FirebaseFirestore firestore,
    required String uid,
    required String teamId,
  }) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('teamMemberships')
        .doc(teamId);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    if (user == null) {
      _lastAuthKey = null;
      _cachedNickname = null;
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }
    final authKey = '${user.uid}|${(user.email ?? '').toLowerCase()}';
    if (_lastAuthKey != authKey) {
      _lastAuthKey = authKey;
      _invalidateMembershipCaches();
      Future<void>.microtask(() => _syncOwnProfile(user));
    }

    final email = user.email?.toLowerCase();
    final isWide = MediaQuery.of(context).size.width >= 900;
    final adminValue = ref.watch(globalAdminProvider);
    final isGlobalAdmin = adminValue.value ?? false;

    final pages = <Widget>[
      _TeamsTab(
        user: user,
        email: email,
        fetchInvites: _fetchInvitesCached,
        acceptInvite: _acceptInvite,
        fetchTeams: _fetchTeamsCached,
        teamNameController: _teamNameController,
        creating: _creating,
        onCreateTeam: _createTeam,
        inviteTeamId: widget.inviteTeamId,
        inviteCode: widget.inviteCode,
        fetchInviteLink: _fetchInviteLink,
        acceptInviteLink: _acceptInviteLink,
        onRefresh: _refreshMembershipData,
      ),
      _SongLibraryTab(onGoTeamsTab: () => _setTab(0)),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.groups), label: '팀/프로젝트'),
      const NavigationDestination(
        icon: Icon(Icons.library_music),
        label: '악보 라이브러리',
      ),
    ];

    final railDestinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.groups),
        label: Text('팀/프로젝트'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.library_music),
        label: Text('악보 라이브러리'),
      ),
    ];

    final maxIndex = pages.length - 1;
    if (_tabIndex > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _tabIndex = maxIndex);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E4E87), Color(0xFF2A7DB0)],
                ),
              ),
              child: const Icon(
                Icons.queue_music_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('WorshipFlow'),
                Text(
                  _tabIndex == 0 ? '팀/프로젝트' : '악보 라이브러리',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (isGlobalAdmin)
            IconButton(
              onPressed: () => context.go('/admin'),
              icon: const Icon(Icons.admin_panel_settings_rounded),
              tooltip: '운영자 도구',
            ),
          IconButton(
            onPressed: () => _openNicknameDialog(context, user),
            icon: const Icon(Icons.badge_rounded),
            tooltip: '닉네임 설정',
          ),
          IconButton(
            onPressed: () => setState(() => _tabIndex = 0),
            icon: const Icon(Icons.home_rounded),
            tooltip: '홈(팀 전환)',
          ),
          IconButton(
            onPressed: _refreshMembershipData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '새로고침',
          ),
          IconButton(
            onPressed: () => ref.read(firebaseAuthProvider).signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: '로그아웃',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  Container(
                    width: 118,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F8FD),
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 14),
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0E4E87), Color(0xFF2A7DB0)],
                            ),
                          ),
                          child: const Icon(
                            Icons.space_dashboard_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Services',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: NavigationRail(
                            selectedIndex: _tabIndex.clamp(0, maxIndex),
                            onDestinationSelected: _setTab,
                            labelType: NavigationRailLabelType.all,
                            groupAlignment: -0.95,
                            destinations: railDestinations,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: pages[_tabIndex.clamp(0, maxIndex)]),
                ],
              )
            : pages[_tabIndex.clamp(0, maxIndex)],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex.clamp(0, maxIndex),
              onDestinationSelected: _setTab,
              destinations: destinations,
            ),
    );
  }
}

class _TeamsTab extends StatelessWidget {
  final User user;
  final String? email;
  final Future<List<_InviteInfo>> Function(String email) fetchInvites;
  final Future<void> Function(BuildContext context, _InviteInfo invite)
  acceptInvite;
  final Future<List<_TeamMembership>> Function(String uid) fetchTeams;
  final TextEditingController teamNameController;
  final bool creating;
  final Future<void> Function(BuildContext context) onCreateTeam;
  final String? inviteTeamId;
  final String? inviteCode;
  final Future<_InviteLinkInfo?> Function(String teamId, String inviteCode)
  fetchInviteLink;
  final Future<void> Function(BuildContext context, _InviteLinkInfo invite)
  acceptInviteLink;
  final VoidCallback onRefresh;

  const _TeamsTab({
    required this.user,
    required this.email,
    required this.fetchInvites,
    required this.acceptInvite,
    required this.fetchTeams,
    required this.teamNameController,
    required this.creating,
    required this.onCreateTeam,
    required this.inviteTeamId,
    required this.inviteCode,
    required this.fetchInviteLink,
    required this.acceptInviteLink,
    required this.onRefresh,
  });

  Widget _stepLine(BuildContext context, String step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            step,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }

  Color _roleColor(BuildContext context, String role) {
    final scheme = Theme.of(context).colorScheme;
    switch (teamRoleKey(role)) {
      case 'admin':
        return scheme.primary;
      case 'leader':
        return scheme.tertiary;
      case 'member':
      default:
        return scheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteLinkSection = inviteTeamId != null && inviteCode != null
        ? FutureBuilder<_InviteLinkInfo?>(
            future: fetchInviteLink(inviteTeamId!, inviteCode!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingState(message: '초대 링크 확인 중...');
              }
              if (snapshot.hasError) {
                return AppStateCard(
                  icon: Icons.link_off,
                  isError: true,
                  title: '초대 링크를 확인할 수 없습니다',
                  message: _friendlyAsyncError(snapshot.error),
                  actionLabel: '다시 시도',
                  onAction: onRefresh,
                );
              }
              final invite = snapshot.data;
              if (invite == null) {
                return AppStateCard(
                  icon: Icons.link_off,
                  isError: true,
                  title: '초대 링크가 유효하지 않습니다',
                  message: '링크가 만료되었거나 이미 비활성화되었습니다. 팀장에게 새 링크를 요청해 주세요.',
                  actionLabel: '새로고침',
                  onAction: onRefresh,
                );
              }
              return AppSectionCard(
                icon: Icons.link_rounded,
                title: '${invite.teamName} 링크 초대',
                subtitle: '역할: ${teamRoleLabel(invite.role)}',
                trailing: FilledButton(
                  onPressed: () => acceptInviteLink(context, invite),
                  child: const Text('바로 참여'),
                ),
                child: Text(
                  '초대 수락 후 바로 팀 홈으로 이동합니다.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            },
          )
        : const SizedBox.shrink();

    final teamsSection = AppSectionCard(
      icon: Icons.groups_2_rounded,
      title: '내 팀',
      subtitle: '팀을 선택하면 프로젝트 화면으로 바로 이동합니다.',
      child: FutureBuilder<List<_TeamMembership>>(
        future: fetchTeams(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingState(message: '팀 목록 불러오는 중...');
          }
          if (snapshot.hasError) {
            return AppStateCard(
              icon: Icons.groups_2_outlined,
              isError: true,
              title: '팀 목록 로드 실패',
              message: _friendlyAsyncError(snapshot.error),
              actionLabel: '다시 시도',
              onAction: onRefresh,
            );
          }
          final teams = snapshot.data ?? [];
          if (teams.isEmpty) {
            return const AppStateCard(
              icon: Icons.group_add_outlined,
              title: '아직 가입된 팀이 없습니다',
              message: '오른쪽에서 새 팀을 만들거나 받은 초대를 먼저 수락해 주세요.',
            );
          }
          final duplicateNameCounts = <String, int>{};
          for (final team in teams) {
            final key = buildTeamNameKey(team.teamName);
            duplicateNameCounts.update(
              key,
              (next) => next + 1,
              ifAbsent: () => 1,
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: teams.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final team = teams[index];
              final roleColor = _roleColor(context, team.role);
              final duplicateCount =
                  duplicateNameCounts[buildTeamNameKey(team.teamName)] ?? 1;
              final hasDuplicateName = duplicateCount > 1;
              final lastProjectId = team.lastProjectId?.trim();
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: roleColor.withValues(alpha: 0.16),
                    foregroundColor: roleColor,
                    child: Text(
                      team.teamName.isEmpty ? '팀' : team.teamName[0],
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(
                    team.teamName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('역할: ${teamRoleLabel(team.role)}'),
                      if (lastProjectId != null && lastProjectId.isNotEmpty)
                        Text('최근 프로젝트: $lastProjectId'),
                      if (hasDuplicateName)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '동일 이름 팀 $duplicateCount개',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          teamRoleLabel(team.role),
                          style: TextStyle(
                            color: roleColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/teams/${team.teamId}'),
                ),
              );
            },
          );
        },
      ),
    );

    final invitesSection = email == null
        ? const SizedBox.shrink()
        : AppSectionCard(
            icon: Icons.mark_email_unread_outlined,
            title: '받은 초대',
            subtitle: '대기 중인 팀 초대를 수락할 수 있습니다.',
            child: FutureBuilder<List<_InviteInfo>>(
              future: fetchInvites(email!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingState(message: '초대 목록 불러오는 중...');
                }
                if (snapshot.hasError) {
                  return AppStateCard(
                    icon: Icons.error_outline,
                    isError: true,
                    title: '초대 목록 로드 실패',
                    message: _friendlyAsyncError(snapshot.error),
                    actionLabel: '다시 시도',
                    onAction: onRefresh,
                  );
                }
                final invites = snapshot.data ?? [];
                if (invites.isEmpty) {
                  return const AppStateCard(
                    icon: Icons.mark_email_read_outlined,
                    title: '대기 중인 초대가 없습니다',
                    message: '팀장에게 이메일 또는 카카오 링크 초대를 요청하세요.',
                  );
                }
                return Column(
                  children: invites
                      .map(
                        (invite) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: const Icon(Icons.mail, size: 16),
                              ),
                              title: Text(invite.teamName),
                              subtitle: Text(
                                '역할: ${teamRoleLabel(invite.role)}',
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: () => acceptInvite(context, invite),
                                child: const Text('수락'),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          );

    final createTeamSection = AppSectionCard(
      icon: Icons.add_circle_outline,
      title: '새 팀 만들기',
      subtitle: '예: 1부예배, 2부예배, 청년부, 수요예배',
      trailing: FilledButton.icon(
        onPressed: creating ? null : () => onCreateTeam(context),
        icon: creating
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(creating ? '생성 중...' : '팀 생성'),
      ),
      child: TextField(
        controller: teamNameController,
        onSubmitted: (_) {
          if (!creating) {
            onCreateTeam(context);
          }
        },
        decoration: appInputDecoration(
          context,
          label: '팀 이름',
          helper: '동일 팀명이 있으면 새 팀 대신 팀장에게 초대 요청이 전송됩니다.',
        ),
      ),
    );

    final guideSection = AppSectionCard(
      icon: Icons.flag_circle_rounded,
      title: '운영 순서',
      subtitle: '서비스 앱 스타일로 실제 예배 흐름 기준으로 정리했습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepLine(context, '1', '내 팀에서 담당 팀을 선택합니다.'),
          const SizedBox(height: 8),
          _stepLine(context, '2', '프로젝트(예배 날짜)를 생성합니다.'),
          const SizedBox(height: 8),
          _stepLine(context, '3', '예배 전 콘티를 입력하고 LiveCue/악보보기를 확인합니다.'),
        ],
      ),
    );

    return AppContentFrame(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1160;
          return ListView(
            children: [
              AppHeroPanel(
                title: '팀/프로젝트 워크스페이스',
                subtitle:
                    'Planning Center Services 흐름처럼 팀 선택 → 프로젝트 생성 → 콘티/LiveCue로 이어집니다.',
                icon: Icons.space_dashboard_rounded,
                actions: [
                  FilledButton.icon(
                    onPressed: creating ? null : () => onCreateTeam(context),
                    icon: creating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(creating ? '팀 생성 중...' : '팀 만들기'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('새로고침'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          teamsSection,
                          const SizedBox(height: 14),
                          invitesSection,
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          if (inviteTeamId != null && inviteCode != null) ...[
                            inviteLinkSection,
                            const SizedBox(height: 14),
                          ],
                          guideSection,
                          const SizedBox(height: 14),
                          createTeamSection,
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                guideSection,
                const SizedBox(height: 14),
                teamsSection,
                const SizedBox(height: 14),
                invitesSection,
                if (inviteTeamId != null && inviteCode != null) ...[
                  const SizedBox(height: 14),
                  inviteLinkSection,
                ],
                const SizedBox(height: 14),
                createTeamSection,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SongLibraryTab extends StatelessWidget {
  final VoidCallback onGoTeamsTab;

  const _SongLibraryTab({required this.onGoTeamsTab});

  @override
  Widget build(BuildContext context) {
    final guideCard = AppSectionCard(
      icon: Icons.info_outline_rounded,
      title: '이 탭은 전역 악보 DB 관리 전용입니다',
      subtitle: '팀 연결/프로젝트 연결은 팀/프로젝트 탭에서 진행하세요.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1) 여기서 교회 공용 곡/악보를 등록합니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '2) 팀/프로젝트 탭에서 해당 곡을 팀에 연결합니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onGoTeamsTab,
              icon: const Icon(Icons.groups_2_rounded),
              label: const Text('팀/프로젝트 탭으로 이동'),
            ),
          ),
        ],
      ),
    );

    return AppContentFrame(
      child: ListView(
        children: [
          const AppHeroPanel(
            title: '악보 라이브러리',
            subtitle: '전역 곡/악보 DB를 관리하는 공간입니다. 팀 연결은 팀/프로젝트 탭에서 처리합니다.',
            icon: Icons.library_music_rounded,
          ),
          const SizedBox(height: 14),
          guideCard,
          const SizedBox(height: 14),
          const AppSectionCard(
            icon: Icons.public_rounded,
            title: '전역 악보 관리',
            subtitle: '교회 전체 공용 곡/악보 데이터 (운영자 권한 필요)',
            child: GlobalSongPanel(),
          ),
        ],
      ),
    );
  }
}

class _TeamMembership {
  final String teamId;
  final String teamName;
  final String role;
  final String? lastProjectId;

  const _TeamMembership({
    required this.teamId,
    required this.teamName,
    required this.role,
    this.lastProjectId,
  });
}

class _InviteInfo {
  final String teamId;
  final String teamName;
  final String role;
  final String docId;

  const _InviteInfo({
    required this.teamId,
    required this.teamName,
    required this.role,
    required this.docId,
  });
}

class _InviteLinkInfo {
  final String teamId;
  final String inviteCode;
  final String teamName;
  final String role;

  const _InviteLinkInfo({
    required this.teamId,
    required this.inviteCode,
    required this.teamName,
    required this.role,
  });
}

enum _JoinRequestOutcome {
  submitted,
  alreadyRequested,
  alreadyMember,
  requiresEmail,
  unavailable,
}

class _TeamNameAlreadyExistsException implements Exception {
  const _TeamNameAlreadyExistsException();
}

class _InvalidTeamNameException implements Exception {
  const _InvalidTeamNameException();
}

class _TeamNameCheckUnavailableException implements Exception {
  const _TeamNameCheckUnavailableException();
}

String _friendlyAsyncError(Object? error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '권한이 없거나 팀 멤버 정보가 아직 동기화되지 않았습니다. 초대 수락 후 새로고침해 주세요.';
      case 'failed-precondition':
        return '데이터 인덱스 준비가 필요합니다. 잠시 후 다시 시도해 주세요.';
      case 'unauthenticated':
        return '로그인 상태가 만료되었습니다. 다시 로그인해 주세요.';
    }
    return error.message ?? error.code;
  }
  return error?.toString() ?? '알 수 없는 오류';
}
