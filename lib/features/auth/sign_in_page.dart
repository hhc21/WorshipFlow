import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/ui_components.dart';
import '../../services/firebase_providers.dart';

class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  static Future<void>? _googleSignInInitializeFuture;

  Future<void> _verifyMobileFirestoreProbe(WidgetRef ref, User user) async {
    final firestore = ref.read(firestoreProvider);
    final probeRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('ClientProbe')
        .doc('mobile');
    await probeRef.set({
      'lastSignInProbeAt': FieldValue.serverTimestamp(),
      'source': 'mobile-sign-in',
    }, SetOptions(merge: true));
    await probeRef.get();
  }

  bool get _isMobileSignInPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<GoogleSignIn> _prepareMobileGoogleSignIn() async {
    if (!_isMobileSignInPlatform) {
      throw UnsupportedError('모바일 Google 로그인은 iOS/Android에서만 지원됩니다.');
    }
    final googleSignIn = GoogleSignIn.instance;
    _googleSignInInitializeFuture ??= googleSignIn.initialize();
    await _googleSignInInitializeFuture;
    return googleSignIn;
  }

  Future<UserCredential?> _signInOnMobile(FirebaseAuth auth) async {
    final googleSignIn = await _prepareMobileGoogleSignIn();
    if (!googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError('현재 플랫폼에서는 Google authenticate API를 지원하지 않습니다.');
    }

    GoogleSignInAccount googleAccount;
    try {
      googleAccount = await googleSignIn.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }

    final idToken = googleAccount.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google ID 토큰을 가져오지 못했습니다.',
      );
    }

    final googleCredential = GoogleAuthProvider.credential(idToken: idToken);
    return auth.signInWithCredential(googleCredential);
  }

  String _googleSignInErrorMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return '로그인이 취소되었습니다.';
      case GoogleSignInExceptionCode.interrupted:
        return '로그인이 중단되었습니다. 다시 시도해 주세요.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google 로그인 UI를 열 수 없습니다.';
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'Google 로그인 설정(client) 확인이 필요합니다.';
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google 로그인 provider 설정 확인이 필요합니다.';
      case GoogleSignInExceptionCode.unknownError:
      case GoogleSignInExceptionCode.userMismatch:
        return 'Google 로그인 실패: ${error.description ?? error.code.name}';
    }
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(firebaseAuthProvider);
    final provider = GoogleAuthProvider();
    try {
      if (kIsWeb) {
        await auth.signInWithPopup(provider);
        return;
      }

      final credential = await _signInOnMobile(auth);
      if (credential == null) {
        return;
      }
      final signedInUser = credential.user ?? auth.currentUser;
      if (signedInUser != null) {
        debugPrint(
          '[SP01][Auth] mobile sign-in success uid=${signedInUser.uid} email=${signedInUser.email ?? ''}',
        );
        try {
          await _verifyMobileFirestoreProbe(ref, signedInUser);
          debugPrint(
            '[SP01][Probe] users/${signedInUser.uid}/ClientProbe/mobile write+read success',
          );
        } catch (probeError) {
          debugPrint('[SP01][Probe] failure: $probeError');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('로그인 후 Firestore 연결 확인 실패: $probeError')),
          );
        }
      }
    } on GoogleSignInException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_googleSignInErrorMessage(error))));
    } on FirebaseAuthException catch (error) {
      if (!kIsWeb) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: ${error.message ?? error.code}')),
        );
        return;
      }

      final needsRedirectFallback =
          error.code == 'popup-blocked' ||
          error.code == 'popup-closed-by-user' ||
          error.code == 'operation-not-supported-in-this-environment' ||
          error.code == 'web-context-cancelled';
      if (needsRedirectFallback) {
        try {
          await auth.signInWithRedirect(provider);
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
