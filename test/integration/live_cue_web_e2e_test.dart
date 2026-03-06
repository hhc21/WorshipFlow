import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:worshipflow/features/projects/live_cue_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';

import '../helpers/test_auth.dart';

class _MockFirebaseStorage extends Mock implements FirebaseStorage {}

Future<void> _pumpLoading(WidgetTester tester, {int ticks = 14}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<({FakeFirebaseFirestore firestore, GoRouter router})> _pumpLiveCueApp(
  WidgetTester tester,
) async {
  final firestore = FakeFirebaseFirestore();
  final auth = buildSignedInAuth(
    uid: 'leader-1',
    email: 'leader@example.com',
    displayName: 'Leader',
  );
  final storage = _MockFirebaseStorage();

  await firestore.collection('teams').doc('team-a').set({
    'name': 'Alpha Team',
    'createdBy': 'leader-1',
    'memberUids': ['leader-1'],
    'createdAt': Timestamp.now(),
  });
  await firestore
      .collection('teams')
      .doc('team-a')
      .collection('members')
      .doc('leader-1')
      .set({
        'userId': 'leader-1',
        'uid': 'leader-1',
        'email': 'leader@example.com',
        'displayName': 'Leader',
        'role': 'admin',
        'createdAt': Timestamp.now(),
      });
  await firestore
      .collection('teams')
      .doc('team-a')
      .collection('projects')
      .doc('p-1')
      .set({
        'date': '2026.03.04',
        'leaderUserId': 'leader-1',
        'createdAt': Timestamp.now(),
      });
  await firestore
      .collection('teams')
      .doc('team-a')
      .collection('projects')
      .doc('p-1')
      .collection('segmentA_setlist')
      .doc('line-1')
      .set({
        'order': 1,
        'displayTitle': '첫 곡',
        'freeTextTitle': '첫 곡',
        'keyText': 'D',
      });
  await firestore
      .collection('teams')
      .doc('team-a')
      .collection('projects')
      .doc('p-1')
      .collection('segmentA_setlist')
      .doc('line-2')
      .set({
        'order': 2,
        'displayTitle': '두 번째 곡',
        'freeTextTitle': '두 번째 곡',
        'keyText': 'E',
      });
  await firestore
      .collection('teams')
      .doc('team-a')
      .collection('projects')
      .doc('p-1')
      .collection('liveCue')
      .doc('state')
      .set({
        'currentCueLabel': '1',
        'currentDisplayTitle': '첫 곡',
        'currentKeyText': 'D',
        'nextCueLabel': '2',
        'nextDisplayTitle': '두 번째 곡',
        'nextKeyText': 'E',
        'updatedAt': Timestamp.now(),
      });

  final router = GoRouter(
    initialLocation: '/teams/team-a/projects/p-1',
    routes: [
      GoRoute(
        path: '/teams',
        builder: (_, _) => const Scaffold(body: Text('teams-root')),
      ),
      GoRoute(
        path: '/teams/:teamId/projects/:projectId',
        builder: (_, state) => Scaffold(
          body: LiveCuePage(
            teamId: state.pathParameters['teamId']!,
            projectId: state.pathParameters['projectId']!,
            canEdit: true,
          ),
        ),
      ),
      GoRoute(
        path: '/teams/:teamId/projects/:projectId/live',
        builder: (_, state) => LiveCueFullScreenPage(
          teamId: state.pathParameters['teamId']!,
          projectId: state.pathParameters['projectId']!,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
        storageProvider.overrideWithValue(storage),
        globalAdminProvider.overrideWith((_) async => true),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _pumpLoading(tester);
  return (firestore: firestore, router: router);
}

void main() {
  testWidgets('live cue e2e: keyboard and swipe move current line', (
    tester,
  ) async {
    final app = await _pumpLiveCueApp(tester);

    expect(find.textContaining('첫 곡'), findsWidgets);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await _pumpLoading(tester, ticks: 10);

    final afterRight = await app.firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects')
        .doc('p-1')
        .collection('liveCue')
        .doc('state')
        .get();
    expect(afterRight.data()?['currentDisplayTitle'], '두 번째 곡');

    final swipeTarget = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector && widget.onHorizontalDragEnd != null,
    );
    expect(swipeTarget, findsWidgets);
    await tester.fling(swipeTarget.first, const Offset(460, 0), 1400);
    await _pumpLoading(tester, ticks: 10);

    final afterSwipe = await app.firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects')
        .doc('p-1')
        .collection('liveCue')
        .doc('state')
        .get();
    expect(afterSwipe.data()?['currentDisplayTitle'], '첫 곡');
  });

  testWidgets('live cue e2e: fullscreen route renders live viewer', (
    tester,
  ) async {
    final app = await _pumpLiveCueApp(tester);

    app.router.go('/teams/team-a/projects/p-1/live');
    await tester.pumpAndSettle(const Duration(milliseconds: 700));
    await _pumpLoading(tester, ticks: 8);

    expect(
      app.router.routeInformationProvider.value.uri.path,
      '/teams/team-a/projects/p-1/live',
    );
    expect(find.text('다시 불러오기'), findsOneWidget);
  });
}
