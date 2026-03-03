import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<bool> copyTextWithFallback(
  BuildContext context, {
  required String text,
  required String successMessage,
  String failureTitle = '자동 복사에 실패했습니다',
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } catch (_) {
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(failureTitle),
        content: SizedBox(width: 520, child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(successMessage)));
              } catch (_) {}
            },
            child: const Text('복사 재시도'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    return false;
  }
}
