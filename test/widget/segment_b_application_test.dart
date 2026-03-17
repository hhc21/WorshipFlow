import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/segment_b_page.dart';
import 'package:worshipflow/services/firebase_providers.dart';

void main() {
  const teamId = 'team-sp05';
  const projectId = 'project-sp05';

  Future<void> seedProject(FakeFirebaseFirestore firestore) async {
    await firestore.collection('teams').doc(teamId).set({
      'name': 'SP05 팀',
      'createdBy': 'owner-user',
    });
    await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .set({
          'date': '2026.03.10',
          'title': 'SP05 프로젝트',
          'leaderUserId': 'leader-user',
        });
  }

  Future<void> pumpSegmentBPage(
    WidgetTester tester,
    FakeFirebaseFirestore firestore,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: const MaterialApp(
          home: Scaffold(
            body: SegmentBPage(
              teamId: teamId,
              projectId: projectId,
              canEdit: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldByLabel(String label) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
  }

  testWidgets('application tab supports single add and bulk add', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProject(firestore);
    await firestore.collection('songs').doc('song-2').set({
      'title': '주의 집에 거하는 자',
      'aliases': const <String>[],
      'searchTokens': const <String>['주의 집에 거하는 자'],
    });
    await firestore.collection('songs').doc('song-3').set({
      'title': '새로운 생명',
      'aliases': const <String>[],
      'searchTokens': const <String>['새로운 생명'],
    });
    await firestore.collection('songs').doc('song-4').set({
      'title': '나를 지으신 이가 하나님',
      'aliases': const <String>[],
      'searchTokens': const <String>['나를 지으신 이가 하나님'],
    });

    await pumpSegmentBPage(tester, firestore);

    await tester.enterText(fieldByLabel('적용찬양 입력'), '1 새로운 생명 G');
    await tester.tap(find.text('추가').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      fieldByLabel('적용찬양 일괄 입력 (여러 줄)'),
      '2 주의 집에 거하는 자 D\n3 나를 지으신 이가 하나님 G',
    );
    await tester.tap(find.text('일괄 추가').first);
    await tester.pumpAndSettle();

    final snapshot = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentB_application')
        .orderBy('order')
        .get();

    expect(snapshot.docs, hasLength(3));
    expect(snapshot.docs[0].data()['displayTitle'], '새로운 생명');
    expect(snapshot.docs[0].data()['keyText'], 'G');
    expect(snapshot.docs[1].data()['displayTitle'], '주의 집에 거하는 자');
    expect(snapshot.docs[1].data()['keyText'], 'D');
    expect(snapshot.docs[2].data()['displayTitle'], '나를 지으신 이가 하나님');
    expect(snapshot.docs[2].data()['keyText'], 'G');
    expect(find.textContaining('새로운 생명'), findsWidgets);
    expect(find.textContaining('주의 집에 거하는 자'), findsWidgets);
    expect(find.textContaining('나를 지으신 이가 하나님'), findsWidgets);
  });
}
