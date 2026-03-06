import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/teams/team_select_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';
import 'package:worshipflow/utils/team_name.dart';

import '../helpers/test_auth.dart';

void main() {
  Future<void> pumpMembershipLoader(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('duplicate team name creates join request instead of new team', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = buildSignedInAuth(
      uid: 'requester-1',
      email: 'requester@example.com',
      displayName: 'Requester',
    );
    const existingTeamId = 'team-alpha';
    const existingTeamName = '청소년부';
    final nameKey = buildTeamNameKey(existingTeamName);

    await firestore.collection('teams').doc(existingTeamId).set({
      'name': existingTeamName,
      'nameKey': nameKey,
      'createdBy': 'leader-1',
      'memberUids': ['leader-1'],
      'createdAt': Timestamp.now(),
    });
    await firestore
        .collection('teams')
        .doc(existingTeamId)
        .collection('members')
        .doc('leader-1')
        .set({
          'userId': 'leader-1',
          'uid': 'leader-1',
          'email': 'leader@example.com',
          'role': 'admin',
          'teamName': existingTeamName,
          'createdAt': Timestamp.now(),
        });
    await firestore.collection('teamNameIndex').doc(nameKey).set({
      'teamId': existingTeamId,
      'teamName': existingTeamName,
      'normalizedName': nameKey,
      'createdBy': 'leader-1',
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

    await tester.dragUntilVisible(
      find.text('새 팀 만들기'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, existingTeamName);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final joinRequest = await firestore
        .collection('teams')
        .doc(existingTeamId)
        .collection('joinRequests')
        .doc('requester-1')
        .get();
    final teamSnapshot = await firestore.collection('teams').get();

    expect(joinRequest.exists, isTrue);
    expect(joinRequest.data()?['status'], 'pending');
    expect(joinRequest.data()?['requesterEmail'], 'requester@example.com');
    expect(teamSnapshot.docs.length, 1);
    expect(find.textContaining('팀장에게 초대 요청을 보냈습니다'), findsOneWidget);
  });
}
