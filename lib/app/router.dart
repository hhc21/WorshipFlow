import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
              final teamId = state.pathParameters['teamId']!;
              return TeamHomePage(teamId: teamId);
            },
            routes: [
              GoRoute(
                path: 'projects/:projectId',
                builder: (context, state) {
                  final teamId = state.pathParameters['teamId']!;
                  final projectId = state.pathParameters['projectId']!;
                  return ProjectDetailPage(
                    teamId: teamId,
                    projectId: projectId,
                  );
                },
                routes: [
                  GoRoute(
                    path: 'live',
                    builder: (context, state) {
                      final teamId = state.pathParameters['teamId']!;
                      final projectId = state.pathParameters['projectId']!;
                      final startInDrawMode =
                          state.uri.queryParameters['memo'] == '1';
                      return LiveCueFullScreenPage(
                        teamId: teamId,
                        projectId: projectId,
                        startInDrawMode: startInDrawMode,
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'songs/:songId',
                builder: (context, state) {
                  final teamId = state.pathParameters['teamId']!;
                  final songId = state.pathParameters['songId']!;
                  final keyText = state.uri.queryParameters['key'];
                  return SongDetailPage(
                    teamId: teamId,
                    songId: songId,
                    keyText: keyText,
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
