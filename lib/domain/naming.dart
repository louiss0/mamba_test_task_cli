import 'validation.dart';

/// Longest accepted task title, in characters.
const int maxTaskTitleLength = 200;

/// Longest accepted list name, in characters.
const int maxListNameLength = 60;

/// Returns the title with surrounding whitespace removed, or throws when the
/// title cannot be used.
String normalizeTaskTitle(String raw) {
  final title = raw.trim();
  if (title.isEmpty) {
    throw ValidationException('A task title cannot be empty.');
  }
  if (title.length > maxTaskTitleLength) {
    throw ValidationException(
      'A task title cannot be longer than $maxTaskTitleLength characters.',
    );
  }
  if (containsControlCharacter(title)) {
    throw ValidationException('A task title cannot contain control characters.');
  }
  return title;
}

/// Returns the name with surrounding whitespace removed, or throws when the
/// name cannot be used.
///
/// [existingNames] holds the names already taken in the book. Comparison
/// ignores case and surrounding whitespace so `Work` and `work` never
/// coexist, which keeps the CLI and the TUI from addressing the same list
/// ambiguously.
String normalizeListName(String raw, {Iterable<String> existingNames = const []}) {
  final name = raw.trim();
  if (name.isEmpty) {
    throw ValidationException('A list name cannot be empty.');
  }
  if (name.length > maxListNameLength) {
    throw ValidationException(
      'A list name cannot be longer than $maxListNameLength characters.',
    );
  }
  if (containsControlCharacter(name)) {
    throw ValidationException('A list name cannot contain control characters.');
  }
  final folded = _foldName(name);
  for (final taken in existingNames) {
    if (_foldName(taken) == folded) {
      throw ValidationException('A list named "$name" already exists.');
    }
  }
  return name;
}

bool containsControlCharacter(String value) =>
    value.runes.any((rune) => rune < 0x20 || rune == 0x7f);

String _foldName(String name) => name.toLowerCase();
