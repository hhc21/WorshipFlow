import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/features/projects/live_cue_page.dart';

void main() {
  test('fullscreen drawing accepts desktop mouse pointers', () {
    expect(supportsLiveCueDrawingPointer(PointerDeviceKind.mouse), isTrue);
    expect(supportsLiveCueDrawingPointer(PointerDeviceKind.touch), isTrue);
    expect(supportsLiveCueDrawingPointer(PointerDeviceKind.stylus), isTrue);
  });
}
