import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/teams/team_select_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';

import '../helpers/test_auth.dart';

void main() {
  Future<void> pumpMembershipLoader(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('read-path: creator team is visible without member repair', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = buildSignedInAuth(
      uid: 'creator-1',
      email: 'creator@example.com',
      displayName: 'Creator',
    );

    await firestore.collection('teams').doc('team-heal').set({
      'name': 'Heal Team',
      'createdBy': 'creator-1',
      'memberUids': <String>[],
      'createdAt': Timestamp.now(),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          globalAdminProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(home: TeamSelectPage()),
      ),
    );
    await pumpMembershipLoader(tester);

    final repairedMember = await firestore
        .collection('teams')
        .doc('team-heal')
        .collection('members')
        .doc('creator-1')
        .get();
    final repairedTeam = await firestore
        .collection('teams')
        .doc('team-heal')
        .get();

    expect(find.text('Heal Team'), findsOneWidget);
    expect(repairedMember.exists, isFalse);
    expect(
      (repairedTeam.data()?['memberUids'] as List?)?.contains('creator-1'),
      isFalse,
    );
  });

  testWidgets(
    'read-path: stale mirror membership is ignored without cleanup write',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = buildSignedInAuth(
        uid: 'user-1',
        email: 'user1@example.com',
        displayName: 'User One',
      );

      await firestore.collection('teams').doc('team-a').set({
        'name': 'Alpha Team',
        'createdBy': 'user-1',
        'memberUids': ['user-1'],
        'createdAt': Timestamp.now(),
      });
      await firestore
          .collection('teams')
          .doc('team-a')
          .collection('members')
          .doc('user-1')
          .set({
            'role': 'admin',
            'email': 'user1@example.com',
            'displayName': 'User One',
            'createdAt': Timestamp.now(),
          });
      await firestore
          .collection('users')
          .doc('user-1')
          .collection('teamMemberships')
          .doc('team-a')
          .set({
            'teamId': 'team-a',
            'teamName': 'Alpha Team',
            'role': 'admin',
            'updatedAt': Timestamp.now(),
          });
      await firestore
          .collection('users')
          .doc('user-1')
          .collection('teamMemberships')
          .doc('ghost-team')
          .set({
            'teamId': 'ghost-team',
            'teamName': 'Ghost Team',
            'role': 'member',
            'updatedAt': Timestamp.now(),
          });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            globalAdminProvider.overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: TeamSelectPage()),
        ),
      );
      await pumpMembershipLoader(tester);

      final staleMirror = await firestore
          .collection('users')
          .doc('user-1')
          .collection('teamMemberships')
          .doc('ghost-team')
          .get();

      expect(find.text('Alpha Team'), findsOneWidget);
      expect(find.text('Ghost Team'), findsNothing);
      expect(staleMirror.exists, isTrue);
    },
  );

  testWidgets('read-path: team lastProjectId is shown without mirror sync', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = buildSignedInAuth(
      uid: 'user-1',
      email: 'user1@example.com',
      displayName: 'User One',
    );

    await firestore.collection('teams').doc('team-a').set({
      'name': 'Alpha Team',
      'createdBy': 'owner-9',
      'memberUids': ['user-1'],
      'lastProjectId': '2026.03.04',
      'createdAt': Timestamp.now(),
    });
    await firestore
        .collection('teams')
        .doc('team-a')
        .collection('members')
        .doc('user-1')
        .set({
          'role': 'member',
          'email': 'user1@example.com',
          'displayName': 'User One',
          'createdAt': Timestamp.now(),
        });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          globalAdminProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(home: TeamSelectPage()),
      ),
    );
    await pumpMembershipLoader(tester);

    final membershipMirror = await firestore
        .collection('users')
        .doc('user-1')
        .collection('teamMemberships')
        .doc('team-a')
        .get();

    expect(find.text('최근 프로젝트: 2026.03.04'), findsOneWidget);
    expect(membershipMirror.exists, isFalse);
  });
}
