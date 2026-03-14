import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'ui_components.dart';
import '../core/ops/ops_metrics.dart';
import '../core/runtime/runtime_guard.dart';
import '../features/admin/global_admin_page.dart';
import '../features/auth/sign_in_page.dart';
import '../features/projects/live_cue_page.dart';
import '../features/projects/project_detail_page.dart';
import '../features/songs/song_detail_page.dart';
import '../features/teams/team_home_page.dart';
import '../features/teams/team_select_page.dart';
import '../services/firebase_providers.dart';

bool _isSafeRedirectPath(String candidate) {
  if (candidate.isEmpty ||
      !candidate.startsWith('/') ||
      candidate.startsWith('//')) {
    return false;
  }
  final parsed = Uri.tryParse(candidate);
  if (parsed == null) return false;
  if (parsed.hasScheme || parsed.hasAuthority) return false;
  return true;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final authState = ref.watch(authStateProvider);
  final firestore = ref.watch(firestoreProvider);
  final isLoading = authState.isLoading;
  final user = authState.valueOrNull;

  return GoRouter(
    initialLocation: '/teams',
    refreshListenable: _AuthRefresh(auth),
    redirect: (context, state) {
      if (isLoading) return null;
      final loggingIn = state.matchedLocation == '/sign-in';
      if (user == null) {
        if (loggingIn) return null;
        final target = state.uri.toString();
        return '/sign-in?redirect=${Uri.encodeComponent(target)}';
      }
      if (loggingIn) {
        final redirectTo = state.uri.queryParameters['redirect'];
        if (redirectTo != null &&
            redirectTo.isNotEmpty &&
            _isSafeRedirectPath(redirectTo)) {
          return redirectTo;
        }
        return '/teams';
      }
      return null;
    },
    errorBuilder: (context, state) => _RouteErrorPage(
      title: '경로를 찾을 수 없습니다',
      message: '요청한 화면 경로가 잘못되었거나 더 이상 유효하지 않습니다.',
      actionLabel: '팀 목록으로 이동',
      onAction: () => context.go('/teams'),
    ),
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const GlobalAdminRoutePage(),
      ),
      GoRoute(
        path: '/teams',
        builder: (context, state) => TeamSelectPage(
          inviteTeamId: state.uri.queryParameters['inviteTeam'],
          inviteCode: state.uri.queryParameters['inviteCode'],
        ),
        routes: [
          GoRoute(
            path: ':teamId',
            builder: (context, state) {
              final teamId = RuntimeGuard.guardFirestoreId(
                state.pathParameters['teamId'],
                field: 'teamId',
                route: '/teams/:teamId',
              );
              if (teamId == null) {
                return _RouteErrorPage(
                  title: '잘못된 팀 경로',
                  message: '팀 ID가 올바르지 않습니다. 팀 목록에서 다시 선택해 주세요.',
                  actionLabel: '팀 목록으로 이동',
                  onAction: () => context.go('/teams'),
                );
              }
              return _RouteDocumentGuard(
                load: () => firestore.collection('teams').doc(teamId).get(),
                loadingMessage: '팀 정보를 확인하는 중...',
                notFoundTitle: '팀을 찾을 수 없습니다',
                notFoundMessage: '삭제되었거나 접근 권한이 없는 팀입니다.',
                child: TeamHomePage(teamId: teamId),
              );
            },
            routes: [
              GoRoute(
                path: 'projects/:projectId',
                builder: (context, state) {
                  final teamId = RuntimeGuard.guardFirestoreId(
                    state.pathParameters['teamId'],
                    field: 'teamId',
                    route: '/teams/:teamId/projects/:projectId',
                  );
                  final projectId = RuntimeGuard.guardFirestoreId(
                    state.pathParameters['projectId'],
                    field: 'projectId',
                    route: '/teams/:teamId/projects/:projectId',
                  );
                  if (teamId == null || projectId == null) {
                    return _RouteErrorPage(
                      title: '잘못된 프로젝트 경로',
                      message: '팀 또는 프로젝트 ID가 올바르지 않습니다.',
                      actionLabel: '팀 목록으로 이동',
                      onAction: () => context.go('/teams'),
                    );
                  }
                  return _RouteDocumentGuard(
                    load: () => firestore
                        .collection('teams')
                        .doc(teamId)
                        .collection('projects')
                        .doc(projectId)
                        .get(),
                    loadingMessage: '프로젝트 정보를 확인하는 중...',
                    notFoundTitle: '프로젝트를 찾을 수 없습니다',
                    notFoundMessage: '삭제되었거나 접근 권한이 없습니다.',
                    child: ProjectDetailPage(
                      teamId: teamId,
                      projectId: projectId,
                    ),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'live',
                    builder: (context, state) {
                      final teamId = RuntimeGuard.guardFirestoreId(
                        state.pathParameters['teamId'],
                        field: 'teamId',
                        route: '/teams/:teamId/projects/:projectId/live',
                      );
                      final projectId = RuntimeGuard.guardFirestoreId(
                        state.pathParameters['projectId'],
                        field: 'projectId',
                        route: '/teams/:teamId/projects/:projectId/live',
                      );
                      if (teamId == null || projectId == null) {
                        return _RouteErrorPage(
                          title: '잘못된 LiveCue 경로',
                          message: '팀 또는 프로젝트 ID가 올바르지 않습니다.',
                          actionLabel: '팀 목록으로 이동',
                          onAction: () => context.go('/teams'),
                        );
                      }
                      final startInDrawMode =
                          state.uri.queryParameters['memo'] == '1';
                      return _RouteDocumentGuard(
                        load: () => firestore
                            .collection('teams')
                            .doc(teamId)
                            .collection('projects')
                            .doc(projectId)
                            .get(),
                        loadingMessage: 'LiveCue 프로젝트를 확인하는 중...',
                        notFoundTitle: 'LiveCue 프로젝트를 찾을 수 없습니다',
                        notFoundMessage: '삭제되었거나 접근 권한이 없습니다.',
                        child: LiveCueFullScreenPage(
                          teamId: teamId,
                          projectId: projectId,
                          startInDrawMode: startInDrawMode,
                          entryStartedAtEpochMs:
                              DateTime.now().millisecondsSinceEpoch,
                        ),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'songs/:songId',
                builder: (context, state) {
                  final teamId = RuntimeGuard.guardFirestoreId(
                    state.pathParameters['teamId'],
                    field: 'teamId',
                    route: '/teams/:teamId/songs/:songId',
                  );
                  final songId = RuntimeGuard.guardFirestoreId(
                    state.pathParameters['songId'],
                    field: 'songId',
                    route: '/teams/:teamId/songs/:songId',
                  );
                  if (teamId == null || songId == null) {
                    return _RouteErrorPage(
                      title: '잘못된 악보 경로',
                      message: '팀 또는 곡 ID가 올바르지 않습니다.',
                      actionLabel: '팀 목록으로 이동',
                      onAction: () => context.go('/teams'),
                    );
                  }
                  final keyText = state.uri.queryParameters['key'];
                  return _RouteDocumentGuard(
                    load: () => firestore.collection('songs').doc(songId).get(),
                    loadingMessage: '악보 정보를 확인하는 중...',
                    notFoundTitle: '악보 정보를 찾을 수 없습니다',
                    notFoundMessage: '삭제되었거나 접근 권한이 없습니다.',
                    child: SongDetailPage(
                      teamId: teamId,
                      songId: songId,
                      keyText: keyText,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _RouteErrorPage extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _RouteErrorPage({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(message),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: onAction, child: Text(actionLabel)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteDocumentGuard extends StatefulWidget {
  final Future<DocumentSnapshot<Map<String, dynamic>>> Function() load;
  final String loadingMessage;
  final String notFoundTitle;
  final String notFoundMessage;
  final Widget child;

  const _RouteDocumentGuard({
    required this.load,
    required this.loadingMessage,
    required this.notFoundTitle,
    required this.notFoundMessage,
    required this.child,
  });

  @override
  State<_RouteDocumentGuard> createState() => _RouteDocumentGuardState();
}

class _RouteDocumentGuardState extends State<_RouteDocumentGuard> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(covariant _RouteDocumentGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.load, widget.load)) {
      _future = widget.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: AppLoadingState(message: widget.loadingMessage),
          );
        }
        if (snapshot.hasError) {
          OpsMetrics.firestoreSnapshotError(
            fields: <String, Object?>{
              'scope': 'router_document_guard',
              'error': snapshot.error.toString(),
            },
          );
          return _RouteErrorPage(
            title: '데이터 접근 오류',
            message: '요청한 데이터를 읽는 중 오류가 발생했습니다: ${snapshot.error}',
            actionLabel: '팀 목록으로 이동',
            onAction: () => context.go('/teams'),
          );
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists || doc.data() == null) {
          OpsMetrics.runtimeGuardTriggered(
            guard: 'router_document_missing',
            fields: <String, Object?>{'title': widget.notFoundTitle},
          );
          return _RouteErrorPage(
            title: widget.notFoundTitle,
            message: widget.notFoundMessage,
            actionLabel: '팀 목록으로 이동',
            onAction: () => context.go('/teams'),
          );
        }
        return widget.child;
      },
    );
  }
}

class _AuthRefresh extends ChangeNotifier {
  final StreamSubscription<User?> _sub;

  _AuthRefresh(FirebaseAuth auth)
    : _sub = auth.authStateChanges().listen((_) {}) {
    _sub.onData((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
