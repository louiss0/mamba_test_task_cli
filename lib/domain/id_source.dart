import 'dart:math';

/// A stable, opaque identifier for a list or a task.
///
/// Identifiers are generated once and never reused, so a task keeps its
/// identity when the list is filtered, sorted, or when neighbouring tasks are
/// deleted.
typedef Identifier = String;

/// Supplies fresh identifiers and timestamps.
///
/// Both are injectable so tests can produce reproducible data instead of
/// depending on the wall clock or the random source.
final class IdSource {
  IdSource({DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final DateTime Function() _clock;
  final Random _random;

  /// The current time, used for task creation stamps.
  DateTime now() => _clock();

  /// Returns an identifier that is unique within a single book.
  ///
  /// The value is 96 bits of randomness in lowercase hex, so it is
  /// shell-safe and its leading 12 characters are unique as well. The
  /// randomness comes first on purpose: a time-based prefix would give every
  /// identifier created in the same instant a shared prefix, which would make
  /// short task references ambiguous.
  Identifier next() {
    final high = _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0');
    final low = _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0');
    final tail = _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0');
    return '$high$low$tail';
  }
}
