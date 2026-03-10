import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/live_cue_note_persistence_adapter.dart';
import 'package:worshipflow/features/projects/models/sketch_stroke.dart';

void main() {
  group('LiveCueNotePersistenceAdapter', () {
    test('save scope follows editing layer and saveBoth flags', () async {
      final firestore = FakeFirebaseFirestore();
      final adapter = LiveCueNotePersistenceAdapter(
        firestore: firestore,
        teamId: 'team-a',
        projectId: 'project-a',
      );
      final stroke = SketchStroke(
        points: const <Offset>[Offset(0.1, 0.1), Offset(0.2, 0.2)],
        colorValue: 0xFFD32F2F,
        width: 2.8,
      );

      final privateResult = await adapter.saveNoteLayers(
        userId: 'user-a',
        actor: 'tester',
        privateText: 'private-1',
        sharedText: 'shared-1',
        privateStrokes: <SketchStroke>[stroke],
        sharedStrokes: <SketchStroke>[stroke],
        editingSharedLayer: false,
      );
      expect(privateResult.wrotePrivate, isTrue);
      expect(privateResult.wroteShared, isFalse);

      final sharedOnlyResult = await adapter.saveNoteLayers(
        userId: 'user-a',
        actor: 'tester',
        privateText: 'private-2',
        sharedText: 'shared-2',
        privateStrokes: <SketchStroke>[stroke],
        sharedStrokes: <SketchStroke>[stroke],
        editingSharedLayer: true,
      );
      expect(sharedOnlyResult.wrotePrivate, isFalse);
      expect(sharedOnlyResult.wroteShared, isTrue);

      final bothResult = await adapter.saveNoteLayers(
        userId: 'user-a',
        actor: 'tester',
        privateText: 'private-3',
        sharedText: 'shared-3',
        privateStrokes: <SketchStroke>[stroke],
        sharedStrokes: <SketchStroke>[stroke],
        editingSharedLayer: false,
        saveBothLayers: true,
      );
      expect(bothResult.wroteBoth, isTrue);

      final loaded = await adapter.loadNoteLayers(userId: 'user-a');
      expect(loaded.privateLayer.text, 'private-3');
      expect(loaded.sharedLayer.text, 'shared-3');
      expect(loaded.privateLayer.strokes, isNotEmpty);
      expect(loaded.sharedLayer.strokes, isNotEmpty);
    });

    test('load returns empty payloads when no note documents exist', () async {
      final firestore = FakeFirebaseFirestore();
      final adapter = LiveCueNotePersistenceAdapter(
        firestore: firestore,
        teamId: 'team-b',
        projectId: 'project-b',
      );

      final loaded = await adapter.loadNoteLayers(userId: 'user-b');
      expect(loaded.privateLayer.text, isEmpty);
      expect(loaded.sharedLayer.text, isEmpty);
      expect(loaded.privateLayer.strokes, isEmpty);
      expect(loaded.sharedLayer.strokes, isEmpty);
    });
  });
}
