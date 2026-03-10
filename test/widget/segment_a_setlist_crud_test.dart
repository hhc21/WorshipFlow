import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/segment_a_page.dart';
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

  Future<void> pumpSegmentAPage(
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
            body: SegmentAPage(
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

  testWidgets('setlist loads existing item from canonical path', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProject(firestore);
    await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist')
        .doc('item-1')
        .set({
          'order': 1,
          'cueLabel': '1',
          'displayTitle': '기존곡',
          'freeTextTitle': '기존곡',
          'keyText': 'D',
        });

    await pumpSegmentAPage(tester, firestore);

    expect(find.textContaining('기존곡'), findsOneWidget);
    expect(find.textContaining('1 D 기존곡'), findsOneWidget);
  });

  testWidgets('setlist supports create/edit/delete and persists on re-entry', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProject(firestore);
    await pumpSegmentAPage(tester, firestore);

    final setlistRef = firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist');
    final liveCueRef = firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('liveCue')
        .doc('state');

    await tester.enterText(fieldByLabel('콘티 입력'), '1 D 테스트곡');
    await tester.tap(find.text('콘티 추가').first);
    await tester.pumpAndSettle();

    var snapshot = await setlistRef.get();
    expect(snapshot.docs, hasLength(1));
    final createdDoc = snapshot.docs.first;
    expect(createdDoc.data()['order'], 1);
    expect(createdDoc.data()['cueLabel'], '1');
    expect(createdDoc.data()['displayTitle'], '테스트곡');
    expect(createdDoc.data()['keyText'], 'D');

    final cueAfterCreate = await liveCueRef.get();
    expect(cueAfterCreate.data()?['currentDisplayTitle'], '테스트곡');
    expect(cueAfterCreate.data()?['currentCueLabel'], '1');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpSegmentAPage(tester, firestore);
    expect(find.textContaining('테스트곡'), findsOneWidget);

    await tester.tap(find.byTooltip('수정').first);
    await tester.pumpAndSettle();
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.at(0), '2');
    await tester.enterText(dialogFields.at(1), '수정곡');
    await tester.enterText(dialogFields.at(2), 'E');
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await tester.pumpAndSettle();

    final editedDoc = await setlistRef.doc(createdDoc.id).get();
    expect(editedDoc.data()?['cueLabel'], '2');
    expect(editedDoc.data()?['displayTitle'], '수정곡');
    expect(editedDoc.data()?['keyText'], 'E');

    await tester.tap(find.byTooltip('삭제').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제'));
    await tester.pumpAndSettle();

    snapshot = await setlistRef.get();
    expect(snapshot.docs, isEmpty);

    final cueAfterDelete = await liveCueRef.get();
    expect(cueAfterDelete.data()?['currentSongId'], isNull);
    expect(cueAfterDelete.data()?['currentDisplayTitle'], isNull);
    expect(cueAfterDelete.data()?['currentCueLabel'], isNull);
  });

  testWidgets(
    'setlist reorder keeps order deterministic and cue move updates current/next',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedProject(firestore);
      final setlistRef = firestore
          .collection('teams')
          .doc(teamId)
          .collection('projects')
          .doc(projectId)
          .collection('segmentA_setlist');
      final liveCueRef = firestore
          .collection('teams')
          .doc(teamId)
          .collection('projects')
          .doc(projectId)
          .collection('liveCue')
          .doc('state');

      await setlistRef.doc('a').set({
        'order': 1,
        'cueLabel': '1',
        'displayTitle': 'A',
        'freeTextTitle': 'A',
        'keyText': 'C',
      });
      await setlistRef.doc('b').set({
        'order': 2,
        'cueLabel': '2',
        'displayTitle': 'B',
        'freeTextTitle': 'B',
        'keyText': 'D',
      });
      await setlistRef.doc('c').set({
        'order': 3,
        'cueLabel': '3',
        'displayTitle': 'C',
        'freeTextTitle': 'C',
        'keyText': 'E',
      });
      await liveCueRef.set({
        'currentDisplayTitle': 'B',
        'currentFreeTextTitle': 'B',
        'currentCueLabel': '2',
        'currentKeyText': 'D',
        'nextDisplayTitle': 'C',
        'nextFreeTextTitle': 'C',
        'nextCueLabel': '3',
        'nextKeyText': 'E',
      });

      await pumpSegmentAPage(tester, firestore);

      await tester.tap(find.byTooltip('아래로 이동').first);
      await tester.pumpAndSettle();

      var reordered = await setlistRef.orderBy('order').get();
      expect(reordered.docs.map((doc) => doc.id).toList(), ['b', 'a', 'c']);
      expect(reordered.docs.map((doc) => doc.data()['order']).toList(), [
        1,
        2,
        3,
      ]);

      var cueAfterReorder = await liveCueRef.get();
      expect(cueAfterReorder.data()?['currentDisplayTitle'], 'B');
      expect(cueAfterReorder.data()?['currentCueLabel'], '2');
      expect(cueAfterReorder.data()?['nextDisplayTitle'], 'A');
      expect(cueAfterReorder.data()?['nextCueLabel'], '1');

      await tester.tap(find.byTooltip('현재 Cue로 이동').at(1));
      await tester.pumpAndSettle();

      final cueAfterMove = await liveCueRef.get();
      expect(cueAfterMove.data()?['currentDisplayTitle'], 'A');
      expect(cueAfterMove.data()?['currentCueLabel'], '1');
      expect(cueAfterMove.data()?['nextDisplayTitle'], 'C');
      expect(cueAfterMove.data()?['nextCueLabel'], '3');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpSegmentAPage(tester, firestore);
      reordered = await setlistRef.orderBy('order').get();
      expect(reordered.docs.map((doc) => doc.id).toList(), ['b', 'a', 'c']);
    },
  );
}
