import 'package:flutter/foundation.dart';

import 'models/sketch_stroke.dart';

class NextViewerInitData {
  final String teamId;
  final String projectId;
  final String? currentSongId;
  final String? currentKeyText;
  final String scoreImageUrl;
  final String idToken;
  final bool canEdit;
  final bool editingSharedLayer;
  final bool willReadFrequently;
  final List<SketchStroke> privateStrokes;
  final List<SketchStroke> sharedStrokes;

  const NextViewerInitData({
    required this.teamId,
    required this.projectId,
    required this.scoreImageUrl,
    required this.idToken,
    required this.canEdit,
    required this.editingSharedLayer,
    required this.willReadFrequently,
    required this.privateStrokes,
    required this.sharedStrokes,
    this.currentSongId,
    this.currentKeyText,
  });

  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'teamId': teamId,
      'projectId': projectId,
      'currentSongId': currentSongId,
      'currentKeyText': currentKeyText,
      'scoreImageUrl': scoreImageUrl,
      'idToken': idToken,
      'canEdit': canEdit,
      'editingLayer': editingSharedLayer ? 'shared' : 'private',
      'willReadFrequently': willReadFrequently,
      'sketchSchemaVersion': SketchStroke.schemaVersion,
      'coordinatePrecision': SketchStroke.coordinatePrecision,
      'privateStrokes': privateStrokes
          .map((stroke) => Map<String, Object?>.from(stroke.toMap()))
          .toList(growable: false),
      'sharedStrokes': sharedStrokes
          .map((stroke) => Map<String, Object?>.from(stroke.toMap()))
          .toList(growable: false),
    };
  }
}

class NextViewerInkState {
  final List<SketchStroke> privateStrokes;
  final List<SketchStroke> sharedStrokes;
  final bool editingSharedLayer;

  const NextViewerInkState({
    required this.privateStrokes,
    required this.sharedStrokes,
    required this.editingSharedLayer,
  });

  factory NextViewerInkState.fromPayload(Map<String, Object?> payload) {
    final layer = payload['editingLayer']?.toString() ?? 'private';
    return NextViewerInkState(
      privateStrokes: SketchStroke.decodeList(
        payload['privateStrokes'],
        defaultWidth: 2.8,
        defaultColorValue: 0xFFD32F2F,
      ),
      sharedStrokes: SketchStroke.decodeList(
        payload['sharedStrokes'],
        defaultWidth: 2.8,
        defaultColorValue: 0xFF1976D2,
      ),
      editingSharedLayer: layer == 'shared',
    );
  }
}

class NextViewerAssetError {
  final String code;
  final String message;
  final String? url;

  const NextViewerAssetError({
    required this.code,
    required this.message,
    this.url,
  });
}

typedef NextViewerInkCommitCallback = void Function(NextViewerInkState state);
typedef NextViewerDirtyChangedCallback = void Function(bool dirty);
typedef NextViewerAssetErrorCallback =
    void Function(NextViewerAssetError error);
typedef NextViewerProtocolLogCallback = void Function(String message);

@immutable
class NextViewerHostProps {
  final String viewerUrl;
  final NextViewerInitData initData;
  final int syncRevision;
  final NextViewerInkCommitCallback onInkCommit;
  final NextViewerDirtyChangedCallback onDirtyChanged;
  final NextViewerAssetErrorCallback onAssetError;
  final NextViewerProtocolLogCallback? onProtocolLog;

  const NextViewerHostProps({
    required this.viewerUrl,
    required this.initData,
    required this.syncRevision,
    required this.onInkCommit,
    required this.onDirtyChanged,
    required this.onAssetError,
    this.onProtocolLog,
  });
}
