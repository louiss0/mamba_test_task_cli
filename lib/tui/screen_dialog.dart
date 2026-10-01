import 'package:nocterm/nocterm.dart';

/// A modal the interface is currently showing.
///
/// A dialog describes intent; the TUI renders it and routes keys to it. The
/// callbacks run application operations, so no dialog reaches the JSON file.
sealed class ScreenDialog {
  const ScreenDialog();
}

/// Asks for a single line of text.
///
/// [validate] runs before [onSubmit] and returns a message, or null when the
/// value is acceptable. A rejection is shown inside the dialog and the dialog
/// stays open, so a bad value never reaches the book.
final class PromptDialog extends ScreenDialog {
  const PromptDialog({
    required this.title,
    required this.actionLabel,
    required this.controller,
    required this.onSubmit,
    this.validate,
  });

  /// The heading shown above the field.
  final String title;

  /// The word used in the confirm hint, for example `Add`.
  final String actionLabel;

  /// Holds the text being edited, seeded with the current value when
  /// renaming.
  final TextEditingController controller;

  /// Returns a message to reject [value], or null to accept it.
  final String? Function(String value)? validate;

  /// Applies the accepted value.
  final Future<void> Function(String value) onSubmit;
}

/// Asks the user to approve a destructive action.
final class ConfirmDialog extends ScreenDialog {
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final String title;
  final String message;

  /// The key hint for the approving key, for example `Delete`.
  final String confirmLabel;

  /// Runs only after the user confirms.
  final Future<void> Function() onConfirm;
}

/// Shows the keyboard reference.
final class HelpDialog extends ScreenDialog {
  const HelpDialog();
}

/// Explains a failure in full, for problems too long to read in the status bar.
///
/// Storage failures carry a file path and recovery steps, so they are presented
/// as something the user dismisses rather than a line that scrolls past.
final class MessageDialog extends ScreenDialog {
  const MessageDialog({required this.title, required this.body});

  /// The one-line summary, repeated at the top of the box.
  final String title;

  /// The full explanation, one entry per line.
  final List<String> body;
}
