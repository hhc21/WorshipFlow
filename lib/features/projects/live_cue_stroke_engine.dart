import 'package:flutter/material.dart';

import 'models/sketch_stroke.dart';

class LiveCueStrokeEngine {
  final ValueNotifier<int> strokeRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> toolRevision = ValueNotifier<int>(0);

  bool _drawingEnabled = false;
  bool _eraserEnabled = false;
  bool _editingSharedLayer = false;
  bool _showPrivateLayer = true;
  bool _showSharedLayer = true;
  double _drawingStrokeWidth;
  int _drawingColorValue;
  List<SketchStroke> _privateLayerStrokes = <SketchStroke>[];
  List<SketchStroke> _sharedLayerStrokes = <SketchStroke>[];
  SketchStroke? _activeLayerStroke;

  LiveCueStrokeEngine({
    double drawingStrokeWidth = 2.8,
    int drawingColorValue = 0xFFD32F2F,
  }) : _drawingStrokeWidth = drawingStrokeWidth,
       _drawingColorValue = drawingColorValue;

  bool get drawingEnabled => _drawingEnabled;
  bool get eraserEnabled => _eraserEnabled;
  bool get editingSharedLayer => _editingSharedLayer;
  bool get showPrivateLayer => _showPrivateLayer;
  bool get showSharedLayer => _showSharedLayer;
  double get drawingStrokeWidth => _drawingStrokeWidth;
  int get drawingColorValue => _drawingColorValue;
  List<SketchStroke> get privateLayerStrokes =>
      List<SketchStroke>.unmodifiable(_privateLayerStrokes);
  List<SketchStroke> get sharedLayerStrokes =>
      List<SketchStroke>.unmodifiable(_sharedLayerStrokes);
  SketchStroke? get activeLayerStroke => _activeLayerStroke;

  void dispose() {
    strokeRevision.dispose();
    toolRevision.dispose();
  }

  void setDrawingEnabled(bool value) {
    if (_drawingEnabled == value) return;
    _drawingEnabled = value;
    if (!value) {
      _activeLayerStroke = null;
      _eraserEnabled = false;
      _bumpStrokeRevision();
    }
    _bumpToolRevision();
  }

  void setEraserEnabled(bool value) {
    if (_eraserEnabled == value) return;
    _eraserEnabled = value;
    if (value) {
      _activeLayerStroke = null;
    }
    _bumpToolRevision();
  }

  void setEditingSharedLayer(bool value) {
    if (_editingSharedLayer == value) return;
    _editingSharedLayer = value;
    _bumpToolRevision();
  }

  void setLayerVisibility({bool? showPrivateLayer, bool? showSharedLayer}) {
    var changed = false;
    if (showPrivateLayer != null) {
      changed = changed || _showPrivateLayer != showPrivateLayer;
      _showPrivateLayer = showPrivateLayer;
    }
    if (showSharedLayer != null) {
      changed = changed || _showSharedLayer != showSharedLayer;
      _showSharedLayer = showSharedLayer;
    }
    if (!changed) return;
    _bumpToolRevision();
    _bumpStrokeRevision();
  }

  void setBrush({double? strokeWidth, int? colorValue}) {
    var changed = false;
    if (strokeWidth != null) {
      changed = changed || _drawingStrokeWidth != strokeWidth;
      _drawingStrokeWidth = strokeWidth;
    }
    if (colorValue != null) {
      changed = changed || _drawingColorValue != colorValue;
      _drawingColorValue = colorValue;
    }
    if (!changed) return;
    _bumpToolRevision();
  }

  void applyViewerCommit({
    required List<SketchStroke> privateStrokes,
    required List<SketchStroke> sharedStrokes,
    required bool editingSharedLayer,
  }) {
    _privateLayerStrokes = List<SketchStroke>.from(privateStrokes);
    _sharedLayerStrokes = List<SketchStroke>.from(sharedStrokes);
    _editingSharedLayer = editingSharedLayer;
    _activeLayerStroke = null;
    _bumpStrokeRevision();
  }

  void replaceLayerStrokes({
    required List<SketchStroke> privateStrokes,
    required List<SketchStroke> sharedStrokes,
  }) {
    _privateLayerStrokes = List<SketchStroke>.from(privateStrokes);
    _sharedLayerStrokes = List<SketchStroke>.from(sharedStrokes);
    _activeLayerStroke = null;
    _bumpStrokeRevision();
  }

  bool eraseAt(Offset localPosition, Size size) {
    if (!_drawingEnabled || !_eraserEnabled) return false;
    final point = _normalizeOffset(localPosition, size);
    final target = _editingSharedLayer
        ? _sharedLayerStrokes
        : _privateLayerStrokes;
    final hasHit = target.any((stroke) => _strokeHit(stroke, point));
    if (!hasHit) return false;
    target.removeWhere((stroke) => _strokeHit(stroke, point));
    _activeLayerStroke = null;
    _bumpStrokeRevision();
    return true;
  }

  bool beginStroke(Offset localPosition, Size size) {
    if (!_drawingEnabled || _eraserEnabled) return false;
    final point = _normalizeOffset(localPosition, size);
    _activeLayerStroke = SketchStroke(
      points: <Offset>[point],
      colorValue: _drawingColorValue,
      width: _drawingStrokeWidth,
    );
    _bumpStrokeRevision();
    return true;
  }

  bool appendStroke(Offset localPosition, Size size) {
    if (_eraserEnabled) return false;
    final active = _activeLayerStroke;
    if (active == null) return false;
    active.points.add(_normalizeOffset(localPosition, size));
    _bumpStrokeRevision();
    return true;
  }

  bool endStroke() {
    final active = _activeLayerStroke;
    if (active == null) return false;
    if (active.points.isNotEmpty) {
      if (_editingSharedLayer) {
        _sharedLayerStrokes.add(active);
      } else {
        _privateLayerStrokes.add(active);
      }
    }
    _activeLayerStroke = null;
    _bumpStrokeRevision();
    return true;
  }

  bool tapStroke(Offset localPosition, Size size) {
    if (!_drawingEnabled || _eraserEnabled) return false;
    final point = _normalizeOffset(localPosition, size);
    final dotStroke = SketchStroke(
      points: <Offset>[point],
      colorValue: _drawingColorValue,
      width: _drawingStrokeWidth,
    );
    if (_editingSharedLayer) {
      _sharedLayerStrokes.add(dotStroke);
    } else {
      _privateLayerStrokes.add(dotStroke);
    }
    _activeLayerStroke = null;
    _bumpStrokeRevision();
    return true;
  }

  void undoCurrentLayer() {
    if (_activeLayerStroke != null) {
      _activeLayerStroke = null;
      _bumpStrokeRevision();
      return;
    }
    final target = _editingSharedLayer
        ? _sharedLayerStrokes
        : _privateLayerStrokes;
    if (target.isNotEmpty) {
      target.removeLast();
    }
    _bumpStrokeRevision();
  }

  void clearCurrentLayer() {
    if (_editingSharedLayer) {
      _sharedLayerStrokes.clear();
    } else {
      _privateLayerStrokes.clear();
    }
    _activeLayerStroke = null;
    _bumpStrokeRevision();
  }

  List<SketchStroke> overlayStrokesForRender() {
    final strokes = <SketchStroke>[];
    if (_showPrivateLayer) {
      strokes.addAll(_privateLayerStrokes);
    }
    if (_showSharedLayer) {
      strokes.addAll(_sharedLayerStrokes);
    }
    if (_activeLayerStroke != null) {
      strokes.add(_activeLayerStroke!);
    }
    return strokes;
  }

  Offset _normalizeOffset(Offset local, Size size) {
    return SketchStroke.normalizeOffset(local, size);
  }

  bool _strokeHit(SketchStroke stroke, Offset point) {
    if (stroke.points.isEmpty) return false;
    final radius = (0.018 + (stroke.width / 450.0)).clamp(0.012, 0.04);
    final radiusSquared = radius * radius;
    if (stroke.points.length == 1) {
      final dot = stroke.points.first;
      final dx = dot.dx - point.dx;
      final dy = dot.dy - point.dy;
      return (dx * dx + dy * dy) <= radiusSquared;
    }
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1];
      final b = stroke.points[i];
      if (_distanceSquaredToSegment(point, a, b) <= radiusSquared) {
        return true;
      }
    }
    return false;
  }

  double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final apx = p.dx - a.dx;
    final apy = p.dy - a.dy;
    final abSquared = (abx * abx) + (aby * aby);
    if (abSquared <= 1e-12) {
      return (apx * apx) + (apy * apy);
    }
    final t = ((apx * abx) + (apy * aby)) / abSquared;
    final clampedT = t.clamp(0.0, 1.0);
    final closestX = a.dx + (abx * clampedT);
    final closestY = a.dy + (aby * clampedT);
    final dx = p.dx - closestX;
    final dy = p.dy - closestY;
    return (dx * dx) + (dy * dy);
  }

  void _bumpStrokeRevision() {
    strokeRevision.value = strokeRevision.value + 1;
  }

  void _bumpToolRevision() {
    toolRevision.value = toolRevision.value + 1;
  }
}
