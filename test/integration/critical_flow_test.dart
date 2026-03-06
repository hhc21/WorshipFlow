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

  testWidgets('critical: user can see joined team in team select', (
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

    expect(find.text('Alpha Team'), findsOneWidget);
  });

  testWidgets(
    'critical: member-only record is loaded and membership mirror is restored',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = buildSignedInAuth(
        uid: 'user-1',
        email: 'user1@example.com',
        displayName: 'User One',
      );

      await firestore.collection('teams').doc('team-a').set({
        'name': 'Alpha Team',
        'createdBy': 'owner-9',
        'memberUids': <String>[],
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
      final repairedTeam = await firestore
          .collection('teams')
          .doc('team-a')
          .get();
      final repairedMemberUids =
          (repairedTeam.data()?['memberUids'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const <String>[];

      expect(find.text('Alpha Team'), findsOneWidget);
      expect(membershipMirror.exists, isTrue);
      expect(membershipMirror.data()?['role'], 'admin');
      expect(repairedMemberUids.contains('user-1'), isTrue);
    },
  );
}
