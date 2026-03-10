import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/ops_metrics.dart';
import '../../utils/firestore_id.dart';
import 'models/sketch_stroke.dart';

class LiveCueNotePayload {
  final String text;
  final List<SketchStroke> strokes;

  const LiveCueNotePayload({
    this.text = '',
    this.strokes = const <SketchStroke>[],
  });

  factory LiveCueNotePayload.fromMap(Map<String, dynamic> data) {
    return LiveCueNotePayload(
      text: data['content']?.toString() ?? '',
      strokes: SketchStroke.decodeList(
        data['drawingStrokes'],
        defaultWidth: 2.8,
        defaultColorValue: 0xFFD32F2F,
      ),
    );
  }
}

class LiveCueNoteLayers {
  final LiveCueNotePayload privateLayer;
  final LiveCueNotePayload sharedLayer;

  const LiveCueNoteLayers({
    required this.privateLayer,
    required this.sharedLayer,
  });
}

class LiveCueNoteSaveResult {
  final bool wrotePrivate;
  final bool wroteShared;

  const LiveCueNoteSaveResult({
    required this.wrotePrivate,
    required this.wroteShared,
  });

  bool get wroteBoth => wrotePrivate && wroteShared;
}

class LiveCueNotePersistenceAdapter {
  final FirebaseFirestore firestore;
  final String teamId;
  final String projectId;

  const LiveCueNotePersistenceAdapter({
    required this.firestore,
    required this.teamId,
    required this.projectId,
  });

  Future<LiveCueNoteLayers> loadNoteLayers({required String userId}) async {
    final privateLayer = await _loadPrivateNotePayload(userId);
    final sharedLayer = await _loadSharedNotePayload();
    return LiveCueNoteLayers(
      privateLayer: privateLayer,
      sharedLayer: sharedLayer,
    );
  }

  Future<LiveCueNoteSaveResult> saveNoteLayers({
    required String userId,
    required String? actor,
    required String privateText,
    required String sharedText,
    required List<SketchStroke> privateStrokes,
    required List<SketchStroke> sharedStrokes,
    required bool editingSharedLayer,
    bool saveBothLayers = false,
  }) async {
    final writeBoth = saveBothLayers;
    final writePrivate = writeBoth || !editingSharedLayer;
    final writeShared = writeBoth || editingSharedLayer;
    final writes = <Future<void>>[];

    if (writeShared) {
      writes.add(
        _sharedProjectNoteRef().set({
          'teamId': teamId,
          'projectId': projectId,
          'visibility': 'team',
          'content': sharedText,
          'drawingStrokes': sharedStrokes
              .map((stroke) => stroke.toMap())
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actor,
        }, SetOptions(merge: true)),
      );
    }

    if (writePrivate) {
      writes.add(
        _privateProjectNoteRef(userId).set({
          'userId': userId,
          'ownerUserId': userId,
          'projectId': projectId,
          'teamId': teamId,
          'visibility': 'private',
          'content': privateText,
          'drawingStrokes': privateStrokes
              .map((stroke) => stroke.toMap())
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actor,
        }, SetOptions(merge: true)),
      );
    }

    await Future.wait(writes);
    return LiveCueNoteSaveResult(
      wrotePrivate: writePrivate,
      wroteShared: writeShared,
    );
  }

  DocumentReference<Map<String, dynamic>> _privateProjectNoteRef(
    String userId,
  ) {
    return firestore
        .collection('teams')
        .doc(teamId)
        .collection('userProjectNotes')
        .doc(privateProjectNoteDocIdV2(projectId, userId));
  }

  DocumentReference<Map<String, dynamic>> _sharedProjectNoteRef() {
    return firestore
        .collection('teams')
        .doc(teamId)
        .collection('projects')
        .doc(projectId)
        .collection('sharedNotes')
        .doc('main');
  }

  Future<LiveCueNotePayload> _loadPrivateNotePayload(String userId) async {
    final v2Ref = _privateProjectNoteRef(userId);
    final v2Doc = await v2Ref.get();
    final v2Data = v2Doc.data();
    if (v2Data != null) {
      return LiveCueNotePayload.fromMap(v2Data);
    }

    final legacyDoc = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('userProjectNotes')
        .doc(privateProjectNoteDocIdLegacy(projectId, userId))
        .get();
    final legacyData = legacyDoc.data();
    if (legacyData != null) {
      unawaited(
        logLegacyFallbackUsage(
          firestore: firestore,
          teamId: teamId,
          path: 'live_cue.legacy_doc_id',
          detail: projectId,
        ),
      );
      final merged = {
        ...legacyData,
        'visibility': 'private',
        'ownerUserId': userId,
        'teamId': teamId,
        'projectId': projectId,
      };
      try {
        await v2Ref.set(merged, SetOptions(merge: true));
      } on FirebaseException {
        // Ignore migration failure and continue with loaded payload.
      }
      return LiveCueNotePayload.fromMap(merged);
    }

    final legacyQuery = await firestore
        .collection('teams')
        .doc(teamId)
        .collection('userProjectNotes')
        .where('userId', isEqualTo: userId)
        .where('projectId', isEqualTo: projectId)
        .limit(1)
        .get();
    if (legacyQuery.docs.isEmpty) return const LiveCueNotePayload();
    unawaited(
      logLegacyFallbackUsage(
        firestore: firestore,
        teamId: teamId,
        path: 'live_cue.legacy_query',
        detail: projectId,
      ),
    );
    final queryData = legacyQuery.docs.first.data();
    final merged = {
      ...queryData,
      'visibility': 'private',
      'ownerUserId': userId,
      'teamId': teamId,
      'projectId': projectId,
    };
    try {
      await v2Ref.set(merged, SetOptions(merge: true));
    } on FirebaseException {
      // Ignore migration failure and continue with loaded payload.
    }
    return LiveCueNotePayload.fromMap(merged);
  }

  Future<LiveCueNotePayload> _loadSharedNotePayload() async {
    final doc = await _sharedProjectNoteRef().get();
    final data = doc.data();
    if (data == null) return const LiveCueNotePayload();
    return LiveCueNotePayload.fromMap(data);
  }
}
