import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/project_detail_page.dart';
import 'package:worshipflow/features/teams/team_home_page.dart';
import 'package:worshipflow/features/teams/team_select_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';

import '../helpers/test_auth.dart';

void main() {
  Future<void> pumpWithSignedOutUser(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(buildSignedOutAuth()),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('TeamSelectPage blocks unauthenticated user', (tester) async {
    await pumpWithSignedOutUser(tester, const TeamSelectPage());

    expect(find.text('로그인이 필요합니다.'), findsOneWidget);
  });

  testWidgets('TeamHomePage blocks unauthenticated user', (tester) async {
    await pumpWithSignedOutUser(tester, const TeamHomePage(teamId: 'team-1'));

    expect(find.text('로그인이 필요합니다.'), findsOneWidget);
  });

  testWidgets('ProjectDetailPage blocks unauthenticated user', (tester) async {
    await pumpWithSignedOutUser(
      tester,
      const ProjectDetailPage(teamId: 'team-1', projectId: '2026.03.04'),
    );

    expect(find.text('로그인이 필요합니다.'), findsOneWidget);
  });
}
