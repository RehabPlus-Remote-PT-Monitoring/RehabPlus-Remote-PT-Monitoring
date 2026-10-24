// lib/widgets/app_dialogs.dart
//
// iOS-style confirmation alerts (title, short message, two buttons side by
// side), used instead of Material AlertDialogs for simple yes/no questions.
// Dialogs that hold their own controls (the pain slider after a session,
// Report a problem) stay Material dialogs, styled by the theme.

import 'package:flutter/cupertino.dart';

import '../core/diagnostic_logger.dart';

/// Asks a yes/no question. Returns true only when [confirmLabel] is tapped;
/// cancelling or dismissing returns false.
///
/// [destructive] colours the confirm button red, as iOS does for actions
/// such as signing out or ending a session.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  try {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDefaultAction: !destructive,
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  } catch (e, st) {
    // Never let a dialog failure confirm a destructive action.
    DiagnosticLogger.I.error(
      'Dialogs',
      'Confirm dialog failed',
      {'title': title},
      e,
      st,
    );
    return false;
  }
}
