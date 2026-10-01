import 'id_source.dart';
import 'task.dart';
import 'validation.dart';

/// A named group of tasks. Every task belongs to exactly one list.
final class TaskList {
  TaskList({
    required this.id,
    required this.name,
    List<Task> tasks = const [],
  }) : tasks = List.unmodifiable(tasks);

  /// The stable identity of this list.
  final Identifier id;

  /// The user-facing name. Unique across the book, ignoring case.
  final String name;

  /// The tasks in this list, in insertion order.
  final List<Task> tasks;

  int get completedCount => tasks.where((task) => task.completed).length;

  int get openCount => tasks.length - completedCount;

  /// Returns the task with [taskId], or null when this list has no such task.
  Task? taskById(Identifier taskId) {
    for (final task in tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  /// Resolves a CLI [reference] to exactly one task.
  ///
  /// Accepts a full identifier or any unambiguous prefix of one. An ambiguous
  /// prefix is rejected rather than resolved arbitrarily, because picking one
  /// of several matches could edit the wrong task.
  Task? taskByReference(String reference) {
    final matches = tasks.where((task) => task.id.startsWith(reference)).toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// The number of tasks whose [reference] starts with [reference].
  int countReferenceMatches(String reference) =>
      tasks.where((task) => task.id.startsWith(reference)).length;

  /// Returns a copy with [task] inserted at the end.
  TaskList withTask(Task task) => TaskList(
        id: id,
        name: name,
        tasks: [...tasks, task],
      );

  /// Returns a copy with the task identified by [taskId] replaced by [change].
  TaskList withChangedTask(Identifier taskId, Task Function(Task) change) =>
      TaskList(
        id: id,
        name: name,
        tasks: [
          for (final task in tasks)
            if (task.id == taskId) change(task) else task,
        ],
      );

  /// Returns a copy without the task identified by [taskId].
  TaskList withoutTask(Identifier taskId) => TaskList(
        id: id,
        name: name,
        tasks: tasks.where((task) => task.id != taskId).toList(),
      );

  /// Returns a copy with a new [name].
  TaskList withName(String newName) => TaskList(
        id: id,
        name: newName,
        tasks: tasks,
      );

  /// Throws unless this list holds [taskId].
  Task requireTask(Identifier taskId) {
    final task = taskById(taskId);
    if (task == null) {
      throw NotFoundException('This list has no task with reference $taskId.');
    }
    return task;
  }

  @override
  String toString() => 'TaskList($id, $name, ${tasks.length} tasks)';
}
