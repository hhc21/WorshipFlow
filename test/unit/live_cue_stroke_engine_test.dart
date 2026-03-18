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

  test('shared-only visibility switches editable target to shared layer', () {
    final engine = LiveCueStrokeEngine();
    addTearDown(engine.dispose);
    const canvasSize = Size(100, 100);

    engine.setDrawingEnabled(true);
    engine.setLayerVisibility(showPrivateLayer: false);

    expect(engine.showPrivateLayer, isFalse);
    expect(engine.showSharedLayer, isTrue);
    expect(engine.editingSharedLayer, isTrue);

    expect(engine.tapStroke(const Offset(40, 40), canvasSize), isTrue);
    expect(engine.privateLayerStrokes, isEmpty);
    expect(engine.sharedLayerStrokes.length, 1);

    engine.setLayerVisibility(showSharedLayer: false);
    expect(engine.showPrivateLayer, isFalse);
    expect(engine.showSharedLayer, isTrue);
    expect(engine.editingSharedLayer, isTrue);
  });

  test('selecting a hidden layer as edit target makes that layer visible', () {
    final engine = LiveCueStrokeEngine();
    addTearDown(engine.dispose);
    const canvasSize = Size(100, 100);

    engine.setDrawingEnabled(true);
    engine.setLayerVisibility(showPrivateLayer: false);

    expect(engine.showPrivateLayer, isFalse);
    expect(engine.showSharedLayer, isTrue);
    expect(engine.editingSharedLayer, isTrue);

    engine.setEditingSharedLayer(false);
    expect(engine.showPrivateLayer, isTrue);
    expect(engine.showSharedLayer, isTrue);
    expect(engine.editingSharedLayer, isFalse);

    expect(engine.tapStroke(const Offset(24, 24), canvasSize), isTrue);
    expect(engine.privateLayerStrokes.length, 1);
    expect(engine.sharedLayerStrokes, isEmpty);
  });
}
