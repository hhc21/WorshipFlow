import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/live_cue_stroke_engine.dart';

void main() {
  test(
    'stroke engine writes private/shared layers and supports erase/undo',
    () {
      final engine = LiveCueStrokeEngine();
      addTearDown(engine.dispose);
      const canvasSize = Size(100, 100);

      engine.setDrawingEnabled(true);
      expect(engine.drawingEnabled, isTrue);

      expect(engine.beginStroke(const Offset(10, 10), canvasSize), isTrue);
      expect(engine.appendStroke(const Offset(20, 20), canvasSize), isTrue);
      expect(engine.endStroke(), isTrue);
      expect(engine.privateLayerStrokes.length, 1);

      engine.setEditingSharedLayer(true);
      expect(engine.tapStroke(const Offset(30, 30), canvasSize), isTrue);
      expect(engine.sharedLayerStrokes.length, 1);

      engine.setEraserEnabled(true);
      expect(engine.eraseAt(const Offset(30, 30), canvasSize), isTrue);
      expect(engine.sharedLayerStrokes, isEmpty);

      engine.setEraserEnabled(false);
      engine.setEditingSharedLayer(false);
      engine.undoCurrentLayer();
      expect(engine.privateLayerStrokes, isEmpty);
    },
  );
}
