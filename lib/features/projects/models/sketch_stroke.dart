import 'dart:ui';

class SketchStroke {
  static const String schemaVersion = 'relative-v1';
  static const int coordinatePrecision = 8;
  static const double _unitMin = 0.0;
  static const double _unitMax = 1.0;
  static const double _precisionScale = 100000000.0;

  final List<Offset> points;
  final int colorValue;
  final double width;

  SketchStroke({
    required this.points,
    required this.colorValue,
    required this.width,
  });

  static double normalizeUnit(double value) {
    final clamped = value.clamp(_unitMin, _unitMax).toDouble();
    return (clamped * _precisionScale).round() / _precisionScale;
  }

  static Offset clampAndQuantizeOffset(Offset raw) {
    return Offset(normalizeUnit(raw.dx), normalizeUnit(raw.dy));
  }

  static Offset normalizeOffset(Offset local, Size size) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    return clampAndQuantizeOffset(
      Offset(local.dx / safeWidth, local.dy / safeHeight),
    );
  }

  static double _normalizeWidth(double value, {double fallback = 2.0}) {
    if (!value.isFinite || value <= 0) {
      return fallback.clamp(0.5, 18.0).toDouble();
    }
    return value.clamp(0.5, 18.0).toDouble();
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'colorValue': colorValue,
      'width': _normalizeWidth(width, fallback: width),
      'points': points
          .map(
            (point) => {
              'x': normalizeUnit(point.dx),
              'y': normalizeUnit(point.dy),
            },
          )
          .toList(),
    };
  }

  static List<SketchStroke> decodeList(
    Object? raw, {
    required double defaultWidth,
    required int defaultColorValue,
  }) {
    if (raw is! List) return <SketchStroke>[];
    final decoded = <SketchStroke>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final width = _normalizeWidth(
        (item['width'] as num?)?.toDouble() ?? defaultWidth,
        fallback: defaultWidth,
      );
      final colorValue =
          (item['colorValue'] as num?)?.toInt() ?? defaultColorValue;
      final pointsRaw = item['points'];
      if (pointsRaw is! List) continue;
      final points = <Offset>[];
      for (final point in pointsRaw) {
        if (point is! Map) continue;
        final dx = (point['x'] as num?)?.toDouble() ?? 0;
        final dy = (point['y'] as num?)?.toDouble() ?? 0;
        points.add(clampAndQuantizeOffset(Offset(dx, dy)));
      }
      if (points.isEmpty) continue;
      decoded.add(
        SketchStroke(points: points, colorValue: colorValue, width: width),
      );
    }
    return decoded;
  }
}
