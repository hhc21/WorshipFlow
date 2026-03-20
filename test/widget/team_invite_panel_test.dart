import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/teams/team_invite_panel.dart';
import 'package:worshipflow/services/firebase_providers.dart';

import '../helpers/test_auth.dart';

void main() {
  Future<void> pumpInvitePanelFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('email invite send path uses dialog feedback and stores invite', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            buildSignedInAuth(
              uid: 'leader-1',
              email: 'leader@example.com',
              displayName: 'Leader',
            ),
          ),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TeamInvitePanel(
              teamId: 'team-alpha',
              teamName: 'Alpha Team',
              isAdmin: true,
            ),
          ),
        ),
      ),
    );
    await pumpInvitePanelFrames(tester);

    await tester.enterText(find.byType(TextField), 'Invitee@Example.com');
    await tester.tap(find.text('초대'));
    await pumpInvitePanelFrames(tester);

    expect(find.text('초대 전송 완료'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('확인'));
    await pumpInvitePanelFrames(tester);

    final inviteDoc = await firestore
        .collection('teams')
        .doc('team-alpha')
        .collection('invites')
        .doc('invitee@example.com')
        .get();

    expect(inviteDoc.exists, isTrue);
    expect(inviteDoc.data()?['email'], 'invitee@example.com');
    expect(inviteDoc.data()?['status'], 'pending');
  });

  testWidgets(
    'leader can see pending join request and invited status remains visible',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('joinRequests')
          .doc('requester-1')
          .set({
            'requesterUid': 'requester-1',
            'requesterEmail': 'requester@example.com',
            'requesterDisplayName': 'Requester',
            'teamId': 'team-alpha',
            'teamName': 'Alpha Team',
            'status': 'pending',
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(
              buildSignedInAuth(
                uid: 'leader-1',
                email: 'leader@example.com',
                displayName: 'Leader',
              ),
            ),
            firestoreProvider.overrideWithValue(firestore),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TeamInvitePanel(
                teamId: 'team-alpha',
                teamName: 'Alpha Team',
                isAdmin: true,
              ),
            ),
          ),
        ),
      );
      await pumpInvitePanelFrames(tester);

      expect(find.text('Requester'), findsOneWidget);
      expect(find.text('초대 전송'), findsOneWidget);

      await tester.tap(find.text('초대 전송'));
      await pumpInvitePanelFrames(tester);

      expect(find.text('합류 요청 처리 완료'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await pumpInvitePanelFrames(tester);

      expect(find.text('초대 전송됨'), findsOneWidget);

      final requestDoc = await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('joinRequests')
          .doc('requester-1')
          .get();
      final inviteDoc = await firestore
          .collection('teams')
          .doc('team-alpha')
          .collection('invites')
          .doc('requester@example.com')
          .get();

      expect(requestDoc.data()?['status'], 'invited');
      expect(inviteDoc.exists, isTrue);
    },
  );
}
