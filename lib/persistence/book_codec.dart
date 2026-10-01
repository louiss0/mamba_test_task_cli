import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../domain/naming.dart';
import '../domain/task.dart';
import '../domain/task_book_state.dart';
import '../domain/task_list.dart';
import '../domain/validation.dart';
import 'corrupted_book_exception.dart';
import 'persisted_state.dart';

/// Converts a [TaskBookState] to JSON text and back.
///
/// The codec is the only place that knows the wire format. Domain code and
/// both front ends work with [TaskBookState] and never see a JSON map.
abstract final class BookCodec {
  /// Renders [state] as indented JSON, so the file stays easy to read and
  /// edit by hand.
  static String encode(TaskBookState state) {
    final persisted = PersistedBook(
      version: currentSchemaVersion,
      lists: [
        for (final list in state.lists)
          PersistedList(
            id: list.id,
            name: list.name,
            tasks: [for (final task in list.tasks) persistedTaskOf(task)],
          ),
      ],
    );
    return const JsonEncoder.withIndent('  ').convert(persisted.toJson());
  }

  /// Parses [source] into application state.
  ///
  /// Throws [CorruptedBookException] for malformed JSON, an unrecognised
  /// shape, or a schema version this build cannot read. It never returns
  /// partially decoded data, so a broken file can never be mistaken for an
  /// empty book.
  static TaskBookState decode(String source, {required String path}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw CorruptedBookException(
        path: path,
        reason: 'The file is not valid JSON (${error.message}).',
        hint: 'Open the file in an editor to inspect or repair it.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw CorruptedBookException(
        path: path,
        reason: 'Expected a JSON object at the top level, '
            'found ${_describe(decoded)}.',
      );
    }

    // Migration runs first: a document from an older release is brought up to
    // the current shape before anything is validated against it.
    final current = _migrate(decoded, path);

    final PersistedBook book;
    try {
      _validateTimestamps(current, path);
      book = PersistedBook.fromJson(current);
    } on CheckedFromJsonException catch (error) {
      throw CorruptedBookException(
        path: path,
        reason: 'A required field is missing or has the wrong type '
            '(${error.key}).',
      );
    } on JsonUnsupportedObjectError catch (error) {
      throw CorruptedBookException(
        path: path,
        reason: error.unsupportedObject.runtimeType.toString(),
      );
    } on TypeError catch (error) {
      throw CorruptedBookException(
        path: path,
        reason: 'A field has an unexpected type (${error.runtimeType}).',
      );
    }

    return _toState(book, path);
  }

  /// Checks every task timestamp before the generated decoder runs.
  ///
  /// The generated code reports a bad date as a generic type problem, which
  /// would leave the user guessing. Reading the value here turns it into a
  /// message that names the list, the task, and the offending text.
  static void _validateTimestamps(Map<String, dynamic> document, String path) {
    final lists = document['lists'];
    if (lists is! List) return;

    for (final entry in lists) {
      if (entry is! Map<String, dynamic>) continue;
      final name = entry['name'];
      final tasks = entry['tasks'];
      if (tasks is! List) continue;

      for (final task in tasks) {
        if (task is! Map<String, dynamic>) continue;
        final createdAt = task['createdAt'];
        if (createdAt is! String || DateTime.tryParse(createdAt) == null) {
          throw CorruptedBookException(
            path: path,
            reason: 'A task in ${name is String ? '"$name"' : 'a list'} has '
                'createdAt ${jsonEncode(createdAt)}, which is not an ISO-8601 '
                'date such as 2026-02-03T09:30:00.000Z.',
          );
        }
      }
    }
  }

  static TaskBookState _toState(PersistedBook book, String path) {
    final seenIds = <String>{};
    final seenNames = <String>{};

    final lists = <TaskList>[];
    for (final persisted in book.lists) {
      _requireIdentifier(path, 'A list', persisted.id);
      _requireAccepted(
        path,
        'The name of the list with id ${persisted.id}',
        persisted.name,
        normalizeListName,
      );
      if (persisted.name != persisted.name.trim()) {
        throw CorruptedBookException(
          path: path,
          reason: 'The list with id ${persisted.id} is named '
              '"${persisted.name}", which has surrounding spaces. Lists are '
              'looked up by name, so it would not be found.',
        );
      }
      if (!seenIds.add(persisted.id)) {
        throw CorruptedBookException(
          path: path,
          reason: 'Two lists share the id ${persisted.id}.',
        );
      }
      if (!seenNames.add(persisted.name.toLowerCase())) {
        throw CorruptedBookException(
          path: path,
          reason: 'Two lists share the name "${persisted.name}".',
        );
      }

      final seenTaskIds = <String>{};
      final tasks = <Task>[];
      for (final persistedTask in persisted.tasks) {
        _requireIdentifier(path, 'A task in "${persisted.name}"', persistedTask.id);
        _requireAccepted(
          path,
          'A task title in "${persisted.name}"',
          persistedTask.title,
          normalizeTaskTitle,
        );
        if (!seenTaskIds.add(persistedTask.id)) {
          throw CorruptedBookException(
            path: path,
            reason: 'Two tasks in "${persisted.name}" share the id '
                '${persistedTask.id}.',
          );
        }
        tasks.add(
          Task(
            id: persistedTask.id,
            title: persistedTask.title,
            completed: persistedTask.completed,
            createdAt: persistedTask.createdAt.toLocal(),
          ),
        );
      }

      lists.add(
        TaskList(id: persisted.id, name: persisted.name, tasks: tasks),
      );
    }

    return TaskBookState(lists: lists);
  }

  /// Enforces the rules the application applies to its own writes.
  ///
  /// Decoding cannot simply normalise what it finds. A value that disagrees
  /// with what this application would have written means the file came from
  /// somewhere else, and accepting it quietly is how a name stored as
  /// " Work " ends up invisible to a lookup for "Work". Rejecting leaves the
  /// file in place for the user to inspect.
  static void _requireAccepted(
    String path,
    String label,
    String value,
    String Function(String) rule,
  ) {
    try {
      rule(value);
    } on ValidationException catch (error) {
      throw CorruptedBookException(path: path, reason: '$label: ${error.message}');
    }
  }

  /// Rejects an identifier the application would never have produced.
  ///
  /// Identifiers are compared verbatim when a task is looked up, so stray
  /// spaces around one would make that task unreachable by reference.
  static void _requireIdentifier(String path, String label, String id) {
    if (id.isEmpty) {
      throw CorruptedBookException(
        path: path,
        reason: '$label has an empty id.',
      );
    }
    if (id != id.trim()) {
      throw CorruptedBookException(
        path: path,
        reason: '$label has an id with surrounding spaces: "$id".',
      );
    }
    if (containsControlCharacter(id)) {
      throw CorruptedBookException(
        path: path,
        reason: '$label has an id containing control characters.',
      );
    }
  }

  /// Brings an older document up to [currentSchemaVersion].
  ///
  /// Each step receives the document as decoded and returns it in the shape
  /// of the next version. Steps are applied in order, so a version 1 file
  /// saved before a future version 2 change still loads.
  static Map<String, dynamic> _migrate(
    Map<String, dynamic> document,
    String path,
  ) {
    final version = document['version'];
    if (version is! int) {
      throw CorruptedBookException(
        path: path,
        reason: 'The "version" field is missing or is not a whole number.',
        hint: 'A task data file always starts with {"version": '
            '$currentSchemaVersion, "lists": []}.',
      );
    }
    if (version == currentSchemaVersion) return document;
    if (version < 1 || version > currentSchemaVersion) {
      throw CorruptedBookException(
        path: path,
        reason: 'The file declares schema version $version, but this build '
            'reads versions 1 to $currentSchemaVersion.',
        hint: 'Install a matching version of the app, or move the file aside '
            'to start a new one.',
      );
    }
    // No older versions exist yet. Future steps are added here, one per
    // released schema version, for example:
    //   if (version < 2) document = _migrateToVersion2(document);
    return document;
  }

  static String _describe(Object? value) => switch (value) {
        null => 'null',
        List() => 'a JSON array',
        String() => 'a JSON string',
        num() => 'a JSON number',
        bool() => 'a JSON boolean',
        _ => value.runtimeType.toString(),
      };
}
