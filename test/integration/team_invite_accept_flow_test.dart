import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worshipflow/features/teams/team_select_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';
import 'package:worshipflow/utils/browser_helpers.dart';

import '../helpers/test_auth.dart';

void main() {
  setUp(clearPendingTeamInviteLink);
  tearDown(clearPendingTeamInviteLink);

  Future<void> pumpMembershipLoader(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pumpTeamSelect(
    WidgetTester tester, {
    required FakeFirebaseFirestore firestore,
    required String uid,
    required String email,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            buildSignedInAuth(uid: uid, email: email, displayName: 'User-$uid'),
          ),
          firestoreProvider.overrideWithValue(firestore),
          globalAdminProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(home: TeamSelectPage()),
      ),
    );
    await pumpMembershipLoader(tester);
  }

  Future<void> pumpTeamSelectWithInviteLink(
    WidgetTester tester, {
    required FakeFirebaseFirestore firestore,
    required String uid,
    required String email,
    required String teamId,
    required String inviteCode,
  }) async {
    final router = GoRouter(
      initialLocation: '/teams',
      routes: [
        GoRoute(
          path: '/teams',
          builder: (_, state) =>
              TeamSelectPage(inviteTeamId: teamId, inviteCode: inviteCode),
        ),
        GoRoute(
          path: '/teams/:teamId',
          builder: (_, state) =>
              Scaffold(body: Text('joined-${state.pathParameters['teamId']}')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            buildSignedInAuth(uid: uid, email: email, displayName: 'User-$uid'),
          ),
          firestoreProvider.overrideWithValue(firestore),
          globalAdminProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await pumpMembershipLoader(tester);
  }

  testWidgets(
    'invited user can see pending email invite and accepting it creates membership mirrors',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('teams').doc('team-alpha').set({
        'name': 'Alpha Team',
        'createdBy': 'leader-1',
        'memberUids': ['leader-1'],
        'createdAt': Timestamp.now(),
      });
      await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('members')
          .doc('leader-1')
          .set({
            'userId': 'leader-1',
            'uid': 'leader-1',
            'email': 'leader@example.com',
            'role': 'admin',
            'teamName': 'Alpha Team',
            'createdAt': Timestamp.now(),
          });
      await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('invites')
          .doc('invited@example.com')
          .set({
            'email': 'invited@example.com',
            'role': 'member',
            'teamId': 'team-alpha',
            'teamName': 'Alpha Team',
            'status': 'pending',
            'createdBy': 'leader-1',
            'createdAt': Timestamp.now(),
          });

      await pumpTeamSelect(
        tester,
        firestore: firestore,
        uid: 'invitee-1',
        email: 'Invited@Example.com',
      );

      await tester.dragUntilVisible(
        find.text('받은 초대'),
        find.byType(Scrollable).first,
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();

      expect(find.text('받은 초대'), findsOneWidget);
      expect(find.text('Alpha Team'), findsOneWidget);
      expect(find.text('수락'), findsOneWidget);

      await tester.tap(find.text('수락'));
      await pumpMembershipLoader(tester);

      expect(find.text('팀 참여 완료'), findsOneWidget);
      expect(find.textContaining('Alpha Team 팀에 참여했습니다'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final memberDoc = await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('members')
          .doc('invitee-1')
          .get();
      final membershipDoc = await firestore
          .collection('users')
          .doc('invitee-1')
          .collection('teamMemberships')
          .doc('team-alpha')
          .get();
      final teamDoc = await firestore
          .collection('teams')
          .doc('team-alpha')
          .get();
      final inviteDoc = await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('invites')
          .doc('invited@example.com')
          .get();

      expect(memberDoc.exists, isTrue);
      expect(membershipDoc.exists, isTrue);
      expect(
        (teamDoc.data()?['memberUids'] as List?)?.contains('invitee-1'),
        isTrue,
      );
      expect(inviteDoc.data()?['status'], 'accepted');
      expect(find.text('대기 중인 초대가 없습니다'), findsOneWidget);
      expect(find.text('Alpha Team'), findsOneWidget);
    },
  );

  testWidgets(
    'stored invite link context survives missing route params and can still join the team',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('teams').doc('team-stored').set({
        'name': 'Stored Team',
        'createdBy': 'leader-stored',
        'memberUids': ['leader-stored'],
        'createdAt': Timestamp.now(),
      });
      await firestore
          .collection('teams')
          .doc('team-stored')
          .collection('members')
          .doc('leader-stored')
          .set({
            'userId': 'leader-stored',
            'uid': 'leader-stored',
            'email': 'leaderstored@example.com',
            'role': 'admin',
            'teamName': 'Stored Team',
            'createdAt': Timestamp.now(),
          });
      await firestore
          .collection('teams')
          .doc('team-stored')
          .collection('inviteLinks')
          .doc('stored-link')
          .set({
            'teamId': 'team-stored',
            'teamName': 'Stored Team',
            'role': 'member',
            'status': 'active',
            'createdBy': 'leader-stored',
            'createdAt': Timestamp.now(),
          });

      savePendingTeamInviteLink(
        teamId: 'team-stored',
        inviteCode: 'stored-link',
      );

      await pumpTeamSelect(
        tester,
        firestore: firestore,
        uid: 'invitee-stored',
        email: 'invitee-stored@example.com',
      );

      await tester.dragUntilVisible(
        find.text('바로 참여'),
        find.byType(Scrollable).first,
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stored Team 링크 초대'), findsOneWidget);

      await tester.tap(find.text('바로 참여'));
      await pumpMembershipLoader(tester);

      expect(find.text('팀 참여 완료'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final memberDoc = await firestore
          .collection('teams')
          .doc('team-stored')
          .collection('members')
          .doc('invitee-stored')
          .get();
      final membershipDoc = await firestore
          .collection('users')
          .doc('invitee-stored')
          .collection('teamMemberships')
          .doc('team-stored')
          .get();

      expect(memberDoc.exists, isTrue);
      expect(membershipDoc.exists, isTrue);
      expect(loadPendingTeamInviteLink(), isNull);
    },
  );

  testWidgets(
    'invite link acceptance creates membership mirrors and navigates to joined team',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('teams').doc('team-beta').set({
        'name': 'Beta Team',
        'createdBy': 'leader-2',
        'memberUids': ['leader-2'],
        'createdAt': Timestamp.now(),
      });
      await firestore
          .collection('teams')
          .doc('team-beta')
          .collection('members')
          .doc('leader-2')
          .set({
            'userId': 'leader-2',
            'uid': 'leader-2',
            'email': 'leader2@example.com',
            'role': 'admin',
            'teamName': 'Beta Team',
            'createdAt': Timestamp.now(),
          });
      await firestore
          .collection('teams')
          .doc('team-beta')
          .collection('inviteLinks')
          .doc('link-beta')
          .set({
            'teamId': 'team-beta',
            'teamName': 'Beta Team',
            'role': 'member',
            'status': 'active',
            'createdBy': 'leader-2',
            'createdAt': Timestamp.now(),
          });

      await pumpTeamSelectWithInviteLink(
        tester,
        firestore: firestore,
        uid: 'invitee-2',
        email: 'Invitee2@Example.com',
        teamId: 'team-beta',
        inviteCode: 'link-beta',
      );

      await tester.dragUntilVisible(
        find.text('바로 참여'),
        find.byType(Scrollable).first,
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();

      expect(find.text('바로 참여'), findsOneWidget);

      await tester.tap(find.text('바로 참여'));
      await pumpMembershipLoader(tester);

      expect(find.text('팀 참여 완료'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final memberDoc = await firestore
          .collection('teams')
          .doc('team-beta')
          .collection('members')
          .doc('invitee-2')
          .get();
      final membershipDoc = await firestore
          .collection('users')
          .doc('invitee-2')
          .collection('teamMemberships')
          .doc('team-beta')
          .get();
      final teamDoc = await firestore
          .collection('teams')
          .doc('team-beta')
          .get();

      expect(memberDoc.exists, isTrue);
      expect(memberDoc.data()?['inviteLinkId'], 'link-beta');
      expect(membershipDoc.exists, isTrue);
      expect(
        (teamDoc.data()?['memberUids'] as List?)?.contains('invitee-2'),
        isTrue,
      );
      expect(find.text('joined-team-beta'), findsOneWidget);
    },
  );
}
