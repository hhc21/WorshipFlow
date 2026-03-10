import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/firebase_providers.dart';
import '../../services/ops_metrics.dart';
import '../../utils/firestore_id.dart';
import 'models/sketch_stroke.dart';

class ProjectNotesPanel extends ConsumerStatefulWidget {
  final String teamId;
  final String projectId;

  const ProjectNotesPanel({
    super.key,
    required this.teamId,
    required this.projectId,
  });

  @override
  ConsumerState<ProjectNotesPanel> createState() => _ProjectNotesPanelState();
}

class _ProjectNotesPanelState extends ConsumerState<ProjectNotesPanel> {
  bool _openingPrivate = false;
  bool _openingShared = false;

  Future<_NotePayload> _loadPrivatePayload(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    final v2DocRef = firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userProjectNotes')
        .doc(privateProjectNoteDocIdV2(widget.projectId, userId));
    final doc = await v2DocRef.get();

    final data = doc.data();
    if (data != null) {
      return _NotePayload.fromMap(data);
    }

    // Legacy fallback #1: old deterministic doc id.
    final legacyDoc = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userProjectNotes')
        .doc(privateProjectNoteDocIdLegacy(widget.projectId, userId))
        .get();
    final legacyDocData = legacyDoc.data();
    if (legacyDocData != null) {
      unawaited(
        logLegacyFallbackUsage(
          firestore: firestore,
          teamId: widget.teamId,
          path: 'project_notes.legacy_doc_id',
          detail: widget.projectId,
        ),
      );
      final merged = {
        ...legacyDocData,
        'visibility': 'private',
        'ownerUserId': userId,
        'teamId': widget.teamId,
        'projectId': widget.projectId,
      };
      // Best-effort: write into v2 doc (do not depend on deleting legacy doc).
      try {
        await v2DocRef.set(merged, SetOptions(merge: true));
      } on FirebaseException {
        // Ignore migration write failure here; caller can still open note payload.
      }
      return _NotePayload.fromMap(merged);
    }

    // Legacy fallback: query-based private note documents.
    final legacyQuery = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userProjectNotes')
        .where('userId', isEqualTo: userId)
        .where('projectId', isEqualTo: widget.projectId)
        .limit(1)
        .get();
    if (legacyQuery.docs.isEmpty) return _NotePayload();
    unawaited(
      logLegacyFallbackUsage(
        firestore: firestore,
        teamId: widget.teamId,
        path: 'project_notes.legacy_query',
        detail: widget.projectId,
      ),
    );
    final legacyData = legacyQuery.docs.first.data();
    final merged = {
      ...legacyData,
      'visibility': 'private',
      'ownerUserId': userId,
      'teamId': widget.teamId,
      'projectId': widget.projectId,
    };
    // Best-effort migration to v2 doc id.
    try {
      await v2DocRef.set(merged, SetOptions(merge: true));
    } on FirebaseException {
      // Ignore migration failure; still allow opening existing content.
    }
    return _NotePayload.fromMap(merged);
  }

  Future<_NotePayload> _loadSharedPayload(FirebaseFirestore firestore) async {
    final doc = await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .collection('sharedNotes')
        .doc('main')
        .get();
    final data = doc.data();
    if (data == null) return _NotePayload();
    return _NotePayload.fromMap(data);
  }

  Future<void> _savePrivate(
    FirebaseFirestore firestore,
    String userId,
    _NotePayload payload,
  ) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    final data = {
      'userId': userId,
      'ownerUserId': userId,
      'projectId': widget.projectId,
      'teamId': widget.teamId,
      'visibility': 'private',
      'content': payload.text,
      'drawingStrokes': payload.toFirestoreStrokes(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user?.uid,
    };

    await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('userProjectNotes')
        .doc(privateProjectNoteDocIdV2(widget.projectId, userId))
        .set(data, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('개인 메모 저장 완료')));
    }
  }

  Future<void> _saveShared(
    FirebaseFirestore firestore,
    _NotePayload payload,
  ) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    await firestore
        .collection('teams')
        .doc(widget.teamId)
        .collection('projects')
        .doc(widget.projectId)
        .collection('sharedNotes')
        .doc('main')
        .set({
          'teamId': widget.teamId,
          'projectId': widget.projectId,
          'visibility': 'team',
          'content': payload.text,
          'drawingStrokes': payload.toFirestoreStrokes(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': user?.uid,
        }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공유 메모 저장 완료')));
    }
  }

  Future<void> _openPrivateEditor(BuildContext context) async {
    if (_openingPrivate) return;
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) return;

    setState(() => _openingPrivate = true);
    final firestore = ref.read(firestoreProvider);
    try {
      final initial = await _loadPrivatePayload(firestore, user.uid);
      if (!context.mounted) return;
      final result = await showDialog<_NotePayload>(
        context: context,
        builder: (_) => _NoteSketchDialog(
          title: '개인 메모',
          description: '나에게만 보입니다. (패드/펜슬 필기 가능)',
          initial: initial,
        ),
      );
      if (result == null) return;
      await _savePrivate(firestore, user.uid, result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(SnackBar(content: Text('개인 메모 처리 실패: $error')));
      }
    } finally {
      if (mounted) setState(() => _openingPrivate = false);
    }
  }

  Future<void> _openSharedEditor(BuildContext context) async {
    if (_openingShared) return;
    setState(() => _openingShared = true);
    final firestore = ref.read(firestoreProvider);

    try {
      final initial = await _loadSharedPayload(firestore);
      if (!context.mounted) return;
      final result = await showDialog<_NotePayload>(
        context: context,
        builder: (_) => _NoteSketchDialog(
          title: '공유 메모',
          description: '팀 전체가 함께 보는 편곡/코드 노트',
          initial: initial,
        ),
      );
      if (result == null) return;
      await _saveShared(firestore, result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(SnackBar(content: Text('공유 메모 처리 실패: $error')));
      }
    } finally {
      if (mounted) setState(() => _openingShared = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.8),
                ),
                child: const Icon(Icons.edit_note_rounded, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                '프로젝트 메모 (선택)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: _openingPrivate
                    ? null
                    : () => _openPrivateEditor(context),
                icon: _openingPrivate
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person),
                label: const Text('개인 메모 열기'),
              ),
              FilledButton.tonalIcon(
                onPressed: _openingShared
                    ? null
                    : () => _openSharedEditor(context),
                icon: _openingShared
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group),
                label: const Text('공유 메모 열기'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '선택 기능입니다. 메모를 입력하지 않고 바로 다음 단계(콘티/LiveCue)로 진행해도 됩니다. 개인 메모는 본인만, 공유 메모는 팀 전체가 봅니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoteSketchDialog extends StatefulWidget {
  final String title;
  final String description;
  final _NotePayload initial;

  const _NoteSketchDialog({
    required this.title,
    required this.description,
    required this.initial,
  });

  @override
  State<_NoteSketchDialog> createState() => _NoteSketchDialogState();
}

class _NoteSketchDialogState extends State<_NoteSketchDialog> {
  late final TextEditingController _textController;
  late List<SketchStroke> _strokes;
  SketchStroke? _activeStroke;
  double _strokeWidth = 2.2;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initial.text);
    _strokes = widget.initial.strokes
        .map(
          (stroke) => SketchStroke(
            points: List<Offset>.from(stroke.points),
            colorValue: stroke.colorValue,
            width: stroke.width,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Offset _normalizeOffset(Offset local, Size size) {
    return SketchStroke.normalizeOffset(local, size);
  }

  void _startStroke(DragStartDetails details, Size size) {
    final point = _normalizeOffset(details.localPosition, size);
    setState(() {
      _activeStroke = SketchStroke(
        points: [point],
        colorValue: Colors.black.toARGB32(),
        width: _strokeWidth,
      );
    });
  }

  void _appendStroke(DragUpdateDetails details, Size size) {
    final active = _activeStroke;
    if (active == null) return;
    final point = _normalizeOffset(details.localPosition, size);
    setState(() {
      active.points.add(point);
    });
  }

  void _endStroke() {
    final active = _activeStroke;
    if (active == null) return;
    if (active.points.length < 2) {
      _activeStroke = null;
      return;
    }
    setState(() {
      _strokes.add(active);
      _activeStroke = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allStrokes = [..._strokes, if (_activeStroke != null) _activeStroke!];

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _NotePayload(
                    text: _textController.text.trim(),
                    strokes: _strokes,
                  ),
                );
              },
              child: const Text('저장'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.description),
                const SizedBox(height: 10),
                TextField(
                  controller: _textController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '텍스트 메모',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('펜 굵기'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 7,
                        value: _strokeWidth,
                        onChanged: (value) {
                          setState(() => _strokeWidth = value);
                        },
                      ),
                    ),
                    Text(_strokeWidth.toStringAsFixed(1)),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _strokes.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _strokes.removeLast();
                              });
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('되돌리기'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: (_strokes.isEmpty && _activeStroke == null)
                          ? null
                          : () {
                              setState(() {
                                _strokes.clear();
                                _activeStroke = null;
                              });
                            },
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text('전체 지우기'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final canvasSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) =>
                              _startStroke(details, canvasSize),
                          onPanUpdate: (details) =>
                              _appendStroke(details, canvasSize),
                          onPanEnd: (_) => _endStroke(),
                          child: CustomPaint(
                            painter: _SketchPainter(strokes: allStrokes),
                            size: Size.infinite,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  final List<SketchStroke> strokes;

  const _SketchPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.colorValue)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      final first = Offset(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      path.moveTo(first.dx, first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}

class _NotePayload {
  final String text;
  final List<SketchStroke> strokes;

  _NotePayload({this.text = '', List<SketchStroke>? strokes})
    : strokes = strokes ?? <SketchStroke>[];

  factory _NotePayload.fromMap(Map<String, dynamic> data) {
    return _NotePayload(
      text: data['content']?.toString() ?? '',
      strokes: _decodeStrokes(data['drawingStrokes']),
    );
  }

  List<Map<String, dynamic>> toFirestoreStrokes() {
    return strokes.map((stroke) => stroke.toMap()).toList();
  }

  static List<SketchStroke> _decodeStrokes(dynamic raw) {
    return SketchStroke.decodeList(
      raw,
      defaultWidth: 2.2,
      defaultColorValue: Colors.black.toARGB32(),
    );
  }
}
