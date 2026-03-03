import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';

class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(firebaseAuthProvider);
    try {
      await auth.signInWithPopup(GoogleAuthProvider());
    } on FirebaseAuthException catch (error) {
      final needsRedirectFallback =
          error.code == 'popup-blocked' ||
          error.code == 'popup-closed-by-user' ||
          error.code == 'operation-not-supported-in-this-environment' ||
          error.code == 'web-context-cancelled';
      if (needsRedirectFallback) {
        try {
          await auth.signInWithRedirect(GoogleAuthProvider());
          return;
        } catch (_) {
          // Fall through to the snackbar with the original error message.
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인 실패: ${error.message ?? error.code}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('로그인 실패: $error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;

    return Scaffold(
      body: AppContentFrame(
        maxWidth: 540,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WorshipFlow',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '교회 찬양팀 운영 도구',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  const AppStateCard(
                    icon: Icons.lightbulb_outline,
                    title: '처음 사용하는 순서',
                    message: '로그인 후 팀 선택 → 프로젝트 생성 → 콘티 입력 → LiveCue 확인',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: authState.isLoading
                          ? null
                          : () => _signIn(context, ref),
                      icon: authState.isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        authState.isLoading ? '로그인 중...' : 'Google 로그인',
                      ),
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${user.displayName ?? user.email ?? '사용자'} 로그인됨',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () => ref.read(firebaseAuthProvider).signOut(),
                      child: const Text('로그아웃'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
