import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/models/sketch_stroke.dart';

void main() {
  group('SketchStroke.normalizeOffset', () {
    test('clamps to unit coordinates and applies fixed-8 precision', () {
      final normalized = SketchStroke.normalizeOffset(
        const Offset(400.123456789, -9.75),
        const Size(300, 200),
      );

      expect(normalized.dx, 1.0);
      expect(normalized.dy, 0.0);
    });
  });

  group('SketchStroke serialization', () {
    test('writes relative-v1 schema and fixed-8 rounded points', () {
      final stroke = SketchStroke(
        points: <Offset>[
          const Offset(0.123456789, 0.987654321),
          const Offset(0.999999999, -0.000000004),
        ],
        colorValue: 0xFF000000,
        width: 2.8,
      );

      final encoded = stroke.toMap();
      final points = encoded['points']! as List<dynamic>;
      final first = points.first as Map<String, dynamic>;
      final second = points.last as Map<String, dynamic>;

      expect(encoded['schemaVersion'], SketchStroke.schemaVersion);
      expect(first['x'], 0.12345679);
      expect(first['y'], 0.98765432);
      expect(second['x'], 1.0);
      expect(second['y'], 0.0);
    });

    test(
      'decodes and rounds out-of-range coordinates to fixed-8 unit space',
      () {
        final decoded = SketchStroke.decodeList(
          <Object?>[
            <String, Object?>{
              'colorValue': 0xFF112233,
              'width': 3.6,
              'points': <Object?>[
                <String, Object?>{'x': 1.234567891, 'y': -0.123456789},
                <String, Object?>{'x': 0.111111119, 'y': 0.222222229},
              ],
            },
          ],
          defaultWidth: 2.0,
          defaultColorValue: 0xFF000000,
        );

        expect(decoded, hasLength(1));
        expect(decoded.first.points.first.dx, 1.0);
        expect(decoded.first.points.first.dy, 0.0);
        expect(decoded.first.points.last.dx, 0.11111112);
        expect(decoded.first.points.last.dy, 0.22222223);
      },
    );
  });
}
