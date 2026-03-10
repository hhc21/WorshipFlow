import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/teams/team_home_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';

import '../helpers/test_auth.dart';

void main() {
  testWidgets('TeamHomePage renders body on narrow layout regression', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('teams').doc('team-1').set({
      'name': '테스트팀',
      'createdBy': 'user-1',
      'lastProjectId': '2026.03.09',
    });
    await firestore
        .collection('teams')
        .doc('team-1')
        .collection('members')
        .doc('user-1')
        .set({'role': 'admin', 'nickname': '리더', 'displayName': '리더'});
    await firestore
        .collection('teams')
        .doc('team-1')
        .collection('projects')
        .doc('2026.03.09')
        .set({
          'date': '2026.03.09',
          'title': '주일 예배',
          'leaderUserId': 'user-1',
          'leaderDisplayName': '리더',
        });

    final auth = buildSignedInAuth(
      uid: 'user-1',
      email: 'user1@example.com',
      displayName: '리더',
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const MaterialApp(home: TeamHomePage(teamId: 'team-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('테스트팀 운영'), findsOneWidget);
    expect(find.text('테스트팀 워크스페이스'), findsOneWidget);
    expect(find.text('프로젝트'), findsWidgets);
  });

  testWidgets('TeamHomePage allows global admin entry without member doc', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('teams').doc('team-admin-view').set({
      'name': '운영자검증팀',
      'createdBy': 'owner-user',
      'lastProjectId': '',
    });
    await firestore.collection('globalAdmins').doc('global-admin').set({
      'grantedAt': DateTime.now().toIso8601String(),
    });

    final auth = buildSignedInAuth(
      uid: 'global-admin',
      email: 'admin@example.com',
      displayName: '운영자',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const MaterialApp(home: TeamHomePage(teamId: 'team-admin-view')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운영자검증팀 운영'), findsOneWidget);
    expect(find.text('팀 접근 권한이 없습니다'), findsNothing);
    expect(find.text('운영자 조회 모드'), findsOneWidget);
  });
}
