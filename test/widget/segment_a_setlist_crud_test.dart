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

  Finder dialogFieldByLabel(WidgetTester _, String label) {
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    );
    if (dialogFields.evaluate().isNotEmpty) {
      return dialogFields.first;
    }
    return find.byWidgetPredicate((_) => false);
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
    await firestore.collection('songs').doc('song-test').set({
      'title': '테스트곡',
      'aliases': const <String>[],
      'searchTokens': const <String>['테스트곡'],
    });
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
    await tester.enterText(
      dialogFieldByLabel(tester, '순서 라벨 (예: 1, 1-2)'),
      '2',
    );
    await tester.enterText(dialogFieldByLabel(tester, '제목'), '수정곡');
    await tester.enterText(dialogFieldByLabel(tester, '키 (선택)'), 'E');
    await tester.enterText(dialogFieldByLabel(tester, '템포 BPM (선택)'), '128');
    await tester.enterText(
      dialogFieldByLabel(tester, '박자표 (선택, 예: 4/4)'),
      ' 6 / 8 ',
    );
    await tester.enterText(
      dialogFieldByLabel(tester, '섹션 마커 (쉼표 구분, 선택)'),
      'Intro, Verse',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await tester.pumpAndSettle();

    final editedDoc = await setlistRef.doc(createdDoc.id).get();
    expect(editedDoc.data()?['cueLabel'], '2');
    expect(editedDoc.data()?['displayTitle'], '수정곡');
    expect(editedDoc.data()?['keyText'], 'E');
    expect(editedDoc.data()?['musicMetadata'], {
      'tempoBpm': 128,
      'timeSignature': '6/8',
      'sectionMarkers': ['Intro', 'Verse'],
    });

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

  testWidgets('bulk setlist input adds multiple items from textarea', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProject(firestore);
    await firestore.collection('songs').doc('song-1').set({
      'title': '당신의 날에',
      'aliases': const <String>[],
      'searchTokens': const <String>['당신의 날에'],
    });
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

    await pumpSegmentAPage(tester, firestore);

    await tester.enterText(
      fieldByLabel('콘티 일괄 입력 (여러 줄)'),
      '1 새로운 생명 G\n2 주의 집에 거하는 자 D\n3 나를 지으신 이가 하나님 G',
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
    expect(snapshot.docs[0].data()['cueLabel'], '1');
    expect(snapshot.docs[0].data()['displayTitle'], '새로운 생명');
    expect(snapshot.docs[0].data()['keyText'], 'G');
    expect(snapshot.docs[1].data()['cueLabel'], '2');
    expect(snapshot.docs[1].data()['displayTitle'], '주의 집에 거하는 자');
    expect(snapshot.docs[1].data()['keyText'], 'D');
    expect(snapshot.docs[2].data()['cueLabel'], '3');
    expect(snapshot.docs[2].data()['displayTitle'], '나를 지으신 이가 하나님');
    expect(snapshot.docs[2].data()['keyText'], 'G');
    expect(find.byTooltip('삭제'), findsNWidgets(3));
    expect(find.byTooltip('아래로 이동'), findsWidgets);
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

  testWidgets('invalid metadata blocks save in the edit dialog', (
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
          'displayTitle': '메타곡',
          'freeTextTitle': '메타곡',
          'keyText': 'C',
        });

    await pumpSegmentAPage(tester, firestore);

    await tester.tap(find.byTooltip('수정').first);
    await tester.pumpAndSettle();
    await tester.enterText(dialogFieldByLabel(tester, '템포 BPM (선택)'), '500');
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('20~300'), findsOneWidget);

    final doc = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist')
        .doc('item-1')
        .get();
    expect(doc.data()?['musicMetadata'], isNull);
  });

  testWidgets('empty metadata input does not create noisy musicMetadata', (
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

    await tester.tap(find.byTooltip('수정').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await tester.pumpAndSettle();

    final doc = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('segmentA_setlist')
        .doc('item-1')
        .get();
    expect(doc.data()?['musicMetadata'], isNull);
  });
}
