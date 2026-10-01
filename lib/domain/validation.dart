/// A validation rule that domain input violated.
///
/// Domain code never depends on a UI framework, so it reports rejections with
/// this type. Presentation layers translate it into their own error channel:
/// the CLI turns it into a `MambaException`, the TUI renders it inline.
final class ValidationException implements Exception {
  ValidationException(this.message);

  /// The message shown to the user, phrased as a direct explanation.
  final String message;

  @override
  String toString() => message;
}

/// Raised when a lookup by name or id finds nothing.
final class NotFoundException implements Exception {
  NotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}
