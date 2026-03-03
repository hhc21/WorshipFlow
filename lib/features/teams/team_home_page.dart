import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import '../../utils/firestore_id.dart';
import '../../utils/team_name.dart';
import '../../utils/user_display_name.dart';
import '../songs/song_library_panel.dart';
import 'team_invite_panel.dart';

class TeamHomePage extends ConsumerStatefulWidget {
  final String teamId;

  const TeamHomePage({super.key, required this.teamId});

  @override
  ConsumerState<TeamHomePage> createState() => _TeamHomePageState();
}

class _TeamHomePageState extends ConsumerState<TeamHomePage> {
  final Set<String> _roleUpdatingUserIds = <String>{};
  final Set<String> _deletingProjectIds = <String>{};
  bool _deletingTeam = false;
  Future<_TeamContext>? _contextFuture;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _membersFuture;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _projectsFuture;

  @override
  void initState() {
    super.initState();
    _resetPageState();
  }

  @override
  void didUpdateWidget(covariant TeamHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      _resetPageState();
    }
  }

  void _resetPageState() {
    final firestore = ref.read(firestoreProvider);
    final currentUser = ref.read(firebaseAuthProvider).currentUser;
    _contextFuture = currentUser == null
        ? null
        : _loadContext(firestore, currentUser.uid);
    _membersFuture = _loadMembers(firestore);
    _projectsFuture = _loadProjects(firestore);
  }

  void _refreshPageState() {
    setState(_resetPageState);
  }

  Future<_TeamContext> _loadContext(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    final teamRef = firestore.collection('teams').doc(widget.teamId);
    final team = await teamRef.get().timeout(const Duration(seconds: 12));
    var member = await teamRef
        .collection('members')
        .doc(userId)
        .get()
        .timeout(const Duration(seconds: 12));
    final createdBy = (team.data()?['createdBy'] ?? '').toString();
    final memberRole = (member.data()?['role'] ?? '').toString().trim();
    final creatorNeedsRepair =
        team.exists &&
        createdBy == userId &&
        (!member.exists || _normalizeRole(memberRole) != 'admin');
    if (creatorNeedsRepair) {
      // Self-heal legacy teams where creator member doc was not written.
      await teamRef.collection('members').doc(userId).set({
        'userId': userId,
        'uid': userId,
        'email': ref
            .read(firebaseAuthProvider)
            .currentUser
            ?.email
            ?.toLowerCase(),
        'displayName': ref.read(firebaseAuthProvider).currentUser?.displayName,
        'nickname': null,
        'role': 'admin',
        'teamName': (team.data()?['name'] ?? '팀').toString(),
        'capabilities': {'songEditor': true},
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      member = await teamRef
          .collection('members')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 12));
      await teamRef.set({
        'memberUids': FieldValue.arrayUnion([userId]),
      }, SetOptions(merge: true));
    }
    return _TeamContext(team: team, member: member);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadProjects(
    FirebaseFirestore firestore,
  ) async {
    try {
      final snapshot = await firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .get()
          .timeout(const Duration(seconds: 12));
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'failed-precondition' ||
          error.code == 'invalid-argument') {
        return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      }
      rethrow;
    } on TimeoutException {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
  }

  int _compareProjects(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aData = a.data();
    final bData = b.data();
    final aDate = (aData['date']?.toString() ?? a.id).trim();
    final bDate = (bData['date']?.toString() ?? b.id).trim();
    final byDate = bDate.compareTo(aDate);
    if (byDate != 0) return byDate;

    final aCreatedAt =
        (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch;
    final bCreatedAt =
        (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch;
    if (aCreatedAt != null && bCreatedAt != null && aCreatedAt != bCreatedAt) {
      return bCreatedAt.compareTo(aCreatedAt);
    }
    return b.id.compareTo(a.id);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadMembers(
    FirebaseFirestore firestore,
  ) async {
    try {
      final snapshot = await firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('members')
          .get()
          .timeout(const Duration(seconds: 12));
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'failed-precondition') {
        return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      }
      rethrow;
    } on TimeoutException {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
  }

  Future<void> _openRecentProject(
    BuildContext context,
    FirebaseFirestore firestore,
    String projectId,
  ) async {
    final candidate = projectId.trim();
    if (!isValidFirestoreDocId(candidate)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('최근 프로젝트 정보가 올바르지 않습니다.')));
      return;
    }
    final projectsRef = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects');
    try {
      final exact = await projectsRef
          .doc(candidate)
          .get()
          .timeout(const Duration(seconds: 12));
      if (exact.exists) {
        if (!context.mounted) return;
        context.go('/teams/${widget.teamId}/projects/$candidate');
        return;
      }

      final snapshot = await projectsRef.get().timeout(
        const Duration(seconds: 12),
      );
      final projects = [...snapshot.docs]..sort(_compareProjects);
      if (projects.isEmpty) {
        await firestore.collection('teams').doc(widget.teamId).set({
          'lastProjectId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('최근 프로젝트가 없어 값을 초기화했습니다.')),
        );
        _refreshPageState();
        return;
      }

      final fallbackId = projects.first.id;
      await firestore.collection('teams').doc(widget.teamId).set({
        'lastProjectId': fallbackId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('최근 프로젝트($candidate)를 찾을 수 없어 $fallbackId 로 이동합니다.'),
        ),
      );
      context.go('/teams/${widget.teamId}/projects/$fallbackId');
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('최근 프로젝트 열기 실패: ${error.message ?? error.code}'),
        ),
      );
    } on TimeoutException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message ?? '요청 시간 초과')));
    }
  }

  String _memberName(
    String? userId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> members,
  ) {
    if (userId == null || userId.isEmpty) return '-';
    for (final doc in members) {
      if (doc.id != userId) continue;
      return memberDisplayNameWithFallback(userId, doc.data());
    }
    return '이름 확인 중';
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return '팀장';
      case 'leader':
      case 'speaker':
        return '인도자';
      case 'member':
      default:
        return '팀원';
    }
  }

  String _normalizeRole(String? role) {
    final normalized = (role ?? 'member').trim().toLowerCase();
    switch (normalized) {
      case 'admin':
      case 'owner':
      case 'team_admin':
      case '팀장':
        return 'admin';
      case 'leader':
      case 'speaker':
      case '인도자':
        return 'leader';
      case 'member':
      default:
        return 'member';
    }
  }

  Future<void> _updateMemberRole({
    required BuildContext context,
    required String actorUserId,
    required String targetUserId,
    required String nextRole,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> members,
  }) async {
    final normalizedNextRole = _normalizeRole(nextRole);
    final targetDoc = members
        .where((doc) => doc.id == targetUserId)
        .firstOrNull;
    if (targetDoc == null) return;
    final currentRole = _normalizeRole(targetDoc.data()['role']?.toString());
    if (currentRole == normalizedNextRole) return;

    final adminCount = members
        .where(
          (doc) => _normalizeRole(doc.data()['role']?.toString()) == 'admin',
        )
        .length;
    final targetIsLastAdmin = currentRole == 'admin' && adminCount <= 1;
    if (targetIsLastAdmin && normalizedNextRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마지막 팀장은 변경할 수 없습니다. 다른 팀장을 먼저 지정하세요.')),
      );
      return;
    }

    setState(() {
      _roleUpdatingUserIds.add(targetUserId);
    });

    final firestore = ref.read(firestoreProvider);
    try {
      await firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('members')
          .doc(targetUserId)
          .set({
            'role': normalizedNextRole,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await firestore
          .collection('users')
          .doc(targetUserId)
          .collection('teamMemberships')
          .doc(widget.teamId)
          .set({
            'teamId': widget.teamId,
            'role': normalizedNextRole,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!context.mounted) return;
      final isSelf = actorUserId == targetUserId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSelf
                ? '내 역할이 ${_roleLabel(normalizedNextRole)}로 변경되었습니다.'
                : '팀원 역할이 ${_roleLabel(normalizedNextRole)}로 변경되었습니다.',
          ),
        ),
      );
      _refreshPageState();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('역할 변경 실패: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _roleUpdatingUserIds.remove(targetUserId);
        });
      }
    }
  }

  Future<void> _openEditLeadersDialog(
    BuildContext context,
    String projectId,
    Map<String, dynamic> projectData,
  ) async {
    final firestore = ref.read(firestoreProvider);
    final members = await _loadMembers(firestore);
    if (!context.mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProjectLeadersDialog(
        teamId: widget.teamId,
        projectId: projectId,
        members: members,
        initialLeaderUserId: projectData['leaderUserId']?.toString(),
      ),
    );
    if (changed == true && mounted) _refreshPageState();
  }

  Future<List<_TeamOption>> _loadMyTeams(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    Future<void> deleteMembershipMirror(String teamId) async {
      try {
        await firestore
            .collection('users')
            .doc(userId)
            .collection('teamMemberships')
            .doc(teamId)
            .delete();
      } on FirebaseException {
        // Best-effort cleanup only.
      }
    }

    final byId = <String, _TeamOption>{};
    try {
      final memberships = await firestore
          .collection('users')
          .doc(userId)
          .collection('teamMemberships')
          .get()
          .timeout(const Duration(seconds: 12));
      for (final doc in memberships.docs) {
        final data = doc.data();
        final teamId = (data['teamId'] ?? doc.id).toString().trim();
        if (!isValidFirestoreDocId(teamId)) continue;
        final teamName = (data['teamName'] ?? '팀').toString().trim();
        byId[teamId] = _TeamOption(
          id: teamId,
          name: teamName.isEmpty ? '팀' : teamName,
        );
      }
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' &&
          error.code != 'failed-precondition') {
        rethrow;
      }
    } on TimeoutException {
      // Keep page responsive and continue with fallback query.
    }

    if (byId.isEmpty) {
      try {
        final teams = await firestore
            .collection('teams')
            .where('memberUids', arrayContains: userId)
            .get()
            .timeout(const Duration(seconds: 12));
        for (final doc in teams.docs) {
          final teamName = (doc.data()['name'] ?? '팀').toString().trim();
          byId[doc.id] = _TeamOption(
            id: doc.id,
            name: teamName.isEmpty ? '팀' : teamName,
          );
        }
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') {
          rethrow;
        }
      } on TimeoutException {
        // Ignore timeout and use currently available data.
      }
    }

    for (final teamId in byId.keys.toList()) {
      if (!isValidFirestoreDocId(teamId)) {
        byId.remove(teamId);
        await deleteMembershipMirror(teamId);
        continue;
      }
      try {
        final teamRef = firestore.collection('teams').doc(teamId);
        final teamDoc = await teamRef.get().timeout(
          const Duration(seconds: 12),
        );
        if (!teamDoc.exists) {
          byId.remove(teamId);
          await deleteMembershipMirror(teamId);
          continue;
        }

        final teamData = teamDoc.data() ?? const <String, dynamic>{};
        final remoteName = (teamData['name'] ?? '').toString().trim();
        final createdBy = (teamData['createdBy'] ?? '').toString();
        final memberUidsRaw = teamData['memberUids'];
        final memberUids = memberUidsRaw is List
            ? memberUidsRaw.map((e) => e.toString()).toList()
            : const <String>[];
        final memberDoc = await teamRef
            .collection('members')
            .doc(userId)
            .get()
            .timeout(const Duration(seconds: 12));
        final hasMembership =
            memberDoc.exists ||
            createdBy == userId ||
            memberUids.contains(userId);

        if (!hasMembership) {
          byId.remove(teamId);
          await deleteMembershipMirror(teamId);
          continue;
        }

        if (remoteName.isNotEmpty) {
          byId[teamId] = _TeamOption(id: teamId, name: remoteName);
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'failed-precondition' ||
            error.code == 'invalid-argument') {
          byId.remove(teamId);
          await deleteMembershipMirror(teamId);
          continue;
        }
        rethrow;
      } on TimeoutException {
        byId.remove(teamId);
        continue;
      }
    }

    final options = byId.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  Future<void> _openCreateProjectDialog(
    BuildContext context,
    FirebaseFirestore firestore,
  ) async {
    final members = await _loadMembers(firestore);
    if (!context.mounted) return;
    final createdProjectId = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CreateProjectDialog(teamId: widget.teamId, members: members),
    );
    if (!context.mounted) return;
    if (createdProjectId != null && createdProjectId.isNotEmpty) {
      context.go('/teams/${widget.teamId}/projects/$createdProjectId');
      return;
    }
    if (mounted) _refreshPageState();
  }

  Future<void> _openTeamSwitcher(
    BuildContext context,
    FirebaseFirestore firestore,
    String userId,
  ) async {
    final teams = await _loadMyTeams(firestore, userId);
    if (!context.mounted) return;
    if (teams.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('전환할 팀이 없습니다.')));
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: teams.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final team = teams[index];
              final isCurrent = team.id == widget.teamId;
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.check_circle : Icons.groups_2_outlined,
                ),
                title: Text(team.name),
                subtitle: Text(isCurrent ? '현재 팀' : '탭해서 이동'),
                onTap: () => Navigator.of(sheetContext).pop(team.id),
              );
            },
          ),
        );
      },
    );

    if (!context.mounted || selected == null || selected.isEmpty) return;
    if (!isValidFirestoreDocId(selected)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('잘못된 팀 정보입니다.')));
      return;
    }
    context.go('/teams/$selected');
  }

  Future<void> _removeCurrentTeamFromMyList(
    BuildContext context,
    String userId,
  ) async {
    final firestore = ref.read(firestoreProvider);
    try {
      await firestore
          .collection('users')
          .doc(userId)
          .collection('teamMemberships')
          .doc(widget.teamId)
          .delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('내 팀 목록에서 제거했습니다.')));
      context.go('/teams');
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('목록 제거 실패: ${error.message ?? error.code}')),
      );
    }
  }

  Future<void> _deleteCollectionDocs(
    FirebaseFirestore firestore,
    CollectionReference<Map<String, dynamic>> collection, {
    int pageSize = 200,
  }) async {
    while (true) {
      final snapshot = await collection.limit(pageSize).get();
      if (snapshot.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < pageSize) return;
    }
  }

  String _privateProjectNoteDocIdV2(String projectId, String userId) {
    return 'v2__${projectId}__$userId';
  }

  String _privateProjectNoteDocIdLegacy(String projectId, String userId) {
    return '${projectId}__$userId';
  }

  Future<void> _deletePrivateProjectNotesForTeam(
    FirebaseFirestore firestore,
    DocumentReference<Map<String, dynamic>> teamRef,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> projectDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs,
  ) async {
    if (projectDocs.isEmpty || memberDocs.isEmpty) return;

    final noteCollection = teamRef.collection('userProjectNotes');
    var batch = firestore.batch();
    var opCount = 0;

    Future<void> flush() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      opCount = 0;
    }

    for (final projectDoc in projectDocs) {
      final projectId = projectDoc.id;
      for (final memberDoc in memberDocs) {
        final userId = memberDoc.id;
        final v2Ref = noteCollection.doc(
          _privateProjectNoteDocIdV2(projectId, userId),
        );
        batch.delete(v2Ref);
        opCount += 1;

        final legacyRef = noteCollection.doc(
          _privateProjectNoteDocIdLegacy(projectId, userId),
        );
        batch.delete(legacyRef);
        opCount += 1;

        if (opCount >= 400) {
          await flush();
        }
      }
    }

    await flush();
  }

  Future<void> _confirmAndDeleteTeam(
    BuildContext context, {
    required String teamName,
    required String? teamNameKey,
    required String userId,
  }) async {
    if (_deletingTeam) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('팀 삭제'),
        content: Text(
          '"$teamName" 팀을 삭제합니다.\n'
          '프로젝트/메모/초대 등 팀 데이터가 함께 정리되며 되돌릴 수 없습니다.',
        ),
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

    setState(() => _deletingTeam = true);
    final firestore = ref.read(firestoreProvider);
    final teamRef = firestore.collection('teams').doc(widget.teamId);
    final providedNameKey = teamNameKey?.trim() ?? '';
    final resolvedNameKey = providedNameKey.isNotEmpty
        ? providedNameKey
        : buildTeamNameKey(teamName);
    var partialCleanupSkipped = false;
    Future<void> safeCleanup(Future<void> Function() action) async {
      try {
        await action();
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'failed-precondition' ||
            error.code == 'unavailable') {
          partialCleanupSkipped = true;
          return;
        }
        rethrow;
      }
    }

    try {
      var membersDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      await safeCleanup(() async {
        final membersSnapshot = await teamRef.collection('members').get();
        membersDocs = membersSnapshot.docs;
      });
      for (final memberDoc in membersDocs) {
        try {
          await firestore
              .collection('users')
              .doc(memberDoc.id)
              .collection('teamMemberships')
              .doc(widget.teamId)
              .delete();
        } on FirebaseException {
          // best-effort cleanup for mirror docs
        }
      }
      // Ensure current actor mirror is also removed even when members query is stale.
      try {
        await firestore
            .collection('users')
            .doc(userId)
            .collection('teamMemberships')
            .doc(widget.teamId)
            .delete();
      } on FirebaseException {
        // ignore
      }

      var projectsDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      await safeCleanup(() async {
        final projectsSnapshot = await teamRef.collection('projects').get();
        projectsDocs = projectsSnapshot.docs;
      });

      await safeCleanup(
        () => _deleteCollectionDocs(firestore, teamRef.collection('invites')),
      );
      await safeCleanup(
        () =>
            _deleteCollectionDocs(firestore, teamRef.collection('inviteLinks')),
      );
      await safeCleanup(
        () => _deleteCollectionDocs(firestore, teamRef.collection('songRefs')),
      );
      try {
        await _deletePrivateProjectNotesForTeam(
          firestore,
          teamRef,
          projectsDocs,
          membersDocs,
        );
      } on FirebaseException {
        partialCleanupSkipped = true;
      }

      for (final projectDoc in projectsDocs) {
        await safeCleanup(
          () => _deleteCollectionDocs(
            firestore,
            projectDoc.reference.collection('segmentA_setlist'),
          ),
        );
        await safeCleanup(
          () => _deleteCollectionDocs(
            firestore,
            projectDoc.reference.collection('segmentB_application'),
          ),
        );
        await safeCleanup(
          () => _deleteCollectionDocs(
            firestore,
            projectDoc.reference.collection('liveCue'),
          ),
        );
        await safeCleanup(
          () => _deleteCollectionDocs(
            firestore,
            projectDoc.reference.collection('sharedNotes'),
          ),
        );
      }
      await safeCleanup(
        () => _deleteCollectionDocs(firestore, teamRef.collection('projects')),
      );
      if (resolvedNameKey.isNotEmpty) {
        try {
          await firestore
              .collection('teamNameIndex')
              .doc(resolvedNameKey)
              .delete();
        } on FirebaseException {
          // Keep deleting team data even when index cleanup fails.
        }
      }

      await teamRef.delete();
      // Delete members last to keep admin permission checks valid during team doc delete.
      await safeCleanup(
        () => _deleteCollectionDocs(firestore, teamRef.collection('members')),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            partialCleanupSkipped
                ? '팀을 삭제했습니다. 일부 정리 작업은 권한 제약으로 건너뛰었습니다.'
                : '팀을 삭제했습니다.',
          ),
        ),
      );
      context.go('/teams');
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      final message = error.code == 'permission-denied'
          ? '팀 삭제 권한이 없습니다. Firestore Rules 게시 상태와 내 역할(팀장)을 확인해 주세요.'
          : '팀 삭제 실패: ${error.message ?? error.code}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('팀 삭제 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _deletingTeam = false);
      }
    }
  }

  Future<void> _confirmAndDeleteProject(
    BuildContext context, {
    required String projectId,
    required String projectLabel,
  }) async {
    if (_deletingProjectIds.contains(projectId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프로젝트 삭제'),
        content: Text(
          '"$projectLabel" 프로젝트를 삭제합니다.\n'
          '콘티/LiveCue/메모가 함께 정리되며 되돌릴 수 없습니다.',
        ),
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

    setState(() => _deletingProjectIds.add(projectId));
    final firestore = ref.read(firestoreProvider);
    final projectRef = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(projectId);
    try {
      await _deleteCollectionDocs(
        firestore,
        projectRef.collection('segmentA_setlist'),
      );
      await _deleteCollectionDocs(
        firestore,
        projectRef.collection('segmentB_application'),
      );
      await _deleteCollectionDocs(firestore, projectRef.collection('liveCue'));
      await _deleteCollectionDocs(
        firestore,
        projectRef.collection('sharedNotes'),
      );
      await projectRef.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로젝트를 삭제했습니다.')));
      _refreshPageState();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('프로젝트 삭제 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _deletingProjectIds.remove(projectId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = ref.watch(firestoreProvider);
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: const Text('팀 홈'),
        actions: [
          IconButton(
            onPressed: () => _openTeamSwitcher(context, firestore, user.uid),
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: '빠른 팀 전환',
          ),
          IconButton(
            onPressed: () => context.go('/teams'),
            icon: const Icon(Icons.home_rounded),
            tooltip: '홈(팀 전환)',
          ),
          IconButton(
            onPressed: _refreshPageState,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '새로고침',
          ),
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: '로그아웃',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<_TeamContext>(
        future: _contextFuture ?? _loadContext(firestore, user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingState(message: '팀 정보를 불러오는 중...');
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            final canCleanupFromList =
                error is FirebaseException &&
                (error.code == 'permission-denied' ||
                    error.code == 'not-found' ||
                    error.code == 'failed-precondition');
            if (canCleanupFromList) {
              return AppContentFrame(
                child: AppStateCard(
                  icon: Icons.groups_2_outlined,
                  isError: true,
                  title: '팀 정보를 찾을 수 없습니다',
                  message: '이미 삭제된 팀이거나 접근 권한이 제거되었습니다. 내 목록에서 정리해 주세요.',
                  actionLabel: '내 목록에서 제거',
                  onAction: () =>
                      _removeCurrentTeamFromMyList(context, user.uid),
                ),
              );
            }
            return AppContentFrame(
              child: AppStateCard(
                icon: Icons.error_outline,
                isError: true,
                title: '팀 정보를 불러오지 못했습니다',
                message: '${snapshot.error}',
                actionLabel: '다시 시도',
                onAction: _refreshPageState,
              ),
            );
          }
          final contextData = snapshot.data;
          if (contextData == null || contextData.team.data() == null) {
            return AppContentFrame(
              child: AppStateCard(
                icon: Icons.groups_2_outlined,
                isError: true,
                title: '팀 정보를 찾을 수 없습니다',
                message: '이미 삭제된 팀일 수 있습니다. 내 팀 목록에서 이 항목을 제거해 주세요.',
                actionLabel: '내 목록에서 제거',
                onAction: () => _removeCurrentTeamFromMyList(context, user.uid),
              ),
            );
          }
          if (!contextData.member.exists) {
            return AppContentFrame(
              child: AppStateCard(
                icon: Icons.lock_outline_rounded,
                isError: true,
                title: '팀 접근 권한이 없습니다',
                message: '권한이 제거되었거나 팀이 정리된 상태입니다. 내 목록에서 제거해 주세요.',
                actionLabel: '내 목록에서 제거',
                onAction: () => _removeCurrentTeamFromMyList(context, user.uid),
              ),
            );
          }

          final teamData = contextData.team.data()!;
          final teamName = teamData['name']?.toString() ?? '팀';
          final lastProjectId = (teamData['lastProjectId'] ?? '')
              .toString()
              .trim();
          final membersFuture = _membersFuture ??= _loadMembers(firestore);
          final projectsFuture = _projectsFuture ??= _loadProjects(firestore);
          final currentUserRole = _normalizeRole(
            contextData.member.data()?['role']?.toString(),
          );
          final isAdmin = currentUserRole == 'admin';

          final roleManagementSection = AppSectionCard(
            icon: Icons.admin_panel_settings_rounded,
            title: '팀원 권한 관리',
            subtitle: '팀장이 팀원 역할(팀장/인도자/팀원)을 직접 지정합니다.',
            child:
                FutureBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>
                >(
                  future: membersFuture,
                  builder: (context, memberSnapshot) {
                    final syncing =
                        memberSnapshot.connectionState ==
                        ConnectionState.waiting;
                    final members = memberSnapshot.data ?? [];
                    if (memberSnapshot.hasError) {
                      return AppStateCard(
                        icon: Icons.groups_2_outlined,
                        isError: true,
                        title: '팀원 목록 로드 실패',
                        message: '${memberSnapshot.error}',
                        actionLabel: '다시 시도',
                        onAction: _refreshPageState,
                      );
                    }
                    if (members.isEmpty) {
                      return AppStateCard(
                        icon: syncing
                            ? Icons.sync_rounded
                            : Icons.person_off_outlined,
                        title: syncing ? '팀원 목록 동기화 중...' : '팀원이 없습니다',
                        message: syncing
                            ? '잠시 후 자동으로 갱신됩니다. 오래 지속되면 새로고침을 눌러 주세요.'
                            : '먼저 팀원을 초대한 뒤 권한을 지정하세요.',
                        actionLabel: syncing ? '새로고침' : null,
                        onAction: syncing ? _refreshPageState : null,
                      );
                    }

                    final sortedMembers = [...members]
                      ..sort((a, b) {
                        final aName = memberDisplayNameWithFallback(
                          a.id,
                          a.data(),
                        );
                        final bName = memberDisplayNameWithFallback(
                          b.id,
                          b.data(),
                        );
                        return aName.compareTo(bName);
                      });

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '프로젝트 편집 권한은 프로젝트 인도자 또는 팀장에게 부여됩니다.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sortedMembers.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final member = sortedMembers[index];
                            final data = member.data();
                            final displayName = memberDisplayNameWithFallback(
                              member.id,
                              data,
                            );
                            final email = (data['email'] ?? '')
                                .toString()
                                .trim();
                            final currentRole = _normalizeRole(
                              data['role']?.toString(),
                            );
                            final updating = _roleUpdatingUserIds.contains(
                              member.id,
                            );
                            final isSelf = member.id == user.uid;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.52),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isSelf
                                              ? '$displayName (나)'
                                              : displayName,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        if (email.isNotEmpty)
                                          Text(
                                            email,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (updating)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    DropdownButton<String>(
                                      value: currentRole,
                                      onChanged: (value) {
                                        if (value == null) return;
                                        _updateMemberRole(
                                          context: context,
                                          actorUserId: user.uid,
                                          targetUserId: member.id,
                                          nextRole: value,
                                          members: members,
                                        );
                                      },
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'admin',
                                          child: Text('팀장'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'leader',
                                          child: Text('인도자'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'member',
                                          child: Text('팀원'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
          );

          final projectsSection = AppSectionCard(
            icon: Icons.calendar_month_rounded,
            title: '프로젝트',
            subtitle: '예배 날짜 기준으로 생성하고, 바로 콘티/LiveCue로 진입합니다.',
            trailing: FilledButton.icon(
              onPressed: !isAdmin
                  ? null
                  : () => _openCreateProjectDialog(context, firestore),
              icon: const Icon(Icons.add),
              label: const Text('프로젝트 생성'),
            ),
            child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              future: projectsFuture,
              builder: (context, projectSnapshot) {
                final syncing =
                    projectSnapshot.connectionState == ConnectionState.waiting;
                if (projectSnapshot.hasError) {
                  return AppStateCard(
                    icon: Icons.event_busy_outlined,
                    isError: true,
                    title: '프로젝트 목록 로드 실패',
                    message: '${projectSnapshot.error}',
                    actionLabel: '다시 시도',
                    onAction: _refreshPageState,
                  );
                }
                final projects = <QueryDocumentSnapshot<Map<String, dynamic>>>[
                  ...(projectSnapshot.data ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[]),
                ]..sort(_compareProjects);
                if (projects.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (syncing)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '프로젝트 목록 동기화 중... 데이터 도착 전에는 비어 보일 수 있습니다.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      AppStateCard(
                        icon: Icons.playlist_add_outlined,
                        title: syncing ? '프로젝트 동기화 중...' : '아직 프로젝트가 없습니다',
                        message: syncing
                            ? '잠시 후 자동으로 갱신됩니다. 오래 지속되면 새로고침을 눌러 주세요.'
                            : (isAdmin
                                  ? '프로젝트 생성 버튼으로 첫 프로젝트를 만들어 주세요.'
                                  : '팀장이 프로젝트를 생성하면 여기에서 바로 진입할 수 있습니다.'),
                        actionLabel: syncing ? '새로고침' : null,
                        onAction: syncing ? _refreshPageState : null,
                      ),
                      if (lastProjectId.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => _openRecentProject(
                            context,
                            firestore,
                            lastProjectId,
                          ),
                          icon: const Icon(Icons.history_rounded),
                          label: Text('최근 프로젝트 열기 ($lastProjectId)'),
                        ),
                      ],
                    ],
                  );
                }
                return FutureBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>
                >(
                  future: membersFuture,
                  builder: (context, memberSnapshot) {
                    final members =
                        memberSnapshot.data ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (memberSnapshot.connectionState ==
                            ConnectionState.waiting)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '팀원 정보 동기화 중... 프로젝트 목록은 먼저 표시됩니다.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (memberSnapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              "팀원 정보 로드 실패: 인도자 이름은 '이름 확인 중'으로 표시됩니다.",
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: projects.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final doc = projects[index];
                            final data = doc.data();
                            final title = (data['title']?.toString() ?? '')
                                .trim();
                            final date = (data['date']?.toString() ?? doc.id)
                                .trim();
                            final projectLabel = title.isEmpty
                                ? date
                                : '$date $title';
                            final mappedLeaderName = _memberName(
                              data['leaderUserId']?.toString(),
                              members,
                            );
                            final leaderNickname =
                                (data['leaderNickname'] ?? '')
                                    .toString()
                                    .trim();
                            final leaderDisplayName =
                                (data['leaderDisplayName'] ?? '')
                                    .toString()
                                    .trim();
                            final leaderName =
                                (mappedLeaderName == '이름 확인 중' ||
                                    mappedLeaderName == '-')
                                ? (leaderNickname.isNotEmpty
                                      ? leaderNickname
                                      : (leaderDisplayName.isNotEmpty
                                            ? leaderDisplayName
                                            : mappedLeaderName))
                                : mappedLeaderName;
                            final deletingProject = _deletingProjectIds
                                .contains(doc.id);
                            final canDeleteProject =
                                isAdmin ||
                                data['leaderUserId']?.toString() == user.uid;
                            return Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                title: Text(projectLabel),
                                subtitle: Text('인도자: $leaderName'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isAdmin)
                                      IconButton(
                                        onPressed: () => _openEditLeadersDialog(
                                          context,
                                          doc.id,
                                          data,
                                        ),
                                        icon: const Icon(Icons.manage_accounts),
                                        tooltip: '인도자 변경',
                                      ),
                                    if (canDeleteProject)
                                      IconButton(
                                        onPressed: deletingProject
                                            ? null
                                            : () => _confirmAndDeleteProject(
                                                context,
                                                projectId: doc.id,
                                                projectLabel: projectLabel,
                                              ),
                                        icon: deletingProject
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.delete_outline),
                                        tooltip: '프로젝트 삭제',
                                      ),
                                    IconButton(
                                      onPressed: () => context.go(
                                        '/teams/${widget.teamId}/projects/${doc.id}',
                                      ),
                                      icon: const Icon(Icons.chevron_right),
                                      tooltip: '프로젝트 이동',
                                    ),
                                  ],
                                ),
                                onTap: () => context.go(
                                  '/teams/${widget.teamId}/projects/${doc.id}',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          );

          final inviteSection = AppSectionCard(
            icon: Icons.person_add_alt_rounded,
            title: '팀원 초대',
            subtitle: '이메일 또는 카카오 링크로 참여를 요청합니다.',
            child: TeamInvitePanel(
              teamId: widget.teamId,
              teamName: teamName,
              isAdmin: isAdmin,
            ),
          );

          final teamSummarySection = AppSectionCard(
            icon: Icons.settings_input_component_rounded,
            title: '$teamName 워크스페이스',
            subtitle: '팀 ID: ${widget.teamId}',
            trailing: isAdmin
                ? FilledButton.tonalIcon(
                    onPressed: _deletingTeam
                        ? null
                        : () => _confirmAndDeleteTeam(
                            context,
                            teamName: teamName,
                            teamNameKey: teamData['nameKey']?.toString(),
                            userId: user.uid,
                          ),
                    icon: _deletingTeam
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_forever_rounded),
                    label: Text(_deletingTeam ? '삭제 중...' : '팀 삭제'),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.group, size: 16),
                      label: Text('내 역할: ${_roleLabel(currentUserRole)}'),
                    ),
                    const Chip(
                      avatar: Icon(Icons.auto_awesome, size: 16),
                      label: Text('콘티 입력 시 LiveCue 자동 반영'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '팀원 초대 → 프로젝트 생성 → 콘티 입력 → LiveCue/악보보기',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );

          final librarySection = AppSectionCard(
            icon: Icons.library_music_rounded,
            title: '팀 곡 라이브러리',
            subtitle: '팀에서 사용하는 곡 연결/검색/악보 열기',
            child: SongLibraryPanel(teamId: widget.teamId),
          );

          return AppContentFrame(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1180;
                final metricCards = [
                  Expanded(
                    child:
                        FutureBuilder<
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >(
                          future: membersFuture,
                          builder: (context, snapshot) {
                            final count = snapshot.data?.length;
                            return _MetricCard(
                              icon: Icons.groups_3_rounded,
                              title: '팀원',
                              value: count == null ? '-' : '$count명',
                              helper: '현재 팀 참여 인원',
                            );
                          },
                        ),
                  ),
                  Expanded(
                    child:
                        FutureBuilder<
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >(
                          future: projectsFuture,
                          builder: (context, snapshot) {
                            final count = snapshot.data?.length;
                            return _MetricCard(
                              icon: Icons.event_note_rounded,
                              title: '프로젝트',
                              value: count == null ? '-' : '$count개',
                              helper: '예배 날짜 단위 운영',
                            );
                          },
                        ),
                  ),
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.verified_user_rounded,
                      title: '내 역할',
                      value: _roleLabel(currentUserRole),
                      helper: isAdmin ? '권한/멤버 관리 가능' : '프로젝트 참여',
                    ),
                  ),
                ];

                return ListView(
                  children: [
                    AppHeroPanel(
                      title: '$teamName 운영',
                      subtitle: isAdmin
                          ? '팀장 화면입니다. 팀원 초대, 역할 지정, 프로젝트 생성을 진행하세요.'
                          : '내 역할: ${_roleLabel(currentUserRole)} · 팀장이 만든 프로젝트에 바로 참여할 수 있습니다.',
                      icon: Icons.groups_rounded,
                      actions: [
                        FilledButton.tonalIcon(
                          onPressed: () => context.go('/teams'),
                          icon: const Icon(Icons.home),
                          label: const Text('팀 전환'),
                        ),
                        if (lastProjectId.isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: () => _openRecentProject(
                              context,
                              firestore,
                              lastProjectId,
                            ),
                            icon: const Icon(Icons.history_rounded),
                            label: Text('최근 프로젝트 $lastProjectId'),
                          ),
                        if (isAdmin)
                          FilledButton.icon(
                            onPressed: () =>
                                _openCreateProjectDialog(context, firestore),
                            icon: const Icon(Icons.add),
                            label: const Text('프로젝트 생성'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          metricCards[0],
                          const SizedBox(width: 10),
                          metricCards[1],
                          const SizedBox(width: 10),
                          metricCards[2],
                        ],
                      )
                    else
                      Column(
                        children: [
                          metricCards[0],
                          const SizedBox(height: 10),
                          metricCards[1],
                          const SizedBox(height: 10),
                          metricCards[2],
                        ],
                      ),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(
                              children: [
                                teamSummarySection,
                                const SizedBox(height: 16),
                                projectsSection,
                                const SizedBox(height: 16),
                                librarySection,
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                if (isAdmin) ...[
                                  inviteSection,
                                  const SizedBox(height: 16),
                                  roleManagementSection,
                                ] else
                                  AppStateCard(
                                    icon: Icons.verified_user_outlined,
                                    title: '현재 권한',
                                    message:
                                        '내 역할은 ${_roleLabel(currentUserRole)}입니다. 권한 변경은 팀장이 수행합니다.',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      teamSummarySection,
                      const SizedBox(height: 16),
                      projectsSection,
                      const SizedBox(height: 16),
                      if (isAdmin) ...[
                        inviteSection,
                        const SizedBox(height: 16),
                        roleManagementSection,
                        const SizedBox(height: 16),
                      ],
                      librarySection,
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CreateProjectDialog extends ConsumerStatefulWidget {
  final String teamId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> members;

  const _CreateProjectDialog({required this.teamId, required this.members});

  @override
  ConsumerState<_CreateProjectDialog> createState() =>
      _CreateProjectDialogState();
}

class _CreateProjectDialogState extends ConsumerState<_CreateProjectDialog> {
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _rehearsalController = TextEditingController();
  String? _leaderUserId;
  bool _saving = false;

  @override
  void dispose() {
    _dateController.dispose();
    _titleController.dispose();
    _rehearsalController.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final rawDate = _dateController.text.trim();
    final date = rawDate
        .replaceAll('/', '.')
        .replaceAll('-', '.')
        .replaceAll(RegExp(r'\s+'), '');
    final title = _titleController.text.trim();
    if (date.isEmpty) return;
    if (date.contains(RegExp(r'[?#\[\]\\]'))) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예배 날짜에 사용할 수 없는 문자가 포함되어 있습니다.')),
      );
      return;
    }
    if (date.length > 40) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예배 날짜 문자열은 40자 이내로 입력해 주세요.')),
      );
      return;
    }

    final firestore = ref.read(firestoreProvider);
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final leaderId = _leaderUserId ?? user.uid;
      final leaderMember = widget.members
          .where((doc) => doc.id == leaderId)
          .firstOrNull;
      final leaderData = leaderMember?.data();
      final leaderDisplayName = memberDisplayNameWithFallback(
        leaderId,
        leaderData ?? const <String, dynamic>{},
      );
      final leaderNickname = (leaderData?['nickname'] ?? '').toString().trim();

      final projectRef = firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(date);
      final teamRef = firestore.collection('teams').doc(widget.teamId);
      final existing = await projectRef.get();
      if (existing.exists) {
        await teamRef.set({
          'lastProjectId': date,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (!context.mounted) return;
        // Same date project already exists: open existing project instead of blocking.
        Navigator.of(context).pop(date);
        return;
      }

      final payload = <String, dynamic>{
        'date': date,
        'rehearsalInfo': _rehearsalController.text.trim(),
        'leaderUserId': leaderId,
        'leaderDisplayName': leaderDisplayName,
        if (leaderNickname.isNotEmpty) 'leaderNickname': leaderNickname,
        'speakerUserId': leaderId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (title.isNotEmpty) {
        payload['title'] = title;
      }

      final batch = firestore.batch();
      batch.set(projectRef, payload);
      batch.set(teamRef, {
        'lastProjectId': date,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(projectRef.collection('liveCue').doc('state'), {
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        firestore
            .collection('teams')
            .doc(widget.teamId)
            .collection('members')
            .doc(leaderId),
        {
          'capabilities': {'songEditor': true},
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      if (!context.mounted) return;
      Navigator.of(context).pop(date);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('프로젝트 생성 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    return AlertDialog(
      title: const Text('프로젝트 생성'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _dateController,
              decoration: appInputDecoration(
                context,
                label: '예배 날짜',
                hint: '예: 2026.02.08',
                helper: '팀 안에서 예배 날짜 기준 프로젝트를 생성합니다.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: appInputDecoration(
                context,
                label: '제목 (선택)',
                hint: '비워두면 날짜만 표시됩니다.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rehearsalController,
              decoration: appInputDecoration(context, label: '리허설 공지 (옵션)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _leaderUserId,
              items: members
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc.id,
                      child: Text(
                        memberDisplayNameWithFallback(doc.id, doc.data()),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _leaderUserId = value),
              decoration: appInputDecoration(context, label: '인도자 (예배 전)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : () => _save(context),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('생성'),
        ),
      ],
    );
  }
}

class _EditProjectLeadersDialog extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> members;
  final String? initialLeaderUserId;

  const _EditProjectLeadersDialog({
    required this.teamId,
    required this.projectId,
    required this.members,
    required this.initialLeaderUserId,
  });

  @override
  ConsumerState<_EditProjectLeadersDialog> createState() =>
      _EditProjectLeadersDialogState();
}

class _EditProjectLeadersDialogState
    extends ConsumerState<_EditProjectLeadersDialog> {
  String? _leaderUserId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _leaderUserId = widget.initialLeaderUserId;
  }

  Future<void> _save(BuildContext context) async {
    final leaderId = _leaderUserId;
    if (leaderId == null) return;
    final leaderMember = widget.members
        .where((doc) => doc.id == leaderId)
        .firstOrNull;
    final leaderData = leaderMember?.data();
    final leaderDisplayName = memberDisplayNameWithFallback(
      leaderId,
      leaderData ?? const <String, dynamic>{},
    );
    final leaderNickname = (leaderData?['nickname'] ?? '').toString().trim();

    setState(() => _saving = true);
    final firestore = ref.read(firestoreProvider);
    try {
      await firestore
          .collection('teams')
          .doc(widget.teamId)
          .collection('projects')
          .doc(widget.projectId)
          .update({
            'leaderUserId': leaderId,
            'leaderDisplayName': leaderDisplayName,
            'leaderNickname': leaderNickname.isNotEmpty
                ? leaderNickname
                : FieldValue.delete(),
            'speakerUserId': leaderId,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!context.mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('인도자 변경 실패: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    return AlertDialog(
      title: const Text('인도자 변경'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _leaderUserId,
              items: members
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc.id,
                      child: Text(
                        memberDisplayNameWithFallback(doc.id, doc.data()),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _leaderUserId = value),
              decoration: appInputDecoration(context, label: '인도자'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : () => _save(context),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('저장'),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String helper;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.82),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(helper, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamContext {
  final DocumentSnapshot<Map<String, dynamic>> team;
  final DocumentSnapshot<Map<String, dynamic>> member;

  const _TeamContext({required this.team, required this.member});
}

class _TeamOption {
  final String id;
  final String name;

  const _TeamOption({required this.id, required this.name});
}
