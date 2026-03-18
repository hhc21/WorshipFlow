import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui_components.dart';
import '../../core/ops/ops_metrics.dart';
import '../../core/roles.dart';
import '../../services/firebase_providers.dart';
import '../../services/ops_metrics.dart';
import 'live_cue_page.dart';
import 'project_delete_helpers.dart';
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
    final member = await memberRef.get().timeout(const Duration(seconds: 12));
    final team = await teamRef.get().timeout(const Duration(seconds: 12));
    final createdBy = (team.data()?['createdBy'] ?? '').toString();
    final isTeamCreator = team.exists && createdBy == userId;

    return _ProjectContext(
      project: project,
      member: member,
      isTeamCreator: isTeamCreator,
    );
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

  Future<void> _confirmAndDeleteProject(
    BuildContext context,
    WidgetRef ref, {
    required String projectLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프로젝트 삭제'),
        content: Text(
          '"$projectLabel" 프로젝트를 즉시 삭제합니다.\n'
          '콘티, LiveCue 상태, 메모 레이어가 함께 삭제되며 되돌릴 수 없습니다.',
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

    final firestore = ref.read(firestoreProvider);
    final currentUserId = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    if (currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 정보가 없어 프로젝트를 삭제할 수 없습니다.')),
      );
      return;
    }

    unawaited(
      logTeamOpsMetric(
        firestore: firestore,
        teamId: teamId,
        category: 'delete',
        action: 'project_delete',
        status: 'started',
        extra: <String, Object?>{'projectId': projectId},
      ),
    );

    try {
      await deleteProjectDirectly(
        firestore: firestore,
        teamId: teamId,
        projectId: projectId,
      );
      unawaited(
        logTeamOpsMetric(
          firestore: firestore,
          teamId: teamId,
          category: 'delete',
          action: 'project_delete',
          status: 'deleted',
          extra: <String, Object?>{'projectId': projectId},
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로젝트를 삭제했습니다.')));
      context.go('/teams/$teamId');
    } on FirebaseException catch (error) {
      unawaited(
        logTeamOpsMetric(
          firestore: firestore,
          teamId: teamId,
          category: 'delete',
          action: 'project_delete',
          status: 'failed',
          code: error.code,
          extra: <String, Object?>{'projectId': projectId},
        ),
      );
      if (!context.mounted) return;
      final message = error.code == 'permission-denied'
          ? '프로젝트 삭제 권한이 없습니다.'
          : '프로젝트 삭제 실패: ${error.message ?? error.code}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      unawaited(
        logTeamOpsMetric(
          firestore: firestore,
          teamId: teamId,
          category: 'delete',
          action: 'project_delete',
          status: 'failed',
          code: 'unknown',
          extra: <String, Object?>{
            'projectId': projectId,
            'error': error.toString(),
          },
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('프로젝트 삭제 실패: $error')));
    }
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
      future: _loadContext(firestore, user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: AppLoadingState(message: '프로젝트 로딩 중...'));
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          OpsMetrics.firestoreSnapshotError(
            fields: <String, Object?>{
              'teamId': teamId,
              'projectId': projectId,
              'scope': 'project_context',
              'error': error.toString(),
            },
          );
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
          OpsMetrics.runtimeGuardTriggered(
            guard: 'project_context_missing',
            fields: <String, Object?>{'teamId': teamId, 'projectId': projectId},
          );
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
        if (!contextData.member.exists && !contextData.isTeamCreator) {
          OpsMetrics.runtimeGuardTriggered(
            guard: 'project_access_denied_non_member',
            fields: <String, Object?>{
              'teamId': teamId,
              'projectId': projectId,
              'uid': user.uid,
            },
          );
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
        final isProjectLeader = leaderId == user.uid;
        final role = contextData.member.data()?['role']?.toString();
        final isAdmin = contextData.isTeamCreator || isAdminRole(role);
        final canEdit = isProjectLeader || isAdmin;
        final roleLabel = isAdmin ? '팀장' : (isProjectLeader ? '인도자' : '팀원');

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
                      if (isProjectLeader)
                        FilledButton.tonalIcon(
                          onPressed: () => _confirmAndDeleteProject(
                            context,
                            ref,
                            projectLabel: projectLabel,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('프로젝트 삭제'),
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
  final bool isTeamCreator;

  const _ProjectContext({
    required this.project,
    required this.member,
    required this.isTeamCreator,
  });
}
