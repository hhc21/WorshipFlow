import 'package:flutter/material.dart';

Future<void> showTeamEntryFeedbackDialog(
  BuildContext context, {
  required String title,
  required String message,
  required IconData icon,
  bool isError = false,
  String confirmLabel = '확인',
  VoidCallback? onConfirmed,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      final tone = isError ? colorScheme.error : colorScheme.primary;
      return AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: tone),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  onConfirmed?.call();
}
