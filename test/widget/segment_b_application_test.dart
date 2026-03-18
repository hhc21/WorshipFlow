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

  testWidgets('application tab reads only canonical applied sections', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProject(firestore);
    final setlistRef = firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist');

    await setlistRef.doc('worship-1').set({
      'order': 1,
      'cueLabel': '1',
      'displayTitle': '예배 전 곡',
      'freeTextTitle': '예배 전 곡',
      'keyText': 'C',
      'sectionType': 'worship',
    });
    await setlistRef.doc('response-1').set({
      'order': 2,
      'cueLabel': '2',
      'displayTitle': '응답 곡',
      'freeTextTitle': '응답 곡',
      'keyText': 'D',
      'sectionType': 'sermon_response',
    });
    await setlistRef.doc('prayer-1').set({
      'order': 3,
      'cueLabel': '3',
      'displayTitle': '기도 곡',
      'freeTextTitle': '기도 곡',
      'keyText': 'E',
      'sectionType': 'prayer',
    });

    await pumpSegmentBPage(tester, firestore);

    expect(find.textContaining('예배 전 곡'), findsNothing);
    expect(find.textContaining('응답 곡'), findsOneWidget);
    expect(find.textContaining('기도 곡'), findsOneWidget);
    expect(find.text('설교 응답'), findsOneWidget);
    expect(find.text('기도'), findsOneWidget);
  });

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
    await tester.tap(find.text('적용찬양 추가').first);
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
        .collection('segmentA_setlist')
        .orderBy('order')
        .get();

    expect(snapshot.docs, hasLength(3));
    expect(snapshot.docs[0].data()['displayTitle'], '새로운 생명');
    expect(snapshot.docs[0].data()['keyText'], 'G');
    expect(snapshot.docs[0].data()['sectionType'], 'sermon_response');
    expect(snapshot.docs[1].data()['displayTitle'], '주의 집에 거하는 자');
    expect(snapshot.docs[1].data()['keyText'], 'D');
    expect(snapshot.docs[1].data()['sectionType'], 'sermon_response');
    expect(snapshot.docs[2].data()['displayTitle'], '나를 지으신 이가 하나님');
    expect(snapshot.docs[2].data()['keyText'], 'G');
    expect(snapshot.docs[2].data()['sectionType'], 'sermon_response');
    expect(find.textContaining('새로운 생명'), findsWidgets);
    expect(find.textContaining('주의 집에 거하는 자'), findsWidgets);
    expect(find.textContaining('나를 지으신 이가 하나님'), findsWidgets);
    expect(find.byTooltip('삭제'), findsNWidgets(3));
    expect(find.byTooltip('아래로 이동'), findsWidgets);

    await tester.tap(find.byTooltip('아래로 이동').first);
    await tester.pumpAndSettle();

    var reordered = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist')
        .orderBy('order')
        .get();
    expect(reordered.docs.map((doc) => doc.data()['displayTitle']).toList(), [
      '주의 집에 거하는 자',
      '새로운 생명',
      '나를 지으신 이가 하나님',
    ]);

    await tester.tap(find.byTooltip('삭제').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제'));
    await tester.pumpAndSettle();

    final afterDelete = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist')
        .orderBy('order')
        .get();
    expect(afterDelete.docs, hasLength(2));
    expect(afterDelete.docs.map((doc) => doc.data()['order']).toList(), [1, 2]);
    expect(find.text('전체 순서 3'), findsNothing);
  });

  testWidgets('application insert stays inside applied section block', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProject(firestore);
    await firestore.collection('songs').doc('song-new').set({
      'title': '새 응답 곡',
      'aliases': const <String>[],
      'searchTokens': const <String>['새 응답 곡'],
    });
    final setlistRef = firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist');

    await setlistRef.doc('w-1').set({
      'order': 1,
      'cueLabel': '1',
      'displayTitle': '앞 찬양',
      'freeTextTitle': '앞 찬양',
      'sectionType': 'worship',
    });
    await setlistRef.doc('r-1').set({
      'order': 2,
      'cueLabel': '2',
      'displayTitle': '응답 곡',
      'freeTextTitle': '응답 곡',
      'sectionType': 'sermon_response',
    });
    await setlistRef.doc('p-1').set({
      'order': 3,
      'cueLabel': '3',
      'displayTitle': '기도 곡',
      'freeTextTitle': '기도 곡',
      'sectionType': 'prayer',
    });
    await setlistRef.doc('w-2').set({
      'order': 4,
      'cueLabel': '4',
      'displayTitle': '뒤 찬양',
      'freeTextTitle': '뒤 찬양',
      'sectionType': 'worship',
    });

    await pumpSegmentBPage(tester, firestore);

    await tester.enterText(fieldByLabel('적용찬양 입력'), '새 응답 곡');
    await tester.tap(find.text('적용찬양 추가').first);
    await tester.pumpAndSettle();

    final snapshot = await setlistRef.orderBy('order').get();
    expect(snapshot.docs.map((doc) => doc.data()['displayTitle']).toList(), [
      '앞 찬양',
      '응답 곡',
      '기도 곡',
      '새 응답 곡',
      '뒤 찬양',
    ]);
    expect(snapshot.docs.map((doc) => doc.data()['order']).toList(), [
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(snapshot.docs[3].data()['sectionType'], 'sermon_response');
  });
}
