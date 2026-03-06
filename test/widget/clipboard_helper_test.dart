import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/clipboard_helper.dart';

BuildContext? _capturedContext;

Future<BuildContext> _pumpHarness(WidgetTester tester) async {
  _capturedContext = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            _capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return _capturedContext!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('copyTextWithFallback shows snackbar on success', (tester) async {
    var clipboardCalls = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardCalls += 1;
      }
      return null;
    });

    final context = await _pumpHarness(tester);
    final result = await copyTextWithFallback(
      context,
      text: 'hello',
      successMessage: '복사 완료',
    );

    await tester.pump();
    expect(result, isTrue);
    expect(clipboardCalls, 1);
    expect(find.text('복사 완료'), findsOneWidget);
  });

  testWidgets('copyTextWithFallback opens dialog when clipboard fails', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'clipboard-failed');
      }
      return null;
    });

    final context = await _pumpHarness(tester);
    final future = copyTextWithFallback(
      context,
      text: 'fallback-text',
      successMessage: '복사 완료',
    );

    await tester.pumpAndSettle();
    expect(find.text('자동 복사에 실패했습니다'), findsOneWidget);
    expect(find.text('복사 재시도'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(await future, isFalse);
  });
}
