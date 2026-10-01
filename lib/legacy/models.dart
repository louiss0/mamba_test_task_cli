import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'models.g.dart';

final class TaskFailure(final String message) implements Exception {
  @override
  String toString() => message;
}

String validatedText(String input, String label, int maximum) {
  final value = input.trim();
  if (value.isEmpty ||
      value.length > maximum ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw TaskFailure(
      '$label must contain 1–$maximum characters without control characters.',
    );
  }
  return value;
}

String _validatedId(String value) {
  if (!Uuid.isValidUUID(fromString: value)) {
    throw const FormatException('Invalid persistent UUID.');
  }
  return value.toLowerCase();
}

int _strictVersion(Object? value) {
  if (value is! int) {
    throw const FormatException('Storage version must be an integer.');
  }
  return value;
}

enum Completion { incomplete, completed }

enum TaskFilter {
  all,
  incomplete,
  completed;

  bool matches(Task task) => switch (this) {
    all => true,
    incomplete => task.completion == Completion.incomplete,
    completed => task.completion == Completion.completed,
  };

  String get label => switch (this) {
    all => 'All',
    incomplete => 'Incomplete',
    completed => 'Completed',
  };
}

final class Task._(
  final String id,
  final String title,
  final Completion completion,
  final DateTime createdAt,
) {
  factory create({
    required String id,
    required String title,
    required Completion completion,
    required DateTime createdAt,
  }) => Task._(
    _validatedId(id),
    validatedText(title, 'Task title', 500),
    completion,
    createdAt.toUtc(),
  );

  bool get completed => completion == Completion.completed;

  Task update({String? title, Completion? completion}) => Task.create(
    id: id,
    title: title ?? this.title,
    completion: completion ?? this.completion,
    createdAt: createdAt,
  );
}

final class TaskList._(
  final String id,
  final String name,
  final List<Task> tasks,
) {
  factory create({
    required String id,
    required String name,
    Iterable<Task> tasks = const [],
  }) {
    final validName = validatedText(name, 'List name', 80);
    if (Uuid.isValidUUID(fromString: validName)) {
      throw TaskFailure('List names cannot be UUIDs; use a descriptive name.');
    }
    return TaskList._(_validatedId(id), validName, List.unmodifiable(tasks));
  }

  TaskList update({String? name, Iterable<Task>? tasks}) => TaskList.create(
    id: id,
    name: name ?? this.name,
    tasks: tasks ?? this.tasks,
  );
}

final class AppState._(final List<TaskList> lists) {
  factory create(Iterable<TaskList> lists) {
    final names = <String>{};
    final ids = <String>{};
    for (final list in lists) {
      if (!names.add(list.name.toLowerCase())) {
        throw TaskFailure(
          'A list named "${list.name}" already exists (names ignore case).',
        );
      }
      if (!ids.add(list.id)) throw const FormatException('Duplicate list ID.');
      for (final task in list.tasks) {
        if (!ids.add(task.id)) {
          throw const FormatException('Duplicate task ID.');
        }
      }
    }
    return AppState._(List.unmodifiable(lists));
  }
}

// Wire DTOs only. Generated, checked decoding never leaks maps into the app.
@JsonSerializable(
  checked: true,
  explicitToJson: true,
  disallowUnrecognizedKeys: true,
)
final class StoredState {
  new({required this.version, required this.lists});
  @JsonKey(fromJson: _strictVersion)
  final int version;
  final List<StoredList> lists;
  factory fromJson(Map<String, dynamic> json) => _$StoredStateFromJson(json);
  Map<String, dynamic> toJson() => _$StoredStateToJson(this);

  factory fromDomain(AppState state) => StoredState(
    version: 1,
    lists: state.lists.map(StoredList.fromDomain).toList(),
  );

  AppState toDomain() {
    if (version != 1) {
      throw FormatException(
        'Unsupported storage version $version (expected 1).',
      );
    }
    return AppState.create(lists.map((list) => list.toDomain()));
  }
}

@JsonSerializable(
  checked: true,
  explicitToJson: true,
  disallowUnrecognizedKeys: true,
)
final class StoredList {
  new({required this.id, required this.name, required this.tasks});
  final String id;
  final String name;
  final List<StoredTask> tasks;
  factory fromJson(Map<String, dynamic> json) => _$StoredListFromJson(json);
  Map<String, dynamic> toJson() => _$StoredListToJson(this);
  factory fromDomain(TaskList list) => StoredList(
    id: list.id,
    name: list.name,
    tasks: list.tasks.map(StoredTask.fromDomain).toList(),
  );
  TaskList toDomain() => TaskList.create(
    id: id,
    name: name,
    tasks: tasks.map((task) => task.toDomain()),
  );
}

@JsonSerializable(checked: true, disallowUnrecognizedKeys: true)
final class StoredTask {
  new({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });
  final String id;
  final String title;
  final bool completed;
  final String createdAt;
  factory fromJson(Map<String, dynamic> json) => _$StoredTaskFromJson(json);
  Map<String, dynamic> toJson() => _$StoredTaskToJson(this);
  factory fromDomain(Task task) => StoredTask(
    id: task.id,
    title: task.title,
    completed: task.completed,
    createdAt: task.createdAt.toIso8601String(),
  );
  Task toDomain() {
    final timestamp = DateTime.tryParse(createdAt);
    if (timestamp == null ||
        !timestamp.isUtc ||
        timestamp.toIso8601String() != createdAt) {
      throw const FormatException(
        'createdAt must be a canonical UTC ISO-8601 timestamp.',
      );
    }
    return Task.create(
      id: id,
      title: title,
      completion: completed ? Completion.completed : Completion.incomplete,
      createdAt: timestamp,
    );
  }
}
