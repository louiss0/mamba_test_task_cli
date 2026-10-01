import 'dart:io';

import '../domain/validation.dart';
import '../persistence/corrupted_book_exception.dart';

/// A failure the interface can explain to the user.
///
/// Domain and persistence code throws its own types so it stays independent of
/// the interface. This turns one of those into wording and, importantly, into
/// a decision about how much of it the user has to read.
final class DisplayedFailure {
  const DisplayedFailure({
    required this.title,
    required this.detail,
    required this.needsReading,
  });

  /// The one-line summary shown in the status bar.
  final String title;

  /// The full explanation, which may span several lines.
  final String detail;

  /// Whether [detail] has to be presented in full rather than clipped to the
  /// width of the status bar.
  ///
  /// A rejected name fits on one line. A storage failure carries a file path
  /// and the steps to recover, so clipping it would hide exactly what the user
  /// needs.
  final bool needsReading;

  @override
  String toString() => '$title: $detail';
}

/// Turns [error] into wording the interface can show.
///
/// Expected failures are named so the user knows what went wrong. Anything
/// else is still shown, rather than swallowed, because an unexpected error in
/// an interactive session is still better explained than lost.
DisplayedFailure describeFailure(Object error) => switch (error) {
      NotFoundException(:final message) =>
        DisplayedFailure(title: 'No longer there', detail: message, needsReading: false),
      ValidationException(:final message) =>
        DisplayedFailure(title: 'Cannot continue', detail: message, needsReading: false),
      CorruptedBookException() => DisplayedFailure(
          title: 'Saved data cannot be read',
          detail: error.toString(),
          needsReading: true,
        ),
      FileSystemException() => DisplayedFailure(
          title: 'Cannot save the data file',
          detail: 'The change was not saved.\n\n$error\n\n'
              'Check that the location is writable and try again.',
          needsReading: true,
        ),
      _ => DisplayedFailure(
          title: 'Something went wrong',
          detail: '${error.runtimeType}: $error',
          needsReading: true,
        ),
    };
