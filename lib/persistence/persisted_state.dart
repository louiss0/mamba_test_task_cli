import 'package:json_annotation/json_annotation.dart';

import '../domain/task.dart';

part 'persisted_state.g.dart';

/// The schema version written into every saved book.
///
/// Bump this whenever the on-disk shape changes, and add the matching step to
/// the migration chain in `persisted_state.dart` so older files keep loading.
const int currentSchemaVersion = 1;

/// The root of the JSON file.
@JsonSerializable(checked: true)
final class PersistedBook {
  const PersistedBook({required this.version, required this.lists});

  factory PersistedBook.fromJson(Map<String, dynamic> json) =>
      _$PersistedBookFromJson(json);

  /// The schema version this document was written with.
  final int version;

  final List<PersistedList> lists;

  Map<String, dynamic> toJson() => _$PersistedBookToJson(this);
}

/// One named list and its tasks.
@JsonSerializable(checked: true)
final class PersistedList {
  const PersistedList({
    required this.id,
    required this.name,
    required this.tasks,
  });

  factory PersistedList.fromJson(Map<String, dynamic> json) =>
      _$PersistedListFromJson(json);

  final String id;
  final String name;
  final List<PersistedTask> tasks;

  Map<String, dynamic> toJson() => _$PersistedListToJson(this);
}

/// One task.
@JsonSerializable(checked: true)
final class PersistedTask {
  const PersistedTask({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });

  factory PersistedTask.fromJson(Map<String, dynamic> json) =>
      _$PersistedTaskFromJson(json);

  final String id;
  final String title;
  final bool completed;

  /// ISO-8601 in UTC, so the file stays readable and unambiguous.
  final DateTime createdAt;

  Map<String, dynamic> toJson() => _$PersistedTaskToJson(this);
}

/// Converts a [Task] into its persisted form.
PersistedTask persistedTaskOf(Task task) => PersistedTask(
      id: task.id,
      title: task.title,
      completed: task.completed,
      createdAt: task.createdAt.toUtc(),
    );
