import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worshipflow/features/projects/project_detail_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';

import '../helpers/test_auth.dart';

Future<void> _pumpProjectDetail(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required String teamId,
  required String projectId,
  required String uid,
  required String email,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(
          buildSignedInAuth(uid: uid, email: email, displayName: 'User-$uid'),
        ),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: MaterialApp(
        home: ProjectDetailPage(teamId: teamId, projectId: projectId),
      ),
    ),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpAndSettle(const Duration(milliseconds: 700));
}

Future<GoRouter> _pumpProjectDetailWithRouter(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required String teamId,
  required String projectId,
  required String uid,
  required String email,
}) async {
  final router = GoRouter(
    initialLocation: '/teams/$teamId/projects/$projectId',
    routes: [
      GoRoute(
        path: '/teams/:teamId',
        builder: (_, state) =>
            Scaffold(body: Text('team-home-${state.pathParameters['teamId']}')),
      ),
      GoRoute(
        path: '/teams/:teamId/projects/:projectId',
        builder: (_, state) => ProjectDetailPage(
          teamId: state.pathParameters['teamId']!,
          projectId: state.pathParameters['projectId']!,
        ),
      ),
    ],
  );

  await tester.binding.setSurfaceSize(const Size(1400, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(
          buildSignedInAuth(uid: uid, email: email, displayName: 'User-$uid'),
        ),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 700));
  return router;
}

void main() {
  testWidgets(
    'shows access denied when member doc is missing for non-creator',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('teams').doc('team-a').set({
        'name': 'Alpha',
        'createdBy': 'someone-else',
      });
      await firestore
          .collection('teams')
          .doc('team-a')
          .collection('projects')
          .doc('p-1')
          .set({'date': '2026.03.04', 'leaderUserId': 'leader-x'});

      await _pumpProjectDetail(
        tester,
        firestore: firestore,
        teamId: 'team-a',
        projectId: 'p-1',
        uid: 'u-1',
        email: 'u1@example.com',
      );

      expect(find.text('프로젝트 접근 권한이 없습니다'), findsOneWidget);
    },
  );

  testWidgets('allows creator access without member repair and renders tabs', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('teams').doc('team-a').set({
      'name': 'Alpha',
      'createdBy': 'u-1',
      'memberUids': <String>[],
    });
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects')
        .doc('p-1')
        .set({
          'date': '2026.03.04',
          'title': '금요예배',
          'leaderUserId': 'u-1',
          'createdAt': Timestamp.now(),
        });
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects')
        .doc('p-1')
        .collection('liveCue')
        .doc('state')
        .set({'currentDisplayTitle': '첫 곡', 'updatedAt': Timestamp.now()});

    await _pumpProjectDetail(
      tester,
      firestore: firestore,
      teamId: 'team-a',
      projectId: 'p-1',
      uid: 'u-1',
      email: 'u1@example.com',
    );

    expect(find.text('예배 전'), findsOneWidget);
    expect(find.text('적용찬양'), findsOneWidget);
    expect(find.text('LiveCue'), findsOneWidget);

    final memberDoc = await firestore
        .collection('teams')
        .doc('team-a')
        .collection('members')
        .doc('u-1')
        .get();
    final teamDoc = await firestore.collection('teams').doc('team-a').get();
    final memberUids =
        (teamDoc.data()?['memberUids'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const <String>[];

    expect(memberDoc.exists, isFalse);
    expect(memberUids.contains('u-1'), isFalse);
  });

  testWidgets('offers fallback project action when target project is missing', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('teams').doc('team-a').set({
      'name': 'Alpha',
      'createdBy': 'u-1',
    });
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('members')
        .doc('u-1')
        .set({'role': 'admin', 'displayName': 'Leader', 'userId': 'u-1'});
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects')
        .doc('p-latest')
        .set({'date': '2026.03.08', 'createdAt': Timestamp.now()});

    await _pumpProjectDetail(
      tester,
      firestore: firestore,
      teamId: 'team-a',
      projectId: 'p-missing',
      uid: 'u-1',
      email: 'u1@example.com',
    );

    expect(find.text('프로젝트를 찾을 수 없습니다'), findsOneWidget);
    expect(find.textContaining('최신 프로젝트 열기'), findsOneWidget);
  });

  testWidgets(
    'directly deletes project from project detail for project leader and returns to team home',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('teams').doc('team-a').set({
        'name': 'Alpha',
        'createdBy': 'team-owner',
      });
      await firestore
          .collection('teams')
          .doc('team-a')
          .collection('members')
          .doc('u-1')
          .set({'role': 'leader', 'displayName': 'Leader', 'userId': 'u-1'});
      await firestore
          .collection('teams')
          .doc('team-a')
          .collection('projects')
          .doc('p-1')
          .set({
            'date': '2026.03.04',
            'title': '금요예배',
            'leaderUserId': 'u-1',
            'createdAt': Timestamp.now(),
          });

      final router = await _pumpProjectDetailWithRouter(
        tester,
        firestore: firestore,
        teamId: 'team-a',
        projectId: 'p-1',
        uid: 'u-1',
        email: 'u1@example.com',
      );

      await tester.tap(find.text('프로젝트 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();

      final deletedProject = await firestore
          .collection('teams')
          .doc('team-a')
          .collection('projects')
          .doc('p-1')
          .get();
      expect(deletedProject.exists, isFalse);
      expect(router.routeInformationProvider.value.uri.path, '/teams/team-a');
      expect(find.text('team-home-team-a'), findsOneWidget);
    },
  );

  testWidgets('admin who is not project leader cannot delete project', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('teams').doc('team-a').set({
      'name': 'Alpha',
      'createdBy': 'team-owner',
    });
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('members')
        .doc('u-2')
        .set({'role': 'admin', 'displayName': '팀장', 'userId': 'u-2'});
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('projects')
        .doc('p-1')
        .set({
          'date': '2026.03.04',
          'title': '금요예배',
          'leaderUserId': 'other-user',
          'createdAt': Timestamp.now(),
        });

    await _pumpProjectDetail(
      tester,
      firestore: firestore,
      teamId: 'team-a',
      projectId: 'p-1',
      uid: 'u-2',
      email: 'u2@example.com',
    );

    expect(find.text('프로젝트 삭제'), findsNothing);
  });
}
