/// Raised when the saved JSON cannot be turned into application state.
///
/// The file is never rewritten after this is thrown: the user keeps the bytes
/// exactly as they were so they can inspect or repair them by hand. The
/// message always names [path] so the user can find the file.
final class CorruptedBookException implements Exception {
  CorruptedBookException({
    required this.path,
    required this.reason,
    this.hint,
  });

  /// The file that could not be read.
  final String path;

  /// What was wrong with it.
  final String reason;

  /// An optional next step, such as how to repair or relocate the file.
  final String? hint;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('Cannot read the task data at:')
      ..writeln('  $path')
      ..writeln()
      ..writeln('Reason: $reason')
      ..writeln()
      ..write(
        'Nothing has been changed and the file has been left in place. '
        'Fix or move that file, then run the command again.',
      );
    if (hint != null) {
      buffer
        ..writeln()
        ..writeln('Hint: $hint');
    }
    return buffer.toString();
  }
}
