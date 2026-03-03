import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';
import 'live_cue_page.dart';
import 'segment_a_page.dart';
import 'segment_b_page.dart';

class ProjectDetailPage extends ConsumerWidget {
  final String teamId;
  final String projectId;

  const ProjectDetailPage({
    super.key,
    required this.teamId,
    required this.projectId,
  });

  Future<_ProjectContext> _loadContext(
    FirebaseFirestore firestore,
    String userId,
    User user,
  ) async {
    final projectRef = firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId);
    final teamRef = firestore.collection('teams').doc(teamId);
    final memberRef = firestore
        .collection('teams')
        .doc(teamId)
        .collection('members')
        .doc(userId);

    final project = await projectRef.get().timeout(const Duration(seconds: 12));
    var member = await memberRef.get().timeout(const Duration(seconds: 12));
    final team = await teamRef.get().timeout(const Duration(seconds: 12));
    final createdBy = (team.data()?['createdBy'] ?? '').toString();
    if (!member.exists && team.exists && createdBy == userId) {
      // Keep creator access resilient when legacy member docs are missing.
      await memberRef.set({
        'userId': userId,
        'uid': userId,
        'email': user.email?.toLowerCase(),
        'displayName': user.displayName,
        'nickname': null,
        'role': 'admin',
        'teamName': (team.data()?['name'] ?? '팀').toString(),
        'capabilities': {'songEditor': true},
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await teamRef.set({
        'memberUids': FieldValue.arrayUnion([userId]),
      }, SetOptions(merge: true));
      member = await memberRef.get().timeout(const Duration(seconds: 12));
    }

    return _ProjectContext(project: project, member: member);
  }

  Future<String?> _resolveFallbackProjectId(FirebaseFirestore firestore) async {
    try {
      final snapshot = await firestore
          .collection('teams')
          .doc(teamId)
          .collection('projects')
          .orderBy('date', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 12));
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.id;
      }
    } on FirebaseException {
      // Ignore and return null below.
    } on TimeoutException {
      // Ignore and return null below.
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    final firestore = ref.watch(firestoreProvider);

    return FutureBuilder<_ProjectContext>(
      future: _loadContext(firestore, user.uid, user),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: AppLoadingState(message: '프로젝트 로딩 중...'));
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is FirebaseException &&
              (error.code == 'permission-denied' ||
                  error.code == 'not-found' ||
                  error.code == 'failed-precondition')) {
            return Scaffold(
              body: AppContentFrame(
                child: AppStateCard(
                  icon: Icons.lock_outline_rounded,
                  isError: true,
                  title: '프로젝트 정보를 찾을 수 없습니다',
                  message: '삭제되었거나 접근 권한이 없습니다. 팀 목록에서 다시 선택해 주세요.',
                  actionLabel: '팀 목록으로',
                  onAction: () => context.go('/teams'),
                ),
              ),
            );
          }
          return Scaffold(
            body: AppContentFrame(
              child: AppStateCard(
                icon: Icons.error_outline,
                isError: true,
                title: '프로젝트 정보를 불러오지 못했습니다',
                message: '${snapshot.error}',
              ),
            ),
          );
        }
        final contextData = snapshot.data;
        if (contextData == null || contextData.project.data() == null) {
          return Scaffold(
            body: AppContentFrame(
              child: FutureBuilder<String?>(
                future: _resolveFallbackProjectId(firestore),
                builder: (context, fallbackSnapshot) {
                  final fallbackId = fallbackSnapshot.data;
                  return AppStateCard(
                    icon: Icons.find_in_page_outlined,
                    isError: true,
                    title: '프로젝트를 찾을 수 없습니다',
                    message: fallbackId == null
                        ? '팀 화면으로 돌아가 프로젝트를 다시 선택해 주세요.'
                        : '요청한 프로젝트가 없어 최신 프로젝트($fallbackId)로 이동할 수 있습니다.',
                    actionLabel: fallbackId == null ? '팀 홈으로' : '최신 프로젝트 열기',
                    onAction: () {
                      if (fallbackId == null) {
                        context.go('/teams/$teamId');
                        return;
                      }
                      context.go('/teams/$teamId/projects/$fallbackId');
                    },
                  );
                },
              ),
            ),
          );
        }
        if (!contextData.member.exists) {
          return Scaffold(
            body: AppContentFrame(
              child: AppStateCard(
                icon: Icons.lock_outline_rounded,
                isError: true,
                title: '프로젝트 접근 권한이 없습니다',
                message: '이 팀의 멤버만 프로젝트를 볼 수 있습니다.',
                actionLabel: '팀 목록으로',
                onAction: () => context.go('/teams'),
              ),
            ),
          );
        }

        final projectData = contextData.project.data()!;
        final projectDate = (projectData['date']?.toString() ?? projectId)
            .trim();
        final projectTitle = (projectData['title']?.toString() ?? '').trim();
        final projectLabel = projectTitle.isEmpty
            ? projectDate
            : '$projectDate $projectTitle';
        final leaderId = projectData['leaderUserId']?.toString();
        final isLeader = leaderId == user.uid;
        final role = contextData.member.data()?['role']?.toString();
        final normalizedRole = (role ?? '').trim().toLowerCase();
        final isAdmin =
            normalizedRole == 'admin' ||
            normalizedRole == 'owner' ||
            normalizedRole == 'team_admin' ||
            normalizedRole == '팀장';
        final canEdit = isLeader || isAdmin;
        final roleLabel = isAdmin ? '팀장' : (isLeader ? '인도자' : '팀원');

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('프로젝트'),
              actions: [
                IconButton(
                  onPressed: () => context.go(
                    '/teams/$teamId/projects/$projectId/live?memo=1',
                  ),
                  tooltip: '악보 메모 레이어',
                  icon: const Icon(Icons.sticky_note_2_outlined),
                ),
                IconButton(
                  onPressed: () =>
                      context.go('/teams/$teamId/projects/$projectId/live'),
                  tooltip: '악보보기',
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
                IconButton(
                  onPressed: () => context.go('/teams/$teamId'),
                  tooltip: '팀 홈',
                  icon: const Icon(Icons.home_rounded),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: [
                  AppHeroPanel(
                    title: projectLabel,
                    subtitle: '팀 역할: $roleLabel · 콘티 입력 후 LiveCue/악보보기로 진행',
                    icon: Icons.event_available_rounded,
                    actions: [
                      FilledButton.tonalIcon(
                        onPressed: () => context.go('/teams/$teamId'),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('팀 홈'),
                      ),
                      FilledButton.icon(
                        onPressed: () => context.go(
                          '/teams/$teamId/projects/$projectId/live',
                        ),
                        icon: const Icon(Icons.fullscreen_rounded),
                        label: const Text('악보보기'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => context.go(
                          '/teams/$teamId/projects/$projectId/live?memo=1',
                        ),
                        icon: const Icon(Icons.sticky_note_2_outlined),
                        label: const Text('메모 레이어'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const TabBar(
                      tabs: [
                        Tab(text: '예배 전'),
                        Tab(text: '적용찬양'),
                        Tab(text: 'LiveCue'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        SegmentAPage(
                          teamId: teamId,
                          projectId: projectId,
                          canEdit: canEdit,
                        ),
                        SegmentBPage(
                          teamId: teamId,
                          projectId: projectId,
                          canEdit: canEdit,
                        ),
                        LiveCuePage(
                          teamId: teamId,
                          projectId: projectId,
                          canEdit: canEdit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProjectContext {
  final DocumentSnapshot<Map<String, dynamic>> project;
  final DocumentSnapshot<Map<String, dynamic>> member;

  const _ProjectContext({required this.project, required this.member});
}
